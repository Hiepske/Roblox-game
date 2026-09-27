--!strict
--[[
	PowerMath
	Every power calculation in one pure module (shared so the client can show
	the same numbers the server uses). All tuning comes from PowerConfig; see
	DESIGN.md "Power math" for the rules in plain words.
]]

local Config = script.Parent.Parent.Config
local PowerConfig = require(Config.PowerConfig)
local RarityConfig = require(Config.RarityConfig)
local Types = require(script.Parent.Parent.Types)

type ItemInstance = Types.ItemInstance

local PowerMath = {}

local ALL_SLOTS: { string } = {}
for _, slot in PowerConfig.WeaponSlots do
	table.insert(ALL_SLOTS, slot)
end
for _, slot in PowerConfig.ArmorSlots do
	table.insert(ALL_SLOTS, slot)
end
table.freeze(ALL_SLOTS)

PowerMath.AllSlots = ALL_SLOTS

-- Character power: floor of the average power of all eight equipped slots.
-- An empty slot counts as 0.
function PowerMath.CharacterPower(items: { [string]: ItemInstance }, equipped: { [string]: string }): number
	local total = 0
	for _, slot in ALL_SLOTS do
		local uid = equipped[slot]
		local item = if uid then items[uid] else nil
		if item then
			total += item.Power
		end
	end
	return total // #ALL_SLOTS
end

local function isEquipLimited(item: ItemInstance): boolean
	local tier = RarityConfig.Tiers[item.Rarity]
	return tier ~= nil and tier.EquipLimitPerCategory ~= nil
end

local function better(candidate: ItemInstance, current: ItemInstance?): boolean
	if current == nil then
		return true
	end
	if candidate.Power ~= current.Power then
		return candidate.Power > current.Power
	end
	return candidate.Uid < current.Uid -- deterministic tie-break
end

-- Best legal pick for one category (weapons or armor): the best item per
-- slot, allowing at most one equip-limited (exotic) item in the category.
local function bestForCategory(items: { [string]: ItemInstance }, slots: { string }): (number, { [string]: string })
	local bestNormal: { [string]: ItemInstance } = {}
	local bestLimited: { [string]: ItemInstance } = {}
	for _, item in items do
		if table.find(slots, item.Slot) then
			local bucket = if isEquipLimited(item) then bestLimited else bestNormal
			if better(item, bucket[item.Slot]) then
				bucket[item.Slot] = item
			end
		end
	end

	local sum = 0
	local picks: { [string]: string } = {}
	for _, slot in slots do
		local item = bestNormal[slot]
		if item then
			sum += item.Power
			picks[slot] = item.Uid
		end
	end

	-- Swap in the single exotic that adds the most power, if any helps.
	local bestGain, bestSlot = 0, nil :: string?
	for _, slot in slots do
		local limited = bestLimited[slot]
		if limited then
			local normal = bestNormal[slot]
			local gain = limited.Power - (if normal then normal.Power else 0)
			if gain > bestGain then
				bestGain, bestSlot = gain, slot
			end
		end
	end
	if bestSlot then
		sum += bestGain
		picks[bestSlot] = bestLimited[bestSlot].Uid
	end
	return sum, picks
end

-- Highest possible character power from everything the player owns (vault
-- and postmaster included), respecting the one-exotic-per-category rule.
-- Drops are generated relative to this number.
function PowerMath.HighestPossible(items: { [string]: ItemInstance }): (number, { [string]: string })
	local weaponSum, weaponPicks = bestForCategory(items, PowerConfig.WeaponSlots)
	local armorSum, armorPicks = bestForCategory(items, PowerConfig.ArmorSlots)
	local picks = weaponPicks
	for slot, uid in armorPicks do
		picks[slot] = uid
	end
	return (weaponSum + armorSum) // #ALL_SLOTS, picks
end

-- Which progression stage a power level is in, for UI and reward rules.
function PowerMath.Stage(power: number): "SoftCap" | "Powerful" | "Pinnacle" | "Max"
	if power < PowerConfig.SoftCap then
		return "SoftCap"
	elseif power < PowerConfig.PowerfulCap then
		return "Powerful"
	elseif power < PowerConfig.PinnacleCap then
		return "Pinnacle"
	end
	return "Max"
end

-- Power of a new drop for a player whose highest possible power is `highest`.
-- `tier` only matters for Powerful rewards (1-3).
function PowerMath.RollDropPower(highest: number, kind: Types.RewardKind, tier: number?, rng: Random): number
	local p = math.floor(highest)

	if kind == "World" then
		if p >= PowerConfig.SoftCap then
			return if PowerConfig.World.AboveSoftCap == "AtSoftCap" then PowerConfig.SoftCap else p
		end
		local bonus = rng:NextInteger(PowerConfig.World.MinBonus, PowerConfig.World.MaxBonus)
		return math.min(p + bonus, PowerConfig.SoftCap)
	elseif kind == "Powerful" then
		if p >= PowerConfig.PowerfulCap then
			return p
		end
		local tiers = PowerConfig.Powerful.TierBonus
		local bonus = tiers[math.clamp(tier or 1, 1, #tiers)]
		return math.min(p + bonus, PowerConfig.PowerfulCap)
	end

	-- Pinnacle
	if p >= PowerConfig.PinnacleCap then
		return PowerConfig.PinnacleCap
	end
	local result = p + rng:NextInteger(PowerConfig.Pinnacle.MinBonus, PowerConfig.Pinnacle.MaxBonus)
	if p < PowerConfig.PowerfulCap then
		-- Never worse than a top-tier Powerful reward below the powerful cap.
		result =
			math.max(result, PowerMath.RollDropPower(p, "Powerful", PowerConfig.Pinnacle.BelowPowerfulCapTier, rng))
	end
	return math.min(result, PowerConfig.PinnacleCap)
end

-- Infusion keeps the target's roll and takes the higher power.
function PowerMath.InfusedPower(targetPower: number, fodderPower: number): number
	return math.max(targetPower, fodderPower)
end

-- Artifact ---------------------------------------------------------------------

function PowerMath.ArtifactBonus(level: number): number
	local artifact = PowerConfig.Artifact
	if not artifact.Enabled then
		return 0
	end
	return math.clamp(math.floor(level), 0, artifact.MaxLevel) * artifact.PowerPerLevel
end

-- XP needed to go from `level - 1` to `level`.
function PowerMath.ArtifactXpForLevel(level: number): number
	local artifact = PowerConfig.Artifact
	return artifact.BaseXp + math.max(0, level - 1) * artifact.XpGrowth
end

-- Combat scaling -----------------------------------------------------------------

-- Damage multipliers for a given power delta (player - activity), read off
-- the PowerConfig.PowerDelta curve with linear interpolation.
function PowerMath.DeltaMultipliers(delta: number): (number, number)
	local points = PowerConfig.PowerDelta.Points
	local first, last = points[1], points[#points]
	if delta <= first.Delta then
		return first.Outgoing, first.Incoming
	elseif delta >= last.Delta then
		return last.Outgoing, last.Incoming
	end
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if delta >= a.Delta and delta <= b.Delta then
			local t = (delta - a.Delta) / (b.Delta - a.Delta)
			return a.Outgoing + (b.Outgoing - a.Outgoing) * t, a.Incoming + (b.Incoming - a.Incoming) * t
		end
	end
	return 1, 1
end

export type CombatContext = {
	CharacterPower: number,
	ArtifactLevel: number,
	ActivityPower: number,
	PowerEnabled: boolean,
	-- Largest delta that still counts (e.g. 0 in contest-mode activities).
	DeltaCap: number?,
}

-- Outgoing (player -> enemy) and incoming (enemy -> player) multipliers.
function PowerMath.CombatMultipliers(context: CombatContext): (number, number)
	if not context.PowerEnabled then
		return 1, 1
	end
	local effective = context.CharacterPower + PowerMath.ArtifactBonus(context.ArtifactLevel)
	local delta = effective - context.ActivityPower
	if context.DeltaCap ~= nil then
		delta = math.min(delta, context.DeltaCap)
	end
	return PowerMath.DeltaMultipliers(delta)
end

-- Base enemy health/damage scale for an activity's recommended power.
function PowerMath.ActivityEnemyScale(activityPower: number): (number, number)
	local scaling = PowerConfig.ActivityScaling
	local over = math.max(0, activityPower - scaling.ReferencePower)
	return 1 + over * scaling.HealthPerPower, 1 + over * scaling.DamagePerPower
end

return PowerMath
