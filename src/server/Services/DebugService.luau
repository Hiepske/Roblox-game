--!strict
--[[
	DebugService
	Developer commands for testing data and progression without playing
	through content. Only players with debug access can use them:
	  * anyone in Studio (GameConfig.Debug.AllowInStudio)
	  * UserIds in GameConfig.Debug.AdminUserIds in live servers
	Anyone else sending a debug command is flagged by NetService.

	The client's developer panel (DebugPanelController) sends these through
	the DebugCommand remote: DebugCommand(command, stringArg?, numberArg?).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ClassConfig = require(Shared.Config.ClassConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Guard = require(Shared.Net.Guard)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRoller = require(Shared.Items.ItemRoller)
local PowerMath = require(Shared.Power.PowerMath)
local RarityConfig = require(Shared.Config.RarityConfig)

local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)

local DebugService = {}

local rng = Random.new()

function DebugService.HasAccess(player: Player): boolean
	local debugConfig = GameConfig.Debug
	if not debugConfig.Enabled then
		return false
	end
	if debugConfig.AllowInStudio and RunService:IsStudio() then
		return true
	end
	return table.find(debugConfig.AdminUserIds, player.UserId) ~= nil
end

local function randomDefOfRarity(rarity: string?): string?
	local candidates: { string } = {}
	for defId, entry in ItemCatalog.All() do
		if rarity == nil or entry.Rarity == rarity then
			table.insert(candidates, defId)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates) -- stable order so the rng is the only randomness
	return candidates[rng:NextInteger(1, #candidates)]
end

local function grantRandomItem(player: Player, rarity: string?, rewardKind: "World" | "Powerful" | "Pinnacle")
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local defId = randomDefOfRarity(rarity)
	if defId == nil then
		NetService.Notify(player, `No items of rarity {rarity}`, "Error")
		return
	end
	local highest = PowerMath.HighestPossible(data.Items)
	local power = PowerMath.RollDropPower(highest, rewardKind, 3, rng)
	local item = ItemRoller.Roll(defId, power, rng, DataService.NewUid(), os.time(), "Random")
	if item == nil then
		return
	end
	local ok, location = DataService.GiveItem(player, item)
	if ok then
		local name = ItemCatalog.Get(defId)
		local godRoll = if ItemRoller.IsGodRoll(item) then " (god roll!)" else ""
		NetService.Notify(
			player,
			`{item.Rarity} {if name then name.Name else defId} at {item.Power} power -> {location}{godRoll}`,
			"Success"
		)
	else
		NetService.Notify(player, "Inventory and postmaster are full.", "Error")
	end
end

type Handler = (player: Player, text: string?, number: number?) -> ()

local Commands: { [string]: Handler } = {
	AddCurrency = function(player, currency, amount)
		if currency == nil or EconomyConfig.Currencies[currency] == nil or amount == nil then
			NetService.Notify(player, "AddCurrency needs a currency and an amount.", "Error")
			return
		end
		local ok, balance = DataService.AddCurrency(player, currency, amount)
		NetService.Notify(
			player,
			if ok then `{currency}: {balance}` else "Not enough currency.",
			if ok then "Success" else "Error"
		)
	end,

	GrantItem = function(player, rarity)
		if rarity ~= nil and RarityConfig.Tiers[rarity] == nil then
			NetService.Notify(player, `Unknown rarity {rarity}`, "Error")
			return
		end
		grantRandomItem(player, rarity, "World")
	end,

	GrantPinnacle = function(player)
		grantRandomItem(player, nil, "Pinnacle")
	end,

	CycleClass = function(player)
		local data = DataService.GetData(player)
		if data == nil then
			return
		end
		local index = 1
		for i, class in ClassConfig.List do
			if class.Id == data.Class then
				index = i % #ClassConfig.List + 1
			end
		end
		local newClass = ClassConfig.List[index].Id
		DataService.Set(player, { "Class" }, newClass)
		-- Class-locked exotic armor can't stay equipped on another class.
		for slot, uid in data.Equipped do
			local item = data.Items[uid]
			local entry = if item then ItemCatalog.Get(item.DefId) else nil
			local restriction = if entry and entry.Armor then entry.Armor.ClassRestriction else nil
			if restriction ~= nil and restriction ~= newClass then
				DataService.Set(player, { "Equipped", slot }, nil)
			end
		end
		NetService.Notify(player, `Class set to {newClass}`, "Success")
	end,

	SaveNow = function(player)
		local ok, err = DataService.SaveNow(player)
		NetService.Notify(player, if ok then "Saved." else `Save failed: {err}`, if ok then "Success" else "Error")
	end,

	ExpireResets = function(player)
		DataService.ExpireResets(player)
		NetService.Notify(player, "Weekly and daily resets applied.", "Success")
	end,

	ResetProfile = function(player)
		DataService.ResetProfile(player)
		NetService.Notify(player, "Profile reset to a new save.", "Warning")
	end,
}

local commandNames = {}
for name in Commands do
	table.insert(commandNames, name)
end
table.sort(commandNames)
DebugService.CommandNames = commandNames

function DebugService.Init()
	NetService.OnEvent(
		"DebugCommand",
		{ Guard.OneOf(commandNames), Guard.Optional(Guard.String(32)), Guard.Optional(Guard.Number(-1e6, 1e6)) },
		function(player: Player, command: string, text: string?, number: number?)
			if not DebugService.HasAccess(player) then
				NetService.Flag(player, 2, `debug command {command} without access`)
				return
			end
			if not DataService.IsLoaded(player) then
				return
			end
			Commands[command](player, text, number)
		end
	)
end

function DebugService.Start()
	local function tag(player: Player)
		player:SetAttribute("DebugAccess", DebugService.HasAccess(player))
	end
	Players.PlayerAdded:Connect(tag)
	for _, player in Players:GetPlayers() do
		tag(player)
	end
end

return DebugService
