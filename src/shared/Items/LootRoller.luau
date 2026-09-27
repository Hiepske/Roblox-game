--!strict
--[[
	LootRoller
	Pure drop generation: which item drops and at what power. The server's
	LootService decides *when* something drops and hands the result to
	DataService; this module only rolls.

	  1. Exotic check (LootSource.ExoticChance) from the ExoticPool.
	  2. Rarity from the source's weights (or an override).
	  3. Weapon or armor (LootSource.ArmorChance).
	  4. A def whose Sources contain the source's PoolTag (plus "World"
	     items when IncludeWorldPool). Class-locked armor only for your class.
	  5. Power from PowerMath.RollDropPower(highest, rewardKind, tier).
]]

local Shared = script.Parent.Parent
local ArmorConfig = require(Shared.Config.ArmorConfig)
local LootConfig = require(Shared.Config.LootConfig)
local PowerMath = require(Shared.Power.PowerMath)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ItemRoller = require(script.Parent.ItemRoller)

type ItemInstance = Types.ItemInstance

local LootRoller = {}

export type RollOptions = {
	-- Replace the source's rarity weights (e.g. story rewards: Rare/Epic only).
	Rarities: { [string]: number }?,
	-- Skip the exotic roll.
	NoExotic: boolean?,
	-- Only items whose Sources contain the pool tag, excluding world items
	-- (raid-exclusive drops).
	ExclusiveOnly: boolean?,
	-- Force a rarity.
	Rarity: string?,
}

-- Picks a key from { key = weight } (keys sorted, so rolls are reproducible).
function LootRoller.PickWeighted(weights: { [string]: number }, rng: Random): string?
	local keys: { string } = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys)
	local ticket = rng:NextNumber() * total
	for _, key in keys do
		ticket -= weights[key]
		if ticket <= 0 then
			return key
		end
	end
	return keys[#keys]
end

local function hasSource(sources: { string }, tag: string): boolean
	return table.find(sources, tag) ~= nil
end

-- Def ids that can drop for a pool tag / rarity / kind.
function LootRoller.Candidates(
	tag: string,
	includeWorld: boolean,
	rarity: string,
	kind: string, -- "Weapon" or "Armor"
	classId: string
): { string }
	local ids: { string } = {}
	local function matches(sources: { string }): boolean
		return hasSource(sources, tag) or (includeWorld and hasSource(sources, "World"))
	end
	if kind == "Weapon" then
		for _, weapon in WeaponConfig.List do
			if weapon.Rarity == rarity and matches(weapon.Sources) then
				table.insert(ids, weapon.Id)
			end
		end
	else
		for _, armor in ArmorConfig.List do
			if
				armor.Rarity == rarity
				and matches(armor.Sources)
				and (armor.ClassRestriction == nil or armor.ClassRestriction == classId)
			then
				table.insert(ids, armor.Id)
			end
		end
	end
	return ids
end

-- Exotic weapons plus exotic armor for this class from the ExoticPool.
function LootRoller.ExoticCandidates(classId: string): { string }
	local ids: { string } = {}
	for _, weapon in WeaponConfig.List do
		if weapon.Rarity == "Exotic" and hasSource(weapon.Sources, "ExoticPool") then
			table.insert(ids, weapon.Id)
		end
	end
	for _, armor in ArmorConfig.List do
		if
			armor.Rarity == "Exotic"
			and hasSource(armor.Sources, "ExoticPool")
			and (armor.ClassRestriction == nil or armor.ClassRestriction == classId)
		then
			table.insert(ids, armor.Id)
		end
	end
	return ids
end

-- Which def drops from `sourceId`. nil only if the pools are empty.
function LootRoller.RollDefId(sourceId: string, rng: Random, classId: string, options: RollOptions?): string?
	local source = LootConfig.Sources[sourceId]
	if source == nil then
		return nil
	end
	local opts: RollOptions = options or {}

	if not opts.NoExotic and not opts.ExclusiveOnly and opts.Rarity == nil then
		if rng:NextNumber() < source.ExoticChance then
			local exotics = LootRoller.ExoticCandidates(classId)
			if #exotics > 0 then
				return exotics[rng:NextInteger(1, #exotics)]
			end
		end
	end

	local rarity = opts.Rarity or LootRoller.PickWeighted(opts.Rarities or source.RarityWeights, rng)
	if rarity == nil then
		return nil
	end
	local includeWorld = source.IncludeWorldPool and not opts.ExclusiveOnly
	local firstKind = if rng:NextNumber() < source.ArmorChance then "Armor" else "Weapon"
	local secondKind = if firstKind == "Armor" then "Weapon" else "Armor"

	local kinds: { string } = { firstKind, secondKind }
	for _, kind in kinds do
		local ids = LootRoller.Candidates(source.PoolTag, includeWorld, rarity, kind, classId)
		if #ids > 0 then
			return ids[rng:NextInteger(1, #ids)]
		end
	end
	-- Nothing of that rarity in this pool: fall back to world items of that
	-- rarity, then of any rarity (ConfigValidator reports such gaps).
	if not opts.ExclusiveOnly then
		for _, candidateRarity in { rarity, "Legendary", "Epic", "Rare" } do
			for _, kind in kinds do
				local ids = LootRoller.Candidates("World", true, candidateRarity, kind, classId)
				if #ids > 0 then
					return ids[rng:NextInteger(1, #ids)]
				end
			end
		end
	end
	return nil
end

-- A complete rolled item for a player whose highest possible power is `highest`.
function LootRoller.RollItem(
	sourceId: string,
	highest: number,
	rewardKind: Types.RewardKind,
	tier: number?,
	rng: Random,
	uid: string,
	now: number,
	classId: string,
	options: RollOptions?
): ItemInstance?
	local defId = LootRoller.RollDefId(sourceId, rng, classId, options)
	if defId == nil then
		return nil
	end
	local power = PowerMath.RollDropPower(highest, rewardKind, tier, rng)
	return ItemRoller.Roll(defId, power, rng, uid, now, "Random")
end

return LootRoller
