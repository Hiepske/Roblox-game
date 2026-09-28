--!strict
--[[
	The Hollow Dark (story mission 3, power 410): beneath the pale woods of
	Hollowmere, the Veiled have hollowed out the mountain. Follow their song
	through glowing crystal caverns and their barracks to the ritual chamber
	where the Hollow Priest leads the choir. Players carry flashlights here
	(the HollowDark lighting preset).

	The caves are Terrain: a solid mass of rock is carved out with Air, then
	floors are refilled flat at Y = 0, so the tunnels are real rock.

	Layout (the path runs along +Z):
	  Zone Mouth      z -95..95    the pale woods (dead trees, shrines) up to the
	                               cave mouth; Shield gate at z 96
	  Zone Caverns    z 96..330    the Glimmering Deep: crystals, stalagmites and
	                               ledges (Veil Seers); a Bridge gate spans the
	                               chasm z 330..372 (a glowing river far below)
	  Zone Barracks   z 372..560   carved halls, bunk rooms, braziers; the ward
	                               seal on the far door (hold E); Door gate at z 561
	  Zone Ritual     z 590..730   a round chamber open to the sky through an
	                               oculus: the ritual crystals, then the Priest

	Markers (Markers/...):
	  Spawns/PlayerStart
	  Checkpoints/CP_Mouth, CP_Caverns, CP_Barracks, CP_Ritual
	  Objectives/CaveMouth, CavernHeart (zone boxes), WardSeal, RitualCrystal_1..3
	  EnemySpawns/Mouth, Caverns, CavernLedges, Barracks, Ritual
	  BossArena/BossSpawn, Ammo_1..3, Pylon_1..3, Teleport_1..4
	Gates: Gate_Mouth (Shield), Gate_Caverns (Bridge), Gate_Barracks (Door).
	KillY -80 (the chasm).
]]

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local HollowDark = {}

local P = MapKit.Palette
local VEIL = Color3.fromRGB(190, 255, 170)
local VIOLET = Color3.fromRGB(170, 110, 255)
local CYAN = Color3.fromRGB(90, 230, 220)
local BONE = Color3.fromRGB(196, 196, 184)
local STONE = Color3.fromRGB(70, 74, 78)
local CLOTH = Color3.fromRGB(52, 60, 54)

local RITUAL = Vector3.new(0, 0, 660)

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
	MapKit.Marker(b, "Spawns/PlayerStart", facing(v(0, 3, -70), v(0, 3, 40)))
	local checkpoints: { [string]: { Vector3 } } = {
		CP_Mouth = { v(0, 3, -70), v(0, 3, 40) },
		CP_Caverns = { v(0, 3, 110), v(0, 3, 200) },
		CP_Barracks = { v(0, 3, 382), v(0, 3, 460) },
		CP_Ritual = { v(0, 3, 598), RITUAL },
	}
	for name, spot in checkpoints do
		MapKit.Marker(b, `Checkpoints/{name}`, facing(spot[1], spot[2]))
	end
	MapKit.Zone(b, "Objectives/CaveMouth", v(0, 0, 76), 16)
	MapKit.Zone(b, "Objectives/CavernHeart", v(0, 0, 165), 22)
	MapKit.Marker(b, "Objectives/WardSeal", CFrame.new(0, 4, 556), v(6, 6, 2))
	for index, degrees in { 90, 210, 330 } do
		MapKit.Marker(b, `Objectives/RitualCrystal_{index}`, CFrame.new(around(RITUAL, 30, degrees, 0.5)))
	end

	MapKit.EnemySpawns(b, "Mouth", {
		v(-50, 0, 40),
		v(50, 0, 30),
		v(-62, 0, -8),
		v(62, 0, -30),
		v(0, 0, 86),
		v(-30, 0, 80),
		v(30, 0, 80),
	}, v(0, 0, -40))
	MapKit.EnemySpawns(b, "Caverns", {
		v(-30, 0, 190),
		v(30, 0, 226),
		v(-26, 0, 282),
		v(26, 0, 304),
		v(0, 0, 322),
		v(-36, 0, 250),
		v(36, 0, 150),
	}, v(0, 0, 130))
	MapKit.EnemySpawns(b, "CavernLedges", { v(-53, 14.5, 200), v(53, 14.5, 204), v(53, 14.5, 290) }, v(0, 0, 200))
	MapKit.EnemySpawns(b, "Barracks", {
		v(-52, 0, 420),
		v(52, 0, 420),
		v(-52, 0, 500),
		v(52, 0, 500),
		v(-25, 0, 548),
		v(25, 0, 548),
	}, v(0, 0, 400))
	local ring: { Vector3 } = {}
	for index = 0, 5 do
		table.insert(ring, around(RITUAL, 56, index * 60 + 30))
	end
	MapKit.EnemySpawns(b, "Ritual", ring, RITUAL)

	MapKit.Marker(b, "BossArena/BossSpawn", facing(RITUAL + v(0, 1, 40), v(0, 1, 598)))
	for index, degrees in { 45, 135, 225, 315 } do
		MapKit.Marker(b, `BossArena/Teleport_{index}`, facing(around(RITUAL, 42, degrees, 2.5), RITUAL))
	end
	for index, degrees in { 30, 150, 270 } do
		MapKit.Marker(b, `BossArena/Pylon_{index}`, CFrame.new(around(RITUAL, 54, degrees, 0.5)))
	end
	for index, degrees in { 0, 120, 240 } do
		MapKit.Marker(b, `BossArena/Ammo_{index}`, CFrame.new(around(RITUAL, 22, degrees, 0.5)))
	end

	MapKit.Gate(b, "Mouth", "Shield", v(24, 22, 1.5), CFrame.new(0, 11, 96), VEIL)
	MapKit.Gate(b, "Caverns", "Bridge", v(12, 1.5, 48), CFrame.new(0, -0.75, 351), CYAN)
	MapKit.Gate(b, "Barracks", "Door", v(20, 22, 3), CFrame.new(0, 11, 561), VEIL)
end

-- Terrain: the woods, the rock mass, and the caves carved into it ------------------------------

local function terrain(b: Builder)
	local rng = b.Rng
	-- The pale woods.
	MapKit.TerrainBlock(b, CFrame.new(0, -8, -2), v(280, 16, 196), Enum.Material.Ground)
	for _ = 1, 10 do
		MapKit.TerrainBall(
			b,
			v(rng:NextNumber(-70, 70), -4, rng:NextNumber(-80, 70)),
			rng:NextNumber(8, 14),
			Enum.Material.Grass
		)
	end
	for z = -110, 90, 40 do
		for _, side in { -1, 1 } do
			MapKit.TerrainBall(
				b,
				v(side * rng:NextNumber(105, 125), rng:NextNumber(0, 20), z),
				rng:NextNumber(45, 65),
				Enum.Material.Rock
			)
		end
	end
	MapKit.TerrainBall(b, v(0, 10, -150), 80, Enum.Material.Rock)

	-- The mountain.
	MapKit.TerrainBlock(b, CFrame.new(0, 25, 450), v(480, 130, 720), Enum.Material.Rock)
	MapKit.TerrainBlock(b, CFrame.new(0, 95, 450), v(480, 10, 720), Enum.Material.Ground)

	-- Carve (Air): the mouth, the caverns and their domes, the ledges.
	local air = Enum.Material.Air
	MapKit.TerrainBlock(b, CFrame.new(0, 13, 105), v(28, 26, 32), air)
	MapKit.TerrainBall(b, v(0, 12, 112), 17, air)
	MapKit.TerrainBlock(b, CFrame.new(0, 20, 225), v(90, 40, 212), air)
	for _, z in { 140, 250, 312 } do
		for _, side in { -1, 1 } do
			MapKit.TerrainBall(b, v(side * 44, 18, z), 20, air)
		end
	end
	for z = 140, 320, 45 do
		for _, x in { -24, 0, 24 } do
			MapKit.TerrainBall(b, v(x, 40, z), 22, air)
		end
	end
	for _, spot in { v(-52, 26, 200), v(52, 26, 202), v(52, 26, 290) } do
		MapKit.TerrainBlock(b, CFrame.new(spot), v(22, 24, 30), air)
	end
	-- The chasm, all the way down.
	MapKit.TerrainBlock(b, CFrame.new(0, -25, 351), v(110, 130, 42), air)
	-- The barracks: a long hall and four side rooms.
	MapKit.TerrainBlock(b, CFrame.new(0, 15, 466), v(80, 30, 190), air)
	for _, z in { 420, 500 } do
		for _, side in { -1, 1 } do
			MapKit.TerrainBlock(b, CFrame.new(side * 52, 10, z), v(24, 20, 30), air)
		end
	end
	MapKit.TerrainBlock(b, CFrame.new(0, 12, 575), v(22, 24, 34), air)
	-- The ritual chamber: a great dome breaking through to the sky.
	MapKit.TerrainBall(b, RITUAL + v(0, 30, 0), 72, air)

	-- Refill flat floors at Y = 0.
	local floor = Enum.Material.Slate
	MapKit.TerrainBlock(b, CFrame.new(0, -6, 105), v(34, 12, 32), floor)
	MapKit.TerrainBlock(b, CFrame.new(0, -6, 225), v(130, 12, 211), floor)
	MapKit.TerrainBlock(b, CFrame.new(0, -6, 466), v(130, 12, 188), floor)
	MapKit.TerrainBlock(b, CFrame.new(0, -6, 575), v(26, 12, 36), floor)
	MapKit.TerrainCylinder(b, CFrame.new(RITUAL + v(0, -6, 0)), 12, 75, floor)
	-- The bottom of the chasm, far below the glowing river.
	MapKit.TerrainBlock(b, CFrame.new(0, -105, 351), v(140, 10, 60), Enum.Material.Basalt)
end

-- Zone 1: the pale woods ---------------------------------------------------------------------------

local function deadTree(b: Builder, base: Vector3, height: number, parent: Instance)
	local model = MapKit.Group(b, "DeadTree", parent)
	local rng = b.Rng
	local top = base + v(rng:NextNumber(-1, 1), height, rng:NextNumber(-1, 1))
	MapKit.Rod(b, base, top, height * 0.07, BONE, Enum.Material.Wood, model)
	for index = 1, 4 do
		local from = base:Lerp(top, rng:NextNumber(0.55, 0.9))
		local angle = rng:NextNumber(0, math.pi * 2)
		local branch = from + v(math.cos(angle), rng:NextNumber(0.4, 1), math.sin(angle)) * height * 0.28
		local rod = MapKit.Rod(b, from, branch, height * (0.035 - index * 0.004), BONE, Enum.Material.Wood, model)
		if rod then
			rod.CanCollide = false
		end
	end
end

local function shrine(b: Builder, base: CFrame, parent: Instance)
	local model = MapKit.Group(b, "Shrine", parent)
	for _, x in { -3, 3 } do
		MapKit.Block(b, v(1.6, 9, 1.6), base * CFrame.new(x, 4.5, 0), STONE, Enum.Material.Slate, model)
	end
	local lintel = MapKit.Block(b, v(8.5, 1.4, 2.2), base * CFrame.new(0, 9.5, 0), STONE, Enum.Material.Slate, model)
	MapKit.Neon(b, v(3.5, 0.5, 2.3), lintel.CFrame, VEIL, model)
	local bowl = MapKit.Cylinder(b, 1, 3, (base * CFrame.new(0, 1.2, 0)).Position, STONE, Enum.Material.Slate, model)
	local flame = Props.Fire(b, bowl.CFrame.Position + v(0, 1.2, 0), 3, model)
	local fire = flame:FindFirstChildOfClass("Fire")
	if fire then
		fire.Color = VEIL
		fire.SecondaryColor = Color3.fromRGB(60, 120, 60)
	end
end

local function woods(b: Builder)
	local area = MapKit.Group(b, "PaleWoods")
	local rng = b.Rng
	for _ = 1, 34 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		deadTree(b, v(side * rng:NextNumber(20, 82), 0, rng:NextNumber(-90, 85)), rng:NextNumber(18, 30), area)
	end
	for _, spot in
		{
			CFrame.new(-18, 0, -22) * CFrame.Angles(0, 0.3, 0),
			CFrame.new(20, 0, 18) * CFrame.Angles(0, -0.4, 0),
			CFrame.new(-8, 0, 52),
		}
	do
		shrine(b, spot, area)
	end
	for _ = 1, 14 do
		Props.Rock(b, v(rng:NextNumber(-70, 70), 0.5, rng:NextNumber(-85, 80)), rng:NextNumber(3, 8), STONE, area)
	end
	-- Old Veiled banners along the path.
	for _, spot in { v(-14, 0, 0), v(14, 0, 36), v(-14, 0, 70) } do
		Props.Banner(b, spot, 14, v(0, 0, -1), CLOTH, VEIL, area)
	end
	-- The cave mouth: carved pillars and a rune lintel.
	for _, x in { -14, 14 } do
		MapKit.Block(b, v(4, 26, 4), CFrame.new(x, 13, 94), STONE, Enum.Material.Slate, area)
		MapKit.Neon(b, v(4.2, 8, 0.4), CFrame.new(x, 12, 91.8), VEIL, area)
	end
	local lintel = MapKit.Block(b, v(32, 4, 5), CFrame.new(0, 27, 94), STONE, Enum.Material.Slate, area)
	MapKit.Neon(b, v(14, 1, 0.4), lintel.CFrame * CFrame.new(0, 0, -2.6), VEIL, area)
	Props.Weather(b, v(0, 60, 0), v(180, 2, 190), "Spores", area)
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 88, 0, -100), v(side * 88, 0, 96), 80)
		MapKit.Barrier(b, v(side * 14, 0, 92), v(side * 88, 0, 92), 80)
	end
	MapKit.Barrier(b, v(-88, 0, -100), v(88, 0, -100), 80)
end

-- Zone 2: the crystal caverns --------------------------------------------------------------------

local function caverns(b: Builder)
	local area = MapKit.Group(b, "Caverns")
	local rng = b.Rng
	local colors = { VIOLET, CYAN, VEIL }
	-- Crystals along the walls and in clusters on the floor.
	for index = 1, 18 do
		local side = if index % 2 == 0 then -1 else 1
		local z = 125 + index * 11
		Props.Crystal(b, v(side * rng:NextNumber(34, 42), 0, z), rng:NextNumber(6, 12), colors[index % 3 + 1], area)
	end
	for _, spot in { v(-12, 0, 180), v(14, 0, 238), v(-8, 0, 296), v(18, 0, 160) } do
		Props.Crystal(b, spot, rng:NextNumber(8, 12), colors[rng:NextInteger(1, 3)], area)
	end
	-- Ceiling crystals hanging down.
	for _ = 1, 10 do
		local spot = v(rng:NextNumber(-30, 30), 38, rng:NextNumber(130, 320))
		local shard = MapKit.Part(b, {
			Name = "Hanging",
			Size = v(1.4, rng:NextNumber(5, 9), 1.4),
			CFrame = CFrame.new(spot) * CFrame.Angles(math.pi + rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), 0),
			Color = colors[rng:NextInteger(1, 3)],
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			CanCollide = false,
			CastShadow = false,
			Parent = area,
		})
		shard.CanQuery = false
	end
	-- Stalagmites for cover.
	for _ = 1, 14 do
		local base = v(rng:NextNumber(-36, 36), 0, rng:NextNumber(130, 320))
		if math.abs(base.X) > 8 then
			local height = rng:NextNumber(6, 14)
			MapKit.Part(b, {
				Name = "Stalagmite",
				Size = v(height * 0.45, height, height * 0.45),
				CFrame = CFrame.new(base + v(0, height / 2 - 0.5, 0))
					* CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.1, 0.1)),
				Color = STONE,
				Material = Enum.Material.Slate,
				Parent = area,
			})
		end
	end
	-- Veiled scaffolding up to the ledges.
	for _, spot in { v(-40, 0, 200), v(40, 0, 204) } do
		MapKit.Block(b, v(6, 14, 6), CFrame.new(spot + v(0, 7, 0)), P.Bark, Enum.Material.WoodPlanks, area)
		Props.Banner(b, spot + v(0, 14, 0), 8, v(0, 0, -1), CLOTH, VEIL, area)
	end
	-- The chasm: a glowing river far below and pillars on the edges.
	local river = MapKit.Neon(b, v(40, 0.5, 60), CFrame.new(0, -78, 351), CYAN, area)
	river.Transparency = 0.2
	MapKit.Light(river, CYAN, 60, 2)
	for _, spot in { v(-10, 0, 327), v(10, 0, 327), v(-10, 0, 375), v(10, 0, 375) } do
		MapKit.Block(b, v(2.5, 10, 2.5), CFrame.new(spot + v(0, 5, 0)), STONE, Enum.Material.Slate, area)
		MapKit.Neon(b, v(1.2, 1.2, 1.2), CFrame.new(spot + v(0, 10.6, 0)), CYAN, area)
	end
end

-- Zone 3: the barracks -----------------------------------------------------------------------------

local function barracks(b: Builder)
	local area = MapKit.Group(b, "Barracks")
	-- Worked stone floor and pillars down the hall.
	MapKit.Block(
		b,
		v(80, 0.4, 186),
		CFrame.new(0, 0.2, 466),
		Color3.fromRGB(86, 88, 90),
		Enum.Material.Cobblestone,
		area
	)
	for z = 390, 550, 32 do
		for _, x in { -28, 28 } do
			MapKit.Block(b, v(4, 30, 4), CFrame.new(x, 15, z), STONE, Enum.Material.Slate, area)
			MapKit.Neon(b, v(0.5, 10, 4.2), CFrame.new(x - math.sign(x) * 2.05, 12, z), VEIL, area)
		end
		local fire = Props.Fire(b, v(0, 1.5, z + 16), 4, area)
		MapKit.Cylinder(b, 1.5, 4, fire.CFrame.Position - v(0, 1, 0), P.DarkMetal, Enum.Material.Metal, area)
	end
	-- Bunk rooms off the hall.
	for _, z in { 420, 500 } do
		for _, side in { -1, 1 } do
			local room = v(side * 52, 0, z)
			for index = -1, 1 do
				MapKit.Block(
					b,
					v(8, 1.2, 4),
					CFrame.new(room + v(side * 3, 2, index * 8)),
					P.Bark,
					Enum.Material.Wood,
					area
				)
				MapKit.Block(
					b,
					v(8, 1.2, 4),
					CFrame.new(room + v(side * 3, 6, index * 8)),
					P.Bark,
					Enum.Material.Wood,
					area
				)
				MapKit.Block(
					b,
					v(8.2, 0.4, 4.2),
					CFrame.new(room + v(side * 3, 2.8, index * 8)),
					CLOTH,
					Enum.Material.Fabric,
					area
				)
			end
			Props.Crate(b, room + v(-side * 6, 0, 10), v(3.5, 3, 3.5), P.Bark, area)
			local lamp = Props.Fire(b, room + v(-side * 8, 2, -10), 2.5, area)
			local fire = lamp:FindFirstChildOfClass("Fire")
			if fire then
				fire.Color = VEIL
			end
		end
	end
	-- Banners and weapon racks along the hall, crates for cover.
	for z = 400, 540, 35 do
		for _, side in { -1, 1 } do
			Props.Banner(b, v(side * 36, 0.4, z), 16, v(-side, 0, 0), CLOTH, VEIL, area)
		end
	end
	for _, spot in { v(-14, 0.4, 410), v(12, 0.4, 450), v(-10, 0.4, 492), v(14, 0.4, 530) } do
		Props.CrateStack(b, spot, area)
	end
	-- The sealed door at the end of the hall: a ring of runes to shatter.
	local seal = Props.Ring(
		b,
		CFrame.new(0, 11, 559) * CFrame.Angles(math.rad(90), 0, 0),
		8,
		0.6,
		1,
		24,
		VEIL,
		Enum.Material.Neon,
		area
	)
	seal.Name = "WardSeal"
	MapKit.Neon(b, v(3, 3, 0.4), CFrame.new(0, 11, 559.3), VEIL, area)
end

-- Zone 4: the ritual chamber ---------------------------------------------------------------------

local function ritual(b: Builder)
	local area = MapKit.Group(b, "Ritual")
	-- The chamber floor, the dark pool and the ritual circle.
	MapKit.Cylinder(b, 0.4, 128, RITUAL + v(0, 0.2, 0), Color3.fromRGB(60, 62, 66), Enum.Material.Slate, area)
	local pool =
		MapKit.Cylinder(b, 0.3, 22, RITUAL + v(0, 0.5, 0), Color3.fromRGB(20, 40, 36), Enum.Material.Glass, area)
	pool.Reflectance = 0.3
	local glow = MapKit.Neon(
		b,
		v(0.2, 16, 16),
		CFrame.new(RITUAL + v(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		VEIL,
		area
	)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 0.5
	MapKit.Light(glow, VEIL, 50, 2)
	Props.Ring(b, CFrame.new(RITUAL + v(0, 0.5, 0)), 30, 0.2, 1, 36, VEIL, Enum.Material.Neon, area)
	Props.Ring(b, CFrame.new(RITUAL + v(0, 0.5, 0)), 44, 0.2, 0.6, 44, VIOLET, Enum.Material.Neon, area)
	-- Pillars around the chamber with pale flames.
	for index = 0, 7 do
		local degrees = index * 45 + 22.5
		local base = around(RITUAL, 58, degrees)
		MapKit.Block(
			b,
			v(5, 40, 5),
			CFrame.new(base + v(0, 20, 0)) * CFrame.Angles(0, math.rad(degrees), 0),
			STONE,
			Enum.Material.Slate,
			area
		)
		local flame = Props.Fire(b, base + v(0, 41, 0), 5, area)
		local fire = flame:FindFirstChildOfClass("Fire")
		if fire then
			fire.Color = VEIL
			fire.SecondaryColor = Color3.fromRGB(80, 140, 80)
		end
	end
	-- Four daises the Priest blinks between.
	for _, degrees in { 45, 135, 225, 315 } do
		local spot = around(RITUAL, 42, degrees)
		MapKit.Cylinder(b, 2, 12, spot + v(0, 1, 0), STONE, Enum.Material.Slate, area)
		MapKit.Neon(
			b,
			v(0.2, 12.4, 12.4),
			CFrame.new(spot + v(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			VIOLET,
			area
		).Shape =
			Enum.PartType.Cylinder
	end
	-- Crystals growing out of the walls.
	for index = 0, 11 do
		Props.Crystal(b, around(RITUAL, 64, index * 30 + 10), 10, if index % 2 == 0 then VIOLET else VEIL, area)
	end
	-- Moonlight falling through the oculus.
	local shaft = MapKit.Part(b, {
		Name = "Moonlight",
		Shape = Enum.PartType.Cylinder,
		Size = v(90, 60, 60),
		CFrame = CFrame.new(RITUAL + v(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 220, 255),
		Material = Enum.Material.ForceField,
		Transparency = 0.85,
		CanCollide = false,
		CastShadow = false,
		Parent = area,
	})
	shaft.CanQuery = false
	Props.Weather(b, RITUAL + v(0, 85, 0), v(70, 2, 70), "Spores", area)
end

function HollowDark.Build(): Model
	local b = MapKit.New("HollowDark")
	b.Model:SetAttribute("KillY", -80)
	b.Model:SetAttribute("DisplayName", "The Hollow Dark")
	markers(b)
	terrain(b)
	woods(b)
	caverns(b)
	barracks(b)
	ritual(b)
	return MapKit.Finish(b)
end

return HollowDark
