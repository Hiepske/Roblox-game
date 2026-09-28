-- InventoryService rules with its collaborators faked.
local roblox = require("@lune/roblox")
local Shared = game.ReplicatedStorage.Shared
local Server = game.ServerScriptService
local ItemRoller = require(Shared.Items.ItemRoller)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local TableUtil = require(Shared.Util.TableUtil)

local counter = 0
local function uid()
	counter += 1
	return "uid-" .. counter
end

local data
local player = { Name = "Tester", Attributes = {} }
function player:GetAttribute(key)
	return self.Attributes[key]
end

local refreshed = { Weapons = 0, Armor = 0 }
VirtualGame.Preload(Server.Services.DataService, {
	GetData = function()
		return data
	end,
	Set = function(_, path, value)
		TableUtil.SetPath(data, path, value)
	end,
	RemoveItem = function(_, itemUid)
		for slot, equipped in data.Equipped do
			if equipped == itemUid then
				data.Equipped[slot] = nil
			end
		end
		local item = data.Items[itemUid]
		data.Items[itemUid] = nil
		return item
	end,
	AddCurrency = function(_, currency, amount)
		data.Currencies[currency] = (data.Currencies[currency] or 0) + amount
		return true, data.Currencies[currency]
	end,
	Spend = function(_, costs)
		for currency, amount in costs do
			if (data.Currencies[currency] or 0) < amount then
				return false
			end
		end
		for currency, amount in costs do
			data.Currencies[currency] -= amount
		end
		return true
	end,
})
VirtualGame.Preload(Server.Services.NetService, { OnInvoke = function() end, OnEvent = function() end })
VirtualGame.Preload(Server.Services.WeaponService, {
	RefreshLoadout = function()
		refreshed.Weapons += 1
	end,
})
local characterPosition = roblox.Vector3.new(0, 0, 0)
local function fakePart(position)
	return {
		Position = position,
		IsA = function(_, className)
			return className == "BasePart"
		end,
	}
end
VirtualGame.Preload(Server.Services.CharacterService, {
	RefreshStats = function()
		refreshed.Armor += 1
	end,
	GetCharacter = function()
		return {
			FindFirstChild = function()
				return fakePart(characterPosition)
			end,
		}
	end,
})
VirtualGame.Preload(Server.Services.WorldService, {
	GetHub = function()
		return {
			FindFirstChild = function(_, name)
				return if name == "Vendor_GUNSMITH" then fakePart(roblox.Vector3.new(160, -28, -60)) else nil
			end,
		}
	end,
})

local InventoryService = require(Server.Services.InventoryService)

local function fresh()
	data = ProfileTemplate.CreateNew(0, uid, VirtualGame.Random.new(3))
	player.Attributes = {}
end

local function give(defId, power, location)
	local item = ItemRoller.Roll(defId, power, VirtualGame.Random.new(counter + 7), uid(), 0, "Random")
	item.Location = location or "Inventory"
	data.Items[item.Uid] = item
	return item
end

describe("Inventory", function()
	it("equips a spare and keeps the old one on the character", function()
		fresh()
		local old = data.Equipped.Kinetic
		local spare = give("W_FRONTIER_STANDARD", 355)
		local ok = InventoryService.Equip(player, spare.Uid)
		expect(ok).toBe(true)
		expect(data.Equipped.Kinetic).toBe(spare.Uid)
		expect(data.Items[old].Location).toBe("Inventory")
		expect(refreshed.Weapons > 0).toBe(true)
	end)

	it("equips straight from the vault when the slot has room", function()
		fresh()
		local stored = give("W_FRONTIER_STANDARD", 360, "Vault")
		expect(InventoryService.Equip(player, stored.Uid)).toBe(true)
		expect(stored.Location).toBe("Inventory")
		expect(data.Equipped.Kinetic).toBe(stored.Uid)
	end)

	it("refuses when the slot is full, until something goes to the vault", function()
		fresh()
		for _ = 1, 9 do
			give("W_FRONTIER_STANDARD", 350)
		end
		local stored = give("W_FRONTIER_STANDARD", 360, "Vault")
		local ok, message = InventoryService.Equip(player, stored.Uid)
		expect(ok).toBe(false)
		expect(message:find("full") ~= nil).toBe(true)
	end)

	it("only allows postmaster pulls in the hub", function()
		fresh()
		local mail = give("W_FRONTIER_STANDARD", 352, "Postmaster")
		player.Attributes.InstanceId = "R1"
		expect(InventoryService.Transfer(player, mail.Uid, "Inventory")).toBe(false)
		player.Attributes.InstanceId = nil
		expect(InventoryService.Transfer(player, mail.Uid, "Inventory")).toBe(true)
		expect(mail.Location).toBe("Inventory")
	end)

	it("swaps out the first exotic when a second one is equipped", function()
		fresh()
		local exoticA, exoticB
		for _, defId in { "W_EXO_EMBERWAKE", "W_EXO_STILLWATER" } do
			local ok, entry = pcall(function()
				return give(defId, 355)
			end)
			if ok and entry then
				if exoticA == nil then
					exoticA = entry
				else
					exoticB = entry
				end
			end
		end
		if exoticA == nil or exoticB == nil or exoticA.Slot == exoticB.Slot then
			-- Fall back to any two exotics in different weapon slots.
			for defId, entry in require(Shared.Items.ItemCatalog).All() do
				if entry.Weapon and entry.Weapon.Rarity == "Exotic" then
					if exoticA == nil then
						exoticA = give(defId, 355)
					elseif exoticB == nil and entry.Weapon.Slot ~= exoticA.Slot then
						exoticB = give(defId, 355)
					end
				end
			end
		end
		expect(InventoryService.Equip(player, exoticA.Uid)).toBe(true)
		local ok, message = InventoryService.Equip(player, exoticB.Uid)
		expect(ok).toBe(true)
		expect(message:find("only one Exotic") ~= nil).toBe(true)
		expect(data.Equipped[exoticB.Slot]).toBe(exoticB.Uid)
		expect(data.Equipped[exoticA.Slot] ~= exoticA.Uid).toBe(true)
	end)

	it("locks items so they can't be dismantled, and dismantling forgets loadouts", function()
		fresh()
		local spare = give("W_FRONTIER_STANDARD", 351)
		InventoryService.ToggleLock(player, spare.Uid)
		expect(InventoryService.Dismantle(player, spare.Uid)).toBe(false)
		InventoryService.ToggleLock(player, spare.Uid)
		data.Loadouts[1].Slots.Kinetic = spare.Uid
		local quanta = data.Currencies.Quanta
		expect(InventoryService.Dismantle(player, spare.Uid)).toBe(true)
		expect(data.Items[spare.Uid]).toBeNil()
		expect(data.Loadouts[1].Slots.Kinetic).toBeNil()
		expect(data.Currencies.Quanta > quanta).toBe(true)
	end)

	it("infuses only at the Gunsmith, for a price", function()
		fresh()
		local target = data.Items[data.Equipped.Kinetic]
		local fuel = give("W_FRONTIER_STANDARD", 372)
		data.Currencies.Quanta = 100000
		characterPosition = roblox.Vector3.new(0, 0, 0)
		local ok, message = InventoryService.Infuse(player, target.Uid, fuel.Uid)
		expect(ok).toBe(false)
		expect(message:find("Gunsmith") ~= nil).toBe(true)
		characterPosition = roblox.Vector3.new(158, -28, -55)
		ok = InventoryService.Infuse(player, target.Uid, fuel.Uid)
		expect(ok).toBe(true)
		expect(target.Power).toBe(372)
		expect(data.Items[fuel.Uid]).toBeNil()
		expect(data.Currencies.Quanta < 100000).toBe(true)
	end)

	it("saves and applies loadouts", function()
		fresh()
		local original = data.Equipped.Kinetic
		expect(InventoryService.SaveLoadout(player, 2)).toBe(true)
		local spare = give("W_FRONTIER_STANDARD", 356)
		InventoryService.Equip(player, spare.Uid)
		expect(data.Equipped.Kinetic).toBe(spare.Uid)
		expect(InventoryService.ApplyLoadout(player, 2)).toBe(true)
		expect(data.Equipped.Kinetic).toBe(original)
		expect(InventoryService.ApplyLoadout(player, 3)).toBe(false) -- empty
	end)

	it("clears the NEW flag", function()
		fresh()
		local drop = give("W_FRONTIER_STANDARD", 353)
		drop.Seen = false
		InventoryService.MarkSeen(player, drop.Uid)
		expect(drop.Seen).toBe(true)
	end)
end)
