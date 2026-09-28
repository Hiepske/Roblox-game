-- Builds every map with Lune's real Roblox Instance implementation (which
-- validates property names and types) and checks that everything the
-- activity configs reference exists in the map.
local roblox = require("@lune/roblox")
VirtualGame.SetGlobal("Instance", roblox.Instance)
for _, name in { "NumberRange", "NumberSequence", "ColorSequence", "ColorSequenceKeypoint" } do
	VirtualGame.SetGlobal(name, (roblox :: any)[name])
end

local Shared = game.ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local VendorConfig = require(Shared.Config.VendorConfig)
local Maps = game.ServerScriptService.MapBuilders
local MapKit = require(Maps.MapKit)

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
	local hub = require(Maps.HubBuilder).Build()

	it("has a spawn, three range dummies and the Director terminal", function()
		local markers = hub:FindFirstChild("Markers")
		expect(findDeep(markers, "HubSpawn") ~= nil).toBe(true)
		expect(findDeep(markers, "RangeZone") ~= nil).toBe(true)
		for index = 1, 3 do
			expect(findDeep(markers, "Dummy_" .. index) ~= nil).toBe(true)
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

	it("has named areas, lifts, hidden caches and a fall limit", function()
		local areas = findDeep(hub:FindFirstChild("Markers"), "Areas")
		local names = {}
		for _, area in areas:GetChildren() do
			expect(type(area:GetAttribute("DisplayName"))).toBe("string")
			names[area.Name] = true
		end
		for _, name in { "Area_Courtyard", "Area_Bazaar", "Area_Hangar", "Area_CommandDeck", "Area_Range" } do
			expect(names[name]).toBe(true)
		end
		local lifts = 0
		for _, descendant in hub:GetDescendants() do
			if descendant.Name == "Elevator" and descendant:HasTag("LL_Mover") then
				lifts += 1
			end
		end
		expect(lifts).toBe(2)
		expect(findDeep(hub, "Chest_HUB_ROOFTOP") ~= nil).toBe(true)
		expect(findDeep(hub, "Chest_HUB_SECRET") ~= nil).toBe(true)
		expect(type(hub:GetAttribute("KillY"))).toBe("number")
	end)

	it("stays within the part budget and has terrain recipes", function()
		local parts = MapKit.CountParts(hub)
		print(`Hub parts: {parts}`)
		expect(parts < 15000).toBe(true)
		local recipes = hub:FindFirstChild("Terrain"):GetChildren()
		expect(#recipes > 10).toBe(true)
		for _, recipe in recipes do
			expect(recipe:GetAttribute("TerrainShape") ~= nil).toBe(true)
			expect(recipe:GetAttribute("TerrainMaterial") ~= nil).toBe(true)
		end
	end)

	it("is the same every time it is built", function()
		local again = require(Maps.HubBuilder).Build()
		expect(MapKit.CountParts(again)).toBe(MapKit.CountParts(hub))
		local a = findDeep(hub, "Chest_HUB_ROOFTOP").PrimaryPart.CFrame
		local b = findDeep(again, "Chest_HUB_ROOFTOP").PrimaryPart.CFrame
		expect((a.Position - b.Position).Magnitude < 1e-6).toBe(true)
	end)
end)

describe("Activity maps", function()
	local MapMarkers = require(game.ServerScriptService.Missions.MapMarkers)
	for _, activity in ActivityRules.Playable() do
		it(activity.Name .. " contains every marker its zones use", function()
			local model = require(Maps[activity.Map .. "Builder"]).Build()
			expect(model.Name).toBe(activity.Map)
			local missing = MapMarkers.Missing(model, activity)
			if #missing > 0 then
				error("missing: " .. table.concat(missing, ", "))
			end
		end)

		it(activity.Name .. " numbers its terrain recipes in build order", function()
			local model = require(Maps[activity.Map .. "Builder"]).Build()
			local seen = {}
			for _, recipe in model:FindFirstChild("Terrain"):GetChildren() do
				local order = recipe:GetAttribute("TerrainOrder")
				expect(type(order)).toBe("number")
				expect(seen[order]).toBeNil()
				seen[order] = true
			end
		end)

		it(activity.Name .. " stays in budget, anchored, with invisible markers", function()
			local model = require(Maps[activity.Map .. "Builder"]).Build()
			local parts = MapKit.CountParts(model)
			print(`{activity.Map} parts: {parts}, terrain recipes: {#model:FindFirstChild("Terrain"):GetChildren()}`)
			expect(parts < 15000).toBe(true)
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") and not descendant.Anchored then
					error(descendant:GetFullName() .. " isn't anchored")
				end
			end
			for _, marker in model:FindFirstChild("Markers"):GetDescendants() do
				if marker:IsA("BasePart") then
					expect(marker.Transparency).toBe(1)
					expect(marker.CanCollide).toBe(false)
				end
			end
		end)
	end
end)
