--!strict
--[[
	ItemCatalog
	One lookup across weapon and armor defs, so code holding a DefId doesn't
	need to know which config it lives in.
]]

local Config = script.Parent.Parent.Config
local ArmorConfig = require(Config.ArmorConfig)
local Types = require(script.Parent.Parent.Types)
local WeaponConfig = require(Config.WeaponConfig)

export type Entry = {
	Kind: Types.ItemKind,
	Weapon: Types.WeaponDef?,
	Armor: Types.ArmorDef?,
	Name: string,
	Rarity: Types.Rarity,
	Slot: Types.GearSlot,
}

local entries: { [string]: Entry } = {}

for id, weapon in WeaponConfig.ById do
	entries[id] = {
		Kind = "Weapon",
		Weapon = weapon,
		Name = weapon.Name,
		Rarity = weapon.Rarity,
		Slot = weapon.Slot,
	}
end

for id, armor in ArmorConfig.ById do
	entries[id] = {
		Kind = "Armor",
		Armor = armor,
		Name = armor.Name,
		Rarity = armor.Rarity,
		Slot = armor.Slot,
	}
end

table.freeze(entries)

local ItemCatalog = {}

function ItemCatalog.Get(defId: string): Entry?
	return entries[defId]
end

function ItemCatalog.All(): { [string]: Entry }
	return entries
end

return ItemCatalog
