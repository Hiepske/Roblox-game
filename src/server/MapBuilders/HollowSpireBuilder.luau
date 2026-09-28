--!strict
--[[
	Hollow Spire (the Nightfall, 450+): a Rustborn cliff fortress at dusk.
	Fight up Redrock Canyon, break the Iron Gate's shield generators, clear
	the inner halls and hold the lift, then climb the grand stairs to the
	Spire Crown, a round arena hanging over the abyss, where Vekta waits.
	At a third of Vekta's health the middle of the arena floor collapses.

	Layout (the path runs along +Z; the canyon floor is Y = 0):
	  Zone Canyon  z -40..300    wrecked vehicles, turrets on the ledges;
	                             Shield gate at the canyon exit (z 300)
	  Zone Gate    z 300..420    the plaza before the fortress wall; three
	                             generators; snipers on the wall; Door gate
	  Zone Halls   z 424..627    the great hall (turret balconies) and the lift
	                             hall (hold the controls); Door gate at z 627
	  Zone Summit  y 60          grand stairs up to the Spire Crown (z 725..835)

	Markers (Markers/...):
	  Spawns/PlayerStart
	  Checkpoints/CP_Canyon, CP_Gate, CP_Halls, CP_Summit
	  Objectives/CanyonBend, LiftControls (zone boxes), Generator_1..3
	  EnemySpawns/Canyon, CanyonLedges, Gate, GateWall, Halls, HallTurrets, Summit
	  BossArena/BossSpawn, Chest, Ammo_1..3, Pylon_1..3
	Gates: Gate_Canyon (Shield), Gate_Gate (Door), Gate_Halls (Door).
	The collapsing floor is the model "CollapseFloor". KillY -40.
]]

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local HollowSpire = {}

local P = MapKit.Palette
local RUST = Color3.fromRGB(150, 78, 44)
local IRON = Color3.fromRGB(58, 54, 56)
local SANDSTONE = Color3.fromRGB(176, 110, 76)

local SUMMIT = Vector3.new(0, 60, 780)
local SUMMIT_RADIUS = 55

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

local function around(center: Vector3, radius: number, degrees: number, y: number?): Vector3
	local angle = math.rad(degrees)
	return center + v(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
end

-- Markers and gates ------------------------------------------------------------------------

local function markers(b: Builder)
	MapKit.Marker(b, "Spawns/PlayerStart", facing(v(0, 3, -25), v(0, 3, 60)))
	local checkpoints: { [string]: { Vector3 } } = {
		CP_Canyon = { v(0, 3, -25), v(0, 3, 60) },
		CP_Gate = { v(0, 3, 308), v(0, 3, 400) },
		CP_Halls = { v(0, 3, 432), v(0, 3, 500) },
		CP_Summit = { v(0, SUMMIT.Y + 3, 721), SUMMIT },
	}
	for name, spot in checkpoints do
		MapKit.Marker(b, `Checkpoints/{name}`, facing(spot[1], spot[2]))
	end
	MapKit.Zone(b, "Objectives/CanyonBend", v(0, 0, 90), 22)
	MapKit.Zone(b, "Objectives/LiftControls", v(0, 0.4, 600), 12)
	for index, spot in { v(-46, 0, 386), v(46, 0, 386), v(0, 0, 346) } do
		MapKit.Marker(b, `Objectives/Generator_{index}`, CFrame.new(spot + v(0, 0.5, 0)))
	end

	MapKit.EnemySpawns(b, "Canyon", {
		v(-26, 0, 150),
		v(24, 0, 170),
		v(-18, 0, 230),
		v(20, 0, 260),
		v(0, 0, 285),
		v(-30, 0, 120),
		v(30, 0, 205),
	}, v(0, 0, 60))
	MapKit.EnemySpawns(b, "CanyonLedges", {
		v(-37, 18.5, 120),
		v(37, 18.5, 180),
		v(-37, 18.5, 250),
		v(37, 18.5, 250),
	}, v(0, 0, 100))
	MapKit.EnemySpawns(b, "Gate", {
		v(-60, 0, 408),
		v(60, 0, 408),
		v(-30, 0, 404),
		v(30, 0, 404),
		v(-70, 0, 352),
		v(70, 0, 362),
	}, v(0, 0, 320))
	MapKit.EnemySpawns(b, "GateWall", { v(-50, 40.5, 420), v(50, 40.5, 420), v(-66, 40.5, 420) }, v(0, 0, 330))
	MapKit.EnemySpawns(b, "Halls", {
		v(-38, 0.4, 526),
		v(38, 0.4, 526),
		v(-28, 0.4, 614),
		v(28, 0.4, 614),
		v(0, 0.4, 620),
		v(-30, 0.4, 490),
	}, v(0, 0.4, 440))
	MapKit.EnemySpawns(
		b,
		"HallTurrets",
		{ v(-40, 10.5, 470), v(40, 10.5, 470), v(-40, 10.5, 510), v(40, 10.5, 510) },
		v(0, 0, 440)
	)
	local ring: { Vector3 } = {}
	for index = 0, 5 do
		table.insert(ring, around(SUMMIT, 47, index * 60 + 30))
	end
	MapKit.EnemySpawns(b, "Summit", ring, SUMMIT)

	MapKit.Marker(b, "BossArena/BossSpawn", facing(SUMMIT + v(0, 1, 36), SUMMIT + v(0, 1, -60)))
	MapKit.Marker(b, "BossArena/Chest", CFrame.new(SUMMIT + v(0, 0.5, -38)))
	for index, degrees in { 60, 180, 300 } do
		MapKit.Marker(b, `BossArena/Ammo_{index}`, CFrame.new(around(SUMMIT, 32, degrees, 0.5)))
	end
	for index, degrees in { 30, 150, 270 } do
		MapKit.Marker(b, `BossArena/Pylon_{index}`, CFrame.new(around(SUMMIT, 44, degrees, 0.5)))
	end

	MapKit.Gate(b, "Canyon", "Shield", v(46, 22, 1.5), CFrame.new(0, 11, 300), P.Orange)
	MapKit.Gate(b, "Gate", "Door", v(24, 26, 4), CFrame.new(0, 13, 420), P.Orange)
	MapKit.Gate(b, "Halls", "Door", v(16, 18, 3), CFrame.new(0, 9.4, 627), P.Orange)
end

-- Terrain ----------------------------------------------------------------------------------------

local function terrain(b: Builder)
	local rng = b.Rng
	-- The canyon floor and the ground up to the cliff edge behind the fortress.
	MapKit.TerrainBlock(b, CFrame.new(0, -8, 280), v(320, 16, 720), Enum.Material.Ground)
	-- Canyon walls with ledges, and the rocky bowl around the gate plaza.
	for _, side in { -1, 1 } do
		MapKit.TerrainBlock(b, CFrame.new(side * 85, 30, 130), v(86, 80, 420), Enum.Material.Sandstone)
		MapKit.TerrainBlock(b, CFrame.new(side * 112, 30, 490), v(64, 80, 300), Enum.Material.Sandstone)
		for _, z in { 120, 180, 250 } do
			MapKit.TerrainBlock(b, CFrame.new(side * 37, 9, z), v(10, 18, 56), Enum.Material.Rock)
		end
		-- The narrow canyon exit.
		MapKit.TerrainBlock(b, CFrame.new(side * 33, 15, 300), v(22, 30, 14), Enum.Material.Rock)
		for z = -60, 640, 70 do
			MapKit.TerrainBall(
				b,
				v(side * rng:NextNumber(150, 190), rng:NextNumber(30, 60), z),
				rng:NextNumber(50, 80),
				Enum.Material.Sandstone
			)
		end
	end
	MapKit.TerrainBall(b, v(0, 20, -120), 90, Enum.Material.Sandstone)
	-- Distant mesas across the abyss.
	for index = 0, 6 do
		local spot = around(SUMMIT, rng:NextNumber(320, 420), 20 + index * 23, -60)
		MapKit.TerrainCylinder(
			b,
			CFrame.new(spot),
			rng:NextNumber(160, 240),
			rng:NextNumber(50, 90),
			Enum.Material.Sandstone
		)
	end
end

-- Zone 1: the canyon ----------------------------------------------------------------------------

local function wreckedCrawler(b: Builder, cframe: CFrame, parent: Instance)
	local model = MapKit.Group(b, "Crawler", parent)
	MapKit.Block(b, v(14, 6, 24), cframe * CFrame.new(0, 4, 0), RUST, Enum.Material.CorrodedMetal, model)
	MapKit.Block(b, v(10, 4, 10), cframe * CFrame.new(0, 9, -3), IRON, Enum.Material.Metal, model)
	MapKit.Rod(
		b,
		(cframe * CFrame.new(0, 9.5, -8)).Position,
		(cframe * CFrame.new(0, 11, -20)).Position,
		1.4,
		IRON,
		Enum.Material.Metal,
		model
	)
	for _, x in { -7.5, 7.5 } do
		MapKit.Block(b, v(3, 5, 26), cframe * CFrame.new(x, 2.5, 0), P.Black, Enum.Material.Rubber, model)
	end
	Props.Fire(b, (cframe * CFrame.new(2, 11, 0)).Position, 6, model)
	Props.Smoke(b, (cframe * CFrame.new(2, 12, 0)).Position, 8, Color3.fromRGB(60, 50, 46), model)
end

local function canyon(b: Builder)
	local area = MapKit.Group(b, "Canyon")
	local rng = b.Rng
	-- A worn road up the middle.
	MapKit.Block(b, v(24, 0.3, 330), CFrame.new(0, 0.15, 130), Color3.fromRGB(120, 90, 70), Enum.Material.Pebble, area)
	wreckedCrawler(b, CFrame.new(-16, 0, 60) * CFrame.Angles(0, math.rad(20), math.rad(6)), area)
	wreckedCrawler(b, CFrame.new(18, 0, 210) * CFrame.Angles(0, math.rad(-150), 0), area)
	for index, spot in { v(22, 3, 120), v(-20, 4, 160), v(-8, 3, 260) } do
		local skiff = Props.Ship(
			b,
			CFrame.new(spot) * CFrame.Angles(math.rad(10), index * 1.9, math.rad(25 - index * 12)),
			1.6,
			RUST,
			P.Orange,
			area
		)
		skiff.Name = "WreckedSkiff"
	end
	for _ = 1, 16 do
		local spot = v(rng:NextNumber(-34, 34), 1, rng:NextNumber(0, 290))
		if math.abs(spot.X) > 8 then
			Props.Rock(b, spot, rng:NextNumber(4, 9), SANDSTONE, area)
		end
	end
	for _, spot in { v(-10, 0, 110), v(12, 0, 150), v(-14, 0, 240), v(6, 0, 190) } do
		MapKit.Block(
			b,
			v(9, 3.5, 2),
			CFrame.new(spot + v(0, 1.75, 0)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			IRON,
			Enum.Material.DiamondPlate,
			area
		)
		Props.Barrel(b, spot + v(4, 0, 2), RUST, area)
	end
	-- Turret nests on the ledges.
	for _, side in { -1, 1 } do
		for _, z in { 120, 180, 250 } do
			MapKit.Block(b, v(1, 2.5, 14), CFrame.new(side * 32.5, 19.25, z), IRON, Enum.Material.Metal, area)
			Props.Banner(b, v(side * 40, 18, z + 20), 12, v(-side, 0, 0), RUST, P.Orange, area)
		end
	end
	-- Rustborn catwalks spanning the canyon overhead, hung with lamps and cables.
	for index, z in { 70, 160, 232 } do
		local walk = CFrame.new(0, 26, z) * CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 2 else -2))
		MapKit.Block(b, v(90, 1.2, 6), walk, IRON, Enum.Material.DiamondPlate, area)
		for _, zSide in { -3, 3 } do
			MapKit.Block(b, v(90, 0.4, 0.4), walk * CFrame.new(0, 3, zSide), RUST, Enum.Material.Metal, area)
		end
		for x = -36, 36, 18 do
			MapKit.Block(b, v(0.4, 3, 0.4), walk * CFrame.new(x, 1.5, 3), RUST, Enum.Material.Metal, area)
			MapKit.Block(b, v(0.4, 3, 0.4), walk * CFrame.new(x, 1.5, -3), RUST, Enum.Material.Metal, area)
		end
		for _, x in { -20, 20 } do
			local hanging = (walk * CFrame.new(x, -0.6, 0)).Position
			local chain = MapKit.Rod(b, hanging, hanging - v(0, 5, 0), 0.25, P.Black, Enum.Material.Metal, area)
			if chain then
				chain.CanCollide = false
			end
			local lamp = MapKit.Neon(b, v(1.4, 1.4, 1.4), CFrame.new(hanging - v(0, 5.8, 0)), P.Orange, area)
			MapKit.Light(lamp, P.Orange, 30, 1.8)
		end
		Props.Banner(b, (walk * CFrame.new(0, -12, 0)).Position, 11, v(0, 0, -1), RUST, P.Orange, area)
	end
	for _, pair in { { v(-43, 34, 20), v(43, 30, 110) }, { v(-43, 32, 190), v(43, 34, 280) } } do
		Props.Cable(b, pair[1], pair[2], 5, area)
	end

	-- Rustborn warning totems at the exit.
	for _, x in { -24, 24 } do
		MapKit.Block(b, v(3, 22, 3), CFrame.new(x, 11, 298), IRON, Enum.Material.Metal, area)
		MapKit.Neon(b, v(3.2, 1, 3.2), CFrame.new(x, 21, 298), P.Orange, area)
	end
	Props.Weather(b, v(0, 70, 150), v(90, 2, 330), "Ash", area)
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 44, 0, -60), v(side * 44, 0, 300), 90)
	end
	MapKit.Barrier(b, v(-44, 0, -60), v(44, 0, -60), 90)
end

-- Zone 2: the Iron Gate --------------------------------------------------------------------------

local function gatePlaza(b: Builder)
	local area = MapKit.Group(b, "IronGate")
	local rng = b.Rng
	-- The fortress wall with a walkway, crenellations and two gate towers.
	for _, side in { -1, 1 } do
		MapKit.Block(b, v(68, 40, 8), CFrame.new(side * 46, 20, 420), IRON, Enum.Material.CorrodedMetal, area)
		for x = 14, 78, 8 do
			MapKit.Block(b, v(4, 4, 2), CFrame.new(side * x, 42, 416.5), IRON, Enum.Material.Metal, area)
		end
		MapKit.Neon(b, v(68, 0.6, 8.2), CFrame.new(side * 46, 30, 420), P.Orange, area)
		local tower = CFrame.new(side * 20, 28, 420)
		MapKit.Block(b, v(14, 56, 14), tower, RUST, Enum.Material.CorrodedMetal, area)
		MapKit.Block(b, v(16, 3, 16), tower * CFrame.new(0, 29, 0), IRON, Enum.Material.Metal, area)
		Props.Banner(b, v(side * 20, 0, 411), 30, v(0, 0, -1), RUST, P.Orange, area)
		local lamp = MapKit.Neon(b, v(3, 3, 3), tower * CFrame.new(0, 32, 0), P.Orange, area)
		MapKit.SpotLight(lamp, P.Orange, 90, 45, Enum.NormalId.Front)
	end
	MapKit.Block(b, v(26, 14, 8), CFrame.new(0, 33, 420), IRON, Enum.Material.CorrodedMetal, area)
	-- Barricades, spikes and burning barrels on the plaza.
	for _, spot in { v(-26, 0, 344), v(28, 0, 360), v(-20, 0, 392), v(18, 0, 398), v(-56, 0, 352), v(58, 0, 354) } do
		MapKit.Block(
			b,
			v(10, 4, 2.5),
			CFrame.new(spot + v(0, 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
			IRON,
			Enum.Material.DiamondPlate,
			area
		)
		for index = -1, 1 do
			MapKit.Wedge(
				b,
				v(0.8, 3, 1.6),
				CFrame.new(spot + v(index * 3, 5, 0)) * CFrame.Angles(0, 0, 0),
				RUST,
				Enum.Material.Metal,
				area
			)
		end
	end
	for _, spot in { v(-40, 0, 320), v(40, 0, 330), v(0, 0, 372), v(-66, 0, 400), v(66, 0, 396) } do
		Props.Barrel(b, spot, RUST, area)
		Props.Fire(b, spot + v(0, 3.6, 0), 3, area)
	end
	Props.ScrapPile(b, v(-60, 0, 372), 10, area)
	Props.ScrapPile(b, v(64, 0, 380), 9, area)
	Props.Weather(b, v(0, 70, 360), v(160, 2, 120), "Ash", area)
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 80, 0, 300), v(side * 80, 0, 420), 90)
		MapKit.Barrier(b, v(side * 22, 0, 302), v(side * 80, 0, 302), 90)
	end
end

-- Zone 3: the inner halls -------------------------------------------------------------------------

local function halls(b: Builder)
	local area = MapKit.Group(b, "Halls")
	MapKit.Room(b, v(0, 0.4, 480), 90, 110, {
		WallHeight = 30,
		WallThickness = 2,
		FloorThickness = 2.4,
		FloorColor = IRON,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = RUST,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = { North = 24, South = 24 },
		TrimColor = P.Orange,
		Roof = true,
		RoofColor = IRON,
		RoofMaterial = Enum.Material.Metal,
	})
	MapKit.Room(b, v(0, 0.4, 582), 70, 90, {
		WallHeight = 36,
		WallThickness = 2,
		FloorThickness = 2.4,
		FloorColor = IRON,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = RUST,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = { North = 16, South = 20 },
		TrimColor = P.Orange,
		Roof = true,
		RoofColor = IRON,
		RoofMaterial = Enum.Material.Metal,
	})
	-- Turret balconies along the great hall.
	for _, side in { -1, 1 } do
		MapKit.Block(b, v(8, 1, 70), CFrame.new(side * 40, 10, 490), IRON, Enum.Material.DiamondPlate, area)
		MapKit.Railing(b, v(side * 36, 10.5, 455), v(side * 36, 10.5, 525), 3.2, IRON, 4, area)
		for z = 440, 530, 30 do
			MapKit.Block(b, v(3, 30, 3), CFrame.new(side * 30, 15.4, z), IRON, Enum.Material.Metal, area)
			local lamp = MapKit.Neon(b, v(1.2, 1.2, 1.2), CFrame.new(side * 30, 22, z - 1.8), P.Orange, area)
			MapKit.Light(lamp, P.Orange, 26, 1.8)
		end
	end
	-- Cover in the great hall.
	for _, spot in { v(-14, 0.4, 455), v(16, 0.4, 470), v(-10, 0.4, 505), v(12, 0.4, 520) } do
		Props.CrateStack(b, spot, area)
	end
	Props.Container(b, CFrame.new(-18, 0.4, 485) * CFrame.Angles(0, math.rad(90), 0), RUST, area)
	Props.Container(b, CFrame.new(18, 0.4, 515) * CFrame.Angles(0, math.rad(90), 0), IRON, area)
	-- The lift hall: controls on a raised pad, the lift machinery overhead.
	local controls = v(0, 0.4, 600)
	MapKit.Cylinder(b, 1, 24, controls + v(0, 0.5, 0), IRON, Enum.Material.DiamondPlate, area)
	MapKit.ZoneRing(b, controls + v(0, 1.1, 0), 12, P.Orange, area)
	Props.Console(b, facing(controls + v(0, 1, -2), controls + v(0, 1, -20)), P.Orange, area)
	for _, x in { -30, 30 } do
		MapKit.Block(b, v(6, 36, 6), CFrame.new(x, 18.4, 610), IRON, Enum.Material.Metal, area)
		Props.Pipe(b, { v(x, 30, 610), v(x, 30, 580), v(0, 30, 580) }, 2, RUST, area)
	end
	for _, spot in { v(-20, 0.4, 560), v(22, 0.4, 575), v(-24, 0.4, 612) } do
		Props.CrateStack(b, spot, area)
	end
	-- Chains, vents and wall machinery.
	for _, spot in { v(-20, 30.4, 450), v(10, 30.4, 480), v(-8, 30.4, 520), v(20, 36.4, 560), v(-18, 36.4, 590) } do
		local chain = MapKit.Rod(b, spot, spot - v(0, 10, 0), 0.35, P.Black, Enum.Material.Metal, area)
		if chain then
			chain.CanCollide = false
		end
		MapKit.Block(b, v(1.6, 1.6, 1.6), CFrame.new(spot - v(0, 10.8, 0)), RUST, Enum.Material.Metal, area)
	end
	for _, spot in { v(-43.5, 6, 450), v(43.5, 6, 500), v(-33.5, 8, 570), v(33.5, 8, 600) } do
		MapKit.Block(b, v(2, 8, 10), CFrame.new(spot), IRON, Enum.Material.Metal, area)
		MapKit.Neon(b, v(2.1, 0.4, 10.1), CFrame.new(spot + v(0, 2, 0)), P.Orange, area)
		Props.Smoke(b, spot + v(0, 4.5, 0), 2, Color3.fromRGB(110, 100, 96), area)
	end
	Props.Banner(b, v(-12, 0.4, 624), 20, v(0, 0, -1), RUST, P.Orange, area)
	Props.Banner(b, v(12, 0.4, 624), 20, v(0, 0, -1), RUST, P.Orange, area)
end

-- Zone 4: the grand stairs and the Spire Crown -----------------------------------------------------

local function summit(b: Builder)
	local area = MapKit.Group(b, "SpireCrown")
	-- The grand stairs from the lift hall up to the crown.
	MapKit.Stairs(b, v(0, 0.4, 628), v(0, SUMMIT.Y, 716), 18, IRON, Enum.Material.DiamondPlate, area)
	for _, x in { -9, 9 } do
		-- Sloped handrails (posts and a rail) with an invisible wall behind them.
		MapKit.Barrier(b, v(x, 0.4, 626), v(x, 0.4, 718), SUMMIT.Y + 30)
		MapKit.Rod(b, v(x, 4, 628), v(x, SUMMIT.Y + 3.6, 716), 0.4, IRON, Enum.Material.Metal, area)
		for z = 632, 712, 10 do
			local y = (z - 628) / 88 * (SUMMIT.Y - 0.4) + 0.4
			MapKit.Block(b, v(0.4, 3.6, 0.4), CFrame.new(x, y + 1.8, z), IRON, Enum.Material.Metal, area)
		end
		for z = 640, 710, 23 do
			local lamp = MapKit.Neon(b, v(1, 1, 1), CFrame.new(x, (z - 628) / 88 * SUMMIT.Y + 6, z), P.Orange, area)
			MapKit.Light(lamp, P.Orange, 18, 1.5)
		end
	end
	MapKit.Block(b, v(22, 2, 12), CFrame.new(0, SUMMIT.Y - 1, 722), IRON, Enum.Material.DiamondPlate, area)
	-- The arena: an outer ring of plates around the floor that will fall.
	local segments = 36
	local chord = 2 * SUMMIT_RADIUS * math.sin(math.pi / segments) + 0.6
	local ringWidth = SUMMIT_RADIUS - 20
	for index = 1, segments do
		local degrees = index * (360 / segments)
		local middle = around(SUMMIT, 20 + ringWidth / 2, degrees, -1.5)
		MapKit.Part(b, {
			Name = "RingPlate",
			Size = v(chord, 3, ringWidth),
			CFrame = CFrame.lookAt(middle, SUMMIT + v(0, -1.5, 0)),
			Color = if index % 2 == 0 then IRON else Color3.fromRGB(70, 64, 64),
			Material = Enum.Material.DiamondPlate,
			Parent = area,
		})
	end
	local collapse = MapKit.Group(b, "CollapseFloor", area)
	MapKit.Cylinder(b, 3, 41, SUMMIT + v(0, -1.5, 0), Color3.fromRGB(90, 80, 76), Enum.Material.Concrete, collapse)
	Props.Ring(b, CFrame.new(SUMMIT + v(0, 0.1, 0)), 14, 0.2, 1, 24, P.Orange, Enum.Material.Neon, collapse)
	MapKit.Neon(
		b,
		v(24, 0.2, 1),
		CFrame.new(SUMMIT + v(0, 0.1, 0)) * CFrame.Angles(0, math.rad(45), 0),
		P.Orange,
		collapse
	)
	MapKit.Neon(
		b,
		v(24, 0.2, 1),
		CFrame.new(SUMMIT + v(0, 0.1, 0)) * CFrame.Angles(0, math.rad(-45), 0),
		P.Orange,
		collapse
	)
	Props.Ring(
		b,
		CFrame.new(SUMMIT + v(0, 0.1, 0)),
		20.3,
		0.2,
		0.8,
		32,
		Color3.fromRGB(255, 70, 40),
		Enum.Material.Neon,
		area
	)
	-- The rim: a low parapet you can't fall over (except where the stairs arrive).
	for index = 1, 24 do
		local a = index * 15
		local from = around(SUMMIT, SUMMIT_RADIUS, a)
		local to = around(SUMMIT, SUMMIT_RADIUS, a + 15)
		local toStairs = math.abs(((a + 7.5) % 360) - 270) < 12
		if not toStairs then
			MapKit.Wall(b, from, to, 3, 1.5, RUST, Enum.Material.CorrodedMetal, area)
			MapKit.Barrier(b, from, to, 40)
			-- Spikes on the parapet.
			MapKit.Wedge(
				b,
				v(0.8, 3, 1.6),
				CFrame.lookAt(from + v(0, 4.5, 0), SUMMIT + v(0, 4.5, 0)),
				IRON,
				Enum.Material.Metal,
				area
			)
		end
	end
	-- Pillars holding the crown up out of the abyss.
	for index = 0, 7 do
		local top = around(SUMMIT, 44, index * 45 + 22.5, -3)
		MapKit.Rod(b, top, top + v(0, -140, 0) + (top - SUMMIT).Unit * 20, 5, IRON, Enum.Material.Metal, area)
	end
	-- Braziers, banners and a tall mast with a beacon.
	for index = 0, 3 do
		local spot = around(SUMMIT, 50, index * 90 + 45)
		Props.Barrel(b, spot, RUST, area)
		Props.Fire(b, spot + v(0, 3.6, 0), 5, area)
		Props.Banner(
			b,
			around(SUMMIT, 52, index * 90),
			18,
			(SUMMIT - around(SUMMIT, 52, index * 90)).Unit,
			RUST,
			P.Orange,
			area
		)
	end
	local mast = around(SUMMIT, 50, 90)
	MapKit.Rod(b, mast, mast + v(0, 40, 0), 2, IRON, Enum.Material.Metal, area)
	local beacon = MapKit.Neon(b, v(3, 3, 3), CFrame.new(mast + v(0, 41, 0)), P.Red, area)
	MapKit.Light(beacon, P.Red, 40, 3)
	Props.Weather(b, SUMMIT + v(0, 40, 0), v(120, 2, 120), "Ash", area)
end

function HollowSpire.Build(): Model
	local b = MapKit.New("HollowSpire")
	b.Model:SetAttribute("KillY", -40)
	b.Model:SetAttribute("DisplayName", "Hollow Spire")
	markers(b)
	terrain(b)
	canyon(b)
	gatePlaza(b)
	halls(b)
	summit(b)
	return MapKit.Finish(b)
end

return HollowSpire
