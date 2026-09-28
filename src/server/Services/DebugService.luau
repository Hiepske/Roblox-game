--!strict
--[[
	DebugService
	Developer commands for testing data and progression without playing
	through content. Only players with debug access can use them:
	  * anyone in Studio (GameConfig.Debug.AllowInStudio)
	  * UserIds in GameConfig.Debug.AdminUserIds in live servers
	Anyone else sending a debug command is flagged by NetService.

	The client's developer panel (DebugPanelController) and the chat commands
	(DevCommandController: /setpower, /give, /launch, /god, /resetweek,
	/wipe, /skip, /zone, /heavy, /kill, /leave) send these through the DebugCommand
	remote: DebugCommand(command, stringArg?, numberArg?). /giveall gives one of
	every weapon.
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
local ActivityConfig = require(Shared.Config.ActivityConfig)
local Inventory = require(Shared.Items.Inventory)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local PowerConfig = require(Shared.Config.PowerConfig)
local PowerMath = require(Shared.Power.PowerMath)
local RarityConfig = require(Shared.Config.RarityConfig)

local ActivityService = require(script.Parent.ActivityService)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local LootService = require(script.Parent.LootService)
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
	if debugConfig.AllowGameOwner and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
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

-- Finds a weapon/armor def by id or (partial) name, ignoring case.
local function findDef(query: string): string?
	local lowered = string.lower(query)
	if ItemCatalog.Get(string.upper(query)) then
		return string.upper(query)
	end
	local best: string? = nil
	for defId, entry in ItemCatalog.All() do
		local def: any = entry.Weapon or entry.Armor
		local name = if def then string.lower(def.Name) else ""
		if string.lower(defId) == lowered or name == lowered then
			return defId
		elseif
			best == nil and (string.find(name, lowered, 1, true) or string.find(string.lower(defId), lowered, 1, true))
		then
			best = defId
		end
	end
	return best
end

local ACTIVITY_ALIASES: { [string]: string } = {
	story = "STORY_01",
	firstlight = "STORY_01",
	mission = "STORY_01",
	nightfall = "NIGHTFALL",
	nf = "NIGHTFALL",
	strike = "NIGHTFALL",
	raid = "RAID_VAULT_OF_ECHOES",
	vault = "RAID_VAULT_OF_ECHOES",
}

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

	-- /setpower <n>: every equipped item is set to power n.
	SetPower = function(player, _, number)
		local data = DataService.GetData(player)
		if data == nil or number == nil then
			NetService.Notify(player, "Usage: /setpower <number>", "Error")
			return
		end
		local power = math.clamp(math.floor(number), 1, PowerConfig.PinnacleCap)
		for _, uid in data.Equipped do
			if data.Items[uid] then
				DataService.Set(player, { "Items", uid, "Power" }, power)
			end
		end
		local highest = PowerMath.HighestPossible(data.Items)
		if highest > data.Lifetime.HighestPower then
			DataService.Set(player, { "Lifetime", "HighestPower" }, highest)
		end
		NetService.Notify(
			player,
			`Equipped gear set to {power}. Power: {PowerMath.CharacterPower(data.Items, data.Equipped)}`,
			"Success"
		)
	end,

	-- /give <weaponId or name>: rolls it at your highest power and equips it.
	Give = function(player, text)
		local data = DataService.GetData(player)
		local defId = if text then findDef(text) else nil
		if data == nil or defId == nil then
			NetService.Notify(player, `Unknown item "{text or ""}". Try W_LAST_EMBER or a weapon name.`, "Error")
			return
		end
		local highest = PowerMath.HighestPossible(data.Items)
		local item = ItemRoller.Roll(defId :: string, highest, rng, DataService.NewUid(), os.time(), "Random")
		if item == nil then
			return
		end
		local ok = DataService.GiveItem(player, item)
		if not ok then
			NetService.Notify(player, "Inventory and postmaster are full.", "Error")
			return
		end
		local equipped, reason = InventoryService.Equip(player, item.Uid)
		LootService.Announce(player, { { Item = item, Location = item.Location, Reason = "Drop" } }, "", false)
		if not equipped then
			NetService.Notify(player, `Added to inventory (not equipped: {reason})`, "Warning")
		end
	end,

	-- /giveall: one of every weapon at your power (overflow goes to the vault).
	GiveAll = function(player)
		local data = DataService.GetData(player)
		if data == nil then
			return
		end
		local highest = PowerMath.HighestPossible(data.Items)
		local given, stored = 0, 0
		for _, weapon in WeaponConfig.List do
			local item = ItemRoller.Roll(weapon.Id, highest, rng, DataService.NewUid(), os.time(), "Random")
			if item then
				local location: string? = if Inventory.HasRoom(data, "Inventory", item.Slot)
					then "Inventory"
					elseif Inventory.HasRoom(data, "Vault") then "Vault"
					else nil
				if location then
					item.Location = location :: any
					item.Seen = false
					DataService.Set(player, { "Items", item.Uid }, item)
					given += 1
					if location == "Vault" then
						stored += 1
					end
				end
			end
		end
		NetService.Notify(
			player,
			`Added {given} weapons ({stored} went to the vault). Open the inventory with Tab.`,
			"Success"
		)
	end,

	-- /launch <activity> [difficulty]: skips unlock checks. Text is "ID" or "ID:Difficulty".
	Launch = function(player, text)
		local raw = text or ""
		local name, difficulty = string.match(raw, "^([^:]+):?(.*)$")
		local key = string.lower(name or "")
		local activityId = ACTIVITY_ALIASES[key] or string.upper(name or "")
		if ActivityConfig.ById[activityId] == nil then
			NetService.Notify(player, "Usage: /launch story | nightfall [adept|hero|legend] | raid", "Error")
			return
		end
		local difficultyId: string? = nil
		if difficulty and difficulty ~= "" then
			difficultyId = string.upper(string.sub(difficulty, 1, 1)) .. string.lower(string.sub(difficulty, 2))
		end
		local ok, message = ActivityService.Launch(player, activityId, difficultyId, true)
		if not ok then
			NetService.Notify(player, message or "Launch failed", "Error")
		end
	end,

	God = function(player)
		local enabled = not CharacterService.IsGodMode(player)
		CharacterService.SetGodMode(player, enabled)
		NetService.Notify(player, if enabled then "God mode ON" else "God mode OFF", "Success")
	end,

	Skip = function(player)
		if not ActivityService.SkipObjective(player) then
			NetService.Notify(player, "You're not in an activity.", "Error")
		end
	end,

	Zone = function(player, _text, number)
		if not ActivityService.JumpToZone(player, number or 1) then
			NetService.Notify(player, "You're not in an activity.", "Error")
		end
	end,

	Heavy = function(player)
		local character = CharacterService.GetCharacter(player)
		if character then
			local instanceId = player:GetAttribute("InstanceId")
			LootService.DropHeavyAmmo(
				character:GetPivot().Position + character:GetPivot().LookVector * 4,
				if type(instanceId) == "string" then instanceId else nil
			)
		end
	end,

	Kill = function(player)
		CharacterService.Kill(player)
	end,

	Leave = function(player)
		ActivityService.Leave(player)
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
		{ Guard.OneOf(commandNames), Guard.Optional(Guard.String(48)), Guard.Optional(Guard.Number(-1e6, 1e6)) },
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
