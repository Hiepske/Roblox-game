--!strict
--[[
	RarityConfig
	Rarity tiers, their colors and how items of each tier roll.

	Weapon stats roll as: archetype base + weapon bias + random(StatRoll.Min, StatRoll.Max)
	so low rolls exist on purpose ("trash" worth dismantling).
	Armor rolls a stat total in ArmorTotal, spread across the six armor stats.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type RarityTier = {
	DisplayName: string,
	Rank: number,
	Color: Color3,
	-- How weapon perks are chosen:
	-- "Random1": one perk drawn from the Trait1 + Trait2 pools
	-- "Columns": one perk per column listed in WeaponColumns
	-- "Fixed": the weapon def's FixedPerks (exotics)
	WeaponPerkMode: "Random1" | "Columns" | "Fixed",
	WeaponColumns: { string },
	-- Can the Gunsmith apply a masterwork, and does a fresh drop come with one?
	CanMasterwork: boolean,
	MasterworkOnDrop: boolean,
	-- Only this many items of the rarity may be equipped per category
	-- (weapons / armor). nil = unlimited.
	EquipLimitPerCategory: number?,
	WeaponStatRoll: { Min: number, Max: number },
	ArmorTotal: { Min: number, Max: number },
}

local Order = { "Rare", "Epic", "Legendary", "Exotic" }

local Tiers: { [string]: RarityTier } = {
	Rare = {
		DisplayName = "Rare",
		Rank = 1,
		Color = Color3.fromRGB(80, 140, 255),
		WeaponPerkMode = "Random1",
		WeaponColumns = {},
		CanMasterwork = false,
		MasterworkOnDrop = false,
		WeaponStatRoll = { Min = -15, Max = 5 },
		ArmorTotal = { Min = 34, Max = 46 },
	},
	Epic = {
		DisplayName = "Epic",
		Rank = 2,
		Color = Color3.fromRGB(165, 90, 235),
		WeaponPerkMode = "Columns",
		WeaponColumns = { "Trait1", "Trait2" },
		CanMasterwork = false,
		MasterworkOnDrop = false,
		WeaponStatRoll = { Min = -10, Max = 8 },
		ArmorTotal = { Min = 42, Max = 54 },
	},
	Legendary = {
		DisplayName = "Legendary",
		Rank = 3,
		Color = Color3.fromRGB(240, 150, 40),
		WeaponPerkMode = "Columns",
		WeaponColumns = { "Barrel", "Magazine", "Trait1", "Trait2" },
		CanMasterwork = true,
		MasterworkOnDrop = true,
		WeaponStatRoll = { Min = -6, Max = 10 },
		ArmorTotal = { Min = 50, Max = 64 },
	},
	Exotic = {
		DisplayName = "Exotic",
		Rank = 4,
		Color = Color3.fromRGB(255, 222, 60),
		WeaponPerkMode = "Fixed",
		WeaponColumns = {},
		CanMasterwork = true,
		MasterworkOnDrop = false,
		EquipLimitPerCategory = 1,
		WeaponStatRoll = { Min = 0, Max = 6 },
		ArmorTotal = { Min = 56, Max = 68 },
	},
}

-- Masterworks add this much to one weapon stat.
local MasterworkBonus = 10
local MasterworkStats = { "Range", "Stability", "Handling", "Reload" }

return TableUtil.DeepFreeze({
	Order = Order,
	Tiers = Tiers,
	MasterworkBonus = MasterworkBonus,
	MasterworkStats = MasterworkStats,
})
