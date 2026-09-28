--!strict
--[[
	HubBuilder: The Spire
	A bright, outdoor, multi-level social space on top of a huge wall that
	towers over a ruined city.

	  Courtyard     (Y 0)    spawn, fountain monument, the Director, weapons +
	                         armor vendors, bounty board, firing range (west)
	  Command Deck  (Y 34)   up the grand stairs or the lift: holo-table,
	                         strike commander, raid banner wall, balcony,
	                         and a secret room behind the east wall
	  Bazaar        (Y -28)  down the east stairs/ramp: stalls, Gunsmith,
	                         Postmaster, Vault terminal, café; a rooftop cache
	                         reachable by jumping up the Relay House ledges
	  Hangar        (Y -70)  down the bazaar stairs or the courtyard lift:
	                         parked ships, containers, crane, shipwright,
	                         landing pad
	Around it: terrain city and mountains 430 studs below, the Lantern (a
	floating sphere) in the sky, and ships looping around the tower.

	Markers (Markers/...):
	  Spawns/HubSpawn             where players appear
	  Range/Dummy_1..3            shooting range targets (15/30/55 studs)
	  Range/RangeZone             weapons are drawn inside this box
	  Areas/Area_*                boxes with a DisplayName shown on entry
	The model's KillY attribute: fall below it and you're put back at spawn.

	Studio: require(game.ServerScriptService.MapBuilders.Generate)("Hub")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.Config.AssetIds)
local VendorConfig = require(ReplicatedStorage.Shared.Config.VendorConfig)

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local HubBuilder = {}

local P = MapKit.Palette

local COURTYARD = 0
local DECK = 34
local BAZAAR = -28
local HANGAR = -70
local CITY = -430

-- Helpers ---------------------------------------------------------------------------------

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- A tiled floor slab between two corners (top surface at `y`).
local function tiledFloor(
	b: Builder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	y: number,
	tile: number,
	colorA: Color3,
	colorB: Color3,
	material: Enum.Material,
	parent: Instance
)
	local countX = math.max(1, math.floor((x1 - x0) / tile + 0.5))
	local countZ = math.max(1, math.floor((z1 - z0) / tile + 0.5))
	local sizeX, sizeZ = (x1 - x0) / countX, (z1 - z0) / countZ
	for ix = 0, countX - 1 do
		for iz = 0, countZ - 1 do
			local center = v(x0 + (ix + 0.5) * sizeX, y - 0.5, z0 + (iz + 0.5) * sizeZ)
			MapKit.Block(
				b,
				v(sizeX - 0.15, 1, sizeZ - 0.15),
				CFrame.new(center),
				if (ix + iz) % 2 == 0 then colorA else colorB,
				material,
				parent
			)
		end
	end
	-- Dark grout underneath shows between the tiles.
	MapKit.Block(
		b,
		v(x1 - x0, 0.9, z1 - z0),
		CFrame.new(v((x0 + x1) / 2, y - 0.55, (z0 + z1) / 2)),
		P.DarkMetal,
		Enum.Material.Metal,
		parent
	)
end

local function vendorNpc(b: Builder, vendorId: string, cframe: CFrame, body: Color3, accent: Color3, parent: Instance)
	local vendor = VendorConfig.ById[vendorId]
	local name = if vendor then vendor.Name else vendorId
	local title = if vendor then vendor.Title else nil
	local _, torso = Props.Npc(b, cframe, name, title, body, accent, parent)
	torso.Name = `Vendor_{vendorId}`
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Talk"
	prompt.ObjectText = name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("VendorId", vendorId)
	prompt.Parent = torso
end

-- A terminal (no person) that behaves like a vendor (Vault).
local function vendorTerminal(b: Builder, vendorId: string, cframe: CFrame, color: Color3, parent: Instance)
	local console = Props.Console(b, cframe, color, parent)
	local body = console.PrimaryPart :: BasePart
	body.Name = `Vendor_{vendorId}`
	local vendor = VendorConfig.ById[vendorId]
	MapKit.Billboard(body, if vendor then vendor.Name else vendorId, if vendor then vendor.Title else nil, color, 5)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Access"
	prompt.ObjectText = if vendor then vendor.Name else vendorId
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("VendorId", vendorId)
	prompt.Parent = body
end

local function area(b: Builder, name: string, displayName: string, min: Vector3, max: Vector3)
	local marker = MapKit.Marker(b, `Areas/Area_{name}`, CFrame.new((min + max) / 2), max - min)
	marker:SetAttribute("DisplayName", displayName)
end

-- The tower ---------------------------------------------------------------------------------

local function buildTower(b: Builder)
	local tower = MapKit.Group(b, "Tower")
	-- The wall's body, down to the city.
	MapKit.Block(b, v(480, 350, 450), CFrame.new(30, -255, 30), P.ConcreteGrey, Enum.Material.Concrete, tower)
	-- Terraces.
	MapKit.Block(b, v(190, 79, 275), CFrame.new(0, -40.5, -47.5), P.ConcreteGrey, Enum.Material.Concrete, tower)
	MapKit.Block(b, v(110, 79, 90), CFrame.new(-150, -40.5, 0), P.ConcreteGrey, Enum.Material.Concrete, tower)
	MapKit.Block(b, v(155, 51, 190), CFrame.new(172.5, -54.5, 0), P.ConcreteGrey, Enum.Material.Concrete, tower)
	MapKit.Block(b, v(215, 9, 165), CFrame.new(162.5, -75.5, 172.5), P.ConcreteGrey, Enum.Material.Concrete, tower)

	-- Buttresses and light strips down the outer faces.
	local rng = b.Rng
	for index = 0, 7 do
		local x = -200 + index * 62
		for _, z in { -196, 256 } do
			MapKit.Block(b, v(12, 340, 10), CFrame.new(x, -260, z), P.Concrete, Enum.Material.Concrete, tower)
			MapKit.Neon(
				b,
				v(1, 300, 0.4),
				CFrame.new(x, -250, z + (if z < 0 then -5.2 else 5.2)),
				if index % 2 == 0 then P.Orange else P.Teal,
				tower
			)
		end
	end
	for index = 0, 6 do
		local z = -180 + index * 70
		for _, x in { -211, 271 } do
			MapKit.Block(b, v(10, 340, 12), CFrame.new(x, -260, z), P.Concrete, Enum.Material.Concrete, tower)
		end
	end
	-- Window slits in the wall faces.
	for _ = 1, 60 do
		local x = rng:NextNumber(-200, 260)
		local y = rng:NextNumber(-400, -110)
		MapKit.Neon(b, v(6, 1.2, 0.3), CFrame.new(x, y, -195.3), Color3.fromRGB(255, 210, 150), tower)
		MapKit.Neon(b, v(6, 1.2, 0.3), CFrame.new(x, y, 255.3), Color3.fromRGB(255, 210, 150), tower)
	end
end

-- Courtyard -----------------------------------------------------------------------------

local function buildDirector(b: Builder, parent: Instance)
	local model = MapKit.Group(b, "Director", parent)
	local base = v(-45, COURTYARD, -62)
	MapKit.Cylinder(b, 1, 18, base + v(0, 0.5, 0), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Cylinder(b, 0.3, 18.4, base + v(0, 1, 0), P.Teal, Enum.Material.Neon, model).CanCollide = false
	local console = MapKit.Part(b, {
		Name = "DirectorTerminal",
		Size = v(10, 5, 4),
		CFrame = CFrame.lookAt(base + v(0, 3.5, 4), base + v(0, 3.5, 20)),
		Color = P.White,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local screen = MapKit.Part(b, {
		Name = "Screen",
		Size = v(9, 4, 0.4),
		CFrame = console.CFrame * CFrame.new(0, 3.8, -0.4) * CFrame.Angles(math.rad(25), 0, 0),
		Color = P.Teal,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	MapKit.Sign(screen, "DIRECTOR", Enum.NormalId.Back, Color3.fromRGB(10, 40, 50))
	-- Tall pylon with a holographic world.
	MapKit.Block(b, v(3, 16, 3), CFrame.new(base + v(0, 9, -3)), P.White, Enum.Material.SmoothPlastic, model)
	local orb = MapKit.Part(b, {
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = v(9, 9, 9),
		CFrame = CFrame.new(base + v(0, 22, -3)),
		Color = P.Teal,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	MapKit.Light(orb, P.Teal, 28, 2)
	local ring = Props.Ring(
		b,
		CFrame.new(base + v(0, 22, -3)) * CFrame.Angles(math.rad(20), 0, 0),
		7,
		0.3,
		0.6,
		20,
		P.Orange,
		Enum.Material.Neon,
		model
	)
	ring:SetAttribute("SpinCenter", base + v(0, 22, -3))
	ring:SetAttribute("SpinAxis", v(0, 1, 0))
	ring:SetAttribute("SpinSpeed", 25)
	ring:AddTag("LL_Spin")
	MapKit.Billboard(orb, "DIRECTOR", "Press M, or walk up and press E", P.Teal, 7)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenDirector"
	prompt.ActionText = "Open the Director"
	prompt.ObjectText = "Director"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	for _, part in { console, screen, orb } do
		local click = Instance.new("ClickDetector")
		click.Name = "OpenDirector"
		click.MaxActivationDistance = 60
		click.Parent = part
	end
end

local function buildFountain(b: Builder, parent: Instance)
	local model = MapKit.Group(b, "Monument", parent)
	local center = v(0, COURTYARD, 15)
	MapKit.Cylinder(b, 2.2, 28, center + v(0, 1.1, 0), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Part(b, {
		Name = "Water",
		Shape = Enum.PartType.Cylinder,
		Size = v(0.4, 25, 25),
		CFrame = CFrame.new(center + v(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 170, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		CanCollide = false,
		Parent = model,
	})
	MapKit.Cylinder(b, 3, 8, center + v(0, 3.5, 0), P.White, Enum.Material.Marble, model)
	-- The Keeper monument: a tall split obelisk around a glowing core.
	for _, x in { -1.6, 1.6 } do
		MapKit.Block(
			b,
			v(1.8, 22, 3.2),
			CFrame.new(center + v(x, 16, 0)) * CFrame.Angles(0, 0, math.rad(-x * 1.5)),
			P.White,
			Enum.Material.Marble,
			model
		)
	end
	local core = MapKit.Neon(b, v(1, 18, 1), CFrame.new(center + v(0, 15, 0)), P.Teal, model)
	MapKit.Light(core, P.Teal, 24, 1.5)
	local halo = Props.Ring(b, CFrame.new(center + v(0, 24, 0)), 5, 0.4, 0.8, 18, P.Orange, Enum.Material.Neon, model)
	halo:SetAttribute("SpinCenter", center + v(0, 24, 0))
	halo:SetAttribute("SpinAxis", v(0, 1, 0))
	halo:SetAttribute("SpinSpeed", -15)
	halo:AddTag("LL_Spin")
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local jet = center + v(math.cos(angle) * 9, 2, math.sin(angle) * 9)
		MapKit.Neon(b, v(0.5, 5, 0.5), CFrame.new(jet + v(0, 2.5, 0)), Color3.fromRGB(170, 230, 255), model).Transparency =
			0.4
	end
	-- Benches around the basin.
	for index = 0, 5 do
		local angle = index * math.pi / 3 + math.pi / 6
		local position = center + v(math.cos(angle) * 22, 0, math.sin(angle) * 22)
		Props.Bench(b, CFrame.lookAt(position, center), model)
	end
end

local function buildCourtyard(b: Builder)
	local model = MapKit.Group(b, "Courtyard")
	tiledFloor(
		b,
		-95,
		-185,
		95,
		90,
		COURTYARD,
		19,
		P.Concrete,
		Color3.fromRGB(226, 224, 216),
		Enum.Material.Concrete,
		model
	)
	-- Teal guide lines toward the landmarks.
	Props.Strip(b, v(0, 0.05, 55), v(0, 0.05, 32), P.Teal, model)
	Props.Strip(b, v(0, 0.05, -2), v(0, 0.05, -56), P.Teal, model)
	Props.Strip(b, v(-14, 0.05, 10), v(-40, 0.05, -52), P.Teal, model)

	buildFountain(b, model)
	buildDirector(b, model)

	-- Planters with trees, lamps, banners.
	for _, spot in
		{
			v(-35, 0, 42),
			v(35, 0, 42),
			v(-35, 0, -22),
			v(35, 0, -22),
			v(-70, 0, 62),
			v(70, 0, 62),
			v(-80, 0, -150),
			v(80, 0, -150),
		}
	do
		Props.Planter(b, spot, v(9, 2.5, 9), true, model)
	end
	for _, spot in
		{
			v(-20, 0, 70),
			v(20, 0, 70),
			v(-60, 0, 20),
			v(60, 0, 20),
			v(-60, 0, -40),
			v(60, 0, -85),
			v(-88, 0, -120),
			v(88, 0, -120),
		}
	do
		Props.Lamp(b, spot, 13, nil, model)
	end
	for index, x in { -86, -60, 60, 86 } do
		local color = if index % 2 == 0 then P.Orange else P.Teal
		Props.Banner(b, v(x, 0, 84), 20, v(0, 0, -1), color, P.White, model)
	end
	for _, x in { -16, 16 } do
		Props.Banner(b, v(x, 0, -54), 16, v(0, 0, 1), P.Orange, P.Teal, model)
	end

	-- Vendors on the east side.
	local eastStall = CFrame.lookAt(v(72, 0, -35), v(40, 0, -35))
	Props.Stall(b, eastStall, 14, P.Orange, model)
	vendorNpc(b, "WEAPONS", eastStall * CFrame.new(0, 0, 3), Color3.fromRGB(90, 70, 60), P.Orange, model)
	-- Gun rack behind her.
	local rack = MapKit.Block(b, v(1, 9, 14), CFrame.new(v(80, 4.5, -35)), P.DarkMetal, Enum.Material.Metal, model)
	for index = -2, 2 do
		MapKit.Block(
			b,
			v(0.6, 0.8, 4.5),
			rack.CFrame * CFrame.new(-0.7, 2.5 - math.abs(index) * 0.2, index * 2.6),
			P.Black,
			Enum.Material.Metal,
			model
		)
		MapKit.Neon(b, v(0.1, 0.2, 2), rack.CFrame * CFrame.new(-1.05, 2.5, index * 2.6), P.Orange, model)
	end

	local armorStall = CFrame.lookAt(v(72, 0, 15), v(40, 0, 15))
	Props.Stall(b, armorStall, 14, P.Teal, model)
	vendorNpc(b, "ARMOR", armorStall * CFrame.new(0, 0, 3), Color3.fromRGB(60, 70, 90), P.Teal, model)
	for index = -1, 1 do
		-- Armor mannequins.
		local spot = armorStall * CFrame.new(index * 4.5, 0, 6)
		MapKit.Block(b, v(1.8, 2.6, 1), spot * CFrame.new(0, 4.5, 0), P.Gunmetal, Enum.Material.DiamondPlate, model)
		MapKit.Block(b, v(1, 1, 1), spot * CFrame.new(0, 6.4, 0), P.DarkMetal, Enum.Material.Metal, model)
		MapKit.Rod(
			b,
			(spot * CFrame.new(0, 0, 0)).Position,
			(spot * CFrame.new(0, 3.2, 0)).Position,
			0.4,
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
	end

	-- Bounty board on the west side.
	local board = MapKit.Block(b, v(1.5, 10, 18), CFrame.new(-82, 7, -40), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(b, v(1, 10, 1), CFrame.new(-82, 2, -49), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(b, v(1, 10, 1), CFrame.new(-82, 2, -31), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Neon(b, v(0.2, 1.2, 16), board.CFrame * CFrame.new(0.8, 4, 0), P.Orange, model)
	local rng = b.Rng
	for index = 1, 10 do
		local y = rng:NextNumber(-3, 2.5)
		local z = -7 + (index - 1) * 1.5
		MapKit.Block(
			b,
			v(0.1, 2.2, 1.3),
			board.CFrame * CFrame.new(0.8, y, z),
			Color3.fromRGB(235, 225, 200),
			Enum.Material.SmoothPlastic,
			model
		)
	end
	local boardSign =
		MapKit.Block(b, v(0.2, 2, 12), board.CFrame * CFrame.new(0.9, 6, 0), P.Black, Enum.Material.Metal, model)
	MapKit.Sign(boardSign, "CONTRACTS", Enum.NormalId.Right, P.Orange)
	local bountyNpcFrame = CFrame.lookAt(v(-76, 0, -30), v(-40, 0, -30))
	vendorNpc(b, "BOUNTIES", bountyNpcFrame, Color3.fromRGB(70, 60, 50), P.Orange, model)

	-- Edge railings (south edge overlooks the hangar, east edge the bazaar).
	MapKit.Railing(b, v(-95, 0, 90), v(70, 0, 90), 3.5, nil, 16, model)
	MapKit.Railing(b, v(95, 0, -185), v(95, 0, -86), 3.5, nil, 16, model)
	MapKit.Railing(b, v(95, 0, -76), v(95, 0, -13), 3.5, nil, 16, model)
	MapKit.Railing(b, v(95, 0, 13), v(95, 0, 90), 3.5, nil, 16, model)
	MapKit.Railing(b, v(-95, 0, -185), v(-95, 0, -45), 3.5, nil, 16, model)
	MapKit.Railing(b, v(-95, 0, 45), v(-95, 0, 90), 3.5, nil, 16, model)
	MapKit.Railing(b, v(-95, 0, -185), v(95, 0, -185), 3.5, nil, 16, model)

	-- Down to the bazaar: wide stairs (east) and a ramp (north-east).
	MapKit.Stairs(b, v(132, BAZAAR, 0), v(96, COURTYARD, 0), 24, P.Concrete, Enum.Material.Concrete, model)
	MapKit.Ramp(b, v(152, BAZAAR, -81), v(96, COURTYARD, -81), 9, P.ConcreteGrey, Enum.Material.Concrete, model)
	for _, z in { -12.5, 12.5 } do
		MapKit.Block(
			b,
			v(36, 2, 1),
			CFrame.new(114, -13, z) * CFrame.Angles(0, 0, math.rad(-38)),
			P.White,
			Enum.Material.Concrete,
			model
		)
	end
	local sign = MapKit.Block(b, v(1, 3, 20), CFrame.new(96, 9, 0), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Sign(sign, "BAZAAR ↓", Enum.NormalId.Left, P.Orange)
	MapKit.Block(b, v(1, 9, 1), CFrame.new(96, 3.5, -9), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(b, v(1, 9, 1), CFrame.new(96, 3.5, 9), P.DarkMetal, Enum.Material.Metal, model)

	-- Lift down to the hangar on a small balcony.
	MapKit.Block(b, v(24, 2, 8), CFrame.new(80, -1, 94), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Railing(b, v(68, 0, 90), v(68, 0, 110), 3.5, nil, 16, model)
	MapKit.Railing(b, v(92, 0, 90), v(92, 0, 110), 3.5, nil, 16, model)
	local car = MapKit.Part(b, {
		Name = "Elevator",
		Size = v(12, 1, 12),
		CFrame = CFrame.new(80, -0.45, 104),
		Color = P.Gunmetal,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	MapKit.Neon(b, v(12.1, 0.2, 0.3), car.CFrame * CFrame.new(0, 0.5, -5.9), P.Orange, model)
	MapKit.Mover(car, v(0, HANGAR - COURTYARD, 0), 30, 4, 0)
	for _, corner in { v(73, 0, 97), v(87, 0, 97), v(73, 0, 111), v(87, 0, 111) } do
		MapKit.Block(b, v(1.2, 80, 1.2), CFrame.new(corner + v(0, -34, 0)), P.DarkMetal, Enum.Material.Metal, model)
	end
	MapKit.Barrier(b, v(73, HANGAR, 111), v(87, HANGAR, 111), 90)
	MapKit.Barrier(b, v(73, HANGAR, 97), v(73, HANGAR, 111), 90)
	MapKit.Barrier(b, v(87, HANGAR, 97), v(87, HANGAR, 111), 90)
	local liftSign = MapKit.Block(b, v(12, 2.4, 0.4), CFrame.new(80, 9, 97), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Sign(liftSign, "HANGAR LIFT", Enum.NormalId.Back, P.Teal)
end

-- Firing range ---------------------------------------------------------------------------

local function buildRange(b: Builder)
	local model = MapKit.Group(b, "FiringRange")
	tiledFloor(b, -205, -40, -95, 40, COURTYARD, 11, P.Gunmetal, P.DarkMetal, Enum.Material.DiamondPlate, model)
	-- Walls.
	for _, z in { -41, 41 } do
		MapKit.Block(b, v(110, 16, 2), CFrame.new(-150, 8, z), P.Concrete, Enum.Material.Concrete, model)
		MapKit.Neon(b, v(110, 0.4, 0.2), CFrame.new(-150, 12, z + (if z < 0 then 1.1 else -1.1)), P.Orange, model)
	end
	MapKit.Block(b, v(6, 26, 84), CFrame.new(-208, 13, 0), P.DarkMetal, Enum.Material.Metal, model)
	for index = -3, 3 do
		MapKit.Block(b, v(2, 20, 10), CFrame.new(-204, 10, index * 11.5), P.Gunmetal, Enum.Material.Fabric, model)
	end
	MapKit.Block(b, v(2, 16, 28), CFrame.new(-96, 8, -27), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(2, 16, 28), CFrame.new(-96, 8, 27), P.Concrete, Enum.Material.Concrete, model)
	local header = MapKit.Block(b, v(2, 4, 26), CFrame.new(-96, 14, 0), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Sign(header, "FIRING RANGE", Enum.NormalId.Right, P.Orange)

	-- Firing line: counters and glass dividers for three lanes.
	for _, z in { -18, 0, 18 } do
		MapKit.Block(b, v(2, 3.2, 12), CFrame.new(-103, 1.6, z), P.Concrete, Enum.Material.Concrete, model)
		MapKit.Neon(b, v(0.1, 0.2, 12), CFrame.new(-104.05, 3, z), P.Teal, model)
	end
	for _, z in { -9, 9, -27, 27 } do
		MapKit.Part(b, {
			Name = "Divider",
			Size = v(8, 7, 0.4),
			CFrame = CFrame.new(-100, 3.5, z),
			Color = P.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.5,
			Parent = model,
		})
	end
	MapKit.Block(b, v(14, 1, 82), CFrame.new(-101, 12, 0), P.White, Enum.Material.SmoothPlastic, model)

	-- Distance markings and the dummies' markers.
	local lanes = { { Z = -18, X = -118 }, { Z = 0, X = -133 }, { Z = 18, X = -158 } }
	for index, lane in lanes do
		local distance = -103 - lane.X
		MapKit.Neon(b, v(0.4, 0.1, 10), CFrame.new(lane.X, 0.06, lane.Z), P.Orange, model)
		local plate = MapKit.Block(
			b,
			v(0.4, 2, 4),
			CFrame.new(lane.X - 1, 1, lane.Z + 6),
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
		MapKit.Sign(plate, `{distance}m`, Enum.NormalId.Right, P.Teal)
		-- Target frame behind each dummy.
		MapKit.Block(b, v(0.6, 10, 0.6), CFrame.new(lane.X - 3, 5, lane.Z - 3), P.DarkMetal, Enum.Material.Metal, model)
		MapKit.Block(b, v(0.6, 10, 0.6), CFrame.new(lane.X - 3, 5, lane.Z + 3), P.DarkMetal, Enum.Material.Metal, model)
		MapKit.Block(b, v(0.6, 0.6, 6.6), CFrame.new(lane.X - 3, 10, lane.Z), P.DarkMetal, Enum.Material.Metal, model)
		MapKit.Marker(b, `Range/Dummy_{index}`, CFrame.lookAt(v(lane.X, 3, lane.Z), v(-90, 3, lane.Z)))
	end
	MapKit.Marker(b, "Range/RangeZone", CFrame.new(-150, 12, 0), v(110, 24, 80))
	area(b, "Range", "The Firing Range", v(-205, -5, -40), v(-95, 30, 40))
end

-- Command Deck ---------------------------------------------------------------------------

local function buildCommandDeck(b: Builder)
	local model = MapKit.Group(b, "CommandDeck")
	-- Raised base the deck stands on, with a colonnade facade.
	-- 33 tall: the floor tiles on top fill the last stud (no coplanar faces).
	MapKit.Block(b, v(120, 33, 80), CFrame.new(0, 16.5, -140), P.Concrete, Enum.Material.Concrete, model)
	for index = -5, 5 do
		local x = index * 10.5
		if math.abs(x) > 14 then
			MapKit.Block(b, v(3, 34, 3), CFrame.new(x, 17, -99), P.White, Enum.Material.Marble, model)
		end
	end
	MapKit.Neon(b, v(120, 0.6, 0.3), CFrame.new(0, 30, -99.8), P.Orange, model)
	MapKit.Neon(b, v(120, 0.3, 0.3), CFrame.new(0, 3, -99.8), P.Teal, model)

	-- Grand stairs up from the courtyard.
	MapKit.Stairs(b, v(0, COURTYARD, -58), v(0, DECK, -100), 24, P.White, Enum.Material.Concrete, model)
	for _, x in { -12.5, 12.5 } do
		MapKit.Block(
			b,
			v(1.2, 3, 54),
			CFrame.new(x, 18, -79) * CFrame.Angles(math.rad(39), 0, 0),
			P.Concrete,
			Enum.Material.Concrete,
			model
		)
		Props.Strip(b, v(x, 1.6, -58), v(x, 35.6, -100), P.Teal, model)
	end

	-- Terrace in front of the deck room.
	tiledFloor(b, -60, -112, 60, -100, DECK, 12, P.Concrete, P.White, Enum.Material.Concrete, model)
	MapKit.Railing(b, v(-60, DECK, -100), v(-12, DECK, -100), 3.5, nil, 16, model)
	MapKit.Railing(b, v(12, DECK, -100), v(44, DECK, -100), 3.5, nil, 16, model)
	MapKit.Railing(b, v(56, DECK, -100), v(60, DECK, -100), 3.5, nil, 16, model)
	MapKit.Railing(b, v(-60, DECK, -112), v(-60, DECK, -100), 3.5, nil, 16, model)

	-- Lift from the courtyard to the terrace.
	local car = MapKit.Part(b, {
		Name = "Elevator",
		Size = v(10, 1, 10),
		CFrame = CFrame.new(50, -0.45, -95),
		Color = P.Gunmetal,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	MapKit.Neon(b, v(10.1, 0.2, 0.3), car.CFrame * CFrame.new(0, 0.5, 4.9), P.Teal, model)
	MapKit.Mover(car, v(0, DECK - COURTYARD, 0), 22, 4, 0.25)
	for _, corner in { v(44.5, 0, -89.5), v(55.5, 0, -89.5) } do
		MapKit.Block(b, v(1, 40, 1), CFrame.new(corner + v(0, 20, 0)), P.DarkMetal, Enum.Material.Metal, model)
	end
	local liftSign = MapKit.Block(b, v(11, 2, 0.4), CFrame.new(50, 41, -89.5), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Sign(liftSign, "COMMAND DECK LIFT", Enum.NormalId.Back, P.Teal)

	-- The deck room: concrete sides, glass front and back, a roof.
	local floorY = DECK
	tiledFloor(b, -55, -175, 55, -112, floorY, 11, P.White, P.Concrete, Enum.Material.Marble, model)
	local wallHeight = 22
	-- West wall (raid banners inside).
	MapKit.Block(
		b,
		v(2, wallHeight, 63),
		CFrame.new(-56, floorY + wallHeight / 2, -143.5),
		P.White,
		Enum.Material.Concrete,
		model
	)
	-- East wall with the secret passage (the middle segment has no collision).
	MapKit.Block(
		b,
		v(2, wallHeight, 45),
		CFrame.new(56, floorY + wallHeight / 2, -152.5),
		P.White,
		Enum.Material.Concrete,
		model
	)
	MapKit.Block(
		b,
		v(2, wallHeight, 12),
		CFrame.new(56, floorY + wallHeight / 2, -118),
		P.White,
		Enum.Material.Concrete,
		model
	)
	local fake = MapKit.Part(b, {
		Name = "Wall",
		Size = v(2, 10, 6),
		CFrame = CFrame.new(56, floorY + 5, -127),
		Color = P.White,
		Material = Enum.Material.Concrete,
		CanCollide = false,
		Parent = model,
	})
	fake.CanQuery = false
	MapKit.Block(
		b,
		v(2, wallHeight - 10, 6),
		CFrame.new(56, floorY + 10 + (wallHeight - 10) / 2, -127),
		P.White,
		Enum.Material.Concrete,
		model
	)
	-- A faint scuff hints at the secret.
	MapKit.Block(
		b,
		v(0.1, 0.4, 3),
		CFrame.new(54.95, floorY + 0.3, -127),
		P.ConcreteDark,
		Enum.Material.Concrete,
		model
	).CanCollide =
		false
	-- South wall: glass panels with a doorway in the middle.
	for _, span in { { -55, -8 }, { 8, 55 } } do
		local width = span[2] - span[1]
		MapKit.Part(b, {
			Name = "Window",
			Size = v(width, wallHeight - 4, 0.6),
			CFrame = CFrame.new((span[1] + span[2]) / 2, floorY + 2 + (wallHeight - 4) / 2, -112),
			Color = P.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Parent = model,
		})
		MapKit.Block(
			b,
			v(width, 2, 1),
			CFrame.new((span[1] + span[2]) / 2, floorY + 1, -112),
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
	end
	MapKit.Block(b, v(16, 6, 1), CFrame.new(0, floorY + wallHeight - 3, -112), P.DarkMetal, Enum.Material.Metal, model)
	-- North wall: glass with an opening onto the balcony.
	for _, span in { { -55, -14 }, { 14, 55 } } do
		local width = span[2] - span[1]
		MapKit.Part(b, {
			Name = "Window",
			Size = v(width, wallHeight - 2, 0.6),
			CFrame = CFrame.new((span[1] + span[2]) / 2, floorY + 1 + (wallHeight - 2) / 2, -175),
			Color = P.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Parent = model,
		})
	end
	MapKit.Block(
		b,
		v(116, 2, 67),
		CFrame.new(0, floorY + wallHeight + 1, -143.5),
		P.White,
		Enum.Material.Concrete,
		model
	)
	for index = -2, 2 do
		MapKit.Neon(
			b,
			v(4, 0.3, 60),
			CFrame.new(index * 20, floorY + wallHeight - 0.2, -143.5),
			Color3.fromRGB(255, 240, 220),
			model
		)
	end
	local ceilingLight = MapKit.Part(b, {
		Name = "CeilingLight",
		Size = v(1, 1, 1),
		CFrame = CFrame.new(0, floorY + wallHeight - 2, -143.5),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	MapKit.Light(ceilingLight, Color3.fromRGB(255, 240, 220), 60, 1.2)

	-- Holo-table.
	local tableCenter = v(0, floorY, -145)
	MapKit.Cylinder(b, 3.5, 16, tableCenter + v(0, 1.75, 0), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Cylinder(b, 0.3, 16.4, tableCenter + v(0, 3.6, 0), P.Teal, Enum.Material.Neon, model).CanCollide = false
	local holo = MapKit.Part(b, {
		Name = "Hologram",
		Shape = Enum.PartType.Ball,
		Size = v(7, 7, 7),
		CFrame = CFrame.new(tableCenter + v(0, 10, 0)),
		Color = P.Teal,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CanCollide = false,
		Parent = model,
	})
	MapKit.Light(holo, P.Teal, 20, 1.5)
	local holoRing = Props.Ring(
		b,
		CFrame.new(tableCenter + v(0, 10, 0)) * CFrame.Angles(math.rad(15), 0, 0),
		6,
		0.2,
		0.3,
		24,
		P.Orange,
		Enum.Material.Neon,
		model
	)
	holoRing:SetAttribute("SpinCenter", tableCenter + v(0, 10, 0))
	holoRing:SetAttribute("SpinAxis", v(0, 1, 0))
	holoRing:SetAttribute("SpinSpeed", 30)
	holoRing:AddTag("LL_Spin")
	for index = 0, 5 do
		local angle = index * math.pi / 3
		local moon = tableCenter + v(math.cos(angle) * 5.5, 6 + (index % 3), math.sin(angle) * 5.5)
		MapKit.Neon(b, v(0.8, 0.8, 0.8), CFrame.new(moon), if index % 2 == 0 then P.Orange else P.White, model).Shape =
			Enum.PartType.Ball
	end

	-- Strike commander with Nightfall banners.
	vendorNpc(
		b,
		"STRIKES",
		CFrame.lookAt(v(-38, floorY, -152), v(0, floorY, -152)),
		Color3.fromRGB(70, 60, 80),
		P.Orange,
		model
	)
	Props.Console(b, CFrame.lookAt(v(-32, floorY, -160), v(-32, floorY, -152)), P.Orange, model)
	for _, z in { -164, -140 } do
		Props.Banner(b, v(-48, floorY, z), 16, v(1, 0, 0), Color3.fromRGB(140, 60, 30), P.Orange, model)
	end

	-- Raid banner wall (west wall inside).
	for index, z in { -165, -150, -135, -120 } do
		local banner = MapKit.Part(b, {
			Name = "RaidBanner",
			Size = v(0.3, 14, 8),
			CFrame = CFrame.new(-54.6, floorY + 11, z),
			Color = if index % 2 == 0 then P.Black else Color3.fromRGB(40, 34, 24),
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = model,
		})
		MapKit.Neon(b, v(0.1, 5, 2), banner.CFrame * CFrame.new(0.2, 1, 0), P.Gold, model)
		MapKit.Neon(b, v(0.1, 2, 5), banner.CFrame * CFrame.new(0.2, 1, 0), P.Gold, model)
	end
	local plaque =
		MapKit.Block(b, v(0.4, 2.5, 20), CFrame.new(-54.7, floorY + 20, -142.5), P.Black, Enum.Material.Metal, model)
	MapKit.Sign(plaque, "VAULT OF ECHOES", Enum.NormalId.Right, P.Gold)

	-- Balcony overlooking the city.
	MapKit.Block(b, v(80, 2, 26), CFrame.new(0, floorY - 1, -188), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Neon(b, v(80, 0.3, 0.3), CFrame.new(0, floorY - 2, -201), P.Orange, model)
	MapKit.Railing(b, v(-40, floorY, -201), v(40, floorY, -201), 3.5, nil, 16, model)
	MapKit.Railing(b, v(-40, floorY, -175), v(-40, floorY, -201), 3.5, nil, 16, model)
	MapKit.Railing(b, v(40, floorY, -175), v(40, floorY, -201), 3.5, nil, 16, model)
	for _, x in { -30, 30 } do
		Props.Bench(b, CFrame.lookAt(v(x, floorY, -190), v(x, floorY, -220)), model)
	end
	Props.Antenna(b, v(-50, floorY + wallHeight + 2, -170), 18, model)
	Props.Antenna(b, v(46, floorY + wallHeight + 2, -120), 12, model)

	area(b, "CommandDeck", "The Command Deck", v(-60, 28, -205), v(60, 70, -100))
end

-- Secret room behind the Command Deck's east wall.
local function buildSecretRoom(b: Builder)
	local model = MapKit.Group(b, "SecretRoom")
	local y = DECK
	MapKit.Block(b, v(18, 33, 30), CFrame.new(66, 16.5, -127), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(16, 1, 28), CFrame.new(66, y - 0.5, -127), P.DarkMetal, Enum.Material.DiamondPlate, model)
	MapKit.Block(b, v(2, 12, 30), CFrame.new(75, y + 6, -127), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(18, 12, 2), CFrame.new(66, y + 6, -113), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(18, 12, 2), CFrame.new(66, y + 6, -141), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(20, 1, 30), CFrame.new(66, y + 12.5, -127), P.Concrete, Enum.Material.Concrete, model)
	local glow = MapKit.Neon(b, v(0.3, 0.3, 26), CFrame.new(73.8, y + 10, -127), P.Violet, model)
	MapKit.Light(glow, P.Violet, 16, 1)
	Props.Console(b, CFrame.lookAt(v(70, y, -135), v(64, y, -135)), P.Violet, model)
	Props.Chest(b, CFrame.lookAt(v(70, y, -120), v(60, y, -120)), "HUB_SECRET", model)
	Props.CrateStack(b, v(62, y, -137), model)
end

-- Bazaar ----------------------------------------------------------------------------------

local function buildBazaar(b: Builder)
	local model = MapKit.Group(b, "Bazaar")
	tiledFloor(
		b,
		95,
		-95,
		250,
		95,
		BAZAAR,
		15.5,
		Color3.fromRGB(222, 212, 196),
		Color3.fromRGB(206, 196, 182),
		Enum.Material.Concrete,
		model
	)

	-- The courtyard's retaining wall, dressed up.
	local wallFace = 95.2
	for index = -4, 4 do
		MapKit.Neon(
			b,
			v(0.3, 20, 0.6),
			CFrame.new(wallFace, BAZAAR + 12, index * 20 + 10),
			if index % 2 == 0 then P.Orange else P.Teal,
			model
		)
	end
	local bigSign = MapKit.Block(
		b,
		v(0.6, 5, 30),
		CFrame.new(wallFace + 0.3, BAZAAR + 21, -45),
		P.DarkMetal,
		Enum.Material.Metal,
		model
	)
	MapKit.Sign(bigSign, "THE BAZAAR", Enum.NormalId.Right, P.Orange)
	Props.Pipe(
		b,
		{ v(96.5, -8, -90), v(96.5, -8, -60), v(96.5, -14, -55), v(96.5, -14, 40) },
		1.4,
		P.ConcreteDark,
		model
	)
	Props.Pipe(b, { v(97.5, -5, 30), v(97.5, -5, 90) }, 1, P.Orange, model)

	-- Market stalls in two rows.
	local awnings = { P.Orange, P.Teal, Color3.fromRGB(200, 70, 60), Color3.fromRGB(230, 200, 80), P.Teal, P.Orange }
	local rng = b.Rng
	for index, spot in
		{
			v(140, BAZAAR, 40),
			v(140, BAZAAR, 70),
			v(165, BAZAAR, -15),
			v(190, BAZAAR, -15),
			v(215, BAZAAR, -15),
			v(215, BAZAAR, 70),
		}
	do
		local facing = if spot.Z > 0 then v(spot.X - 30, spot.Y, spot.Z) else v(spot.X, spot.Y, spot.Z + 30)
		Props.Stall(b, CFrame.lookAt(spot, facing), 10, awnings[index], model)
		Props.CrateStack(b, spot + v(rng:NextNumber(-6, 6), 0, if spot.Z > 0 then 8 else -8), model)
	end

	-- Gunsmith workshop.
	local smith = CFrame.lookAt(v(160, BAZAAR, -62), v(160, BAZAAR, -30))
	Props.Stall(b, smith, 16, Color3.fromRGB(80, 80, 90), model)
	vendorNpc(b, "GUNSMITH", smith * CFrame.new(0, 0, 3), Color3.fromRGB(80, 60, 50), P.Orange, model)
	local bench =
		MapKit.Block(b, v(8, 3.4, 3), smith * CFrame.new(-10, 1.7, 6), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(b, v(2, 1, 1), bench.CFrame * CFrame.new(1, 2.2, 0), P.Gunmetal, Enum.Material.Metal, model)
	local forge = MapKit.Neon(b, v(2.5, 0.6, 2), bench.CFrame * CFrame.new(-2.5, 2, 0), P.Orange, model)
	MapKit.Light(forge, P.Orange, 14, 2)
	for index = -3, 3 do
		MapKit.Block(
			b,
			v(0.5, 0.6, 4),
			smith * CFrame.new(index * 1.8, 6.5, 7.5) * CFrame.Angles(math.rad(80), 0, 0),
			P.Black,
			Enum.Material.Metal,
			model
		)
	end

	-- Postmaster: counter, mail wall, parcels.
	local post = CFrame.lookAt(v(203, BAZAAR, -60), v(203, BAZAAR, -30))
	Props.Stall(b, post, 12, Color3.fromRGB(120, 100, 200), model)
	vendorNpc(b, "POSTMASTER", post * CFrame.new(0, 0, 3), Color3.fromRGB(90, 80, 130), P.Violet, model)
	local mailWall = MapKit.Block(b, v(14, 10, 1), post * CFrame.new(0, 5, 7), P.DarkMetal, Enum.Material.Metal, model)
	for row = -1, 1 do
		for column = -2, 2 do
			MapKit.Block(
				b,
				v(2, 2, 0.3),
				mailWall.CFrame * CFrame.new(column * 2.6, row * 2.6, -0.6),
				Color3.fromRGB(150, 140, 190),
				Enum.Material.Metal,
				model
			)
		end
	end
	for _ = 1, 5 do
		Props.Crate(
			b,
			(post * CFrame.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-6, -3))).Position,
			v(2, 1.6, 2),
			Color3.fromRGB(190, 160, 120),
			model
		)
	end

	-- Vault terminal and door on the east wall.
	local vaultDoor = MapKit.Part(b, {
		Name = "VaultDoor",
		Shape = Enum.PartType.Cylinder,
		Size = v(3, 22, 22),
		CFrame = CFrame.new(249, BAZAAR + 12, 10),
		Color = P.Gunmetal,
		Material = Enum.Material.DiamondPlate,
		Parent = model,
	})
	Props.Ring(
		b,
		CFrame.new(247.4, BAZAAR + 12, 10) * CFrame.Angles(0, 0, math.rad(90)),
		11,
		0.8,
		0.8,
		24,
		P.Gold,
		Enum.Material.Neon,
		model
	)
	MapKit.Block(b, v(4, 26, 30), CFrame.new(252, BAZAAR + 13, 10), P.Concrete, Enum.Material.Concrete, model)
	vendorTerminal(b, "VAULT", CFrame.lookAt(v(238, BAZAAR, 10), v(200, BAZAAR, 10)), P.Gold, model)
	local _ = vaultDoor

	-- Café.
	local cafe = MapKit.Group(b, "Cafe", model)
	MapKit.Block(b, v(20, 4, 3), CFrame.new(185, BAZAAR + 2, 58), P.White, Enum.Material.Marble, cafe)
	MapKit.Block(b, v(20, 12, 2), CFrame.new(185, BAZAAR + 6, 64), P.DarkMetal, Enum.Material.Wood, cafe)
	local cafeSign =
		MapKit.Block(b, v(14, 2.4, 0.4), CFrame.new(185, BAZAAR + 13, 63), P.Black, Enum.Material.Metal, cafe)
	MapKit.Sign(cafeSign, "THE LAST CUP", Enum.NormalId.Front, P.Orange)
	for index, spot in
		{ v(170, BAZAAR, 38), v(185, BAZAAR, 36), v(200, BAZAAR, 40), v(178, BAZAAR, 24), v(194, BAZAAR, 24) }
	do
		Props.Table(b, spot, cafe)
		if index % 2 == 1 then
			Props.Parasol(b, spot + v(0, 3.3, 0), if index == 1 then P.Orange else P.Teal, cafe)
		end
	end
	Props.Planter(b, v(160, BAZAAR, 30), v(6, 2, 6), false, cafe)
	Props.Planter(b, v(210, BAZAAR, 30), v(6, 2, 6), false, cafe)

	-- Lights, banners, cables between the stall posts.
	for _, spot in
		{
			v(120, BAZAAR, -40),
			v(120, BAZAAR, 20),
			v(180, BAZAAR, -40),
			v(240, BAZAAR, -40),
			v(240, BAZAAR, 50),
			v(160, BAZAAR, 85),
		}
	do
		Props.Lamp(b, spot, 12, nil, model)
	end
	Props.Cable(b, v(120, BAZAAR + 12, -40), v(180, BAZAAR + 12, -40), 3, model)
	Props.Cable(b, v(180, BAZAAR + 12, -40), v(240, BAZAAR + 12, -40), 3, model)
	Props.Cable(b, v(120, BAZAAR + 12, 20), v(160, BAZAAR + 12, 85), 3, model)

	-- Edges.
	MapKit.Railing(b, v(250, BAZAAR, -95), v(250, BAZAAR, -2), 3.5, nil, 16, model)
	MapKit.Railing(b, v(250, BAZAAR, 22), v(250, BAZAAR, 95), 3.5, nil, 16, model)
	MapKit.Railing(b, v(100, BAZAAR, 95), v(218, BAZAAR, 95), 3.5, nil, 16, model)
	MapKit.Railing(b, v(232, BAZAAR, 95), v(250, BAZAAR, 95), 3.5, nil, 16, model)
	MapKit.Railing(b, v(155, BAZAAR, -95), v(250, BAZAAR, -95), 3.5, nil, 16, model)

	-- Stairs down to the hangar.
	MapKit.Stairs(b, v(225, HANGAR, 140), v(225, BAZAAR, 96), 12, P.Concrete, Enum.Material.Concrete, model)
	for _, x in { 218.5, 231.5 } do
		MapKit.Block(
			b,
			v(1, 3, 60),
			CFrame.new(x, (BAZAAR + HANGAR) / 2 + 2, 118) * CFrame.Angles(math.rad(43.7), 0, 0),
			P.White,
			Enum.Material.Concrete,
			model
		)
	end
	local sign =
		MapKit.Block(b, v(12, 2.4, 0.4), CFrame.new(225, BAZAAR + 8, 94), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Sign(sign, "HANGAR ↓", Enum.NormalId.Front, P.Teal)
	MapKit.Block(b, v(1, 8, 1), CFrame.new(219, BAZAAR + 4, 94), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(b, v(1, 8, 1), CFrame.new(231, BAZAAR + 4, 94), P.DarkMetal, Enum.Material.Metal, model)

	area(b, "Bazaar", "The Bazaar", v(95, BAZAAR - 5, -95), v(250, BAZAAR + 26, 95))
end

-- The Relay House and its hidden rooftop cache (reached by jumping up ledges).
local function buildRooftop(b: Builder)
	local model = MapKit.Group(b, "RelayHouse")
	local roofY = 12
	local height = roofY - BAZAAR
	MapKit.Block(
		b,
		v(26, height, 24),
		CFrame.new(235, BAZAAR + height / 2, -80),
		P.Concrete,
		Enum.Material.Concrete,
		model
	)
	for index = 1, 3 do
		local y = BAZAAR + index * 10
		MapKit.Part(b, {
			Name = "Windows",
			Size = v(22, 3, 0.3),
			CFrame = CFrame.new(235, y, -67.9),
			Color = Color3.fromRGB(60, 80, 100),
			Material = Enum.Material.Glass,
			Parent = model,
		})
	end
	-- Ledges (vents and AC boxes) climbing the south face.
	local ledges = {
		v(214, BAZAAR + 4, -64),
		v(220, BAZAAR + 9, -64),
		v(226, BAZAAR + 14, -64.5),
		v(232, BAZAAR + 19, -64.5),
		v(238, BAZAAR + 24, -64.5),
		v(244, BAZAAR + 29, -64.5),
		v(247, BAZAAR + 34, -70),
	}
	for index, spot in ledges do
		MapKit.Block(b, v(4, 1, 4), CFrame.new(spot - v(0, 0.5, 0)), P.DarkMetal, Enum.Material.DiamondPlate, model)
		if index > 1 then
			MapKit.Block(b, v(3.5, 2, 3.5), CFrame.new(spot - v(0, 2, 0)), P.Gunmetal, Enum.Material.Metal, model)
		end
	end
	MapKit.Block(b, v(4, 4, 4), CFrame.new(214, BAZAAR + 2, -64), P.Gunmetal, Enum.Material.Metal, model)
	Props.Crate(b, v(210, BAZAAR, -62), v(3, 2, 3), nil, model)
	-- Roof with the cache.
	MapKit.Block(b, v(26, 1, 24), CFrame.new(235, roofY + 0.5, -80), P.ConcreteGrey, Enum.Material.Concrete, model)
	Props.Chest(b, CFrame.lookAt(v(235, roofY + 1, -82), v(235, roofY + 1, -70)), "HUB_ROOFTOP", model)
	Props.Antenna(b, v(244, roofY + 1, -88), 14, model)
	Props.CrateStack(b, v(228, roofY + 1, -86), model)
	MapKit.Barrier(b, v(222, roofY + 1, -92), v(248, roofY + 1, -92), 12)
	MapKit.Barrier(b, v(248, roofY + 1, -92), v(248, roofY + 1, -73), 12)
end

-- Hangar ----------------------------------------------------------------------------------

local function buildHangar(b: Builder)
	local model = MapKit.Group(b, "Hangar")
	tiledFloor(
		b,
		55,
		90,
		270,
		255,
		HANGAR,
		21.5,
		Color3.fromRGB(150, 152, 156),
		Color3.fromRGB(138, 140, 146),
		Enum.Material.Concrete,
		model
	)
	-- Yellow/black safety lines.
	for _, x in { 100, 240 } do
		MapKit.Neon(b, v(0.8, 0.1, 100), CFrame.new(x, HANGAR + 0.06, 165), Color3.fromRGB(255, 200, 60), model)
	end

	-- Hangar hall.
	local top = HANGAR + 46
	MapKit.Block(b, v(3, 46, 100), CFrame.new(100, HANGAR + 23, 165), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(3, 46, 100), CFrame.new(240, HANGAR + 23, 165), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(40, 46, 3), CFrame.new(120, HANGAR + 23, 115), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(40, 46, 3), CFrame.new(220, HANGAR + 23, 115), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(60, 16, 3), CFrame.new(170, HANGAR + 38, 115), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, v(146, 3, 106), CFrame.new(170, top + 1.5, 165), P.White, Enum.Material.Concrete, model)
	for index = 0, 4 do
		local z = 122 + index * 22
		MapKit.Block(b, v(140, 2.5, 2), CFrame.new(170, top - 1.3, z), P.DarkMetal, Enum.Material.Metal, model)
		MapKit.Part(b, {
			Name = "Skylight",
			Size = v(120, 0.4, 8),
			CFrame = CFrame.new(170, top + 3.2, z + 11),
			Color = P.Glass,
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Parent = model,
		})
		local lamp = MapKit.Neon(b, v(6, 0.5, 2), CFrame.new(170, top - 2.8, z), Color3.fromRGB(255, 245, 225), model)
		MapKit.SpotLight(lamp, Color3.fromRGB(255, 245, 225), 60, 70, Enum.NormalId.Bottom)
	end
	-- Door frame toward the landing pad.
	MapKit.Block(b, v(146, 8, 4), CFrame.new(170, top - 4, 215), P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Neon(b, v(140, 0.6, 0.3), CFrame.new(170, top - 7.9, 217.2), P.Orange, model)
	local sign = MapKit.Block(b, v(30, 4, 0.4), CFrame.new(170, top - 4, 217.3), P.Black, Enum.Material.Metal, model)
	MapKit.Sign(sign, "HANGAR 3", Enum.NormalId.Back, P.Teal)

	-- Ships, containers, crane, shipwright.
	local ships = MapKit.Group(b, "Ships", model)
	Props.Ship(b, CFrame.lookAt(v(140, HANGAR + 4, 165), v(140, HANGAR + 4, 250)), 1.4, P.White, P.Orange, ships)
	Props.Ship(
		b,
		CFrame.lookAt(v(205, HANGAR + 4, 170), v(170, HANGAR + 4, 250)),
		1.2,
		Color3.fromRGB(70, 80, 95),
		P.Teal,
		ships
	)
	local containers = MapKit.Group(b, "Containers", model)
	local colors = {
		Color3.fromRGB(190, 90, 50),
		Color3.fromRGB(60, 110, 140),
		Color3.fromRGB(220, 200, 190),
		Color3.fromRGB(90, 120, 80),
	}
	for index = 0, 2 do
		Props.Container(b, CFrame.new(108, HANGAR, 132 + index * 24), colors[index % 4 + 1], containers)
		Props.Container(b, CFrame.new(108, HANGAR + 8.5, 132 + index * 24), colors[(index + 1) % 4 + 1], containers)
	end
	for index = 0, 3 do
		Props.Container(
			b,
			CFrame.new(70 + index * 10, HANGAR, 240) * CFrame.Angles(0, math.rad(90), 0),
			colors[(index + 2) % 4 + 1],
			containers
		)
	end
	Props.Crane(b, v(170, HANGAR, 200), 36, 128, model)
	local wright = CFrame.lookAt(v(160, HANGAR, 140), v(140, HANGAR, 150))
	vendorNpc(b, "MECHANIC", wright, Color3.fromRGB(110, 90, 60), P.Orange, model)
	MapKit.Block(b, v(6, 3, 3), wright * CFrame.new(4, 1.5, -2), P.Orange, Enum.Material.Metal, model)
	Props.Barrel(b, (wright * CFrame.new(-4, 0, -3)).Position, nil, model)
	Props.Barrel(b, (wright * CFrame.new(-6.5, 0, -2)).Position, P.Teal, model)
	Props.CrateStack(b, v(226, HANGAR, 130), model)

	-- Landing pad on struts beyond the wall.
	local padCenter = v(170, HANGAR, 285)
	MapKit.Cylinder(b, 3, 74, padCenter - v(0, 1.5, 0), P.Gunmetal, Enum.Material.DiamondPlate, model)
	MapKit.Block(b, v(40, 3, 40), CFrame.new(170, HANGAR - 1.5, 250), P.Gunmetal, Enum.Material.DiamondPlate, model)
	Props.Ring(b, CFrame.new(padCenter + v(0, 0.1, 0)), 32, 0.2, 1.2, 36, P.Orange, Enum.Material.Neon, model)
	for _, offset in { v(-5, 0, 0), v(5, 0, 0) } do
		MapKit.Neon(b, v(1.5, 0.2, 14), CFrame.new(padCenter + offset + v(0, 0.1, 0)), P.White, model)
	end
	MapKit.Neon(b, v(10, 0.2, 1.5), CFrame.new(padCenter + v(0, 0.1, 0)), P.White, model)
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local foot = padCenter + v(math.cos(angle) * 25, -2, math.sin(angle) * 25)
		MapKit.Rod(b, foot, v(foot.X * 0.3 + 170 * 0.7, HANGAR - 90, 255), 3, P.DarkMetal, Enum.Material.Metal, model)
	end
	Props.Ship(b, CFrame.lookAt(padCenter + v(0, 5, 0), padCenter + v(-40, 5, 20)), 1.6, P.White, P.Teal, model)
	-- Railing around the pad (open toward the hangar).
	for index = 0, 15 do
		local a0 = index / 16 * math.pi * 2
		local a1 = (index + 1) / 16 * math.pi * 2
		local p0 = padCenter + v(math.cos(a0) * 36.5, 0, math.sin(a0) * 36.5)
		local p1 = padCenter + v(math.cos(a1) * 36.5, 0, math.sin(a1) * 36.5)
		if not (p0.Z < 260 and p1.Z < 260) then
			MapKit.Railing(b, p0, p1, 3.5, nil, 16, model)
		end
	end

	-- Edges.
	MapKit.Railing(b, v(55, HANGAR, 90), v(55, HANGAR, 255), 3.5, nil, 16, model)
	MapKit.Railing(b, v(270, HANGAR, 90), v(270, HANGAR, 255), 3.5, nil, 16, model)
	MapKit.Railing(b, v(55, HANGAR, 255), v(150, HANGAR, 255), 3.5, nil, 16, model)
	MapKit.Railing(b, v(190, HANGAR, 255), v(270, HANGAR, 255), 3.5, nil, 16, model)

	area(b, "Hangar", "The Hangar", v(55, HANGAR - 10, 88), v(270, HANGAR + 38, 325))
end

-- Scenery ---------------------------------------------------------------------------------

local function buildCity(b: Builder)
	local city = MapKit.Group(b, "City")
	city.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local rng = b.Rng
	-- Ground, grass, a river, and mountains around the valley.
	MapKit.TerrainBlock(b, CFrame.new(0, CITY - 12, 0), v(2600, 24, 2600), Enum.Material.Ground)
	for _ = 1, 14 do
		local x, z = rng:NextNumber(-1100, 1100), rng:NextNumber(-1100, 1100)
		MapKit.TerrainCylinder(b, CFrame.new(x, CITY - 1, z), 3, rng:NextNumber(60, 180), Enum.Material.Grass)
	end
	MapKit.TerrainBlock(b, CFrame.new(-560, CITY - 8, 0), v(130, 20, 2600), Enum.Material.Air)
	MapKit.TerrainBlock(b, CFrame.new(-560, CITY - 12, 0), v(120, 12, 2600), Enum.Material.Water)
	for index = 0, 9 do
		local angle = index * math.pi * 2 / 10 + rng:NextNumber(-0.2, 0.2)
		local distance = rng:NextNumber(1150, 1350)
		local base = v(math.cos(angle) * distance, CITY, math.sin(angle) * distance)
		local scale = rng:NextNumber(0.8, 1.2)
		MapKit.TerrainBall(b, base, 240 * scale, Enum.Material.Rock)
		MapKit.TerrainBall(b, base + v(0, 200 * scale, 0), 160 * scale, Enum.Material.Rock)
		MapKit.TerrainBall(b, base + v(0, 340 * scale, 0), 90 * scale, Enum.Material.Slate)
		MapKit.TerrainBall(b, base + v(0, 400 * scale, 0), 50 * scale, Enum.Material.Snow)
	end

	-- Ruined city blocks around the tower's base.
	local roadColor = Color3.fromRGB(58, 60, 64)
	for _, z in { -700, -350, 350, 700 } do
		MapKit.Part(b, {
			Name = "Road",
			Size = v(2000, 1, 26),
			CFrame = CFrame.new(100, CITY + 0.4, z),
			Color = roadColor,
			Material = Enum.Material.Asphalt,
			CastShadow = false,
			Parent = city,
		})
	end
	local placed = 0
	local attempts = 0
	while placed < 130 and attempts < 1000 do
		attempts += 1
		local x, z = rng:NextNumber(-1050, 1050), rng:NextNumber(-1050, 1050)
		local clearOfTower = math.abs(x - 30) > 270 or math.abs(z - 30) > 260
		local clearOfRiver = math.abs(x + 560) > 90
		local clearOfRoads = math.abs(math.abs(z) - 350) > 30 and math.abs(math.abs(z) - 700) > 30
		if clearOfTower and clearOfRiver and clearOfRoads then
			placed += 1
			local width, depth = rng:NextNumber(30, 70), rng:NextNumber(30, 70)
			local height = rng:NextNumber(40, 170)
			local shade = rng:NextNumber(0.55, 0.85)
			Props.Building(
				b,
				v(x, CITY, z),
				v(width, height, depth),
				Color3.new(shade, shade, shade * 0.98),
				rng:NextNumber() < 0.45,
				city
			)
		end
	end
end

local function buildSky(b: Builder)
	local sky = MapKit.Group(b, "Sky")
	sky.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	-- The Lantern: a pale sphere with glowing seams and three slow orbit rings.
	local center = v(-900, 420, -1400)
	local lantern = MapKit.Group(b, "Lantern", sky)
	local sphere = MapKit.Part(b, {
		Name = "Sphere",
		Shape = Enum.PartType.Ball,
		Size = v(600, 600, 600),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(232, 228, 220),
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.05,
		CanCollide = false,
		Parent = lantern,
	})
	sphere.CanQuery = false
	for index, tilt in { 0, 60, 120 } do
		Props.Ring(
			b,
			CFrame.new(center) * CFrame.Angles(math.rad(tilt), math.rad(index * 25), math.rad(90)),
			301,
			2,
			4,
			48,
			Color3.fromRGB(190, 240, 255),
			Enum.Material.Neon,
			lantern
		)
	end
	for index, spec in
		{
			{ Radius = 420, Tilt = 12, Speed = 3 },
			{ Radius = 480, Tilt = -24, Speed = -2 },
			{ Radius = 545, Tilt = 38, Speed = 1.5 },
		}
	do
		local ring = Props.Ring(
			b,
			CFrame.new(center) * CFrame.Angles(math.rad(spec.Tilt), math.rad(index * 40), 0),
			spec.Radius,
			3,
			10,
			40,
			Color3.fromRGB(205, 200, 190),
			Enum.Material.Metal,
			lantern
		)
		ring:SetAttribute("SpinCenter", center)
		ring:SetAttribute("SpinAxis", (CFrame.Angles(math.rad(spec.Tilt), math.rad(index * 40), 0)).UpVector)
		ring:SetAttribute("SpinSpeed", spec.Speed)
		ring:AddTag("LL_Spin")
	end

	-- Ships looping around the tower (animated by each client).
	local flights = {
		{ Center = v(0, 120, 0), Radius = 520, Speed = 0.05, Phase = 0, Scale = 2.2, Hull = P.White },
		{
			Center = v(200, 60, 300),
			Radius = 320,
			Speed = -0.07,
			Phase = 2,
			Scale = 1.8,
			Hull = Color3.fromRGB(70, 80, 95),
		},
		{ Center = v(-400, 210, -300), Radius = 720, Speed = 0.03, Phase = 4, Scale = 3, Hull = P.White },
		{
			Center = v(300, 20, -500),
			Radius = 260,
			Speed = 0.09,
			Phase = 1,
			Scale = 1.6,
			Hull = Color3.fromRGB(180, 80, 50),
		},
		{ Center = v(0, -200, 600), Radius = 420, Speed = 0.06, Phase = 3, Scale = 2.4, Hull = P.White },
	}
	for index, flight in flights do
		local start = flight.Center
			+ v(math.cos(flight.Phase) * flight.Radius, 0, math.sin(flight.Phase) * flight.Radius)
		local ship = Props.Ship(
			b,
			CFrame.new(start),
			flight.Scale,
			flight.Hull,
			if index % 2 == 0 then P.Orange else P.Teal,
			sky
		)
		ship.Name = `Flyer_{index}`
		for _, part in ship:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		ship:SetAttribute("FlightCenter", flight.Center)
		ship:SetAttribute("FlightRadius", flight.Radius)
		ship:SetAttribute("FlightSpeed", flight.Speed)
		ship:SetAttribute("FlightPhase", flight.Phase)
		ship:AddTag("LL_Flyer")
	end
end

local function sound(b: Builder, name: string, id: number, position: Vector3, range: number, volume: number)
	local holder = MapKit.Part(b, {
		Name = name,
		Size = v(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local audio = Instance.new("Sound")
	audio.Name = name
	audio.Looped = true
	audio.Volume = volume
	audio.RollOffMaxDistance = range
	audio.SoundId = AssetIds.Get(id)
	audio.Playing = id ~= 0
	audio.Parent = holder
end

local function buildAmbience(b: Builder)
	local ambient = AssetIds.Sounds.Ambient
	sound(b, "Wind", ambient.HubWind, v(0, 30, 0), 2000, 0.4)
	sound(b, "Crowd", ambient.HubCrowd, v(0, 3, 0), 160, 0.5)
	sound(b, "CrowdBazaar", ambient.HubCrowd, v(175, BAZAAR + 3, 0), 140, 0.5)
	sound(b, "Ships", ambient.HubShips, v(170, HANGAR + 10, 180), 260, 0.6)
end

-- Build -----------------------------------------------------------------------------------

function HubBuilder.Build(): Model
	local b = MapKit.New("Hub", 1337)
	b.Model:SetAttribute("DisplayName", "The Spire")
	b.Model:SetAttribute("KillY", -120)

	MapKit.Marker(b, "Spawns/HubSpawn", CFrame.lookAt(v(0, 3, 62), v(0, 3, 0)))
	buildTower(b)
	buildCourtyard(b)
	buildRange(b)
	buildCommandDeck(b)
	buildSecretRoom(b)
	buildBazaar(b)
	buildRooftop(b)
	buildHangar(b)
	buildCity(b)
	buildSky(b)
	buildAmbience(b)
	area(b, "Courtyard", "The Courtyard", v(-95, -5, -185), v(95, 30, 110))
	return MapKit.Finish(b)
end

return HubBuilder
