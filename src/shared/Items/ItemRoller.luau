--!strict
--[[
	ItemRoller
	Turns a config def + power into a concrete ItemInstance with rolled stats
	and perks. Pure: randomness comes from the Random passed in and the uid is
	supplied by the caller (the server uses HttpService GUIDs), so rolls are
	reproducible in tests.

	Modes:
	  "Random"  normal drops: stats roll within the rarity's range, perks are
	            drawn from each column's pool
	  "Base"    deterministic median roll (starter gear, previews, tests)
]]

local Config = script.Parent.Parent.Config
local ArmorConfig = require(Config.ArmorConfig)
local PerkConfig = require(Config.PerkConfig)
local PowerConfig = require(Config.PowerConfig)
local RarityConfig = require(Config.RarityConfig)
local Types = require(script.Parent.Parent.Types)
local WeaponTypeConfig = require(Config.WeaponTypeConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)

type ItemInstance = Types.ItemInstance

export type RollMode = "Random" | "Base"

local ItemRoller = {}

local function clampPower(power: number): number
	return math.clamp(math.floor(power), 1, PowerConfig.PinnacleCap)
end

local function pick<T>(list: { T }, rng: Random, mode: RollMode): T
	if mode == "Base" then
		return list[1]
	end
	return list[rng:NextInteger(1, #list)]
end

function ItemRoller.RollWeapon(
	def: Types.WeaponDef,
	power: number,
	rng: Random,
	uid: string,
	now: number,
	mode: RollMode
): ItemInstance
	local archetype = WeaponTypeConfig.Types[def.Type]
	local rarity = RarityConfig.Tiers[def.Rarity]

	local stats: { [string]: number } = {}
	for _, stat in WeaponTypeConfig.RolledStats do
		local base = archetype.BaseStats[stat] or 50
		local bias = if def.StatBias then def.StatBias[stat] or 0 else 0
		local roll = if mode == "Base" then 0 else rng:NextInteger(rarity.WeaponStatRoll.Min, rarity.WeaponStatRoll.Max)
		stats[stat] = math.clamp(base + bias + roll, WeaponTypeConfig.StatMin, WeaponTypeConfig.StatMax)
	end

	local perks: { string } = {}
	if def.FixedPerks then
		-- Exotics and curated weapons always carry their listed perks.
		perks = table.clone(def.FixedPerks)
	elseif rarity.WeaponPerkMode == "Random1" then
		local pool = PerkConfig.PoolFor("Trait1", def.Type)
		for _, perk in PerkConfig.PoolFor("Trait2", def.Type) do
			table.insert(pool, perk)
		end
		if #pool > 0 then
			table.insert(perks, pick(pool, rng, mode).Id)
		end
	elseif rarity.WeaponPerkMode == "Columns" then
		for _, column in rarity.WeaponColumns do
			local pool = PerkConfig.PoolFor(column, def.Type)
			if #pool > 0 then
				table.insert(perks, pick(pool, rng, mode).Id)
			end
		end
	end

	local masterwork: string? = nil
	if rarity.MasterworkOnDrop then
		masterwork = pick(RarityConfig.MasterworkStats, rng, mode)
	end

	return {
		Uid = uid,
		DefId = def.Id,
		Kind = "Weapon",
		Slot = def.Slot,
		Rarity = def.Rarity,
		Power = clampPower(power),
		Stats = stats,
		Perks = perks,
		Masterwork = masterwork,
		Location = "Inventory",
		Locked = false,
		AcquiredAt = now,
	}
end

-- Spreads `total` points across the armor stats. Every stat starts at the
-- per-piece minimum; focus stats are twice as likely to receive points.
local function distributeArmorStats(
	total: number,
	rng: Random,
	mode: RollMode,
	focus: { string }?
): { [string]: number }
	local order = ArmorConfig.StatOrder
	local minPer = ArmorConfig.StatMinPerPiece
	local maxPer = ArmorConfig.StatMaxPerPiece
	local stats: { [string]: number } = {}
	for _, stat in order do
		stats[stat] = minPer
	end

	local remaining = math.clamp(total - minPer * #order, 0, (maxPer - minPer) * #order)

	if mode == "Base" then
		local share = remaining // #order
		local extra = remaining % #order
		for index, stat in order do
			stats[stat] += share + (if index <= extra then 1 else 0)
		end
		return stats
	end

	local weights: { [string]: number } = {}
	for _, stat in order do
		weights[stat] = if focus and table.find(focus, stat) then 2 else 1
	end

	while remaining > 0 do
		local totalWeight = 0
		for _, stat in order do
			if stats[stat] < maxPer then
				totalWeight += weights[stat]
			end
		end
		local ticket = rng:NextNumber() * totalWeight
		for _, stat in order do
			if stats[stat] < maxPer then
				ticket -= weights[stat]
				if ticket <= 0 then
					stats[stat] += 1
					break
				end
			end
		end
		remaining -= 1
	end
	return stats
end

function ItemRoller.RollArmor(
	def: Types.ArmorDef,
	power: number,
	rng: Random,
	uid: string,
	now: number,
	mode: RollMode
): ItemInstance
	local range = RarityConfig.Tiers[def.Rarity].ArmorTotal
	local total = if mode == "Base" then (range.Min + range.Max) // 2 else rng:NextInteger(range.Min, range.Max)

	return {
		Uid = uid,
		DefId = def.Id,
		Kind = "Armor",
		Slot = def.Slot,
		Rarity = def.Rarity,
		Power = clampPower(power),
		Stats = distributeArmorStats(total, rng, mode, def.StatFocus),
		Perks = if def.FixedPerks then table.clone(def.FixedPerks) else {},
		Masterwork = nil,
		Location = "Inventory",
		Locked = false,
		AcquiredAt = now,
	}
end

-- Rolls any item by def id. Returns nil for unknown ids.
function ItemRoller.Roll(
	defId: string,
	power: number,
	rng: Random,
	uid: string,
	now: number,
	mode: RollMode?
): ItemInstance?
	local entry = ItemCatalog.Get(defId)
	if entry == nil then
		return nil
	end
	local rollMode: RollMode = mode or "Random"
	if entry.Weapon then
		return ItemRoller.RollWeapon(entry.Weapon, power, rng, uid, now, rollMode)
	elseif entry.Armor then
		return ItemRoller.RollArmor(entry.Armor, power, rng, uid, now, rollMode)
	end
	return nil
end

-- True when the item carries a Trait1 + Trait2 pair listed in PerkConfig.Synergies.
function ItemRoller.HasSynergy(item: ItemInstance): boolean
	for i = 1, #item.Perks do
		for j = i + 1, #item.Perks do
			if PerkConfig.IsSynergy(item.Perks[i], item.Perks[j]) then
				return true
			end
		end
	end
	return false
end

-- How lucky the stat roll was, 0 (worst possible) to 1 (best possible).
-- Weapons compare against the rarity's roll range; armor against its total range.
function ItemRoller.RollQuality(item: ItemInstance): number
	local entry = ItemCatalog.Get(item.DefId)
	if entry == nil then
		return 0
	end
	local rarity = RarityConfig.Tiers[item.Rarity]
	if entry.Weapon then
		local archetype = WeaponTypeConfig.Types[entry.Weapon.Type]
		local bias = entry.Weapon.StatBias
		local sum, count = 0, 0
		for _, stat in WeaponTypeConfig.RolledStats do
			local expected = (archetype.BaseStats[stat] or 50) + (if bias then bias[stat] or 0 else 0)
			sum += (item.Stats[stat] or expected) - expected
			count += 1
		end
		local range = rarity.WeaponStatRoll
		if range.Max == range.Min then
			return 1
		end
		return math.clamp((sum / count - range.Min) / (range.Max - range.Min), 0, 1)
	end
	local total = 0
	for _, value in item.Stats do
		total += value
	end
	local range = rarity.ArmorTotal
	if range.Max == range.Min then
		return 1
	end
	return math.clamp((total - range.Min) / (range.Max - range.Min), 0, 1)
end

-- A "god roll": synergistic perks on a top-quartile stat roll.
function ItemRoller.IsGodRoll(item: ItemInstance): boolean
	return ItemRoller.HasSynergy(item) and ItemRoller.RollQuality(item) >= 0.75
end

return ItemRoller
