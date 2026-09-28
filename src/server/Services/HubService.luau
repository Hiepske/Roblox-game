--!strict
--[[
	HubService
	Rules that only apply in the hub (The Spire):

	  * Weapons are holstered: players can run and jump but not shoot,
	    except inside the firing range (Markers/Range/RangeZone). Inside an
	    activity weapons are always drawn. The state is the player attribute
	    "WeaponsDrawn", which WeaponService and the HUD read.
	  * Falling off the tower (below the hub model's KillY attribute) puts
	    you back at the spawn.
	  * Hidden caches (Props.Chest, prompt "OpenChest" with a ChestId) pay
	    WorldConfig.Chests rewards once per daily/weekly reset.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WorldConfig = require(Shared.Config.WorldConfig)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local LootService = require(script.Parent.LootService)
local NetService = require(script.Parent.NetService)
local WorldService = require(script.Parent.WorldService)

local HubService = {}

local rng = Random.new()

local function inside(box: BasePart, point: Vector3): boolean
	local offset = box.CFrame:PointToObjectSpace(point)
	local half = box.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

local function claimChest(player: Player, chestId: string)
	local chest = WorldConfig.Chests[chestId]
	local data = DataService.GetData(player)
	if chest == nil or data == nil then
		return
	end
	local claims = if chest.Reset == "Daily" then data.Daily.ClaimedRewards else data.Weekly.ClaimedRewards
	local path = if chest.Reset == "Daily" then "Daily" else "Weekly"
	if (claims[chestId] or 0) > 0 then
		NetService.Notify(player, `Empty. It refills at the next {string.lower(chest.Reset)} reset.`, "Info")
		return
	end
	DataService.Set(player, { path, "ClaimedRewards", chestId }, 1)
	local gained: { string } = {}
	for currency, amount in chest.Currencies do
		DataService.AddCurrency(player, currency, amount)
		table.insert(gained, `+{amount} {currency}`)
	end
	table.sort(gained)
	NetService.Notify(player, `{chest.Message}  {table.concat(gained, "  ")}`, "Success")
	if rng:NextNumber() < chest.DropChance then
		local item = LootService.Roll(player, "World", "World", nil, { NoExotic = true })
		if item then
			LootService.Announce(player, { { Item = item, Location = item.Location, Reason = "Drop" } }, "", false)
		end
	end
end

local function update()
	local hub = WorldService.GetHub()
	local killY = tonumber(hub:GetAttribute("KillY")) or -math.huge
	local range = WorldService.GetHubMarker("RangeZone")
	for _, player in Players:GetPlayers() do
		local inActivity = player:GetAttribute("InstanceId") ~= nil
		local character = CharacterService.GetCharacter(player)
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local drawn = inActivity
		if not inActivity and root and root:IsA("BasePart") then
			if root.Position.Y < killY then
				CharacterService.Teleport(player, WorldService.GetHubSpawn())
			end
			drawn = range ~= nil and inside(range, root.Position)
		end
		if player:GetAttribute("WeaponsDrawn") ~= drawn then
			player:SetAttribute("WeaponsDrawn", drawn)
		end
	end
end

function HubService.Init() end

function HubService.Start()
	for _, descendant in WorldService.GetHub():GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "OpenChest" then
			local chestId = descendant:GetAttribute("ChestId")
			descendant.Triggered:Connect(function(player: Player)
				if type(chestId) == "string" and DataService.IsLoaded(player) then
					claimChest(player, chestId)
				end
			end)
		end
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(update :: any)
			if not ok then
				warn(`[HubService] {err}`)
			end
			task.wait(0.25)
		end
	end)
end

return HubService
