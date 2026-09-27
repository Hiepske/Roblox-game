--!strict
--[[
	Inventory
	Read-only helpers over ProfileData item storage. Mutations happen on the
	server (DataService); these helpers are shared so the client UI shows the
	same capacities the server enforces.

	Buckets:
	  Inventory   on the character; SlotCapacity per gear slot plus the equipped item
	  Vault       account storage, VaultCapacity items total
	  Postmaster  overflow for drops when the slot is full, PostmasterCapacity total
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Types = require(script.Parent.Parent.Types)

type ProfileData = Types.ProfileData

local Inventory = {}

function Inventory.IsEquipped(data: ProfileData, uid: string): boolean
	for _, equippedUid in data.Equipped do
		if equippedUid == uid then
			return true
		end
	end
	return false
end

-- Items in `location`, optionally only those for one gear slot. Equipped
-- items are not counted against the character's slot capacity.
function Inventory.Count(data: ProfileData, location: Types.ItemLocation, slot: string?): number
	local count = 0
	for uid, item in data.Items do
		if item.Location == location and (slot == nil or item.Slot == slot) then
			if not (location == "Inventory" and Inventory.IsEquipped(data, uid)) then
				count += 1
			end
		end
	end
	return count
end

function Inventory.HasRoom(data: ProfileData, location: Types.ItemLocation, slot: string?): boolean
	local capacity = GameConfig.Inventory
	if location == "Inventory" then
		assert(slot ~= nil, "Inventory capacity is per slot")
		return Inventory.Count(data, "Inventory", slot) < capacity.SlotCapacity
	elseif location == "Vault" then
		return Inventory.Count(data, "Vault") < capacity.VaultCapacity
	end
	return Inventory.Count(data, "Postmaster") < capacity.PostmasterCapacity
end

-- Where a newly dropped item should go: the character if the slot has room,
-- otherwise the postmaster. nil when both are full.
function Inventory.ResolveDropLocation(data: ProfileData, slot: string): Types.ItemLocation?
	if Inventory.HasRoom(data, "Inventory", slot) then
		return "Inventory"
	elseif Inventory.HasRoom(data, "Postmaster") then
		return "Postmaster"
	end
	return nil
end

return Inventory
