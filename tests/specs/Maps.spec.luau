-- Builds every map with Lune's real Roblox Instance implementation (which
-- validates property names and types) and checks that everything the
-- activity configs reference exists in the map.
local roblox = require("@lune/roblox")
VirtualGame.SetGlobal("Instance", roblox.Instance)

local Shared = game.ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local VendorConfig = require(Shared.Config.VendorConfig)
local Maps = game.ServerScriptService.Maps

local function find(model, folderName, name)
	local folder = model:FindFirstChild(folderName)
	return folder and folder:FindFirstChild(name)
end

local function findDeep(model, name)
	for _, descendant in model:GetDescendants() do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end

describe("Hub map", function()
	local hub = require(Maps.Hub).Build()

	it("has a spawn, three range dummies and the Director terminal", function()
		expect(find(hub, "Markers", "HubSpawn") ~= nil).toBe(true)
		for index = 1, 3 do
			expect(find(hub, "Markers", "Dummy_" .. index) ~= nil).toBe(true)
		end
		local terminal = findDeep(hub, "DirectorTerminal")
		expect(terminal ~= nil).toBe(true)
		expect(terminal:FindFirstChild("OpenDirector") ~= nil).toBe(true)
	end)

	it("has a booth for every vendor", function()
		for _, vendor in VendorConfig.List do
			expect(findDeep(hub, "Vendor_" .. vendor.Id) ~= nil).toBe(true)
		end
	end)
end)

describe("Activity maps", function()
	for _, activity in ActivityRules.Playable() do
		it(activity.Name .. " contains every marker its objectives use", function()
			local model = require(Maps[activity.Map]).Build()
			expect(model.Name).toBe(activity.Map)
			expect(find(model, "Markers", "PlayerStart") ~= nil).toBe(true)

			local missing = {}
			local function need(ok, what)
				if not ok then
					table.insert(missing, what)
				end
			end
			for _, entry in ActivityRules.ObjectiveList(activity) do
				local objective = entry.Objective
				if objective.Target then
					need(find(model, "Markers", objective.Target) ~= nil, "marker " .. objective.Target)
				end
				if objective.Checkpoint then
					need(find(model, "Markers", objective.Checkpoint) ~= nil, "checkpoint " .. objective.Checkpoint)
				end
				if objective.Door then
					need(find(model, "Doors", objective.Door) ~= nil, "door " .. objective.Door)
				end
				for _, spawn in objective.Spawns or {} do
					need(find(model, "Markers", "Spawn_" .. spawn.Group .. "_1") ~= nil, "spawn group " .. spawn.Group)
				end
				if objective.AddsGroup then
					need(
						find(model, "Markers", "Spawn_" .. objective.AddsGroup .. "_1") ~= nil,
						"adds group " .. objective.AddsGroup
					)
				end
				if objective.Mechanic == "EchoPlates" then
					for index = 1, 3 do
						need(findDeep(model, "Plate_" .. index) ~= nil, "Plate_" .. index)
					end
				end
			end
			if #missing > 0 then
				error("missing: " .. table.concat(missing, ", "))
			end
		end)
	end
end)
