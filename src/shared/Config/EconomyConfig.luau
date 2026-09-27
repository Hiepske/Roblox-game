--!strict
--[[
	EconomyConfig
	Currencies, dismantling, infusion and gunsmith costs.

	  Quanta     common currency (vendors, bounties, infusion)
	  Alloy      resonant alloy from dismantling Epic+ gear
	  Fluxite    upgrade material: infusion and masterworks
	  Starglass  rare material for exotic purchases and upgrades
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type CurrencyDef = {
	Name: string,
	Description: string,
	Cap: number,
	Color: Color3,
}

local Currencies: { [string]: CurrencyDef } = {
	Quanta = {
		Name = "Quanta",
		Description = "Common currency accepted by every vendor in Haven Spire.",
		Cap = 250000,
		Color = Color3.fromRGB(120, 220, 255),
	},
	Alloy = {
		Name = "Resonant Alloy",
		Description = "Refined from dismantled Epic and better gear.",
		Cap = 20000,
		Color = Color3.fromRGB(200, 170, 255),
	},
	Fluxite = {
		Name = "Fluxite",
		Description = "Unstable crystal used to infuse and masterwork gear.",
		Cap = 200,
		Color = Color3.fromRGB(120, 255, 190),
	},
	Starglass = {
		Name = "Starglass",
		Description = "A shard of fallen starlight. Exotic smiths want nothing else.",
		Cap = 50,
		Color = Color3.fromRGB(255, 225, 110),
	},
}

-- Guaranteed amounts, plus optional { Chance, Amount } bonus rolls.
export type DismantleEntry = {
	Give: { [string]: number },
	Bonus: { [string]: { Chance: number, Amount: number } },
}

local Dismantle: { [string]: DismantleEntry } = {
	Rare = { Give = { Quanta = 250 }, Bonus = {} },
	Epic = { Give = { Quanta = 500, Alloy = 2 }, Bonus = {} },
	Legendary = {
		Give = { Quanta = 1000, Alloy = 8 },
		Bonus = { Fluxite = { Chance = 0.25, Amount = 1 } },
	},
	Exotic = { Give = { Quanta = 1500, Starglass = 1 }, Bonus = {} },
}

-- Cost to infuse INTO an item of this rarity (the target keeps its roll and
-- takes the fodder's power; the fodder is destroyed).
local Infusion: { [string]: { [string]: number } } = {
	Rare = { Quanta = 500 },
	Epic = { Quanta = 1500, Alloy = 5 },
	Legendary = { Quanta = 5000, Fluxite = 1 },
	Exotic = { Quanta = 7500, Fluxite = 1, Starglass = 1 },
}

local Gunsmith = {
	-- Reroll one perk column on an Epic/Legendary weapon.
	RerollColumn = { Epic = { Quanta = 2500, Alloy = 10 }, Legendary = { Quanta = 5000, Alloy = 20 } },
	-- Apply a masterwork (Legendary/Exotic weapons without one).
	Masterwork = {
		Legendary = { Quanta = 10000, Fluxite = 5 },
		Exotic = { Quanta = 10000, Fluxite = 3, Starglass = 1 },
	},
	-- Change which stat an existing masterwork boosts.
	ChangeMasterwork = { Quanta = 2500, Fluxite = 1 },
}

return TableUtil.DeepFreeze({
	Currencies = Currencies,
	Order = { "Quanta", "Alloy", "Fluxite", "Starglass" },
	Dismantle = Dismantle,
	Infusion = Infusion,
	Gunsmith = Gunsmith,
})
