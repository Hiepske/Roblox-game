--!strict
--[[
	WorldService
	Builds the world when the server starts:
	  * applies the hub lighting preset
	  * builds the hub (MapBuilders/HubBuilder) into Workspace.Hub, or uses a
	    hand-built Workspace.Hub, and fills in the hub's terrain
	  * builds each activity map into ServerStorage.Activities (skipping any
	    map a designer already placed there by hand); their terrain is
	    applied per instance by ActivityService
	  * creates the runtime folders: Workspace.Instances, .Enemies, .Pickups
	  * wires the Director terminal and vendor prompts in the hub
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local LightingPresets = require(Shared.World.LightingPresets)
local VendorConfig = require(Shared.Config.VendorConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

local MapBuilderFolder = script.Parent.Parent.MapBuilders
local MapKit = require(MapBuilderFolder.MapKit)
local HubBuilder = require(MapBuilderFolder.HubBuilder)

-- Map name -> builder module (MapBuilders/<Name>Builder).
local function builderFor(name: string): { Build: () -> Model }?
	local module = MapBuilderFolder:FindFirstChild(`{name}Builder`)
	if module and module:IsA("ModuleScript") then
		return require(module) :: any
	end
	return nil
end

local NetService = require(script.Parent.NetService)

local WorldService = {}

local hub: Model
local activitiesFolder: Folder
local folders: { [string]: Folder } = {}

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- Studio's Baseplate template ships a baseplate and spawn at the origin that
-- would overlap the hub. Remove them for this session only.
local function removeTemplateLeftovers()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") and baseplate.Size.X >= 512 then
		baseplate:Destroy()
	end
	local spawn = Workspace:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn:Destroy()
	end
end

function WorldService.Init()
	LightingPresets.Apply("Hub")
	removeTemplateLeftovers()

	local existingHub = Workspace:FindFirstChild("Hub")
	if existingHub and existingHub:IsA("Model") then
		hub = existingHub
	else
		hub = HubBuilder.Build()
		hub.Parent = Workspace
	end

	activitiesFolder = folder(ServerStorage, "Activities")
	for _, name in WorldConfig.Maps do
		if activitiesFolder:FindFirstChild(name) == nil then
			local builder = builderFor(name)
			if builder then
				local model = builder.Build()
				model.Parent = activitiesFolder
			else
				warn(`[WorldService] No builder or hand-built model for map {name}`)
			end
		end
	end

	for _, name in { "Instances", "Enemies", "Pickups" } do
		folders[name] = folder(Workspace, name)
	end
end

-- Vendors whose prompt opens a screen instead of a greeting.
local VENDOR_MENUS: { [string]: string } = {
	POSTMASTER = "Postmaster",
	VAULT = "Vault",
	GUNSMITH = "Infuse",
}

function WorldService.Start()
	-- The hub's city, river and mountains (can take a few seconds).
	task.spawn(MapKit.ApplyTerrain, hub)

	-- Director terminal: proximity prompt and clicking the console/screen/orb.
	for _, descendant in hub:GetDescendants() do
		if descendant.Name == "OpenDirector" then
			if descendant:IsA("ProximityPrompt") then
				descendant.Triggered:Connect(function(player: Player)
					NetService.FireClient(player, "OpenDirector")
				end)
			elseif descendant:IsA("ClickDetector") then
				descendant.MouseClick:Connect(function(player: Player)
					NetService.FireClient(player, "OpenDirector")
				end)
			end
		elseif descendant:IsA("ProximityPrompt") and descendant.Name == "Talk" then
			local vendorId = descendant:GetAttribute("VendorId")
			descendant.Triggered:Connect(function(player: Player)
				local vendor = if type(vendorId) == "string" then VendorConfig.ById[vendorId] else nil
				if vendor == nil then
					return
				end
				local menu = VENDOR_MENUS[vendor.Id]
				if menu then
					NetService.FireClient(player, "OpenMenu", "Inventory", menu)
				end
				NetService.Notify(player, `{vendor.Name}: "{vendor.Greeting}"`)
			end)
		end
	end
end

-- Where players stand in the hub. Spread a little so a group doesn't stack.
function WorldService.GetHubSpawn(): CFrame
	local markers = hub:FindFirstChild("Markers")
	local marker = if markers then markers:FindFirstChild("HubSpawn", true) else nil
	local base = if marker and marker:IsA("BasePart")
		then marker.CFrame
		else CFrame.new(0, WorldConfig.HubSpawnHeight, 12)
	local angle = math.random() * math.pi * 2
	local radius = math.random() * 5
	return base + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function WorldService.GetHubMarker(name: string): BasePart?
	local markers = hub:FindFirstChild("Markers")
	local marker = if markers then markers:FindFirstChild(name, true) else nil
	return if marker and marker:IsA("BasePart") then marker else nil
end

function WorldService.GetHub(): Model
	return hub
end

function WorldService.GetMapTemplate(name: string): Model?
	local model = activitiesFolder:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

-- Runtime folders: "Instances", "Enemies", "Pickups".
function WorldService.Folder(name: string): Folder
	local found = folders[name]
	assert(found, `Unknown world folder {name}`)
	return found
end

-- Every player character, for raycast exclusion lists.
function WorldService.PlayerCharacters(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- The slot position for activity instance number `slot` (1-based).
function WorldService.InstanceOrigin(slot: number): Vector3
	return Vector3.new(GameConfig.Activities.InstanceSpacing * slot, 0, 0)
end

return WorldService
