--!strict
--[[
	InventoryService
	Every change the inventory screen can make, validated on the server:

	  EquipItem(uid)                put an owned item in its slot. Items in the
	                                vault or postmaster move to the character
	                                first (the postmaster only in the hub).
	                                Class-locked armor must match your class.
	                                Equipping a second Exotic swaps the first
	                                one out for your best non-exotic item.
	  DismantleItem(uid)            destroy an unequipped, unlocked item for
	                                EconomyConfig.Dismantle materials
	  ToggleLock(uid)               lock/unlock (locked items can't be dismantled
	                                or used as infusion fuel)
	  TransferItem(uid, where)      "Vault" or "Inventory" (the 200-slot vault
	                                works anywhere; the postmaster is in the hub)
	  InfuseItem(target, fuel)      at the Gunsmith: the target takes the fuel's
	                                higher power, the fuel is destroyed, costs
	                                EconomyConfig.Infusion[target rarity]
	  MarkSeen(uid)                 clears the "NEW" dot
	  SaveLoadout(i) / ApplyLoadout(i)   three saved equipment presets

	Functions return (ok, message). After a weapon change the live loadout
	(WeaponService) and armor stats (CharacterService) refresh immediately.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Guard = require(Shared.Net.Guard)
local Inventory = require(Shared.Items.Inventory)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local PowerConfig = require(Shared.Config.PowerConfig)
local PowerMath = require(Shared.Power.PowerMath)
local RarityConfig = require(Shared.Config.RarityConfig)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)
local WeaponService = require(script.Parent.WeaponService)
local WorldService = require(script.Parent.WorldService)

type ItemInstance = Types.ItemInstance

local InventoryService = {}

local rng = Random.new()

-- How close to the Gunsmith you must stand to infuse.
local GUNSMITH_RANGE = 30

local function displayName(defId: string): string
	local entry = ItemCatalog.Get(defId)
	if entry and entry.Weapon then
		return entry.Weapon.Name
	elseif entry and entry.Armor then
		return entry.Armor.Name
	end
	return defId
end

local function inHub(player: Player): boolean
	return player:GetAttribute("InstanceId") == nil
end

local function isLimited(item: ItemInstance): boolean
	local tier = RarityConfig.Tiers[item.Rarity]
	return tier ~= nil and tier.EquipLimitPerCategory ~= nil
end

local function refresh(player: Player, item: ItemInstance)
	if item.Kind == "Weapon" then
		WeaponService.RefreshLoadout(player)
	else
		CharacterService.RefreshStats(player)
	end
end

local function setLocation(player: Player, item: ItemInstance, location: Types.ItemLocation)
	if item.Location ~= location then
		DataService.Set(player, { "Items", item.Uid, "Location" }, location)
	end
end

-- The best non-limited (non-exotic) item on the character for `slot`.
local function bestReplacement(data: Types.ProfileData, slot: string, exclude: string): ItemInstance?
	local best: ItemInstance? = nil
	for uid, item in data.Items do
		if uid ~= exclude and item.Slot == slot and item.Location == "Inventory" and not isLimited(item) then
			if best == nil or item.Power > best.Power then
				best = item
			end
		end
	end
	return best
end

-- Equipping --------------------------------------------------------------------------------

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
	local restriction = if entry.Armor then entry.Armor.ClassRestriction else nil
	if restriction ~= nil and restriction ~= data.Class then
		return false, `Only a {restriction} can wear that`
	end
	if item.Location == "Postmaster" and not inHub(player) then
		return false, "Collect it from the Postmaster in the hub first"
	end
	if item.Location ~= "Inventory" and not Inventory.HasRoom(data, "Inventory", item.Slot) then
		-- The item it replaces stays on the character, so the slot needs a free space.
		return false, `Your {item.Slot} slots are full; move something to the vault`
	end

	-- One Exotic weapon and one Exotic armor piece at a time.
	local message: string? = nil
	if isLimited(item) then
		for slot, otherUid in data.Equipped do
			local other = data.Items[otherUid]
			if slot ~= item.Slot and other and other.Kind == item.Kind and isLimited(other) then
				local replacement = bestReplacement(data, slot, otherUid)
				DataService.Set(player, { "Equipped", slot }, if replacement then replacement.Uid else nil)
				message = `Swapped out {displayName(other.DefId)}: only one Exotic {string.lower(item.Kind)} at a time`
			end
		end
	end

	setLocation(player, item, "Inventory")
	DataService.Set(player, { "Equipped", item.Slot }, uid)
	if item.Seen == false then
		DataService.Set(player, { "Items", uid, "Seen" }, true)
	end
	refresh(player, item)
	if message then
		-- The swapped-out slot may be the other kind's refresh target too.
		WeaponService.RefreshLoadout(player)
		CharacterService.RefreshStats(player)
	end
	return true, message
end

-- Dismantling ------------------------------------------------------------------------------

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
	-- Forget it in saved loadouts.
	local loadouts = TableUtil.DeepCopy(data.Loadouts)
	local changed = false
	for _, loadout in loadouts do
		for slot, loadoutUid in loadout.Slots do
			if loadoutUid == uid then
				loadout.Slots[slot] = nil
				changed = true
			end
		end
	end
	if changed then
		DataService.Set(player, { "Loadouts" }, loadouts)
	end
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

-- Lock, move, seen --------------------------------------------------------------------------

function InventoryService.ToggleLock(player: Player, uid: string): (boolean, string?)
	local data = DataService.GetData(player)
	local item = if data then data.Items[uid] else nil
	if item == nil then
		return false, "You don't own that item"
	end
	local locked = not item.Locked
	DataService.Set(player, { "Items", uid, "Locked" }, locked)
	return true, if locked then "Locked" else "Unlocked"
end

function InventoryService.Transfer(player: Player, uid: string, destination: string): (boolean, string?)
	local data = DataService.GetData(player)
	local item = if data then data.Items[uid] else nil
	if data == nil or item == nil then
		return false, "You don't own that item"
	end
	if item.Location == destination then
		return true, nil
	end
	if item.Location == "Postmaster" and not inHub(player) then
		return false, "Visit the Postmaster in the hub"
	end
	if destination == "Vault" then
		if Inventory.IsEquipped(data, uid) then
			return false, "Unequip it first"
		end
		if not Inventory.HasRoom(data, "Vault") then
			return false, `The vault is full ({Inventory.Count(data, "Vault")} items)`
		end
		setLocation(player, item, "Vault")
		return true, `Moved {displayName(item.DefId)} to the vault`
	elseif destination == "Inventory" then
		if not Inventory.HasRoom(data, "Inventory", item.Slot) then
			return false, `Your {item.Slot} slots are full`
		end
		setLocation(player, item, "Inventory")
		return true, `{displayName(item.DefId)} is on your character`
	end
	return false, "Unknown destination"
end

function InventoryService.MarkSeen(player: Player, uid: string)
	local data = DataService.GetData(player)
	local item = if data then data.Items[uid] else nil
	if item and item.Seen == false then
		DataService.Set(player, { "Items", uid, "Seen" }, true)
	end
end

-- Infusion ----------------------------------------------------------------------------------

local function nearGunsmith(player: Player): boolean
	if not inHub(player) then
		return false
	end
	local character = CharacterService.GetCharacter(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local smith = WorldService.GetHub():FindFirstChild("Vendor_GUNSMITH", true)
	if root == nil or not root:IsA("BasePart") or smith == nil or not smith:IsA("BasePart") then
		return false
	end
	return (root.Position - smith.Position).Magnitude <= GUNSMITH_RANGE
end

function InventoryService.Infuse(player: Player, targetUid: string, fuelUid: string): (boolean, string?)
	local data = DataService.GetData(player)
	if data == nil then
		return false, "Data not loaded"
	end
	local target, fuel = data.Items[targetUid], data.Items[fuelUid]
	if target == nil or fuel == nil or targetUid == fuelUid then
		return false, "Pick two different items you own"
	end
	if target.Slot ~= fuel.Slot or target.Kind ~= fuel.Kind then
		return false, "Infusion needs two items for the same slot"
	end
	if fuel.Power <= target.Power then
		return false, "The fuel must have higher power than the target"
	end
	if Inventory.IsEquipped(data, fuelUid) then
		return false, "Unequip the fuel item first"
	end
	if fuel.Locked then
		return false, "The fuel item is locked"
	end
	if not nearGunsmith(player) then
		return false, "Visit the Gunsmith in the Bazaar to infuse"
	end
	local cost: { [string]: number } = EconomyConfig.Infusion[target.Rarity] or {}
	if not DataService.Spend(player, cost) then
		local parts: { string } = {}
		for currency, amount in cost do
			table.insert(parts, `{amount} {currency}`)
		end
		table.sort(parts)
		return false, `Infusion costs {table.concat(parts, ", ")}`
	end
	local newPower = math.min(PowerMath.InfusedPower(target.Power, fuel.Power), PowerConfig.PinnacleCap)
	DataService.RemoveItem(player, fuelUid)
	DataService.Set(player, { "Items", targetUid, "Power" }, newPower)
	if Inventory.IsEquipped(data, targetUid) then
		refresh(player, target)
	end
	return true, `{displayName(target.DefId)} is now {newPower} power`
end

-- Loadouts ----------------------------------------------------------------------------------

function InventoryService.SaveLoadout(player: Player, index: number): (boolean, string?)
	local data = DataService.GetData(player)
	if data == nil or data.Loadouts[index] == nil then
		return false, "Unknown loadout"
	end
	local loadouts = TableUtil.DeepCopy(data.Loadouts)
	loadouts[index].Slots = table.clone(data.Equipped)
	DataService.Set(player, { "Loadouts" }, loadouts)
	return true, `Saved {loadouts[index].Name}`
end

function InventoryService.ApplyLoadout(player: Player, index: number): (boolean, string?)
	local data = DataService.GetData(player)
	local loadout = if data then data.Loadouts[index] else nil
	if data == nil or loadout == nil then
		return false, "Unknown loadout"
	end
	local equipped, failed = 0, 0
	local slots = table.clone(loadout.Slots)
	for _, slot in PowerMath.AllSlots do
		local uid = slots[slot]
		if uid and data.Items[uid] then
			local ok = InventoryService.Equip(player, uid)
			if ok then
				equipped += 1
			else
				failed += 1
			end
		end
	end
	if equipped == 0 and failed == 0 then
		return false, `{loadout.Name} is empty. Save your current gear to it first.`
	end
	return true,
		if failed > 0
			then `Applied {loadout.Name} ({failed} item(s) couldn't be equipped)`
			else `Applied {loadout.Name}`
end

-- Remotes ---------------------------------------------------------------------------------------

function InventoryService.Init()
	local uidCheck = Guard.String(64, 1)
	NetService.OnInvoke("EquipItem", { uidCheck }, function(player: Player, uid: string)
		return InventoryService.Equip(player, uid)
	end)
	NetService.OnInvoke("DismantleItem", { uidCheck }, function(player: Player, uid: string)
		return InventoryService.Dismantle(player, uid)
	end)
	NetService.OnInvoke("ToggleLock", { uidCheck }, function(player: Player, uid: string)
		return InventoryService.ToggleLock(player, uid)
	end)
	NetService.OnInvoke(
		"TransferItem",
		{ uidCheck, Guard.OneOf({ "Vault", "Inventory" }) },
		function(player: Player, uid: string, destination: string)
			return InventoryService.Transfer(player, uid, destination)
		end
	)
	NetService.OnInvoke("InfuseItem", { uidCheck, uidCheck }, function(player: Player, target: string, fuel: string)
		return InventoryService.Infuse(player, target, fuel)
	end)
	NetService.OnInvoke("SaveLoadout", { Guard.Integer(1, 3) }, function(player: Player, index: number)
		return InventoryService.SaveLoadout(player, index)
	end)
	NetService.OnInvoke("ApplyLoadout", { Guard.Integer(1, 3) }, function(player: Player, index: number)
		return InventoryService.ApplyLoadout(player, index)
	end)
	NetService.OnEvent("MarkSeen", { uidCheck }, function(player: Player, uid: string)
		InventoryService.MarkSeen(player, uid)
	end)
end

function InventoryService.Start() end

return InventoryService
