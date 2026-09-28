--!strict
--[[
	Sunken Relay (story mission 2, power 380): a drowned coastal city on the
	Meridian Coast, swallowed by jungle. A Concord relay tower still hums at
	the end of the flooded market; climb it floor by floor and silence it.

	Layout (the path runs along +Z; the ocean is to the south):
	  Zone Beach       z -90..60    Glasswater Beach: landing craft, huts, palms;
	                                 Shield gate in the sea wall at z 60
	  Zone Market      z 60..305    the Drowned Market: streets under 2 studs of
	                                 water, boardwalks, stalls, balconies (marksmen);
	                                 Door gate into the tower at z 305
	  Zone LowerDeck   tower y 1    relay conduits and server racks; the stairs up
	                                 the east wall end on a landing behind a Door
	  Zone SignalDeck  tower y 31   three signal jammers; the stairs up the west
	                                 wall end on a landing behind a Shield
	  Zone Crown       tower y 61   the rooftop around the great antenna (boss)
	The tower is 90 x 90 (x -45..45, z 305..395).

	Markers (Markers/...):
	  Spawns/PlayerStart
	  Checkpoints/CP_Beach, CP_Market, CP_LowerDeck, CP_SignalDeck, CP_Crown
	  Objectives/Dunes (zone box), Jammer_1..3
	  EnemySpawns/Beach, Market, MarketBalconies, LowerDeck, SignalDeck, Crown
	  BossArena/BossSpawn, Ammo_1..3, Pylon_1..3
	Gates: Gate_Beach (Shield), Gate_Market (Door), Gate_LowerDeck (Door),
	Gate_SignalDeck (Shield).
]]

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local SunkenRelay = {}

local P = MapKit.Palette
local STUCCO = Color3.fromRGB(214, 200, 176)
local TEAL = Color3.fromRGB(80, 230, 230)
local CONCORD = Color3.fromRGB(120, 230, 255)

local TOWER = Vector3.new(0, 0, 350)
local LEVEL_2 = 31
local ROOF = 61

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

-- Markers and gates ------------------------------------------------------------------------

local function markers(b: Builder)
	MapKit.Marker(b, "Spawns/PlayerStart", facing(v(0, 3, -45), v(0, 3, 40)))
	local checkpoints: { [string]: { Vector3 } } = {
		CP_Beach = { v(0, 3, -45), v(0, 3, 40) },
		CP_Market = { v(0, 3, 70), v(0, 3, 200) },
		CP_LowerDeck = { v(0, 4, 314), v(0, 4, 360) },
		CP_SignalDeck = { v(37, LEVEL_2 + 3, 388), v(0, LEVEL_2 + 3, 388) },
		CP_Crown = { v(-37, ROOF + 3, 314), v(0, ROOF + 3, 314) },
	}
	for name, spot in checkpoints do
		MapKit.Marker(b, `Checkpoints/{name}`, facing(spot[1], spot[2]))
	end
	MapKit.Zone(b, "Objectives/Dunes", v(0, 0, 12), 20)
	for index, spot in { v(-26, LEVEL_2, 320), v(12, LEVEL_2, 345), v(-18, LEVEL_2, 385) } do
		MapKit.Marker(b, `Objectives/Jammer_{index}`, CFrame.new(spot + v(0, 0.5, 0)))
	end

	MapKit.EnemySpawns(b, "Beach", {
		v(-52, 0, 40),
		v(-22, 0, 50),
		v(22, 0, 52),
		v(52, 0, 40),
		v(-68, 0, 8),
		v(68, 0, 4),
	}, v(0, 0, -20))
	MapKit.EnemySpawns(b, "Market", {
		v(-30, 0, 150),
		v(30, 0, 172),
		v(-26, 0, 232),
		v(26, 0, 252),
		v(0, 0, 288),
		v(-40, 0, 282),
		v(40, 0, 282),
	}, v(0, 0, 120))
	MapKit.EnemySpawns(b, "MarketBalconies", { v(-37, 15, 140), v(37, 15, 205), v(-37, 15, 262) }, v(0, 0, 150))
	MapKit.EnemySpawns(b, "LowerDeck", {
		v(-36, 1, 388),
		v(-10, 1, 388),
		v(20, 1, 330),
		v(-36, 1, 330),
		v(0, 1, 372),
	}, v(0, 1, 310))
	MapKit.EnemySpawns(b, "SignalDeck", {
		v(-8, LEVEL_2, 312),
		v(20, LEVEL_2, 312),
		v(-20, LEVEL_2, 360),
		v(10, LEVEL_2, 390),
		v(-38, LEVEL_2, 388),
	}, v(37, LEVEL_2, 388))
	local crown: { Vector3 } = {}
	for index = 0, 5 do
		local angle = math.rad(index * 60 + 15)
		table.insert(crown, v(math.cos(angle) * 34, ROOF, TOWER.Z + math.sin(angle) * 34))
	end
	MapKit.EnemySpawns(b, "Crown", crown, TOWER)

	MapKit.Marker(b, "BossArena/BossSpawn", facing(v(20, ROOF + 1, 380), v(-37, ROOF + 1, 314)))
	MapKit.Marker(b, "BossArena/Ammo_1", CFrame.new(v(34, ROOF + 0.5, 318)))
	MapKit.Marker(b, "BossArena/Ammo_2", CFrame.new(v(-30, ROOF + 0.5, 388)))
	MapKit.Marker(b, "BossArena/Ammo_3", CFrame.new(v(34, ROOF + 0.5, 388)))
	MapKit.Marker(b, "BossArena/Pylon_1", CFrame.new(v(-34, ROOF + 0.5, 392 - 6)))
	MapKit.Marker(b, "BossArena/Pylon_2", CFrame.new(v(38, ROOF + 0.5, 312)))
	MapKit.Marker(b, "BossArena/Pylon_3", CFrame.new(v(38, ROOF + 0.5, 390)))

	MapKit.Gate(b, "Beach", "Shield", v(24, 16, 1.5), CFrame.new(0, 8, 60), CONCORD)
	MapKit.Gate(b, "Market", "Door", v(20, 18, 3), CFrame.new(0, 10, 305), CONCORD)
	MapKit.Gate(b, "LowerDeck", "Door", v(1.5, 12, 13), CFrame.new(29.25, LEVEL_2 + 6, 387), CONCORD)
	MapKit.Gate(b, "SignalDeck", "Shield", v(1.5, 12, 23), CFrame.new(-29.25, ROOF + 6, 318), CONCORD)
end

-- Terrain ----------------------------------------------------------------------------------------

local function terrain(b: Builder)
	-- The ocean to the south, its sand floor, and the beach rising out of it.
	MapKit.TerrainBlock(b, CFrame.new(0, -40, -300), v(1100, 10, 500), Enum.Material.Sand)
	MapKit.TerrainBlock(b, CFrame.new(0, -17.5, -300), v(1100, 35, 500), Enum.Material.Water)
	-- The shore slopes down into the water (a wedge's tall side is its +Z face).
	MapKit.TerrainWedge(b, CFrame.new(0, -8, -75), v(260, 16, 30), Enum.Material.Sand)
	MapKit.TerrainBlock(b, CFrame.new(0, -8, 0), v(260, 16, 120), Enum.Material.Sand)
	-- The drowned market: mud under two studs of water.
	MapKit.TerrainBlock(b, CFrame.new(0, -9.5, 182), v(260, 16, 244), Enum.Material.Mud)
	MapKit.TerrainBlock(b, CFrame.new(0, -0.5, 182), v(124, 2, 240), Enum.Material.Water)
	MapKit.TerrainBlock(b, CFrame.new(0, -8, 350), v(200, 16, 110), Enum.Material.Mud)
	-- Jungle hills on both sides and behind the tower.
	local rng = b.Rng
	for z = -60, 480, 60 do
		for _, side in { -1, 1 } do
			local x = side * rng:NextNumber(130, 170)
			MapKit.TerrainBall(b, v(x, rng:NextNumber(-10, 10), z), rng:NextNumber(55, 80), Enum.Material.Ground)
			MapKit.TerrainBall(
				b,
				v(x + side * 8, rng:NextNumber(18, 30), z + 12),
				rng:NextNumber(40, 60),
				Enum.Material.LeafyGrass
			)
		end
	end
	for x = -180, 180, 90 do
		MapKit.TerrainBall(b, v(x, 20, 520), rng:NextNumber(80, 110), Enum.Material.LeafyGrass)
	end
end

-- Zone 1: the beach ---------------------------------------------------------------------------------

local function beach(b: Builder)
	local area = MapKit.Group(b, "Beach")
	local rng = b.Rng
	-- Our landing craft, run up on the sand.
	local craft = MapKit.Group(b, "LandingCraft", area)
	local hull = CFrame.new(-10, 1.5, -64) * CFrame.Angles(0, math.rad(12), math.rad(4))
	MapKit.Block(b, v(14, 3, 26), hull, P.Gunmetal, Enum.Material.Metal, craft)
	MapKit.Wedge(
		b,
		v(14, 3, 8),
		hull * CFrame.new(0, 0, -17) * CFrame.Angles(0, math.rad(180), 0),
		P.Gunmetal,
		Enum.Material.Metal,
		craft
	)
	MapKit.Block(b, v(14, 6, 1), hull * CFrame.new(0, 4.5, 13), P.DarkMetal, Enum.Material.Metal, craft)
	MapKit.Block(
		b,
		v(12, 0.6, 10),
		hull * CFrame.new(0, 0.2, -24) * CFrame.Angles(math.rad(-25), 0, 0),
		P.DarkMetal,
		Enum.Material.DiamondPlate,
		craft
	)
	MapKit.Neon(b, v(14.2, 0.4, 0.4), hull * CFrame.new(0, 1.6, 0), P.Teal, craft)
	-- Palms, huts, parasols, boats.
	for _ = 1, 22 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.Palm(b, v(side * rng:NextNumber(30, 95), 0, rng:NextNumber(-50, 55)), rng:NextNumber(16, 26), area)
	end
	local hutColors =
		{ Color3.fromRGB(90, 170, 190), Color3.fromRGB(230, 170, 90), Color3.fromRGB(220, 110, 90), STUCCO }
	for index, spot in { v(-60, 0, -10), v(-40, 0, 30), v(46, 0, 22), v(72, 0, -20), v(-78, 0, 44) } do
		Props.House(
			b,
			facing(spot, v(0, 0, 0)),
			v(12, 8, 10),
			hutColors[index % #hutColors + 1],
			Color3.fromRGB(150, 120, 80),
			false,
			area
		)
	end
	for _, spot in { v(-20, 0, -20), v(-14, 0, 2), v(24, 0, -12), v(30, 0, 14) } do
		Props.Parasol(b, spot, if spot.X < 0 then P.Orange else P.Teal, area)
	end
	for index, spot in { v(40, 0, -58), v(62, 0, -40), v(-54, 0, -48) } do
		local boat = MapKit.Group(b, "Boat", area)
		local frame = CFrame.new(spot + v(0, 1.2, 0))
			* CFrame.Angles(0, index * 1.3, math.rad(if index == 2 then 150 else 14))
		MapKit.Block(b, v(5, 2, 13), frame, Color3.fromRGB(220, 225, 230), Enum.Material.SmoothPlastic, boat)
		MapKit.Wedge(
			b,
			v(5, 2, 4),
			frame * CFrame.new(0, 0, -8.5) * CFrame.Angles(0, math.rad(180), 0),
			Color3.fromRGB(220, 225, 230),
			Enum.Material.SmoothPlastic,
			boat
		)
		MapKit.Block(b, v(5.1, 0.4, 13.1), frame * CFrame.new(0, 0.6, 0), P.Teal, Enum.Material.SmoothPlastic, boat)
	end
	-- A lifeguard tower and driftwood cover.
	Props.Watchtower(b, v(10, 0, 32), 10, area)
	for _, spot in { v(-30, 0, 18), v(8, 0, 44), v(38, 0, 46), v(-8, 0, 28) } do
		MapKit.Block(
			b,
			v(9, 1.6, 1.6),
			CFrame.new(spot + v(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.1),
			P.Bark,
			Enum.Material.Wood,
			area
		)
		Props.Crate(b, spot + v(3, 0, 3), v(4, 3.5, 4), Color3.fromRGB(150, 120, 80), area)
	end
	-- The broken sea wall with its Concord barrier.
	for _, side in { -1, 1 } do
		MapKit.Wall(b, v(side * 12, 0, 60), v(side * 105, 0, 60), 14, 4, P.ConcreteGrey, Enum.Material.Concrete, area)
		for x = 20, 100, 16 do
			Props.Vines(b, v(side * x, 14, 58), v(0, 0, -1), 10, 10, area)
		end
		MapKit.Block(b, v(3, 18, 4), CFrame.new(side * 13.5, 9, 60), P.DarkMetal, Enum.Material.Metal, area)
		MapKit.Neon(b, v(3.2, 1, 4.2), CFrame.new(side * 13.5, 17, 60), CONCORD, area)
	end
	-- A skyscraper that fell into the sea.
	local sunk = CFrame.new(-150, 20, -170) * CFrame.Angles(math.rad(-18), math.rad(30), math.rad(24))
	MapKit.Block(b, v(40, 160, 40), sunk, STUCCO, Enum.Material.Concrete, area).CanQuery = false
	for y = -60, 60, 14 do
		MapKit.Block(b, v(40.4, 3, 40.4), sunk * CFrame.new(0, y, 0), P.Black, Enum.Material.Glass, area).CanQuery =
			false
	end
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 100, 0, -95), v(side * 100, 0, 62), 80)
	end
	MapKit.Barrier(b, v(-100, 0, -95), v(100, 0, -95), 80)
end

-- Zone 2: the drowned market -----------------------------------------------------------------------

local function balconyBuilding(b: Builder, base: Vector3, side: number, parent: Instance)
	local building = MapKit.Group(b, "BalconyBuilding", parent)
	local body = CFrame.new(base + v(side * 10, 11, 0))
	MapKit.Block(b, v(20, 22, 22), body, STUCCO, Enum.Material.Concrete, building)
	-- The balcony faces the street.
	local balcony = CFrame.new(base + v(-side * 2, 14, 0))
	MapKit.Block(b, v(6, 1, 16), balcony, P.ConcreteGrey, Enum.Material.Concrete, building)
	MapKit.Railing(b, base + v(-side * 5, 14.5, -8), base + v(-side * 5, 14.5, 8), 3.2, P.Gunmetal, 3, building)
	for _, y in { 5, 16 } do
		MapKit.Block(
			b,
			v(0.4, 4, 18),
			CFrame.new(base + v(side * 0.05 - side * 0.2, y, 0)),
			P.Black,
			Enum.Material.Glass,
			building
		)
	end
	Props.Vines(b, base + v(side * 0.2, 22, 0) + v(-side * 0.4, 0, 0), v(-side, 0, 0), 18, 16, building)
	Props.Planter(b, base + v(side * 10, 22, 0), v(14, 1.2, 14), true, building)
end

local function market(b: Builder)
	local area = MapKit.Group(b, "Market")
	local rng = b.Rng
	-- Boardwalks above the water along both sides.
	for _, x in { -20, 20 } do
		MapKit.Block(b, v(7, 0.8, 230), CFrame.new(x, 0.9, 185), P.Bark, Enum.Material.WoodPlanks, area)
		for z = 75, 295, 12 do
			MapKit.Block(b, v(0.8, 3, 0.8), CFrame.new(x - 3.3, -0.5, z), P.Bark, Enum.Material.Wood, area)
			MapKit.Block(b, v(0.8, 3, 0.8), CFrame.new(x + 3.3, -0.5, z), P.Bark, Enum.Material.Wood, area)
		end
	end
	-- Buildings on both sides; some with balconies for marksmen.
	for _, z in { 140, 205, 262 } do
		local side = if z == 205 then 1 else -1
		balconyBuilding(b, v(side * 40, 0, z), side, area)
	end
	-- The rest of the street (the balcony buildings sit at z 140/262 west, 205 east).
	for index, spot in { { 1, 100 }, { 1, 150 }, { 1, 250 }, { 1, 288 }, { -1, 100 }, { -1, 200 }, { -1, 290 } } do
		local side, z = spot[1], spot[2]
		local size = v(rng:NextNumber(18, 24), rng:NextNumber(18, 34), rng:NextNumber(18, 24))
		local building = Props.Building(
			b,
			v(side * (40 + size.X / 2), 0, z),
			size,
			if index % 2 == 0 then STUCCO else Color3.fromRGB(180, 190, 176),
			true,
			area
		)
		Props.Vines(b, v(side * 40.2, size.Y * 0.7, z), v(-side, 0, 0), size.Z * 0.8, size.Y * 0.6, building)
	end
	-- Half-drowned stalls, parasols, floating crates and barrels.
	for index, z in { 95, 128, 185, 220, 270 } do
		local side = if index % 2 == 0 then 1 else -1
		Props.Stall(b, facing(v(side * 10, -1, z), v(0, -1, z)), 10, if side > 0 then P.Teal else P.Orange, area)
	end
	for _, spot in { v(-6, 0, 110), v(8, 0, 160), v(-10, 0, 200), v(4, 0, 245), v(-4, 0, 280) } do
		-- Crates bobbing in the flood, tipped at odd angles.
		MapKit.Block(
			b,
			v(4, 3.5, 4),
			CFrame.new(spot + v(0, 0.4, 0)) * CFrame.Angles(0.15, rng:NextNumber(0, 3), 0.1),
			Color3.fromRGB(150, 120, 80),
			Enum.Material.WoodPlanks,
			area
		)
	end
	for _ = 1, 8 do
		Props.Barrel(
			b,
			v(rng:NextNumber(-14, 14), -0.6, rng:NextNumber(80, 295)),
			if rng:NextNumber() < 0.5 then P.Rust else P.Teal,
			area
		)
	end
	for _ = 1, 10 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.Palm(b, v(side * rng:NextNumber(24, 34), -1, rng:NextNumber(70, 300)), rng:NextNumber(18, 28), area)
	end
	-- Cables and string lights between the buildings.
	for z = 100, 290, 38 do
		Props.StringLights(b, v(-39, 16, z), v(39, 16, z + 12), Color3.fromRGB(255, 210, 140), area)
	end
	Props.Weather(b, v(0, 80, 185), v(130, 2, 240), "Rain", area)
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 62, 0, 58), v(side * 62, 0, 306), 80)
	end
end

-- The tower ------------------------------------------------------------------------------------------

local function towerShell(b: Builder, area: Instance)
	-- Base platform above the water and the outer walls of each level.
	MapKit.Block(b, v(100, 4, 100), CFrame.new(TOWER + v(0, -1, 0)), P.ConcreteGrey, Enum.Material.Concrete, area)
	local walls = { P.White, STUCCO, P.White }
	for level, base in { 1, LEVEL_2, ROOF } do
		local height = if base == ROOF then 0 else 30
		if height > 0 then
			local color = walls[level]
			-- Front (with the entrance on level 1), back, and sides with window bands.
			if base == 1 then
				MapKit.Wall(b, v(-45, base, 305), v(-10, base, 305), height, 3, color, Enum.Material.Concrete, area)
				MapKit.Wall(b, v(10, base, 305), v(45, base, 305), height, 3, color, Enum.Material.Concrete, area)
				MapKit.Block(
					b,
					v(20, height - 18, 3),
					CFrame.new(0, base + 18 + (height - 18) / 2, 305),
					color,
					Enum.Material.Concrete,
					area
				)
			else
				MapKit.Wall(b, v(-45, base, 305), v(45, base, 305), 6, 3, color, Enum.Material.Concrete, area)
				MapKit.Wall(
					b,
					v(-45, base + 20, 305),
					v(45, base + 20, 305),
					10,
					3,
					color,
					Enum.Material.Concrete,
					area
				)
				MapKit.Block(b, v(90, 14, 0.4), CFrame.new(0, base + 13, 305), P.Glass, Enum.Material.Glass, area).Transparency =
					0.6
			end
			MapKit.Wall(b, v(-45, base, 395), v(45, base, 395), height, 3, color, Enum.Material.Concrete, area)
			for _, x in { -45, 45 } do
				MapKit.Wall(b, v(x, base, 305), v(x, base, 395), height, 3, color, Enum.Material.Concrete, area)
				Props.Vines(b, v(x * 1.035, base + height, 350), v(x, 0, 0), 60, 14, area)
			end
			MapKit.Neon(b, v(91, 0.5, 3.2), CFrame.new(0, base + height - 1, 305), CONCORD, area)
			MapKit.Neon(b, v(91, 0.5, 3.2), CFrame.new(0, base + height - 1, 395), CONCORD, area)
		end
	end
	-- Level 2 floor, open above the east stairs (x 30..44, z 328..380).
	MapKit.Block(b, v(73.5, 1, 87), CFrame.new(-6.75, LEVEL_2 - 0.5, 350), P.Gunmetal, Enum.Material.DiamondPlate, area)
	MapKit.Block(
		b,
		v(13.5, 1, 21.5),
		CFrame.new(36.75, LEVEL_2 - 0.5, 317.25),
		P.Gunmetal,
		Enum.Material.DiamondPlate,
		area
	)
	MapKit.Block(
		b,
		v(13.5, 1, 13.5),
		CFrame.new(36.75, LEVEL_2 - 0.5, 386.75),
		P.Gunmetal,
		Enum.Material.DiamondPlate,
		area
	)
	-- The roof, open above the west stairs (x -44..-30, z 330..380).
	MapKit.Block(b, v(73.5, 1, 87), CFrame.new(6.75, ROOF - 0.5, 350), P.ConcreteGrey, Enum.Material.Concrete, area)
	MapKit.Block(
		b,
		v(13.5, 1, 23.5),
		CFrame.new(-36.75, ROOF - 0.5, 318.25),
		P.ConcreteGrey,
		Enum.Material.Concrete,
		area
	)
	MapKit.Block(
		b,
		v(13.5, 1, 13.5),
		CFrame.new(-36.75, ROOF - 0.5, 386.75),
		P.ConcreteGrey,
		Enum.Material.Concrete,
		area
	)
	-- East stairs: level 1 up to the landing behind Gate_LowerDeck.
	MapKit.Stairs(b, v(37, 1, 328), v(37, LEVEL_2, 380), 12, P.Gunmetal, Enum.Material.DiamondPlate, area)
	MapKit.Barrier(b, v(30.5, 1, 326), v(30.5, 1, 381), 45)
	MapKit.Railing(b, v(30.5, LEVEL_2, 327), v(30.5, LEVEL_2, 380), 3.5, P.Gunmetal, 1, area)
	-- West stairs: level 2 up to the roof landing behind Gate_SignalDeck.
	MapKit.Stairs(b, v(-37, LEVEL_2, 380), v(-37, ROOF, 330), 12, P.Gunmetal, Enum.Material.DiamondPlate, area)
	MapKit.Barrier(b, v(-30.5, LEVEL_2, 329), v(-30.5, LEVEL_2, 382), 45)
	MapKit.Railing(b, v(-30.5, ROOF, 330), v(-30.5, ROOF, 380), 3.5, P.Gunmetal, 1, area)
	-- The roof parapet.
	for _, edge in
		{
			{ v(-45, ROOF, 305), v(45, ROOF, 305) },
			{ v(-45, ROOF, 395), v(45, ROOF, 395) },
			{ v(-45, ROOF, 305), v(-45, ROOF, 395) },
			{ v(45, ROOF, 305), v(45, ROOF, 395) },
		}
	do
		MapKit.Wall(b, edge[1], edge[2], 2.5, 2, P.White, Enum.Material.Concrete, area)
		MapKit.Barrier(b, edge[1], edge[2], 40)
	end
end

local function lowerDeck(b: Builder, area: Instance)
	-- Floor, the relay heart and server racks.
	MapKit.Block(b, v(88, 0.4, 88), CFrame.new(TOWER + v(0, 1.2, 0)), P.DarkMetal, Enum.Material.DiamondPlate, area)
	local core = TOWER + v(-8, 1.4, 0)
	MapKit.Cylinder(b, 1, 18, core + v(0, 0.5, 0), P.Gunmetal, Enum.Material.Metal, area)
	local beam = MapKit.Cylinder(b, 29, 4, core + v(0, 15, 0), TEAL, Enum.Material.Neon, area)
	MapKit.Light(beam, TEAL, 50, 2.5)
	for _, y in { 4, 12, 20 } do
		Props.Ring(b, CFrame.new(core + v(0, y, 0)), 5, 0.8, 1.2, 16, P.DarkMetal, Enum.Material.Metal, area)
	end
	for index = 0, 5 do
		local x = -40 + index * 13
		for _, z in { 330, 370 } do
			if x < 26 then
				MapKit.Block(b, v(4, 10, 8), CFrame.new(x, 6.4, z), P.Black, Enum.Material.Metal, area)
				MapKit.Neon(b, v(4.1, 0.3, 8.1), CFrame.new(x, 4 + (index % 3) * 2, z), CONCORD, area)
			end
		end
	end
	for _, spot in { v(-30, 1.4, 350), v(15, 1.4, 350), v(-15, 1.4, 315) } do
		Props.Console(b, facing(spot, core), CONCORD, area)
	end
	for _, x in { -30, -10, 10 } do
		local lamp = MapKit.Neon(b, v(6, 0.4, 6), CFrame.new(x, 30.4, 350), P.White, area)
		MapKit.Light(lamp, Color3.fromRGB(220, 240, 255), 40, 1.5)
	end
end

local function signalDeck(b: Builder, area: Instance)
	-- Antenna feeds from the floor to the roof, desks and cover.
	for _, spot in { v(-10, LEVEL_2, 330), v(10, LEVEL_2, 370), v(-24, LEVEL_2, 360) } do
		MapKit.Block(b, v(10, 4, 3), CFrame.new(spot + v(0, 2, 0)), P.Gunmetal, Enum.Material.Metal, area)
		MapKit.Neon(b, v(10.1, 0.3, 3.1), CFrame.new(spot + v(0, 3, 0)), CONCORD, area)
	end
	for _, spot in { v(0, LEVEL_2, 318), v(-38, LEVEL_2, 340), v(20, LEVEL_2, 388) } do
		Props.CrateStack(b, spot, area)
	end
	Props.Pipe(b, { v(-8, LEVEL_2, 350), v(-8, ROOF - 1, 350) }, 3, P.Gunmetal, area)
	for _, x in { -30, -8, 14 } do
		local lamp = MapKit.Neon(b, v(6, 0.4, 6), CFrame.new(x, ROOF - 1.2, 350), P.White, area)
		MapKit.Light(lamp, Color3.fromRGB(220, 240, 255), 40, 1.5)
	end
end

local function crown(b: Builder, area: Instance)
	-- The great antenna: a mast with spinning rings and a glowing tip.
	local base = v(-8, ROOF, 350)
	MapKit.Cylinder(b, 2, 14, base + v(0, 1, 0), P.DarkMetal, Enum.Material.DiamondPlate, area)
	MapKit.Rod(b, base, base + v(0, 48, 0), 3, P.White, Enum.Material.Metal, area)
	local tip = MapKit.Neon(b, v(4, 4, 4), CFrame.new(base + v(0, 50, 0)), CONCORD, area)
	tip.Shape = Enum.PartType.Ball
	MapKit.Light(tip, CONCORD, 60, 3)
	for index, y in { 18, 30, 40 } do
		local ring =
			Props.Ring(b, CFrame.new(base + v(0, y, 0)), 9 - index * 1.5, 0.6, 1, 16, CONCORD, Enum.Material.Neon, area)
		ring:SetAttribute("SpinCenter", base + v(0, y, 0))
		ring:SetAttribute("SpinAxis", v(0, 1, 0))
		ring:SetAttribute("SpinSpeed", if index % 2 == 0 then -30 else 30)
		ring:AddTag("LL_Spin")
	end
	-- Dishes on the corners, vents and cover.
	for _, spot in { v(34, ROOF, 334), v(-24, ROOF, 388), v(30, ROOF, 368) } do
		MapKit.Block(b, v(8, 5, 8), CFrame.new(spot + v(0, 2.5, 0)), P.Gunmetal, Enum.Material.Metal, area)
		MapKit.Neon(b, v(8.1, 0.4, 8.1), CFrame.new(spot + v(0, 4, 0)), CONCORD, area)
	end
	for _, spot in { v(-24, ROOF, 330), v(18, ROOF, 312), v(4, ROOF, 385) } do
		MapKit.Block(b, v(10, 3.5, 2), CFrame.new(spot + v(0, 1.75, 0)), P.White, Enum.Material.Concrete, area)
	end
end

local function skyline(b: Builder)
	local area = MapKit.Group(b, "Skyline")
	local rng = b.Rng
	for _ = 1, 16 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local base = v(side * rng:NextNumber(180, 320), -2, rng:NextNumber(-40, 520))
		local size = v(rng:NextNumber(30, 50), rng:NextNumber(60, 140), rng:NextNumber(30, 50))
		local building = Props.Building(
			b,
			base,
			size,
			if rng:NextNumber() < 0.5 then STUCCO else Color3.fromRGB(170, 180, 170),
			true,
			area
		)
		Props.Vines(
			b,
			base + v(-side * size.X / 2, size.Y * 0.5, 0),
			v(-side, 0, 0),
			size.Z * 0.6,
			size.Y * 0.4,
			building
		)
	end
end

function SunkenRelay.Build(): Model
	local b = MapKit.New("SunkenRelay")
	b.Model:SetAttribute("KillY", -30)
	b.Model:SetAttribute("DisplayName", "Sunken Relay")
	markers(b)
	terrain(b)
	beach(b)
	market(b)
	local tower = MapKit.Group(b, "RelayTower")
	towerShell(b, tower)
	lowerDeck(b, tower)
	signalDeck(b, tower)
	crown(b, tower)
	skyline(b)
	return MapKit.Finish(b)
end

return SunkenRelay
