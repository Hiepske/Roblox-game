--!strict
--[[
	Vault of Echoes (raid, 6 players, solo-launchable): a gold-and-black
	vault sunk under Solace Deep, where every sound is a weapon.

	Layout (the path runs along +Z):
	  Upper level (Y = 0)
	    Entrance      z -60..0      PlayerStart, CP_Gate
	    The Gate      z 0..170      round arena (r 70): Harrowmaw before the
	                                vault gate; echo plates Plate_1..3; Door
	                                gate Gate_Gate at z 168
	  The Descent     z 175..410    a jumping puzzle dropping to Y = -30:
	                                static and moving platforms over the abyss
	                                (fall = back to CP_Descent); Shield gate
	                                Gate_Descent at z 410
	  Lower level (Y = -30)
	    Echo Chamber  hub (0, 480)  the well in the middle with Oriane on its
	                                pillar; three rooms (west, east, north)
	                                where the Echo Bearers appear; Door gate
	                                Gate_Chamber in the north room (z 570)
	    Silent Hall   z 570..770    laser traps (sweeping and blinking) and a
	                                sentinel patrol; Shield gate Gate_SilentHall
	    The Throne    (0, 850)      round arena (r 65): the Echo Sovereign

	Markers (Markers/...):
	  Spawns/PlayerStart
	  Checkpoints/CP_Gate, CP_Descent, CP_Chamber, CP_SilentHall, CP_Throne
	  Objectives/GateEntry, DescentEnd, ChamberEntry, HallEnd, ThroneEntry
	  EnemySpawns/Gate, Chamber, Throne, HallPatrol (the patrol route)
	  GateArena/BossSpawn, Ammo_1..3, Chest
	  ChamberArena/BossSpawn, EchoWell, Room_1..3, Ammo_1..3, Chest
	  ThroneArena/BossSpawn, Safe_1..4, Pylon_1..3, Teleport_1..3, Ammo_1..3, Chest
	Lasers are parts tagged LL_Laser (the server burns players inside them).
	KillY -120.
]]

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local VaultOfEchoes = {}

local GOLD = Color3.fromRGB(214, 170, 78)
local BLACK = Color3.fromRGB(20, 20, 24)
local MARBLE = Color3.fromRGB(34, 34, 40)
local ECHO = Color3.fromRGB(110, 235, 255)
local LASER = Color3.fromRGB(255, 50, 60)

local GATE = Vector3.new(0, 0, 85)
local LOW = -30
local HUB = Vector3.new(0, LOW, 480)
local THRONE = Vector3.new(0, LOW, 850)

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

-- Shared pieces -----------------------------------------------------------------------------

-- A round arena floor with a gold rim, and a wall around it (gaps at the
-- given angles for doorways).
local function arena(b: Builder, center: Vector3, radius: number, openings: { number }, parent: Instance)
	MapKit.Cylinder(b, 2, radius * 2 + 4, center + v(0, -1, 0), MARBLE, Enum.Material.Marble, parent)
	Props.Ring(b, CFrame.new(center + v(0, 0.05, 0)), radius * 0.62, 0.1, 1.2, 40, GOLD, Enum.Material.Neon, parent)
	Props.Ring(b, CFrame.new(center + v(0, 0.05, 0)), radius - 2, 0.1, 1.6, 48, GOLD, Enum.Material.Neon, parent)
	local segments = 32
	for index = 0, segments - 1 do
		local a = index * 360 / segments
		local mid = a + 180 / segments
		local open = false
		for _, gap in openings do
			local diff = math.abs(((mid - gap + 180) % 360) - 180)
			if diff < 10 then
				open = true
			end
		end
		if not open then
			local from = around(center, radius + 1, a)
			local to = around(center, radius + 1, a + 360 / segments)
			MapKit.Wall(b, from, to, 22, 3, BLACK, Enum.Material.Marble, parent)
			MapKit.Neon(
				b,
				v(3.2, 0.6, (to - from).Magnitude),
				CFrame.lookAt((from + to) / 2 + v(0, 18, 0), (to + v(0, 18, 0))),
				GOLD,
				parent
			)
		end
	end
	-- Gold pillars around the rim.
	for index = 0, 7 do
		local spot = around(center, radius - 4, index * 45 + 22.5)
		MapKit.Block(b, v(4, 26, 4), CFrame.new(spot + v(0, 13, 0)), BLACK, Enum.Material.Marble, parent)
		MapKit.Block(b, v(4.6, 1, 4.6), CFrame.new(spot + v(0, 26.5, 0)), GOLD, Enum.Material.Metal, parent)
		local glow = MapKit.Neon(b, v(1, 8, 4.2), CFrame.new(spot + v(0, 10, 0)), ECHO, parent)
		MapKit.Light(glow, ECHO, 26, 1.4)
	end
end

local function laser(b: Builder, size: Vector3, cframe: CFrame, parent: Instance): Part
	local beam = MapKit.Part(b, {
		Name = "Laser",
		Size = size,
		CFrame = cframe,
		Color = LASER,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
	beam:SetAttribute("Damage", 45)
	beam:AddTag("LL_Laser")
	return beam
end

-- Markers and gates ------------------------------------------------------------------------

local function markers(b: Builder)
	MapKit.Marker(b, "Spawns/PlayerStart", facing(v(0, 3, -45), GATE))
	local checkpoints: { [string]: { Vector3 } } = {
		CP_Gate = { v(0, 3, -40), GATE },
		CP_Descent = { v(0, 3, 182), v(0, 3, 260) },
		CP_Chamber = { v(0, LOW + 3, 438), HUB },
		CP_SilentHall = { v(0, LOW + 3, 580), v(0, LOW + 3, 700) },
		CP_Throne = { v(0, LOW + 3, 790), THRONE },
	}
	for name, spot in checkpoints do
		MapKit.Marker(b, `Checkpoints/{name}`, facing(spot[1], spot[2]))
	end
	MapKit.Zone(b, "Objectives/GateEntry", v(0, 0, 28), 16)
	MapKit.Zone(b, "Objectives/DescentEnd", v(0, LOW, 398), 13)
	MapKit.Zone(b, "Objectives/ChamberEntry", v(0, LOW, 456), 10)
	MapKit.Zone(b, "Objectives/HallEnd", v(0, LOW, 758), 12)
	MapKit.Zone(b, "Objectives/ThroneEntry", v(0, LOW, 800), 12)

	-- The Gate.
	MapKit.Marker(b, "GateArena/BossSpawn", facing(v(0, 1, 140), GATE))
	MapKit.Marker(b, "GateArena/Chest", CFrame.new(v(0, 0.5, 60)))
	for index, degrees in { 200, 340, 90 } do
		MapKit.Marker(b, `GateArena/Ammo_{index}`, CFrame.new(around(GATE, 30, degrees, 0.5)))
	end
	local gateRing: { Vector3 } = {}
	for index = 0, 7 do
		table.insert(gateRing, around(GATE, 60, index * 45 + 10))
	end
	MapKit.EnemySpawns(b, "Gate", gateRing, GATE)

	-- The Echo Chamber.
	MapKit.Marker(b, "ChamberArena/BossSpawn", facing(HUB + v(0, 13, 0), v(0, LOW, 440)))
	MapKit.Zone(b, "ChamberArena/EchoWell", HUB, 9, 12)
	for index, spot in { v(-66, LOW, 480), v(66, LOW, 480), v(0, LOW, 552) } do
		MapKit.Marker(b, `ChamberArena/Room_{index}`, facing(spot + v(0, 0.5, 0), HUB))
	end
	for index, degrees in { 150, 30, 270 } do
		MapKit.Marker(b, `ChamberArena/Ammo_{index}`, CFrame.new(around(HUB, 22, degrees, 0.5)))
	end
	MapKit.Marker(b, "ChamberArena/Chest", CFrame.new(v(0, LOW + 0.5, 458)))
	MapKit.EnemySpawns(b, "Chamber", {
		v(-74, LOW, 470),
		v(-60, LOW, 494),
		v(74, LOW, 470),
		v(60, LOW, 494),
		v(-10, LOW, 560),
		v(10, LOW, 544),
		around(HUB, 26, 200),
		around(HUB, 26, 340),
	}, HUB)

	-- The Silent Hall's patrol route (zig-zag between the traps).
	MapKit.EnemySpawns(b, "HallPatrol", {
		v(-10, LOW, 596),
		v(10, LOW, 640),
		v(-10, LOW, 690),
		v(10, LOW, 735),
		v(-10, LOW, 750),
		v(10, LOW, 612),
	}, v(0, LOW, 680))

	-- The Throne.
	MapKit.Marker(b, "ThroneArena/BossSpawn", facing(THRONE + v(0, 4, 42), v(0, LOW, 790)))
	MapKit.Marker(b, "ThroneArena/Chest", CFrame.new(THRONE + v(0, 0.5, -45)))
	for index, degrees in { 45, 135, 225, 315 } do
		MapKit.Marker(b, `ThroneArena/Safe_{index}`, CFrame.new(around(THRONE, 40, degrees, 0.5)))
	end
	for index, degrees in { 60, 180, 300 } do
		MapKit.Marker(b, `ThroneArena/Pylon_{index}`, CFrame.new(around(THRONE, 52, degrees, 0.5)))
	end
	for index, degrees in { 0, 120, 240 } do
		MapKit.Marker(b, `ThroneArena/Teleport_{index}`, facing(around(THRONE, 44, degrees, 2), THRONE))
	end
	for index, degrees in { 90, 210, 330 } do
		MapKit.Marker(b, `ThroneArena/Ammo_{index}`, CFrame.new(around(THRONE, 24, degrees, 0.5)))
	end
	local throneRing: { Vector3 } = {}
	for index = 0, 5 do
		table.insert(throneRing, around(THRONE, 56, index * 60 + 30))
	end
	MapKit.EnemySpawns(b, "Throne", throneRing, THRONE)

	-- Gates.
	MapKit.Gate(b, "Gate", "Door", v(30, 36, 4), CFrame.new(0, 18, 168), GOLD)
	MapKit.Gate(b, "Descent", "Shield", v(30, 18, 1.5), CFrame.new(0, LOW + 9, 410), ECHO)
	MapKit.Gate(b, "Chamber", "Door", v(14, 16, 3), CFrame.new(0, LOW + 8, 570), GOLD)
	MapKit.Gate(b, "SilentHall", "Shield", v(30, 20, 1.5), CFrame.new(0, LOW + 10, 772), ECHO)
end

-- Upper level: the entrance and the Gate -------------------------------------------------------

local function entrance(b: Builder)
	local area = MapKit.Group(b, "Entrance")
	MapKit.Room(b, v(0, 0, -30), 40, 60, {
		WallHeight = 24,
		WallThickness = 3,
		FloorColor = MARBLE,
		FloorMaterial = Enum.Material.Marble,
		WallColor = BLACK,
		WallMaterial = Enum.Material.Marble,
		Openings = { South = 20 },
		TrimColor = GOLD,
	})
	for z = -52, -8, 11 do
		for _, x in { -16, 16 } do
			MapKit.Block(b, v(3, 24, 3), CFrame.new(x, 12, z), BLACK, Enum.Material.Marble, area)
			local sconce = MapKit.Neon(b, v(1, 3, 1), CFrame.new(x - math.sign(x) * 1.6, 12, z), GOLD, area)
			MapKit.Light(sconce, GOLD, 20, 1.2)
		end
	end
	Props.Banner(b, v(0, 0, -58), 18, v(0, 0, 1), BLACK, GOLD, area)
end

local function gate(b: Builder)
	local area = MapKit.Group(b, "TheGate")
	arena(b, GATE, 70, { 270, 90 }, area)
	-- The path in from the entrance.
	MapKit.Block(b, v(20, 2, 20), CFrame.new(0, -1, 7), MARBLE, Enum.Material.Marble, area)
	-- The three echo plates (visible, named Plate_n; the plate mechanic finds them).
	for index, degrees in { 150, 30, 270 } do
		local spot = around(GATE, 45, degrees)
		MapKit.Cylinder(b, 0.8, 16, spot + v(0, 0.4, 0), BLACK, Enum.Material.Marble, area)
		local plate = MapKit.Part(b, {
			Name = `Plate_{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = v(0.4, 12, 12),
			CFrame = CFrame.new(spot + v(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(70, 70, 80),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = area,
		})
		plate.CanCollide = false
		MapKit.Light(plate, GOLD, 16, 1)
	end
	-- The passage through the vault gate to the Descent.
	MapKit.Block(b, v(30, 2, 26), CFrame.new(0, -1, 164), MARBLE, Enum.Material.Marble, area)
	for _, x in { -15, 15 } do
		MapKit.Wall(b, v(x, 0, 152), v(x, 0, 176), 30, 2, BLACK, Enum.Material.Marble, area)
	end
	-- Harrowmaw's dais and the vault gate behind it.
	MapKit.Cylinder(b, 1, 30, v(0, 0.5, 140), GOLD, Enum.Material.Metal, area)
	for _, x in { -20, 20 } do
		MapKit.Block(b, v(8, 44, 8), CFrame.new(x, 22, 168), BLACK, Enum.Material.Marble, area)
		MapKit.Block(b, v(8.6, 2, 8.6), CFrame.new(x, 44, 168), GOLD, Enum.Material.Metal, area)
	end
	MapKit.Block(b, v(48, 8, 8), CFrame.new(0, 40, 168), BLACK, Enum.Material.Marble, area)
	local halo = Props.Ring(
		b,
		CFrame.new(0, 26, 172) * CFrame.Angles(math.rad(90), 0, 0),
		20,
		1.2,
		1.4,
		36,
		GOLD,
		Enum.Material.Neon,
		area
	)
	halo:SetAttribute("SpinCenter", v(0, 26, 172))
	halo:SetAttribute("SpinAxis", v(0, 0, 1))
	halo:SetAttribute("SpinSpeed", 12)
	halo:AddTag("LL_Spin")
	Props.Weather(b, GATE + v(0, 50, 0), v(130, 2, 130), "Spores", area)
end

-- The Descent: a jumping puzzle ------------------------------------------------------------

type Platform = { X: number, Y: number, Z: number, Size: number, Move: Vector3?, Period: number?, Phase: number? }

local PLATFORMS: { Platform } = {
	{ X = 0, Y = -2, Z = 206, Size = 10 },
	{ X = 0, Y = -5, Z = 222, Size = 9, Move = Vector3.new(14, 0, 0), Period = 9, Phase = 0 },
	{ X = 14, Y = -8, Z = 238, Size = 9 },
	{ X = 14, Y = -10, Z = 254, Size = 8, Move = Vector3.new(-16, 0, 0), Period = 10, Phase = 0.3 },
	{ X = -2, Y = -13, Z = 270, Size = 10 },
	{ X = -2, Y = -15, Z = 286, Size = 8, Move = Vector3.new(0, 8, 0), Period = 8, Phase = 0.1 },
	{ X = -2, Y = -17, Z = 302, Size = 9 },
	{ X = -16, Y = -19, Z = 318, Size = 8, Move = Vector3.new(14, 0, 0), Period = 9, Phase = 0.6 },
	{ X = -16, Y = -22, Z = 334, Size = 9 },
	{ X = -16, Y = -24, Z = 350, Size = 8, Move = Vector3.new(16, 0, 0), Period = 10, Phase = 0.5 },
	{ X = 0, Y = -27, Z = 368, Size = 12 },
}

local function descent(b: Builder)
	local area = MapKit.Group(b, "Descent")
	-- The start ledge beyond the vault gate and the end ledge far below.
	MapKit.Block(b, v(30, 2, 22), CFrame.new(0, -1, 186), MARBLE, Enum.Material.Marble, area)
	MapKit.Block(b, v(30, 2, 30), CFrame.new(0, LOW - 1, 395), MARBLE, Enum.Material.Marble, area)
	local ledges: { { Center: Vector3, Depth: number } } = {
		{ Center = v(0, 0, 186), Depth = 22 },
		{ Center = v(0, LOW, 395), Depth = 30 },
	}
	for _, ledge in ledges do
		local center, depth = ledge.Center, ledge.Depth
		for _, x in { -15, 15 } do
			MapKit.Railing(b, center + v(x, 0, -depth / 2), center + v(x, 0, depth / 2), 3.5, GOLD, 40, area)
		end
	end
	for index, platform in PLATFORMS do
		local cframe = CFrame.new(platform.X, platform.Y - 0.75, platform.Z)
		local slab = MapKit.Part(b, {
			Name = if platform.Move then "MovingPlatform" else "Platform",
			Size = v(platform.Size, 1.5, platform.Size),
			CFrame = cframe,
			Color = MARBLE,
			Material = Enum.Material.Marble,
			Parent = area,
		})
		local trim = MapKit.Neon(
			b,
			v(platform.Size + 0.2, 0.3, platform.Size + 0.2),
			cframe * CFrame.new(0, -0.7, 0),
			if platform.Move then ECHO else GOLD,
			area
		)
		if platform.Move then
			MapKit.Mover(slab, platform.Move, platform.Period or 9, 1.8, platform.Phase)
			MapKit.Mover(trim, platform.Move, platform.Period or 9, 1.8, platform.Phase)
		end
		if index % 3 == 0 then
			MapKit.Light(trim, if platform.Move then ECHO else GOLD, 22, 1.2)
		end
	end
	-- Great gold rings turning slowly in the abyss, and light shafts below.
	for index, spot in { v(0, -20, 250), v(0, -40, 330) } do
		local ring = Props.Ring(
			b,
			CFrame.new(spot) * CFrame.Angles(math.rad(90), 0, 0),
			55 + index * 10,
			2,
			3,
			48,
			GOLD,
			Enum.Material.Metal,
			area
		)
		ring:SetAttribute("SpinCenter", spot)
		ring:SetAttribute("SpinAxis", v(0, 0, 1))
		ring:SetAttribute("SpinSpeed", if index == 1 then 6 else -5)
		ring:AddTag("LL_Spin")
	end
	for _, spot in { v(-40, -100, 260), v(35, -100, 320), v(0, -100, 380) } do
		local shaft = MapKit.Part(b, {
			Name = "LightShaft",
			Size = v(6, 120, 6),
			CFrame = CFrame.new(spot),
			Color = ECHO,
			Material = Enum.Material.ForceField,
			Transparency = 0.6,
			CanCollide = false,
			CastShadow = false,
			Parent = area,
		})
		shaft.CanQuery = false
	end
	-- The corridor from the end ledge to the Echo Chamber.
	MapKit.Block(b, v(16, 2, 42), CFrame.new(0, LOW - 1, 431), MARBLE, Enum.Material.Marble, area)
	for _, x in { -8, 8 } do
		MapKit.Wall(b, v(x, LOW, 410), v(x, LOW, 452), 18, 2, BLACK, Enum.Material.Marble, area)
	end
end

-- Lower level: the Echo Chamber --------------------------------------------------------------

local function chamber(b: Builder)
	local area = MapKit.Group(b, "EchoChamber")
	arena(b, HUB, 32, { 270, 180, 0, 90 }, area)
	-- The well: a gold ring around a glowing pool, and Oriane's pillar in it.
	Props.Ring(b, CFrame.new(HUB + v(0, 0.3, 0)), 9, 0.6, 1.4, 28, GOLD, Enum.Material.Metal, area)
	local pool =
		MapKit.Neon(b, v(0.2, 17, 17), CFrame.new(HUB + v(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), ECHO, area)
	pool.Shape = Enum.PartType.Cylinder
	pool.Transparency = 0.35
	MapKit.Light(pool, ECHO, 40, 2)
	MapKit.Cylinder(b, 12, 6, HUB + v(0, 6, 0), BLACK, Enum.Material.Marble, area)
	MapKit.Cylinder(b, 1, 8, HUB + v(0, 12.5, 0), GOLD, Enum.Material.Metal, area)
	-- The three rooms and their corridors.
	local rooms: { { Vector3 } } = {
		{ v(-66, LOW, 480), v(-1, 0, 0) },
		{ v(66, LOW, 480), v(1, 0, 0) },
		{ v(0, LOW, 552), v(0, 0, 1) },
	}
	for _, entry in rooms do
		local center, out = entry[1], entry[2]
		local openings = if out.X < 0
			then { East = 14 }
			elseif out.X > 0 then { West = 14 }
			else { South = 14, North = 14 }
		MapKit.Room(b, center, 36, 36, {
			WallHeight = 20,
			WallThickness = 2,
			FloorColor = MARBLE,
			FloorMaterial = Enum.Material.Marble,
			WallColor = BLACK,
			WallMaterial = Enum.Material.Marble,
			Openings = openings,
			TrimColor = GOLD,
		})
		-- Corridor between the hub and the room.
		local from = HUB + out * 32
		local to = center - out * 18
		local length = (to - from).Magnitude
		local middle = (from + to) / 2
		MapKit.Block(
			b,
			v(if out.X ~= 0 then length + 2 else 14, 2, if out.X ~= 0 then 14 else length + 2),
			CFrame.new(middle - v(0, 1, 0)),
			MARBLE,
			Enum.Material.Marble,
			area
		)
		local side = Vector3.new(-out.Z, 0, out.X) * 7
		MapKit.Wall(b, from + side, to + side, 16, 1.5, BLACK, Enum.Material.Marble, area)
		MapKit.Wall(b, from - side, to - side, 16, 1.5, BLACK, Enum.Material.Marble, area)
		-- A gold echo sigil in each room where the Bearer appears.
		Props.Ring(b, CFrame.new(center + v(0, 0.1, 0)), 5, 0.1, 0.8, 20, GOLD, Enum.Material.Neon, area)
		for _, offset in { v(-12, 0, -12), v(12, 0, 12) } do
			Props.CrateStack(b, center + offset, area)
		end
		local lamp = MapKit.Neon(b, v(4, 0.4, 4), CFrame.new(center + v(0, 20.5, 0)), GOLD, area)
		MapKit.Light(lamp, GOLD, 34, 1.5)
	end
	-- Organ pipes around the hub, singing the echo.
	for index = 0, 11 do
		local degrees = index * 30 + 15
		if index % 3 ~= 0 then
			local spot = around(HUB, 36, degrees)
			local height = 18 + (index % 4) * 5
			MapKit.Cylinder(b, height, 2.4, spot + v(0, height / 2, 0), GOLD, Enum.Material.Metal, area)
		end
	end
end

-- The Silent Hall: laser traps and patrols ------------------------------------------------------

local function silentHall(b: Builder)
	local area = MapKit.Group(b, "SilentHall")
	MapKit.Room(b, v(0, LOW, 671), 30, 198, {
		WallHeight = 24,
		WallThickness = 2,
		FloorColor = MARBLE,
		FloorMaterial = Enum.Material.Marble,
		WallColor = BLACK,
		WallMaterial = Enum.Material.Marble,
		Openings = { North = 14, South = 30 },
		TrimColor = GOLD,
		Roof = true,
		RoofColor = BLACK,
		RoofMaterial = Enum.Material.Marble,
	})
	-- 1: a low beam sweeping along the hall (jump it).
	local sweep = laser(b, v(30, 0.8, 0.8), CFrame.new(0, LOW + 1.5, 598), area)
	MapKit.Mover(sweep, v(0, 0, 30), 7, 0.4, 0)
	-- 2: half-width walls sliding across (use the gap).
	for index, z in { 648, 664 } do
		local wall = laser(b, v(14, 20, 0.8), CFrame.new(-8, LOW + 10, z), area)
		MapKit.Mover(wall, v(16, 0, 0), 6, 0.8, index * 0.5)
	end
	-- 3: full walls that blink (cross while they're off).
	for index, z in { 690, 700 } do
		local grid = laser(b, v(30, 20, 0.8), CFrame.new(0, LOW + 10, z), area)
		grid:SetAttribute("LaserPeriod", 4)
		grid:SetAttribute("LaserOn", 0.5)
		grid:SetAttribute("LaserPhase", index * 0.5)
		grid:AddTag("LL_Laser")
	end
	-- 4: two crossing sweepers and a last blinking wall before the door.
	for index, z in { 722, 734 } do
		local beam = laser(b, v(0.8, 20, 0.8), CFrame.new(-14, LOW + 10, z), area)
		MapKit.Mover(beam, v(28, 0, 0), 5, 0.3, index * 0.5)
	end
	local last = laser(b, v(30, 20, 0.8), CFrame.new(0, LOW + 10, 748), area)
	last:SetAttribute("LaserPeriod", 3)
	last:SetAttribute("LaserOn", 0.45)
	-- Emitters on the walls for each trap row, and hall lights.
	for z = 598, 748, 25 do
		for _, x in { -14.5, 14.5 } do
			MapKit.Block(b, v(1, 3, 3), CFrame.new(x, LOW + 10, z), GOLD, Enum.Material.Metal, area)
		end
	end
	for z = 590, 760, 34 do
		local lamp = MapKit.Neon(b, v(3, 0.3, 3), CFrame.new(0, LOW + 23.6, z), ECHO, area)
		MapKit.Light(lamp, ECHO, 24, 1)
	end
end

-- The Throne ----------------------------------------------------------------------------------

local function throne(b: Builder)
	local area = MapKit.Group(b, "Throne")
	arena(b, THRONE, 65, { 270 }, area)
	-- The corridor from the Silent Hall.
	MapKit.Block(b, v(30, 2, 20), CFrame.new(0, LOW - 1, 780), MARBLE, Enum.Material.Marble, area)
	for _, x in { -15, 15 } do
		MapKit.Wall(b, v(x, LOW, 770), v(x, LOW, 788), 20, 2, BLACK, Enum.Material.Marble, area)
	end
	-- The Sovereign's dais and a great turning halo behind it.
	MapKit.Cylinder(b, 4, 24, THRONE + v(0, 2, 42), BLACK, Enum.Material.Marble, area)
	MapKit.Cylinder(b, 0.6, 25, THRONE + v(0, 4.2, 42), GOLD, Enum.Material.Metal, area)
	for index, radius in { 22, 30 } do
		local center = THRONE + v(0, 30, 58)
		local ring = Props.Ring(
			b,
			CFrame.new(center) * CFrame.Angles(math.rad(90), 0, 0),
			radius,
			1.2,
			1.6,
			40,
			if index == 1 then ECHO else GOLD,
			Enum.Material.Neon,
			area
		)
		ring:SetAttribute("SpinCenter", center)
		ring:SetAttribute("SpinAxis", v(0, 0, 1))
		ring:SetAttribute("SpinSpeed", if index == 1 then 18 else -10)
		ring:AddTag("LL_Spin")
	end
	-- The four safe circles, their gold rims always visible.
	for _, degrees in { 45, 135, 225, 315 } do
		Props.Ring(b, CFrame.new(around(THRONE, 40, degrees, 0.1)), 10, 0.1, 0.6, 24, ECHO, Enum.Material.Neon, area)
	end
	-- Low cover.
	for _, degrees in { 0, 90, 180 } do
		local spot = around(THRONE, 26, degrees)
		MapKit.Block(
			b,
			v(10, 4, 2),
			CFrame.lookAt(spot + v(0, 2, 0), THRONE + v(0, 2, 0)),
			BLACK,
			Enum.Material.Marble,
			area
		)
	end
	Props.Weather(b, THRONE + v(0, 50, 0), v(120, 2, 120), "Spores", area)
end

function VaultOfEchoes.Build(): Model
	local b = MapKit.New("VaultOfEchoes")
	b.Model:SetAttribute("KillY", -120)
	b.Model:SetAttribute("DisplayName", "Vault of Echoes")
	markers(b)
	entrance(b)
	gate(b)
	descent(b)
	chamber(b)
	silentHall(b)
	throne(b)
	return MapKit.Finish(b)
end

return VaultOfEchoes
