--!strict
--[[
	ConfigValidator
	Cross-checks every config module so balancing mistakes fail loudly at
	server start (and in tests) instead of surfacing as broken drops later.

	local problems = ConfigValidator.Validate()
	-- { "WeaponConfig W_FOO: unknown perk BAR", ... } ; empty = all good
]]

local Config = script.Parent.Config
local ActivityConfig = require(Config.ActivityConfig)
local ArmorConfig = require(Config.ArmorConfig)
local BountyConfig = require(Config.BountyConfig)
local ClassConfig = require(Config.ClassConfig)
local EconomyConfig = require(Config.EconomyConfig)
local ElementConfig = require(Config.ElementConfig)
local EnemyConfig = require(Config.EnemyConfig)
local GameConfig = require(Config.GameConfig)
local InputConfig = require(Config.InputConfig)
local LootConfig = require(Config.LootConfig)
local MilestoneConfig = require(Config.MilestoneConfig)
local PerkConfig = require(Config.PerkConfig)
local PowerConfig = require(Config.PowerConfig)
local RarityConfig = require(Config.RarityConfig)
local VendorConfig = require(Config.VendorConfig)
local WeaponConfig = require(Config.WeaponConfig)
local WeaponTypeConfig = require(Config.WeaponTypeConfig)
local AssetIds = require(Config.AssetIds)
local WorldConfig = require(Config.WorldConfig)

local ConfigValidator = {}

-- `for _ in optional or {} do` confuses the type checker; this keeps it typed.
local function listOf<T>(list: { T }?): { T }
	return list or {}
end

-- Minimum content the design calls for.
ConfigValidator.ContentTargets = {
	Weapons = 40,
	ExoticWeapons = 6,
	TraitPerks = 20,
	StoryMissions = 8,
	Strikes = 3,
	RaidEncounters = 3,
	Factions = 2,
	SubclassesPerClass = 2,
}

local ITEM_SOURCES = {
	Starter = true,
	World = true,
	Story = true,
	Patrol = true,
	Strike = true,
	Nightfall = true,
	Dungeon = true,
	Raid = true,
	PvP = true,
	Vendor = true,
	Quest = true,
	ExoticPool = true,
	-- Per-mission weapon pools.
	FirstLight = true,
	SunkenRelay = true,
	HollowDark = true,
}

local WEAPON_SLOTS = { Kinetic = true, Energy = true, Heavy = true }

-- Boss mechanics implemented in src/server/Activities/BossMechanics.
local BOSS_MECHANICS = { Standard = true, ImmuneAdds = true, EchoPlates = true }

function ConfigValidator.Validate(): { string }
	local problems: { string } = {}
	local function report(message: string)
		table.insert(problems, message)
	end

	local function checkCosts(where: string, costs: { [string]: any })
		for currency, amount in costs do
			if EconomyConfig.Currencies[currency] == nil then
				report(`{where}: unknown currency {currency}`)
			elseif type(amount) == "number" and amount < 0 then
				report(`{where}: negative cost for {currency}`)
			end
		end
	end

	-- Power ------------------------------------------------------------------------
	if
		not (
			PowerConfig.StartingPower < PowerConfig.SoftCap
			and PowerConfig.SoftCap < PowerConfig.PowerfulCap
			and PowerConfig.PowerfulCap < PowerConfig.PinnacleCap
		)
	then
		report("PowerConfig: caps must satisfy Starting < SoftCap < PowerfulCap < PinnacleCap")
	end
	if PowerConfig.World.MinBonus > PowerConfig.World.MaxBonus then
		report("PowerConfig.World: MinBonus > MaxBonus")
	end
	if PowerConfig.Pinnacle.MinBonus > PowerConfig.Pinnacle.MaxBonus then
		report("PowerConfig.Pinnacle: MinBonus > MaxBonus")
	end
	local points = PowerConfig.PowerDelta.Points
	for i = 2, #points do
		if points[i].Delta <= points[i - 1].Delta then
			report("PowerConfig.PowerDelta: points must be sorted by strictly increasing Delta")
		end
		if points[i].Outgoing < points[i - 1].Outgoing or points[i].Incoming > points[i - 1].Incoming then
			report(`PowerConfig.PowerDelta: curve is not monotonic at Delta {points[i].Delta}`)
		end
	end

	-- Rarity -------------------------------------------------------------------------
	for _, rarityId in RarityConfig.Order do
		local tier = RarityConfig.Tiers[rarityId]
		if tier == nil then
			report(`RarityConfig: missing tier {rarityId}`)
			continue
		end
		if tier.WeaponStatRoll.Min > tier.WeaponStatRoll.Max then
			report(`RarityConfig {rarityId}: WeaponStatRoll Min > Max`)
		end
		if tier.ArmorTotal.Min > tier.ArmorTotal.Max then
			report(`RarityConfig {rarityId}: ArmorTotal Min > Max`)
		end
		local statCount = #ArmorConfig.StatOrder
		if
			tier.ArmorTotal.Min < ArmorConfig.StatMinPerPiece * statCount
			or tier.ArmorTotal.Max > ArmorConfig.StatMaxPerPiece * statCount
		then
			report(`RarityConfig {rarityId}: ArmorTotal outside what per-stat limits allow`)
		end
		if tier.EquipLimitPerCategory ~= nil and tier.EquipLimitPerCategory ~= 1 then
			report(`RarityConfig {rarityId}: only an equip limit of 1 is supported`)
		end
		if tier.MasterworkOnDrop and not tier.CanMasterwork then
			report(`RarityConfig {rarityId}: MasterworkOnDrop requires CanMasterwork`)
		end
		for _, column in tier.WeaponColumns do
			if column ~= "Barrel" and column ~= "Magazine" and column ~= "Trait1" and column ~= "Trait2" then
				report(`RarityConfig {rarityId}: unknown weapon column {column}`)
			end
		end
		if EconomyConfig.Dismantle[rarityId] == nil then
			report(`EconomyConfig.Dismantle: missing rarity {rarityId}`)
		end
		if EconomyConfig.Infusion[rarityId] == nil then
			report(`EconomyConfig.Infusion: missing rarity {rarityId}`)
		end
	end
	for _, stat in RarityConfig.MasterworkStats do
		if table.find(WeaponTypeConfig.RolledStats, stat) == nil then
			report(`RarityConfig.MasterworkStats: {stat} is not a rolled weapon stat`)
		end
	end

	-- Weapon archetypes ---------------------------------------------------------------
	for _, typeId in WeaponTypeConfig.Order do
		local archetype = WeaponTypeConfig.Types[typeId]
		if archetype == nil then
			report(`WeaponTypeConfig: missing type {typeId}`)
			continue
		end
		for _, stat in WeaponTypeConfig.RolledStats do
			local value = archetype.BaseStats[stat]
			if value == nil or value < WeaponTypeConfig.StatMin or value > WeaponTypeConfig.StatMax then
				report(`WeaponTypeConfig {typeId}: base stat {stat} missing or out of range`)
			end
		end
		if archetype.PrecisionMultiplier < 1 then
			report(`WeaponTypeConfig {typeId}: PrecisionMultiplier below 1`)
		end
		if archetype.AmmoType ~= "Primary" and (archetype.Reserves == nil or archetype.Reserves <= 0) then
			report(`WeaponTypeConfig {typeId}: {archetype.AmmoType} weapons need Reserves`)
		end
		for _, slot in archetype.AllowedSlots do
			if not WEAPON_SLOTS[slot] then
				report(`WeaponTypeConfig {typeId}: unknown slot {slot}`)
			end
		end
	end

	-- Perks --------------------------------------------------------------------------
	local traitCount = 0
	local seenPerks: { [string]: boolean } = {}
	for _, perk in PerkConfig.List do
		if seenPerks[perk.Id] then
			report(`PerkConfig: duplicate perk id {perk.Id}`)
		end
		seenPerks[perk.Id] = true
		if perk.Column == "Trait1" or perk.Column == "Trait2" then
			traitCount += 1
		end
		if #perk.AppliesTo == 0 then
			report(`PerkConfig {perk.Id}: AppliesTo is empty`)
		end
		for _, target in perk.AppliesTo do
			if target ~= "Armor" and WeaponTypeConfig.Types[target] == nil then
				report(`PerkConfig {perk.Id}: unknown weapon type {target}`)
			end
		end
		if perk.StatModifiers then
			for stat in perk.StatModifiers do
				if table.find(WeaponTypeConfig.RolledStats, stat) == nil then
					report(`PerkConfig {perk.Id}: unknown stat {stat}`)
				end
			end
		end
	end
	if traitCount < ConfigValidator.ContentTargets.TraitPerks then
		report(`PerkConfig: only {traitCount} trait perks, want {ConfigValidator.ContentTargets.TraitPerks}`)
	end
	for _, pair in PerkConfig.Synergies do
		local a, b = PerkConfig.ById[pair[1]], PerkConfig.ById[pair[2]]
		if a == nil or b == nil then
			report(`PerkConfig.Synergies: unknown perk in {pair[1]} + {pair[2]}`)
			continue
		end
		if a.Column ~= "Trait1" or b.Column ~= "Trait2" then
			report(`PerkConfig.Synergies: {a.Id} + {b.Id} must be a Trait1 + Trait2 pair`)
		end
		local shared = false
		for _, target in a.AppliesTo do
			if table.find(b.AppliesTo, target) then
				shared = true
				break
			end
		end
		if not shared then
			report(`PerkConfig.Synergies: {a.Id} + {b.Id} never roll on the same weapon type`)
		end
	end

	-- Every column a rarity rolls must have options for every weapon type.
	for _, rarityId in RarityConfig.Order do
		local tier = RarityConfig.Tiers[rarityId]
		for _, typeId in WeaponTypeConfig.Order do
			for _, column in tier.WeaponColumns do
				if #PerkConfig.PoolFor(column, typeId) == 0 then
					report(`PerkConfig: no {column} perks for {typeId} ({rarityId} weapons roll that column)`)
				end
			end
		end
	end

	-- Weapons ------------------------------------------------------------------------
	local seenWeapons: { [string]: boolean } = {}
	local seenNames: { [string]: boolean } = {}
	local exoticCount = 0
	for _, weapon in WeaponConfig.List do
		local where = `WeaponConfig {weapon.Id}`
		if seenWeapons[weapon.Id] then
			report(`{where}: duplicate id`)
		end
		seenWeapons[weapon.Id] = true
		if seenNames[weapon.Name] then
			report(`{where}: duplicate name {weapon.Name}`)
		end
		seenNames[weapon.Name] = true

		local archetype = WeaponTypeConfig.Types[weapon.Type]
		if archetype == nil then
			report(`{where}: unknown type {weapon.Type}`)
			continue
		end
		if RarityConfig.Tiers[weapon.Rarity] == nil then
			report(`{where}: unknown rarity {weapon.Rarity}`)
			continue
		end
		if table.find(archetype.AllowedSlots, weapon.Slot) == nil then
			report(`{where}: {weapon.Type} cannot go in the {weapon.Slot} slot`)
		end
		if ElementConfig.Elements[weapon.Element] == nil then
			report(`{where}: unknown element {weapon.Element}`)
		elseif (weapon.Slot == "Kinetic") ~= (weapon.Element == "Kinetic") then
			report(`{where}: Kinetic slot weapons must be Kinetic element and vice versa`)
		end
		if #weapon.Sources == 0 then
			report(`{where}: no Sources`)
		end
		for _, source in weapon.Sources do
			if not ITEM_SOURCES[source] then
				report(`{where}: unknown source {source}`)
			end
		end
		if weapon.StatBias then
			for stat in weapon.StatBias do
				if table.find(WeaponTypeConfig.RolledStats, stat) == nil then
					report(`{where}: StatBias has unknown stat {stat}`)
				end
			end
		end

		local tier = RarityConfig.Tiers[weapon.Rarity]
		if tier.WeaponPerkMode == "Fixed" and weapon.FixedPerks == nil then
			report(`{where}: {weapon.Rarity} weapons need FixedPerks`)
		end
		if weapon.Rarity == "Exotic" then
			exoticCount += 1
			local signature = false
			for _, perkId in listOf(weapon.FixedPerks) do
				local perk = PerkConfig.ById[perkId]
				if perk and perk.Column == "Exotic" then
					signature = true
				end
			end
			if not signature then
				report(`{where}: exotic weapons need an Exotic signature perk`)
			end
		end
		for _, perkId in listOf(weapon.FixedPerks) do
			local perk = PerkConfig.ById[perkId]
			if perk == nil then
				report(`{where}: unknown perk {perkId}`)
			elseif table.find(perk.AppliesTo, weapon.Type) == nil then
				report(`{where}: perk {perkId} does not apply to {weapon.Type}`)
			elseif perk.Column == "Exotic" and weapon.Rarity ~= "Exotic" then
				report(`{where}: only exotic weapons may use signature perk {perkId}`)
			end
		end
	end
	if #WeaponConfig.List < ConfigValidator.ContentTargets.Weapons then
		report(`WeaponConfig: {#WeaponConfig.List} weapons, want {ConfigValidator.ContentTargets.Weapons}`)
	end
	if exoticCount < ConfigValidator.ContentTargets.ExoticWeapons then
		report(`WeaponConfig: {exoticCount} exotics, want {ConfigValidator.ContentTargets.ExoticWeapons}`)
	end

	-- Armor ---------------------------------------------------------------------------
	for _, armor in ArmorConfig.List do
		local where = `ArmorConfig {armor.Id}`
		if table.find(ArmorConfig.Slots, armor.Slot) == nil then
			report(`{where}: unknown slot {armor.Slot}`)
		end
		if RarityConfig.Tiers[armor.Rarity] == nil then
			report(`{where}: unknown rarity {armor.Rarity}`)
		end
		if armor.ClassRestriction and ClassConfig.ById[armor.ClassRestriction] == nil then
			report(`{where}: unknown class {armor.ClassRestriction}`)
		end
		if armor.Rarity == "Exotic" and (armor.FixedPerks == nil or #armor.FixedPerks == 0) then
			report(`{where}: exotic armor needs a signature perk`)
		end
		for _, perkId in listOf(armor.FixedPerks) do
			local perk = PerkConfig.ById[perkId]
			if perk == nil then
				report(`{where}: unknown perk {perkId}`)
			elseif table.find(perk.AppliesTo, "Armor") == nil then
				report(`{where}: perk {perkId} is not an armor perk`)
			end
		end
		for _, stat in listOf(armor.StatFocus) do
			if ArmorConfig.Stats[stat] == nil then
				report(`{where}: unknown focus stat {stat}`)
			end
		end
		for _, source in armor.Sources do
			if not ITEM_SOURCES[source] then
				report(`{where}: unknown source {source}`)
			end
		end
	end

	-- Classes ---------------------------------------------------------------------------
	for _, class in ClassConfig.List do
		if #class.Subclasses < ConfigValidator.ContentTargets.SubclassesPerClass then
			report(
				`ClassConfig {class.Id}: needs at least {ConfigValidator.ContentTargets.SubclassesPerClass} subclasses`
			)
		end
		for _, subclass in class.Subclasses do
			if ElementConfig.Elements[subclass.Element] == nil or subclass.Element == "Kinetic" then
				report(`ClassConfig {subclass.Id}: subclasses need an energy element`)
			end
		end
	end
	for classId, subclassId in GameConfig.NewPlayer.Subclasses do
		if ClassConfig.ById[classId] == nil or ClassConfig.SubclassOwner[subclassId] ~= classId then
			report(`GameConfig.NewPlayer.Subclasses: {subclassId} is not a {classId} subclass`)
		end
	end
	if ClassConfig.ById[GameConfig.NewPlayer.Class] == nil then
		report(`GameConfig.NewPlayer.Class: unknown class {GameConfig.NewPlayer.Class}`)
	end

	-- Starter loadout ---------------------------------------------------------------------
	for _, slot in PowerConfig.WeaponSlots do
		local defId = GameConfig.NewPlayer.StarterLoadout[slot]
		local weapon = if defId then WeaponConfig.ById[defId] else nil
		if weapon == nil or weapon.Slot ~= slot or weapon.Rarity == "Exotic" then
			report(`GameConfig.NewPlayer.StarterLoadout.{slot}: needs a non-exotic {slot} weapon`)
		end
	end
	for _, slot in PowerConfig.ArmorSlots do
		local defId = GameConfig.NewPlayer.StarterLoadout[slot]
		local armor = if defId then ArmorConfig.ById[defId] else nil
		if armor == nil or armor.Slot ~= slot or armor.Rarity == "Exotic" or armor.ClassRestriction ~= nil then
			report(`GameConfig.NewPlayer.StarterLoadout.{slot}: needs a non-exotic, classless {slot} armor piece`)
		end
	end
	checkCosts("GameConfig.NewPlayer.Currencies", GameConfig.NewPlayer.Currencies)

	-- Enemies ------------------------------------------------------------------------------
	local factionHasFlyer: { [string]: boolean } = {}
	local factionHasBoss: { [string]: boolean } = {}
	local factionCount = 0
	for _ in EnemyConfig.Factions do
		factionCount += 1
	end
	if factionCount < ConfigValidator.ContentTargets.Factions then
		report(`EnemyConfig: {factionCount} factions, want {ConfigValidator.ContentTargets.Factions}`)
	end
	for _, enemy in EnemyConfig.List do
		local where = `EnemyConfig {enemy.Id}`
		if EnemyConfig.Factions[enemy.Faction] == nil then
			report(`{where}: unknown faction {enemy.Faction}`)
		end
		if EnemyConfig.Tiers[enemy.Tier] == nil then
			report(`{where}: unknown tier {enemy.Tier}`)
		end
		if
			enemy.Shield and (enemy.Shield.Element == "Kinetic" or ElementConfig.Elements[enemy.Shield.Element] == nil)
		then
			report(`{where}: shields need an energy element`)
		end
		if enemy.Flying then
			factionHasFlyer[enemy.Faction] = true
		end
		if enemy.Tier == "Boss" then
			factionHasBoss[enemy.Faction] = true
		end
		for _, mechanic in listOf(enemy.Mechanics) do
			for _, add in listOf(mechanic.Enemies) do
				if EnemyConfig.ById[add.Id] == nil then
					report(`{where}: mechanic spawns unknown enemy {add.Id}`)
				end
			end
		end
	end
	for factionId in EnemyConfig.Factions do
		if not factionHasFlyer[factionId] then
			report(`EnemyConfig: faction {factionId} has no flying enemy`)
		end
		if not factionHasBoss[factionId] then
			report(`EnemyConfig: faction {factionId} has no boss`)
		end
	end

	-- Activities ----------------------------------------------------------------------------
	local storyCount, strikeCount = 0, 0
	for _, activity in ActivityConfig.List do
		local where = `ActivityConfig {activity.Id}`
		if activity.Type == "Story" then
			storyCount += 1
		elseif activity.Type == "Strike" then
			strikeCount += 1
		end
		if ActivityConfig.Destinations[activity.Destination] == nil then
			report(`{where}: unknown destination {activity.Destination}`)
		end
		if
			activity.RecommendedPower < PowerConfig.StartingPower
			or activity.RecommendedPower > PowerConfig.PinnacleCap
		then
			report(`{where}: RecommendedPower outside the power range`)
		end
		if activity.MinPlayers < 1 or activity.MinPlayers > activity.MaxPlayers then
			report(`{where}: bad player counts`)
		end
		if LootConfig.Sources[activity.LootSource] == nil then
			report(`{where}: unknown loot source {activity.LootSource}`)
		end
		if AssetIds.Places[activity.Place] == nil then
			report(`{where}: unknown place {activity.Place}`)
		end
		for _, faction in activity.Factions do
			if EnemyConfig.Factions[faction] == nil then
				report(`{where}: unknown faction {faction}`)
			end
		end
		if activity.Unlock and activity.Unlock.Story and ActivityConfig.ById[activity.Unlock.Story] == nil then
			report(`{where}: unlock requires unknown mission {activity.Unlock.Story}`)
		end

		-- `playable` enables the checks the runtime needs (maps, spawns, zones).
		local function checkObjectives(objectives: { ActivityConfig.ObjectiveDef }?, label: string, playable: boolean)
			for _, objective in listOf(objectives) do
				if objective.Enemy and EnemyConfig.ById[objective.Enemy] == nil then
					report(`{label}: objective references unknown enemy {objective.Enemy}`)
				end
				if objective.Faction and EnemyConfig.Factions[objective.Faction] == nil then
					report(`{label}: objective references unknown faction {objective.Faction}`)
				end
				if objective.Mechanic and not BOSS_MECHANICS[objective.Mechanic] then
					report(`{label}: unknown boss mechanic {objective.Mechanic}`)
				end
				if not playable then
					continue
				end
				if objective.Kind == "Boss" and objective.Enemy == nil then
					report(`{label}: Boss objectives need an Enemy`)
				end
				if (objective.Kind == "Travel" or objective.Kind == "Defend") and objective.Target == nil then
					report(`{label}: {objective.Kind} objectives need a Target zone`)
				end
				if objective.Kind == "Defend" and (objective.Duration == nil or objective.Duration <= 0) then
					report(`{label}: Defend objectives need a Duration`)
				end
				if objective.Kind == "Defeat" and #listOf(objective.Spawns) == 0 then
					report(`{label}: Defeat objectives need Spawns`)
				end
				for _, spawn in listOf(objective.Spawns) do
					for _, entry in spawn.Enemies do
						if EnemyConfig.ById[entry.Id] == nil then
							report(`{label}: spawn group {spawn.Group} has unknown enemy {entry.Id}`)
						elseif EnemyConfig.ById[entry.Id].Dummy then
							report(`{label}: spawn group {spawn.Group} spawns a range dummy`)
						end
					end
				end
			end
		end
		checkObjectives(activity.Objectives, where, activity.Playable == true)
		for _, encounter in listOf(activity.Encounters) do
			checkObjectives(encounter.Objectives, `{where}/{encounter.Id}`, encounter.Playable == true)
			if encounter.Milestone and MilestoneConfig.ById[encounter.Milestone] == nil then
				report(`{where}/{encounter.Id}: unknown milestone {encounter.Milestone}`)
			end
			if encounter.Playable and #listOf(encounter.Objectives) == 0 then
				report(`{where}/{encounter.Id}: playable encounters need objectives`)
			end
		end
		for _, difficulty in listOf(activity.Difficulties) do
			for _, milestoneId in listOf(difficulty.Milestones) do
				if MilestoneConfig.ById[milestoneId] == nil then
					report(`{where}/{difficulty.Id}: unknown milestone {milestoneId}`)
				end
			end
		end
		if activity.Playable then
			if activity.Map == nil or table.find(WorldConfig.Maps, activity.Map) == nil then
				report(`{where}: playable activities need a Map from WorldConfig.Maps`)
			end
			if #listOf(activity.Objectives) == 0 and #listOf(activity.Encounters) == 0 then
				report(`{where}: playable activities need objectives or encounters`)
			end
			if activity.Rewards == nil then
				report(`{where}: playable activities need Rewards`)
			end
		end
		if activity.Rewards then
			local drops = activity.Rewards.Drops
			if drops.Min < 0 or drops.Min > drops.Max then
				report(`{where}: Rewards.Drops must satisfy 0 <= Min <= Max`)
			end
			if activity.Rewards.Rarities then
				for rarityId in activity.Rewards.Rarities do
					if RarityConfig.Tiers[rarityId] == nil or rarityId == "Exotic" then
						report(`{where}: Rewards.Rarities has bad rarity {rarityId}`)
					end
				end
			end
		end
		for _, strikeId in listOf(activity.Rotation) do
			local strike = ActivityConfig.ById[strikeId]
			if strike == nil or strike.Type ~= "Strike" then
				report(`{where}: rotation entry {strikeId} is not a strike`)
			end
		end
		if activity.Type == "Raid" and #listOf(activity.Encounters) < ConfigValidator.ContentTargets.RaidEncounters then
			report(`{where}: raids need {ConfigValidator.ContentTargets.RaidEncounters} encounters`)
		end
	end
	if storyCount < ConfigValidator.ContentTargets.StoryMissions then
		report(`ActivityConfig: {storyCount} story missions, want {ConfigValidator.ContentTargets.StoryMissions}`)
	end
	if strikeCount < ConfigValidator.ContentTargets.Strikes then
		report(`ActivityConfig: {strikeCount} strikes, want {ConfigValidator.ContentTargets.Strikes}`)
	end

	for modifierId, modifier in ActivityConfig.NightfallModifiers do
		if modifier.Surge and ElementConfig.Elements[modifier.Surge] == nil then
			report(`ActivityConfig.NightfallModifiers.{modifierId}: unknown surge element {modifier.Surge}`)
		end
	end

	-- Loot, milestones, bounties, vendors --------------------------------------------------
	for sourceId, source in LootConfig.Sources do
		local totalWeight = 0
		for rarityId, weight in source.RarityWeights do
			if RarityConfig.Tiers[rarityId] == nil or rarityId == "Exotic" then
				report(`LootConfig {sourceId}: bad rarity {rarityId} (exotics use ExoticChance)`)
			end
			totalWeight += weight
		end
		if totalWeight <= 0 then
			report(`LootConfig {sourceId}: rarity weights sum to 0`)
		end
		if not ITEM_SOURCES[source.PoolTag] then
			report(`LootConfig {sourceId}: unknown pool tag {source.PoolTag}`)
		end
		-- Every rarity a source can roll needs at least one item to drop.
		for rarityId, weight in source.RarityWeights do
			if weight > 0 and RarityConfig.Tiers[rarityId] then
				local found = false
				for _, weapon in WeaponConfig.List do
					local sources = weapon.Sources
					if
						weapon.Rarity == rarityId
						and (
							table.find(sources, source.PoolTag)
							or (source.IncludeWorldPool and not source.WeaponPoolOnly and table.find(sources, "World"))
						)
					then
						found = true
						break
					end
				end
				for _, armor in ArmorConfig.List do
					local sources = armor.Sources
					if
						not found
						and armor.Rarity == rarityId
						and armor.ClassRestriction == nil
						and (
							table.find(sources, source.PoolTag)
							or (source.IncludeWorldPool and table.find(sources, "World"))
						)
					then
						found = true
					end
				end
				if not found then
					report(`LootConfig {sourceId}: nothing can drop at {rarityId} (add the source tag to some items)`)
				end
			end
		end
	end
	for _, milestone in MilestoneConfig.List do
		local reward = milestone.Reward
		if reward.Kind == "Powerful" then
			local tier = reward.Tier
			if tier == nil or PowerConfig.Powerful.TierBonus[tier] == nil then
				report(`MilestoneConfig {milestone.Id}: Powerful rewards need a valid Tier`)
			end
		end
		if milestone.Track.ActivityId and ActivityConfig.ById[milestone.Track.ActivityId] == nil then
			report(`MilestoneConfig {milestone.Id}: unknown activity {milestone.Track.ActivityId}`)
		end
	end
	for _, bounty in BountyConfig.List do
		checkCosts(`BountyConfig {bounty.Id}`, bounty.Cost)
		local objective = bounty.Objective
		if objective.Faction and EnemyConfig.Factions[objective.Faction] == nil then
			report(`BountyConfig {bounty.Id}: unknown faction {objective.Faction}`)
		end
		if objective.WeaponType and WeaponTypeConfig.Types[objective.WeaponType] == nil then
			report(`BountyConfig {bounty.Id}: unknown weapon type {objective.WeaponType}`)
		end
		if objective.Element and ElementConfig.Elements[objective.Element] == nil then
			report(`BountyConfig {bounty.Id}: unknown element {objective.Element}`)
		end
	end
	for _, vendor in VendorConfig.List do
		for _, stock in listOf(vendor.Stock) do
			checkCosts(`VendorConfig {vendor.Id}`, stock.Price)
			if RarityConfig.Tiers[stock.Rarity] == nil then
				report(`VendorConfig {vendor.Id}: unknown rarity {stock.Rarity}`)
			end
		end
	end
	for rarityId, entry in EconomyConfig.Dismantle do
		checkCosts(`EconomyConfig.Dismantle.{rarityId}`, entry.Give)
		checkCosts(`EconomyConfig.Dismantle.{rarityId}.Bonus`, entry.Bonus)
	end
	for rarityId, cost in EconomyConfig.Infusion do
		checkCosts(`EconomyConfig.Infusion.{rarityId}`, cost)
	end

	-- Input --------------------------------------------------------------------------------
	for action in InputConfig.Keyboard do
		if table.find(InputConfig.Actions, action) == nil then
			report(`InputConfig.Keyboard: unknown action {action}`)
		end
	end
	for action in InputConfig.Gamepad do
		if table.find(InputConfig.Actions, action) == nil then
			report(`InputConfig.Gamepad: unknown action {action}`)
		end
	end

	return problems
end

return ConfigValidator
