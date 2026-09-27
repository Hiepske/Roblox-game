--!strict
--[[
	InventoryService
	Equipping and dismantling gear from the character screen.

	  EquipItem(uid)      puts an owned item in its gear slot. Items waiting
	                      in the postmaster move to the inventory first.
	                      Rules: class-locked armor must match your class,
	                      and only one Exotic weapon and one Exotic armor
	                      piece can be equipped at a time.
	  DismantleItem(uid)  destroys an unequipped, unlocked item for
	                      EconomyConfig.Dismantle materials.

	Both are RemoteFunctions returning (ok, message). After a weapon change
	the live loadout (WeaponService) and armor stats (CharacterService) are
	refreshed immediately.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Guard = require(Shared.Net.Guard)
local Inventory = require(Shared.Items.Inventory)
local ItemCatalog = require(Shared.Items.ItemCatalog)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)
local WeaponService = require(script.Parent.WeaponService)

local InventoryService = {}

local rng = Random.new()

local function displayName(defId: string): string
	local entry = ItemCatalog.Get(defId)
	if entry and entry.Weapon then
		return entry.Weapon.Name
	elseif entry and entry.Armor then
		return entry.Armor.Name
	end
	return defId
end

-- (ok, message). Also used by the /give dev command to auto-equip.
function InventoryService.Equip(player: Player, uid: string): (boolean, string?)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Data not loaded"
	end
	local item = data.Items[uid]
	if item == nil then
		return false, "You don't own that item"
	end
	local entry = ItemCatalog.Get(item.DefId)
	if entry == nil then
		return false, "Unknown item"
	end
	if data.Equipped[item.Slot] == uid then
		return true, nil
	end
	if item.Location == "Vault" then
		return false, "Pull it from the vault first"
	end

	local restriction = if entry.Armor then entry.Armor.ClassRestriction else nil
	if restriction ~= nil and restriction ~= data.Class then
		return false, `Only a {restriction} can wear that`
	end
	if item.Rarity == "Exotic" then
		for slot, otherUid in data.Equipped do
			local other = data.Items[otherUid]
			if slot ~= item.Slot and other and other.Rarity == "Exotic" and other.Kind == item.Kind then
				return false, `Only one Exotic {string.lower(item.Kind)} can be equipped ({displayName(other.DefId)})`
			end
		end
	end

	if item.Location == "Postmaster" then
		-- The item that gets unequipped stays in the inventory, so the slot
		-- needs room for one more.
		if not Inventory.HasRoom(data, "Inventory", item.Slot) then
			return false, "No room in that inventory slot"
		end
		DataService.Set(player, { "Items", uid, "Location" }, "Inventory")
	end

	DataService.Set(player, { "Equipped", item.Slot }, uid)
	if item.Kind == "Weapon" then
		WeaponService.RefreshLoadout(player)
	else
		CharacterService.RefreshStats(player)
	end
	return true, nil
end

function InventoryService.Dismantle(player: Player, uid: string): (boolean, string?)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Data not loaded"
	end
	local item = data.Items[uid]
	if item == nil then
		return false, "You don't own that item"
	end
	if Inventory.IsEquipped(data, uid) then
		return false, "Unequip it first"
	end
	if item.Locked then
		return false, "That item is locked"
	end
	local reward = EconomyConfig.Dismantle[item.Rarity]
	DataService.RemoveItem(player, uid)
	local gained: { string } = {}
	if reward then
		for currency, amount in reward.Give do
			DataService.AddCurrency(player, currency, amount)
			table.insert(gained, `+{amount} {currency}`)
		end
		for currency, bonus in reward.Bonus do
			if rng:NextNumber() < bonus.Chance then
				DataService.AddCurrency(player, currency, bonus.Amount)
				table.insert(gained, `+{bonus.Amount} {currency}`)
			end
		end
	end
	table.sort(gained)
	return true, `Dismantled {displayName(item.DefId)}  {table.concat(gained, "  ")}`
end

function InventoryService.Init()
	NetService.OnInvoke("EquipItem", { Guard.String(64, 1) }, function(player: Player, uid: string)
		return InventoryService.Equip(player, uid)
	end)
	NetService.OnInvoke("DismantleItem", { Guard.String(64, 1) }, function(player: Player, uid: string)
		return InventoryService.Dismantle(player, uid)
	end)
end

function InventoryService.Start() end

return InventoryService
