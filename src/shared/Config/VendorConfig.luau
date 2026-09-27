--!strict
--[[
	VendorConfig
	Haven Spire vendors (Phase 5 builds their NPCs and screens).

	Service says which system backs the vendor's screen:
	  Shop        sells Stock items for currency
	  Gunsmith    perk reroll, infusion, masterwork (EconomyConfig.Gunsmith)
	  Bounties    daily/weekly bounties (BountyConfig)
	  Postmaster  overflow drops (GameConfig.Inventory.PostmasterCapacity)
	  Vault       account storage (GameConfig.Inventory.VaultCapacity)
	  Playlist    launches strikes / the weekly hardened strike

	Stock entries pick a random def from Pool (a Source tag) at the given
	rarity each weekly reset; Price is per item.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type StockEntry = {
	Kind: "Weapon" | "Armor",
	Rarity: string,
	Pool: string,
	Count: number,
	Price: { [string]: number },
}

export type VendorDef = {
	Id: string,
	Name: string,
	Title: string,
	Service: "Shop" | "Gunsmith" | "Bounties" | "Postmaster" | "Vault" | "Playlist",
	Greeting: string,
	-- Name of the NPC/anchor part in the hub map.
	Anchor: string,
	Stock: { StockEntry }?,
}

local List: { VendorDef } = {
	{
		Id = "WEAPONS",
		Name = "Ilsa Varn",
		Title = "Quartermaster",
		Service = "Shop",
		Greeting = "Every gun on this rack has kept someone alive. Pick one that'll do the same for you.",
		Anchor = "Vendor_Weapons",
		Stock = {
			{ Kind = "Weapon", Rarity = "Epic", Pool = "Vendor", Count = 3, Price = { Quanta = 3000 } },
			{
				Kind = "Weapon",
				Rarity = "Legendary",
				Pool = "Vendor",
				Count = 2,
				Price = { Quanta = 9000, Alloy = 25 },
			},
		} :: { StockEntry },
	},
	{
		Id = "ARMOR",
		Name = "Brannoc Hale",
		Title = "Outfitter",
		Service = "Shop",
		Greeting = "Plate, weave or both. Just don't bring it back full of holes.",
		Anchor = "Vendor_Armor",
		Stock = {
			{ Kind = "Armor", Rarity = "Epic", Pool = "Vendor", Count = 3, Price = { Quanta = 2500 } },
			{ Kind = "Armor", Rarity = "Legendary", Pool = "Vendor", Count = 2, Price = { Quanta = 8000, Alloy = 20 } },
		} :: { StockEntry },
	},
	{
		Id = "STRIKES",
		Name = "Commander Oreth Vale",
		Title = "Strike Commander",
		Service = "Playlist",
		Greeting = "Three Keepers, one target, no retreat. Report in when it's done.",
		Anchor = "Vendor_Strikes",
	},
	{
		Id = "GUNSMITH",
		Name = "Tamsin Rook",
		Title = "Gunsmith",
		Service = "Gunsmith",
		Greeting = "Bring me a gun and a reason. I'll make it sing.",
		Anchor = "Vendor_Gunsmith",
	},
	{
		Id = "BOUNTIES",
		Name = "The Contract Board",
		Title = "Bounties",
		Service = "Bounties",
		Greeting = "Fresh contracts posted every reset.",
		Anchor = "Vendor_Bounties",
	},
	{
		Id = "POSTMASTER",
		Name = "Pim",
		Title = "Courier Depot",
		Service = "Postmaster",
		Greeting = "You dropped these. Out there. While being shot at. Sign here.",
		Anchor = "Vendor_Postmaster",
	},
	{
		Id = "VAULT",
		Name = "Deep Vault",
		Title = "Storage",
		Service = "Vault",
		Greeting = "Access granted.",
		Anchor = "Vendor_Vault",
	},
}

local ById: { [string]: VendorDef } = {}
for _, vendor in List do
	ById[vendor.Id] = vendor
end

return TableUtil.DeepFreeze({
	List = List,
	ById = ById,
})
