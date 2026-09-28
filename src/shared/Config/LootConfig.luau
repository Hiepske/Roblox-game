--!strict
--[[
	LootConfig
	Drop tables. Each source says how rare its drops are and what kind of
	power reward it is. LootService (Phase 3) rolls:
	  1. rarity from RarityWeights (Exotic is rolled separately via ExoticChance)
	  2. weapon vs armor via ArmorChance
	  3. a def whose Sources include PoolTag (plus "World" items if IncludeWorldPool)
	  4. power from PowerMath.RollDropPower(highest, RewardKind, tier)
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type LootSource = {
	RewardKind: "World" | "Powerful" | "Pinnacle",
	RarityWeights: { [string]: number },
	ExoticChance: number,
	ArmorChance: number,
	-- Items whose def Sources contain this tag can drop here.
	PoolTag: string,
	IncludeWorldPool: boolean,
	-- Weapons only come from PoolTag (armor may still come from the world
	-- pool): gives each mission its own set of guns to chase.
	WeaponPoolOnly: boolean?,
}

local Sources: { [string]: LootSource } = {
	-- Enemy kills and chests anywhere.
	World = {
		RewardKind = "World",
		RarityWeights = { Rare = 70, Epic = 25, Legendary = 5 },
		ExoticChance = 0.002,
		ArmorChance = 0.5,
		PoolTag = "World",
		IncludeWorldPool = true,
	},
	Story = {
		RewardKind = "World",
		RarityWeights = { Rare = 45, Epic = 45, Legendary = 10 },
		ExoticChance = 0.01,
		ArmorChance = 0.4,
		PoolTag = "Story",
		IncludeWorldPool = true,
	},
	-- Story missions: each has its own weapon pool.
	FirstLight = {
		RewardKind = "World",
		RarityWeights = { Rare = 60, Epic = 40 },
		ExoticChance = 0.01,
		ArmorChance = 0.35,
		PoolTag = "FirstLight",
		IncludeWorldPool = true,
		WeaponPoolOnly = true,
	},
	SunkenRelay = {
		RewardKind = "World",
		RarityWeights = { Rare = 50, Epic = 50 },
		ExoticChance = 0.015,
		ArmorChance = 0.35,
		PoolTag = "SunkenRelay",
		IncludeWorldPool = true,
		WeaponPoolOnly = true,
	},
	HollowDark = {
		RewardKind = "World",
		RarityWeights = { Rare = 35, Epic = 50, Legendary = 15 },
		ExoticChance = 0.02,
		ArmorChance = 0.35,
		PoolTag = "HollowDark",
		IncludeWorldPool = true,
		WeaponPoolOnly = true,
	},
	Patrol = {
		RewardKind = "World",
		RarityWeights = { Rare = 50, Epic = 40, Legendary = 10 },
		ExoticChance = 0.005,
		ArmorChance = 0.5,
		PoolTag = "Patrol",
		IncludeWorldPool = true,
	},
	Strike = {
		RewardKind = "World",
		RarityWeights = { Rare = 10, Epic = 50, Legendary = 40 },
		ExoticChance = 0.02,
		ArmorChance = 0.5,
		PoolTag = "Strike",
		IncludeWorldPool = false,
	},
	Nightfall = {
		RewardKind = "World",
		RarityWeights = { Epic = 30, Legendary = 70 },
		ExoticChance = 0.05,
		ArmorChance = 0.4,
		PoolTag = "Nightfall",
		IncludeWorldPool = false,
	},
	Dungeon = {
		RewardKind = "World",
		RarityWeights = { Legendary = 100 },
		ExoticChance = 0.05,
		ArmorChance = 0.5,
		PoolTag = "Dungeon",
		IncludeWorldPool = false,
	},
	Raid = {
		RewardKind = "World",
		RarityWeights = { Legendary = 100 },
		ExoticChance = 0.08,
		ArmorChance = 0.5,
		PoolTag = "Raid",
		IncludeWorldPool = false,
	},
	PvP = {
		RewardKind = "World",
		RarityWeights = { Epic = 50, Legendary = 50 },
		ExoticChance = 0.01,
		ArmorChance = 0.4,
		PoolTag = "PvP",
		IncludeWorldPool = false,
	},
}

return TableUtil.DeepFreeze({
	Sources = Sources,
	-- Chance an enemy of each tier drops gear when killed.
	EnemyGearChance = { Minor = 0.02, Major = 0.1, Boss = 1 },
	-- Ammo brick drop chances per kill by enemy tier.
	AmmoDrops = {
		Special = { Minor = 0.08, Major = 0.35, Boss = 1 },
		Heavy = { Minor = 0.01, Major = 0.08, Boss = 0.5 },
	},
	-- How much of a magazine's reserve an ammo brick restores.
	AmmoBrickFraction = { Special = 0.35, Heavy = 0.25 },
})
