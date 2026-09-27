--!strict
--[[
	ArmorConfig
	Armor slots, stats and every armor piece.

	Stats (original names; the key is the id, DisplayName is what players see):
	  Agility    movement speed and jump height
	  Fortitude  damage reduction
	  Vitality   health regeneration speed
	  Ordnance   grenade cooldown
	  Focus      super charge rate
	  Might      melee cooldown

	Each stat is split into tiers of 10 points (0-10 tiers). A piece rolls a
	stat total from RarityConfig.Tiers[rarity].ArmorTotal and spreads it across
	the six stats, so some pieces are clearly better than others.

	Most armor comes in sets (one piece per slot) generated from Sets below.
	Exotic armor is listed individually and is locked to one class.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Types = require(script.Parent.Parent.Types)

type ArmorDef = Types.ArmorDef

export type StatDef = { DisplayName: string, Description: string }

local Stats: { [string]: StatDef } = {
	Agility = { DisplayName = "Agility", Description = "Movement speed and jump height." },
	Fortitude = { DisplayName = "Fortitude", Description = "Reduces incoming damage." },
	Vitality = { DisplayName = "Vitality", Description = "Faster health regeneration." },
	Ordnance = { DisplayName = "Ordnance", Description = "Faster grenade cooldown." },
	Focus = { DisplayName = "Focus", Description = "Faster super charge." },
	Might = { DisplayName = "Might", Description = "Faster melee cooldown." },
}

local StatOrder = { "Agility", "Fortitude", "Vitality", "Ordnance", "Focus", "Might" }
local Slots: { Types.ArmorSlot } = { "Helmet", "Arms", "Chest", "Legs", "ClassItem" }

-- Per-stat roll bounds on a single piece.
local StatMinPerPiece = 2
local StatMaxPerPiece = 30
local PointsPerTier = 10
local MaxTier = 10

-- What each tier of a stat does (index = tier + 1, so tier 0 is the first entry).
-- Cooldown multipliers < 1 mean faster.
local TierEffects = {
	Agility = { WalkSpeedBonus = 0.4, JumpBonus = 0.3 }, -- per tier, studs/s and studs
	Fortitude = { DamageReductionPerTier = 0.012 }, -- 12% at tier 10
	Vitality = { RegenDelayReductionPerTier = 0.05 }, -- 50% shorter delay at tier 10
	Ordnance = { CooldownScalePerTier = 0.04 },
	Focus = { CooldownScalePerTier = 0.035 },
	Might = { CooldownScalePerTier = 0.04 },
}

-- Armor sets ------------------------------------------------------------------------

type ArmorSet = {
	Id: string,
	Name: string,
	Rarity: Types.Rarity,
	Flavor: string,
	Sources: { string },
	StatFocus: { string }?,
	PieceNames: { [string]: string },
}

local Sets: { ArmorSet } = {
	{
		Id = "FRONTIER",
		Name = "Frontier Issue",
		Rarity = "Rare",
		Flavor = "Spire quartermaster stock. Patched, reliable, everywhere.",
		Sources = { "Starter", "World", "Story" },
		PieceNames = {
			Helmet = "Frontier Issue Helm",
			Arms = "Frontier Issue Gloves",
			Chest = "Frontier Issue Vest",
			Legs = "Frontier Issue Boots",
			ClassItem = "Frontier Issue Mark",
		},
	},
	{
		Id = "WAYFARER",
		Name = "Wayfarer Weave",
		Rarity = "Rare",
		Flavor = "Light layers for long patrols.",
		Sources = { "World", "Patrol" },
		StatFocus = { "Agility", "Vitality" },
		PieceNames = {
			Helmet = "Wayfarer Hood",
			Arms = "Wayfarer Wraps",
			Chest = "Wayfarer Coat",
			Legs = "Wayfarer Striders",
			ClassItem = "Wayfarer Sash",
		},
	},
	{
		Id = "BASTION",
		Name = "Bastion Mk.II",
		Rarity = "Epic",
		Flavor = "The second model. The first one didn't come back.",
		Sources = { "World", "Strike", "Nightfall", "Vendor" },
		StatFocus = { "Fortitude", "Might" },
		PieceNames = {
			Helmet = "Bastion Mk.II Visor",
			Arms = "Bastion Mk.II Gauntlets",
			Chest = "Bastion Mk.II Plate",
			Legs = "Bastion Mk.II Greaves",
			ClassItem = "Bastion Mk.II Crest",
		},
	},
	{
		Id = "TIDEWALKER",
		Name = "Tidewalker Plate",
		Rarity = "Epic",
		Flavor = "Sealed against the black water of Solace Deep.",
		Sources = { "World", "Patrol", "PvP" },
		StatFocus = { "Vitality", "Focus" },
		PieceNames = {
			Helmet = "Tidewalker Mask",
			Arms = "Tidewalker Grips",
			Chest = "Tidewalker Carapace",
			Legs = "Tidewalker Treads",
			ClassItem = "Tidewalker Seal",
		},
	},
	{
		Id = "HALCYON",
		Name = "Halcyon Aegis",
		Rarity = "Legendary",
		Flavor = "Awarded to Keepers who hold the line when the line should not hold.",
		Sources = { "Strike", "Nightfall", "Vendor", "World" },
		PieceNames = {
			Helmet = "Halcyon Aegis Helm",
			Arms = "Halcyon Aegis Gauntlets",
			Chest = "Halcyon Aegis Cuirass",
			Legs = "Halcyon Aegis Greaves",
			ClassItem = "Halcyon Aegis Mantle",
		},
	},
	{
		Id = "CROWNFALL",
		Name = "Crownfall Regalia",
		Rarity = "Legendary",
		Flavor = "Pried from the drowned court. It still hums with the star's last light.",
		Sources = { "Raid" },
		StatFocus = { "Focus", "Ordnance" },
		PieceNames = {
			Helmet = "Crownfall Diadem",
			Arms = "Crownfall Vambraces",
			Chest = "Crownfall Hauberk",
			Legs = "Crownfall Sabatons",
			ClassItem = "Crownfall Sigil",
		},
	},
}

local List: { ArmorDef } = {}

for _, set in Sets do
	for _, slot in Slots do
		local piece: ArmorDef = {
			Id = `A_{set.Id}_{string.upper(slot)}`,
			Name = set.PieceNames[slot],
			Flavor = set.Flavor,
			Rarity = set.Rarity,
			Slot = slot :: Types.ArmorSlot,
			SetId = set.Id,
			Sources = set.Sources,
			StatFocus = set.StatFocus,
			Model = `Armor_{set.Id}_{slot}`,
		}
		table.insert(List, piece)
	end
end

-- Exotic armor (one per piece, class-locked) ---------------------------------------------

local Exotics: { ArmorDef } = {
	{
		Id = "A_EXO_ANVIL_CROWN",
		Name = "Anvil Crown",
		Flavor = "Struck on the same anvil as the Spire's first wall.",
		Rarity = "Exotic",
		Slot = "Helmet",
		ClassRestriction = "Bulwark",
		Sources = { "ExoticPool" },
		FixedPerks = { "EXA_ANVIL_CROWN" },
		StatFocus = { "Fortitude" },
		Model = "Armor_Exotic_AnvilCrown",
	},
	{
		Id = "A_EXO_HEARTHGUARD",
		Name = "Hearthguard Gauntlets",
		Flavor = "Warm to the touch, even in the void between worlds.",
		Rarity = "Exotic",
		Slot = "Arms",
		ClassRestriction = "Bulwark",
		Sources = { "ExoticPool" },
		FixedPerks = { "EXA_HEARTHGUARD" },
		StatFocus = { "Might" },
		Model = "Armor_Exotic_Hearthguard",
	},
	{
		Id = "A_EXO_QUICKSTEP",
		Name = "Quickstep Striders",
		Flavor = "Never where the bullet lands.",
		Rarity = "Exotic",
		Slot = "Legs",
		ClassRestriction = "Ranger",
		Sources = { "ExoticPool" },
		FixedPerks = { "EXA_QUICKSTEP" },
		StatFocus = { "Agility" },
		Model = "Armor_Exotic_Quickstep",
	},
	{
		Id = "A_EXO_UNSEEN_VEIL",
		Name = "Veil of the Unseen",
		Flavor = "Stitched from fog harvested on Hollowmere.",
		Rarity = "Exotic",
		Slot = "Chest",
		ClassRestriction = "Ranger",
		Sources = { "Nightfall", "ExoticPool" },
		FixedPerks = { "EXA_UNSEEN_VEIL" },
		StatFocus = { "Vitality" },
		Model = "Armor_Exotic_UnseenVeil",
	},
	{
		Id = "A_EXO_EMBER_CROWN",
		Name = "Crown of Kindling",
		Flavor = "Thoughts become sparks. Sparks become fire.",
		Rarity = "Exotic",
		Slot = "Helmet",
		ClassRestriction = "Mystic",
		Sources = { "ExoticPool" },
		FixedPerks = { "EXA_EMBER_CROWN" },
		StatFocus = { "Ordnance" },
		Model = "Armor_Exotic_EmberCrown",
	},
	{
		Id = "A_EXO_WEAVERS_GRASP",
		Name = "Weaver's Grasp",
		Flavor = "Every strike a thread; every thread a snare.",
		Rarity = "Exotic",
		Slot = "Arms",
		ClassRestriction = "Mystic",
		Sources = { "Dungeon", "ExoticPool" },
		FixedPerks = { "EXA_WEAVERS_GRASP" },
		StatFocus = { "Might" },
		Model = "Armor_Exotic_WeaversGrasp",
	},
}

for _, exotic in Exotics do
	table.insert(List, exotic)
end

local ById: { [string]: ArmorDef } = {}
for _, armor in List do
	ById[armor.Id] = armor
end

return TableUtil.DeepFreeze({
	Stats = Stats,
	StatOrder = StatOrder,
	Slots = Slots,
	StatMinPerPiece = StatMinPerPiece,
	StatMaxPerPiece = StatMaxPerPiece,
	PointsPerTier = PointsPerTier,
	MaxTier = MaxTier,
	TierEffects = TierEffects,
	Sets = Sets,
	List = List,
	ById = ById,
})
