--!strict
--[[
	First Light (story mission 1, power 350): a snowy mountain valley on
	Frostreach. Your ship went down; the beacon you followed leads through a
	frozen village to a Rustborn outpost, into its reactor and down to the
	Scrap Warden's pit.

	Layout (the path runs along +Z; ground is Y = 0, terrain snow):
	  Zone CrashSite  z -80..140   the wreck, a tree line; Shield gate at z 140
	  Zone Village    z 140..440   Frostfall: a snowy street, a frozen fountain,
	                               two flat-roofed watch houses (snipers)
	  Zone Outpost    z 440..620   walled courtyard, watchtowers, the uplink
	                               terminal (hold 60 s); Door gates at z 440/620
	  Zone Reactor    z 620..760   a bunker hall around the glowing core; three
	                               coolant regulators; Bridge gate over the chasm
	  Zone ScrapPit   z 815..945   a round platform over the abyss (boss)

	Markers (Markers/...):
	  Spawns/PlayerStart
	  Checkpoints/CP_CrashSite, CP_Village, CP_Outpost, CP_Reactor, CP_ScrapPit
	  Objectives/Wreck, VillageGate, Uplink (zone boxes), Regulator_1..3
	  EnemySpawns/CrashSite, Village, VillageRoofs, Outpost, OutpostTurrets,
	              Reactor, ScrapPit
	  BossArena/BossSpawn, Ammo_1..3
	Gates: Gate_CrashSite (Shield), Gate_Village (Door), Gate_Outpost (Door),
	Gate_Reactor (Bridge). KillY -60: fall into the abyss and you're back at
	the checkpoint.
]]

local MapKit = require(script.Parent.MapKit)
local Props = require(script.Parent.Props)

type Builder = MapKit.Builder

local FirstLight = {}

local P = MapKit.Palette
local SNOW = Color3.fromRGB(236, 241, 247)
local ICE = Color3.fromRGB(170, 215, 235)
local WOOD = Color3.fromRGB(120, 86, 60)
local RUST = Color3.fromRGB(150, 78, 44)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

-- Markers and gates ------------------------------------------------------------------------

local function markers(b: Builder)
	MapKit.Marker(b, "Spawns/PlayerStart", facing(v(0, 3, -50), v(0, 3, 40)))
	local checkpoints: { [string]: { Vector3 } } = {
		CP_CrashSite = { v(0, 3, -50), v(0, 3, 40) },
		CP_Village = { v(0, 3, 152), v(0, 3, 300) },
		CP_Outpost = { v(0, 3, 452), v(0, 3, 530) },
		CP_Reactor = { v(0, 3, 640), v(0, 3, 700) },
		CP_ScrapPit = { v(0, 3, 826), v(0, 3, 900) },
	}
	for name, spot in checkpoints do
		MapKit.Marker(b, `Checkpoints/{name}`, facing(spot[1], spot[2]))
	end

	MapKit.Zone(b, "Objectives/Wreck", v(20, 0, 8), 16)
	MapKit.Zone(b, "Objectives/VillageGate", v(0, 0, 188), 20)
	MapKit.Zone(b, "Objectives/Uplink", v(0, 0, 530), 14)
	for index, angle in { 200, 340, 90 } do
		local rad = math.rad(angle)
		MapKit.Marker(
			b,
			`Objectives/Regulator_{index}`,
			CFrame.new(v(math.cos(rad) * 26, 0.5, 695 + math.sin(rad) * 26))
		)
	end

	MapKit.EnemySpawns(b, "CrashSite", {
		v(-56, 0, 64),
		v(-38, 0, 100),
		v(0, 0, 118),
		v(38, 0, 100),
		v(56, 0, 64),
		v(-62, 0, 18),
		v(62, 0, -14),
	}, v(0, 0, 0))
	MapKit.EnemySpawns(b, "Village", {
		v(-30, 0, 232),
		v(30, 0, 270),
		v(-30, 0, 308),
		v(30, 0, 384),
		v(-18, 0, 420),
		v(18, 0, 420),
		v(0, 0, 410),
	}, v(0, 0, 250))
	MapKit.EnemySpawns(b, "VillageRoofs", { v(-34, 19, 252), v(34, 19, 346), v(-36, 19, 258) }, v(0, 0, 290))
	MapKit.EnemySpawns(b, "Outpost", {
		v(-46, 0, 606),
		v(46, 0, 606),
		v(0, 0, 606),
		v(-50, 0, 520),
		v(50, 0, 540),
	}, v(0, 0, 500))
	MapKit.EnemySpawns(b, "OutpostTurrets", {
		v(-30, 15, 619),
		v(30, 15, 619),
		v(-59, 15, 560),
		v(59, 15, 500),
	}, v(0, 0, 500))
	MapKit.EnemySpawns(b, "Reactor", {
		v(-36, 0, 752),
		v(36, 0, 752),
		v(-40, 12.6, 705),
		v(40, 12.6, 725),
		v(0, 0, 752),
	}, v(0, 0, 680))
	local pit = v(0, 0, 880)
	local ring: { Vector3 } = {}
	for index = 0, 5 do
		local angle = math.rad(20 + index * 28)
		table.insert(ring, pit + v(math.cos(angle) * 52, 0, math.sin(angle) * 52))
	end
	MapKit.EnemySpawns(b, "ScrapPit", ring, pit)

	MapKit.Marker(b, "BossArena/BossSpawn", facing(v(0, 1, 915), v(0, 1, 840)))
	MapKit.Marker(b, "BossArena/Ammo_1", CFrame.new(v(-42, 0.5, 872)))
	MapKit.Marker(b, "BossArena/Ammo_2", CFrame.new(v(42, 0.5, 872)))
	MapKit.Marker(b, "BossArena/Ammo_3", CFrame.new(v(0, 0.5, 846)))

	-- Gates.
	MapKit.Gate(b, "CrashSite", "Shield", v(34, 18, 1.5), CFrame.new(0, 9, 140), P.Orange)
	MapKit.Gate(b, "Village", "Door", v(26, 20, 3), CFrame.new(0, 10, 440), P.Orange)
	MapKit.Gate(b, "Outpost", "Door", v(20, 16, 3), CFrame.new(0, 8, 620), P.Orange)
	MapKit.Gate(b, "Reactor", "Bridge", v(14, 1.5, 48), CFrame.new(0, -0.75, 791), P.Teal)
end

-- Terrain ----------------------------------------------------------------------------------------

local function terrain(b: Builder)
	-- The valley floor (stops at the chasm before the pit).
	MapKit.TerrainBlock(b, CFrame.new(0, -8, 342), v(420, 16, 860), Enum.Material.Snow)
	-- A frozen pond by the wreck, and a frozen stream through the village.
	MapKit.TerrainBlock(b, CFrame.new(-44, -0.6, 28), v(28, 2, 40), Enum.Material.Glacier)
	MapKit.TerrainBlock(b, CFrame.new(0, -0.6, 166), v(110, 2, 10), Enum.Material.Glacier)
	-- Mountains on both sides, snow over rock, and big peaks behind them.
	local rng = b.Rng
	for z = -160, 740, 55 do
		for _, side in { -1, 1 } do
			local x = side * rng:NextNumber(118, 150)
			local radius = rng:NextNumber(62, 92)
			MapKit.TerrainBall(b, v(x, rng:NextNumber(-6, 18), z), radius, Enum.Material.Rock)
			MapKit.TerrainBall(b, v(x + side * 10, rng:NextNumber(26, 40), z + 10), radius * 0.72, Enum.Material.Snow)
			if z % 110 == 0 then
				MapKit.TerrainBall(
					b,
					v(side * rng:NextNumber(250, 300), 70, z),
					rng:NextNumber(120, 160),
					Enum.Material.Snow
				)
			end
		end
	end
	-- Behind the start.
	MapKit.TerrainBall(b, v(0, 10, -190), 110, Enum.Material.Rock)
	MapKit.TerrainBall(b, v(0, 60, -220), 90, Enum.Material.Snow)
	-- The crater around the Scrap Pit, far below its rim.
	local pit = v(0, 0, 880)
	for index = 0, 13 do
		local angle = math.rad(index * (360 / 14))
		local center = pit + v(math.cos(angle) * 185, -30, math.sin(angle) * 185)
		if center.Z > 770 then
			MapKit.TerrainBall(b, center, 80, Enum.Material.Rock)
			MapKit.TerrainBall(b, center + v(0, 70, 0) + (center - pit).Unit * 25, 52, Enum.Material.Snow)
		end
	end
end

-- Zone 1: the crash site -----------------------------------------------------------------------

local function crashSite(b: Builder)
	local area = MapKit.Group(b, "CrashSite")
	-- The wreck: our ship, nose-down in the snow, with a scorched trail behind it.
	local ship = Props.Ship(
		b,
		CFrame.new(28, 5, 12) * CFrame.Angles(0, math.rad(35), 0) * CFrame.Angles(math.rad(12), 0, math.rad(-18)),
		3,
		P.White,
		P.Teal,
		area
	)
	ship.Name = "Wreck"
	for index = 1, 3 do
		Props.Fire(b, v(22 + index * 5, 4 + index, 4 + index * 4), 7, area)
	end
	for t = 0, 1, 0.1 do
		local point = v(70, 0, -70):Lerp(v(32, 0, 6), t)
		MapKit.Part(b, {
			Name = "Scorch",
			Size = v(12, 0.2, 10),
			CFrame = CFrame.new(point + v(0, 0.1, 0)) * CFrame.Angles(0, t * 2, 0),
			Color = Color3.fromRGB(40, 36, 36),
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = area,
		}).CanQuery =
			false
	end
	Props.Debris(b, v(40, 0, -20), 26, 24, P.Gunmetal, area)
	Props.Smoke(b, v(30, 10, 10), 12, Color3.fromRGB(70, 70, 76), area)
	-- Hull plates torn off on the way down, stuck in the snow.
	for index, spot in { v(62, 0, -58), v(52, 0, -40), v(46, 0, -18), v(-8, 0, 2) } do
		MapKit.Block(
			b,
			v(8 - index, 0.6, 5),
			CFrame.new(spot + v(0, 1.5, 0)) * CFrame.Angles(math.rad(50 + index * 7), math.rad(index * 40), 0),
			if index % 2 == 0 then P.White else P.Gunmetal,
			Enum.Material.Metal,
			area
		)
	end
	-- The distress beacon we followed down, still blinking on the hull.
	local beacon = MapKit.Neon(b, v(1.2, 1.2, 1.2), CFrame.new(20, 11, 20), P.Red, area)
	MapKit.Light(beacon, P.Red, 18, 2)
	-- Spilled cargo to take cover behind.
	for _, spot in { v(8, 0, 20), v(14, 0, 30), v(-10, 0, 38), v(40, 0, 36), v(-20, 0, 70), v(20, 0, 76) } do
		Props.Crate(b, spot, v(5, 4, 5), P.Gunmetal, area)
	end
	Props.Container(b, CFrame.new(-26, 0, 50) * CFrame.Angles(0, math.rad(70), math.rad(8)), P.Teal, area)
	-- Pines along the tree line and snow drifts.
	local rng = b.Rng
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local spot = v(side * rng:NextNumber(46, 72), 0, rng:NextNumber(-70, 128))
		Props.Pine(b, spot, rng:NextNumber(22, 34), area)
	end
	for _ = 1, 8 do
		MapKit.TerrainBall(
			b,
			v(rng:NextNumber(-60, 60), -3, rng:NextNumber(-60, 120)),
			rng:NextNumber(5, 9),
			Enum.Material.Snow
		)
	end
	-- Rocks flanking the pass and the Rustborn shield pylons.
	for _, side in { -1, 1 } do
		for index = 0, 3 do
			Props.Rock(b, v(side * (22 + index * 9), 6, 138 + index * 3), 16 - index * 2, P.Stone, area)
		end
		MapKit.Block(b, v(3, 20, 3), CFrame.new(side * 18.5, 10, 140), P.DarkMetal, Enum.Material.Metal, area)
		-- The pass is closed on both sides of the shield.
		MapKit.Barrier(b, v(side * 17, 0, 140), v(side * 80, 0, 140), 80)
		MapKit.TerrainBall(b, v(side * 52, 2, 146), 26, Enum.Material.Rock)
		MapKit.TerrainBall(b, v(side * 50, 18, 150), 16, Enum.Material.Snow)
		MapKit.Neon(b, v(3.2, 1, 3.2), CFrame.new(side * 18.5, 19, 140), P.Orange, area)
		Props.Banner(b, v(side * 24, 0, 132), 16, v(0, 0, -1), RUST, P.Orange, area)
	end
	Props.Weather(b, v(0, 70, 30), v(170, 2, 230), "Snow", area)
	-- Keep players in the valley.
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 78, 0, -85), v(side * 78, 0, 142), 80)
	end
	MapKit.Barrier(b, v(-78, 0, -85), v(78, 0, -85), 80)
end

-- Zone 2: Frostfall village --------------------------------------------------------------------

local function village(b: Builder)
	local area = MapKit.Group(b, "Village")
	local rng = b.Rng
	-- The street: packed snow with a stone curb.
	MapKit.Block(b, v(26, 0.4, 290), CFrame.new(0, 0.2, 295), Color3.fromRGB(190, 196, 204), Enum.Material.Pebble, area)
	for _, x in { -13.5, 13.5 } do
		MapKit.Block(b, v(1, 0.8, 290), CFrame.new(x, 0.4, 295), P.ConcreteGrey, Enum.Material.Concrete, area)
	end
	-- Cottages facing the street.
	local walls =
		{ Color3.fromRGB(150, 110, 84), Color3.fromRGB(176, 150, 120), Color3.fromRGB(120, 96, 80), P.ConcreteGrey }
	local roofs = { Color3.fromRGB(90, 60, 50), P.DarkMetal, Color3.fromRGB(70, 80, 96) }
	for index, z in { 176, 214, 290, 328, 366, 404 } do
		for _, side in { -1, 1 } do
			if not ((side == -1 and z == 290) or (side == 1 and z == 328)) then
				local size = v(rng:NextNumber(16, 20), rng:NextNumber(10, 13), rng:NextNumber(14, 18))
				local spot = v(side * (22 + size.Z / 2), 0, z)
				local frame = facing(spot, v(0, 0, z))
				Props.House(b, frame, size, walls[(index + side) % #walls + 1], roofs[index % #roofs + 1], true, area)
				if (index + side) % 2 == 0 then
					local chimneyTop = frame * CFrame.new(size.X / 4, size.Y + size.X * 0.35 + 3.6, size.Z / 4)
					Props.Smoke(b, chimneyTop.Position, 3, nil, area)
				end
			end
		end
	end
	-- Two flat-roofed watch houses: snipers take the roofs.
	for _, spot in { v(-34, 0, 255), v(34, 0, 346) } do
		local house = MapKit.Group(b, "WatchHouse", area)
		MapKit.Block(b, v(16, 18, 16), CFrame.new(spot + v(0, 9, 0)), P.ConcreteGrey, Enum.Material.Concrete, house)
		MapKit.Block(b, v(17, 0.6, 17), CFrame.new(spot + v(0, 18.3, 0)), SNOW, Enum.Material.Snow, house)
		local parapets: { Vector3 } = { v(0, 0, 8.2), v(0, 0, -8.2), v(8.2, 0, 0), v(-8.2, 0, 0) }
		for _, offset in parapets do
			local along = if offset.X == 0 then v(16, 1.6, 0.6) else v(0.6, 1.6, 16)
			MapKit.Block(b, along, CFrame.new(spot + offset + v(0, 19.4, 0)), P.DarkMetal, Enum.Material.Metal, house)
		end
		for level = 1, 2 do
			MapKit.Neon(
				b,
				v(12, 1.6, 16.2),
				CFrame.new(spot + v(0, level * 7 - 1, 0)),
				Color3.fromRGB(255, 190, 110),
				house
			).Transparency =
				0.35
		end
		Props.Antenna(b, spot + v(5, 19, 5), 9, house)
	end
	-- A second row of cottages behind the street (scenery beyond the fence line).
	for index, z in { 196, 262, 318, 392 } do
		for _, side in { -1, 1 } do
			local size = v(rng:NextNumber(15, 19), rng:NextNumber(9, 12), rng:NextNumber(13, 16))
			local spot = v(side * rng:NextNumber(74, 84), 0, z + side * 12)
			Props.House(
				b,
				facing(spot, v(0, 0, z)),
				size,
				walls[index % #walls + 1],
				roofs[(index + 1) % #roofs + 1],
				true,
				area
			)
		end
	end
	-- Festival lights strung across the street.
	for z = 186, 420, 48 do
		Props.StringLights(
			b,
			v(-12, 10.6, z),
			v(12, 10.6, z + 15),
			if z % 96 == 90 then P.Orange else Color3.fromRGB(255, 220, 150),
			area
		)
	end
	-- The village sign at the entrance.
	local post = MapKit.Block(b, v(1, 9, 1), CFrame.new(-16, 4.5, 176), P.Bark, Enum.Material.Wood, area)
	local board = MapKit.Block(b, v(9, 3, 0.5), post.CFrame * CFrame.new(4, 3, 0), WOOD, Enum.Material.WoodPlanks, area)
	MapKit.Sign(board, "FROSTFALL", Enum.NormalId.Front, Color3.fromRGB(250, 240, 220))
	MapKit.Sign(board, "FROSTFALL", Enum.NormalId.Back, Color3.fromRGB(250, 240, 220))
	MapKit.Block(b, v(9.4, 0.4, 0.9), board.CFrame * CFrame.new(0, 1.7, 0), SNOW, Enum.Material.Snow, area)

	-- The plaza with its frozen fountain.
	local plaza = v(0, 0, 309)
	MapKit.Cylinder(b, 1.2, 30, plaza + v(0, 0.6, 0), P.ConcreteGrey, Enum.Material.Cobblestone, area)
	MapKit.Cylinder(b, 2.4, 16, plaza + v(0, 1.2, 0), P.Concrete, Enum.Material.Concrete, area)
	MapKit.Cylinder(b, 0.6, 14, plaza + v(0, 2.4, 0), ICE, Enum.Material.Ice, area)
	MapKit.Cylinder(b, 6, 2, plaza + v(0, 5, 0), P.Concrete, Enum.Material.Concrete, area)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		MapKit.Part(b, {
			Name = "Icicle",
			Size = v(0.5, 3, 0.5),
			CFrame = CFrame.new(plaza + v(math.cos(angle) * 1.4, 6.5, math.sin(angle) * 1.4))
				* CFrame.Angles(0, 0, 0.3),
			Color = ICE,
			Material = Enum.Material.Ice,
			Parent = area,
		}).Transparency =
			0.2
	end
	-- Lamps, fences, carts, crates and drifts.
	for z = 180, 420, 30 do
		for _, side in { -1, 1 } do
			Props.Lamp(b, v(side * 12, 0, z + (if side > 0 then 15 else 0)), 11, Color3.fromRGB(255, 205, 150), area)
		end
	end
	for _, z in { 195, 233, 347, 385 } do
		for _, side in { -1, 1 } do
			Props.Fence(b, v(side * 16, 0, z - 6), v(side * 16, 0, z + 6), WOOD, area)
		end
	end
	for _, spot in { v(-6, 0, 240), v(8, 0, 262), v(-8, 0, 352), v(6, 0, 396), v(9, 0, 205) } do
		Props.Crate(b, spot, v(4, 3.5, 4), WOOD, area)
	end
	Props.CrateStack(b, v(-9, 0, 280), area)
	Props.CrateStack(b, v(10, 0, 372), area)
	-- A snow-buried cart.
	local cart = MapKit.Group(b, "Cart", area)
	MapKit.Block(
		b,
		v(5, 2, 8),
		CFrame.new(7, 2.4, 225) * CFrame.Angles(0, 0.3, 0.05),
		WOOD,
		Enum.Material.WoodPlanks,
		cart
	)
	for _, offset in { v(-2.8, 1.2, -2.5), v(2.8, 1.2, -2.5), v(-2.8, 1.2, 2.5), v(2.8, 1.2, 2.5) } do
		MapKit.Part(b, {
			Name = "Wheel",
			Shape = Enum.PartType.Cylinder,
			Size = v(0.5, 2.4, 2.4),
			CFrame = CFrame.new(7, 0, 225) * CFrame.Angles(0, 0.3, 0) * CFrame.new(offset),
			Color = P.Bark,
			Material = Enum.Material.Wood,
			Parent = cart,
		})
	end
	for _ = 1, 10 do
		MapKit.TerrainBall(
			b,
			v(rng:NextNumber(-50, 50), -3, rng:NextNumber(160, 430)),
			rng:NextNumber(4, 8),
			Enum.Material.Snow
		)
	end
	for _ = 1, 14 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.Pine(b, v(side * rng:NextNumber(50, 64), 0, rng:NextNumber(150, 430)), rng:NextNumber(24, 34), area)
	end
	-- A little footbridge over the frozen stream.
	MapKit.Block(b, v(18, 0.6, 12), CFrame.new(0, 0.7, 166), WOOD, Enum.Material.WoodPlanks, area)
	Props.Weather(b, v(0, 70, 295), v(130, 2, 300), "Snow", area)
	for _, side in { -1, 1 } do
		MapKit.Barrier(b, v(side * 58, 0, 138), v(side * 58, 0, 442), 80)
	end
	-- The outpost's outer wall is the end of the street.
	Props.Banner(b, v(-16, 0, 432), 18, v(0, 0, -1), RUST, P.Orange, area)
	Props.Banner(b, v(16, 0, 432), 18, v(0, 0, -1), RUST, P.Orange, area)
end

-- Zone 3: the outpost ---------------------------------------------------------------------------

local function outpostWall(b: Builder, from: Vector3, to: Vector3, gap: number?, parent: Instance)
	local height = 14
	if gap then
		local middle = (from + to) / 2
		local direction = (to - from).Unit
		MapKit.Wall(b, from, middle - direction * gap / 2, height, 3, P.Concrete, Enum.Material.Concrete, parent)
		MapKit.Wall(b, middle + direction * gap / 2, to, height, 3, P.Concrete, Enum.Material.Concrete, parent)
		-- A heavy lintel over the gate.
		local lintel = MapKit.Block(
			b,
			v(3.2, 4, gap + 2),
			CFrame.lookAt(middle + v(0, 22, 0), middle + v(0, 22, 0) + direction),
			P.DarkMetal,
			Enum.Material.DiamondPlate,
			parent
		)
		MapKit.Neon(b, v(3.3, 0.5, gap), lintel.CFrame * CFrame.new(0, -1.6, 0), P.Orange, parent)
		for _, sign in { -1, 1 } do
			MapKit.Block(
				b,
				v(4, 24, 4),
				CFrame.new(middle + direction * sign * (gap / 2 + 2) + v(0, 12, 0)),
				P.DarkMetal,
				Enum.Material.Metal,
				parent
			)
		end
	else
		MapKit.Wall(b, from, to, height, 3, P.Concrete, Enum.Material.Concrete, parent)
	end
	if gap == nil then
		local length = (to - from).Magnitude
		local middle = (from + to) / 2 + v(0, height + 0.25, 0)
		MapKit.Block(
			b,
			v(3.4, 0.5, length),
			CFrame.lookAt(middle, middle + (to - from)),
			P.DarkMetal,
			Enum.Material.DiamondPlate,
			parent
		)
		MapKit.Neon(
			b,
			v(3.5, 0.3, length),
			CFrame.lookAt(middle - v(0, 3, 0), middle - v(0, 3, 0) + (to - from)),
			P.Orange,
			parent
		)
	end
end

local function outpost(b: Builder)
	local area = MapKit.Group(b, "Outpost")
	-- Paving.
	MapKit.Block(b, v(120, 0.6, 180), CFrame.new(0, 0.3, 530), P.ConcreteGrey, Enum.Material.Concrete, area)
	for z = 460, 600, 20 do
		MapKit.Block(b, v(120, 0.62, 0.4), CFrame.new(0, 0.32, z), P.ConcreteDark, Enum.Material.Concrete, area)
	end
	outpostWall(b, v(-60, 0, 440), v(60, 0, 440), 26, area)
	outpostWall(b, v(-60, 0, 620), v(60, 0, 620), 20, area)
	outpostWall(b, v(-60, 0, 440), v(-60, 0, 620), nil, area)
	outpostWall(b, v(60, 0, 440), v(60, 0, 620), nil, area)
	for _, x in { -55, 55 } do
		for _, z in { 446, 614 } do
			Props.Watchtower(b, v(x, 0, z), 18, area)
		end
	end
	-- The uplink terminal in the middle, with a big dish.
	local uplink = v(0, 0, 530)
	MapKit.Cylinder(b, 1, 20, uplink + v(0, 0.8, 0), P.DarkMetal, Enum.Material.DiamondPlate, area)
	MapKit.ZoneRing(b, uplink + v(0, 0.9, 0), 14, P.Teal, area)
	Props.Console(b, facing(uplink + v(0, 1.3, -3), uplink + v(0, 1.3, -20)), P.Teal, area)
	Props.Antenna(b, uplink + v(5, 1.3, 4), 16, area)
	local dishPole =
		MapKit.Block(b, v(1.6, 10, 1.6), CFrame.new(uplink + v(-5, 6, 4)), P.Gunmetal, Enum.Material.Metal, area)
	local dish = MapKit.Part(b, {
		Name = "Dish",
		Shape = Enum.PartType.Cylinder,
		Size = v(1, 12, 12),
		CFrame = CFrame.new(dishPole.CFrame.Position + v(0, 7, 0)) * CFrame.Angles(0, math.rad(40), math.rad(60)),
		Color = P.White,
		Material = Enum.Material.Metal,
		Parent = area,
	})
	MapKit.Neon(b, v(1.1, 2, 2), dish.CFrame, P.Teal, area)
	-- Cover: containers, crate stacks, barricades.
	Props.Container(b, CFrame.new(-30, 0, 478) * CFrame.Angles(0, math.rad(10), 0), RUST, area)
	Props.Container(b, CFrame.new(32, 0, 498) * CFrame.Angles(0, math.rad(80), 0), P.Teal, area)
	Props.Container(b, CFrame.new(-26, 0, 586) * CFrame.Angles(0, math.rad(95), 0), P.Gunmetal, area)
	Props.Container(b, CFrame.new(34, 0, 580) * CFrame.Angles(0, math.rad(-5), 0), RUST, area)
	for _, spot in { v(-14, 0, 500), v(16, 0, 560), v(-40, 0, 540), v(42, 0, 530), v(0, 0, 590) } do
		Props.CrateStack(b, spot, area)
	end
	for _, spot in { v(-12, 0, 470), v(14, 0, 470), v(-20, 0, 555), v(20, 0, 510) } do
		MapKit.Block(b, v(10, 4, 2), CFrame.new(spot + v(0, 2, 0)), P.ConcreteGrey, Enum.Material.Concrete, area)
		MapKit.Block(b, v(10.2, 0.4, 2.2), CFrame.new(spot + v(0, 4.1, 0)), P.Orange, Enum.Material.Metal, area)
	end
	for _, x in { -40, 40 } do
		for _, z in { 470, 600 } do
			Props.Lamp(b, v(x, 0.6, z), 14, Color3.fromRGB(255, 225, 190), area)
		end
	end
	-- Sandbag nests, cables between the towers, generators.
	for _, spot in { v(-36, 0.6, 468), v(36, 0.6, 468), v(0, 0.6, 604) } do
		for index = -2, 2 do
			for layer = 0, 1 do
				MapKit.Block(
					b,
					v(2.6, 1.1, 1.6),
					CFrame.new(spot + v(index * 2.5 + layer * 1.2, 0.55 + layer * 1.1, 0)),
					Color3.fromRGB(150, 140, 110),
					Enum.Material.Fabric,
					area
				)
			end
		end
	end
	for _, pair in
		{
			{ v(-55, 23, 446), v(55, 23, 446) },
			{ v(-55, 23, 614), v(55, 23, 614) },
			{ v(-55, 23, 446), v(-55, 23, 614) },
			{ v(55, 23, 446), v(55, 23, 614) },
		}
	do
		Props.Cable(b, pair[1], pair[2], 6, area)
	end
	for _, spot in { v(-50, 0.6, 590), v(50, 0.6, 470) } do
		MapKit.Block(b, v(6, 5, 4), CFrame.new(spot + v(0, 2.5, 0)), P.Gunmetal, Enum.Material.Metal, area)
		MapKit.Neon(b, v(6.1, 0.6, 4.1), CFrame.new(spot + v(0, 3.5, 0)), P.Teal, area)
		Props.Smoke(b, spot + v(1.5, 5.5, 0), 2, Color3.fromRGB(90, 90, 96), area)
	end
	Props.Banner(b, v(-50, 0.6, 610), 18, v(0, 0, -1), RUST, P.Orange, area)
	Props.Banner(b, v(50, 0.6, 610), 18, v(0, 0, -1), RUST, P.Orange, area)
	Props.Weather(b, v(0, 70, 530), v(130, 2, 190), "Snow", area)
end

-- Zone 4: the reactor ---------------------------------------------------------------------------

local function reactor(b: Builder)
	local area = MapKit.Group(b, "Reactor")
	local center = v(0, 0.4, 695)
	MapKit.Room(b, v(0, 0.4, 695), 90, 130, {
		WallHeight = 34,
		WallThickness = 3,
		FloorThickness = 2.4,
		FloorColor = P.DarkMetal,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = P.Gunmetal,
		WallMaterial = Enum.Material.Metal,
		Openings = { North = 20, South = 16 },
		TrimColor = P.Orange,
		Roof = true,
		RoofColor = P.DarkMetal,
		RoofMaterial = Enum.Material.Metal,
	})
	-- The bunker is dug into the mountain.
	for _, side in { -1, 1 } do
		MapKit.TerrainBlock(b, CFrame.new(side * 90, 16, 695), v(84, 48, 150), Enum.Material.Rock)
	end
	MapKit.TerrainBlock(b, CFrame.new(0, 50, 695), v(260, 26, 150), Enum.Material.Snow)
	-- The core: glass column around a glowing heart, braced by rings.
	MapKit.Cylinder(b, 2, 28, center + v(0, 1, 0), P.Gunmetal, Enum.Material.DiamondPlate, area)
	local heart = MapKit.Cylinder(b, 28, 7, center + v(0, 16, 0), P.Orange, Enum.Material.Neon, area)
	MapKit.Light(heart, P.Orange, 60, 3)
	local glass = MapKit.Cylinder(b, 28, 12, center + v(0, 16, 0), P.Glass, Enum.Material.Glass, area)
	glass.Transparency = 0.6
	for _, y in { 5, 15, 25 } do
		Props.Ring(b, CFrame.new(center + v(0, y, 0)), 6.6, 1.2, 1.6, 20, P.DarkMetal, Enum.Material.Metal, area)
	end
	MapKit.Cylinder(b, 3, 16, center + v(0, 31.5, 0), P.DarkMetal, Enum.Material.Metal, area)
	-- Pipes from the core into the walls.
	for _, x in { -1, 1 } do
		Props.Pipe(b, {
			center + v(x * 6, 22, 0),
			center + v(x * 30, 22, 0),
			center + v(x * 30, 22, 40),
			center + v(x * 44, 22, 40),
		}, 2.2, P.Gunmetal, area)
		Props.Pipe(
			b,
			{ center + v(x * 6, 8, 3), center + v(x * 20, 8, 3), center + v(x * 20, 0.5, 3) },
			1.6,
			RUST,
			area
		)
	end
	-- Catwalks along both side walls, with stairs up from the entrance.
	for _, side in { -1, 1 } do
		local x = side * 40
		MapKit.Block(b, v(8, 1, 90), CFrame.new(x, 12.4, 710), P.DarkMetal, Enum.Material.DiamondPlate, area)
		MapKit.Railing(b, v(x - side * 4, 12.9, 665), v(x - side * 4, 12.9, 755), 3.5, P.Gunmetal, 6, area)
		MapKit.Stairs(b, v(x, 0.4, 640), v(x, 12.9, 665), 6, P.DarkMetal, Enum.Material.DiamondPlate, area)
		for z = 660, 750, 30 do
			local lamp = MapKit.Neon(b, v(1.4, 1.4, 1.4), CFrame.new(side * 43.5, 20, z), P.Orange, area)
			MapKit.Light(lamp, P.Orange, 30, 1.6)
		end
	end
	-- Hazard stripes and machinery.
	for _, spot in { v(-24, 0.4, 650), v(24, 0.4, 650), v(-28, 0.4, 745), v(28, 0.4, 745) } do
		MapKit.Block(b, v(8, 6, 6), CFrame.new(spot + v(0, 3, 0)), P.Gunmetal, Enum.Material.Metal, area)
		MapKit.Neon(b, v(8.1, 0.5, 6.1), CFrame.new(spot + v(0, 4.5, 0)), P.Orange, area)
	end
	for _, spot in { v(-14, 0.4, 670), v(14, 0.4, 725), v(-10, 0.4, 740) } do
		Props.CrateStack(b, spot, area)
	end
	-- Control consoles, steam vents and hanging cables.
	for _, spot in { v(-30, 0.4, 636), v(30, 0.4, 636), v(-43, 0.4, 700), v(43, 0.4, 690) } do
		Props.Console(b, facing(spot, v(0, 0.4, 695)), P.Orange, area)
	end
	for _, spot in { v(-20, 0.4, 700), v(20, 0.4, 690), v(0, 0.4, 740), v(-30, 0.4, 720) } do
		MapKit.Block(b, v(4, 0.6, 4), CFrame.new(spot + v(0, 0.3, 0)), P.Black, Enum.Material.DiamondPlate, area)
		Props.Smoke(b, spot + v(0, 1, 0), 4, Color3.fromRGB(220, 220, 225), area)
	end
	for _, x in { -24, -8, 8, 24 } do
		Props.Cable(b, v(x, 35, 640), v(x + 4, 35, 750), 10, area)
	end
	for _, x in { -9, 9 } do
		local warning = MapKit.Neon(b, v(1, 1, 1), CFrame.new(x, 16, 759), P.Red, area)
		MapKit.Light(warning, P.Red, 14, 2)
	end
	-- The back door opens onto a ledge over the chasm.
	MapKit.Block(b, v(24, 2.4, 12), CFrame.new(0, -0.8, 766), P.DarkMetal, Enum.Material.DiamondPlate, area)
	MapKit.Railing(b, v(-12, 0.4, 760), v(-12, 0.4, 772), 3.5, P.Gunmetal, 20, area)
	MapKit.Railing(b, v(12, 0.4, 760), v(12, 0.4, 772), 3.5, P.Gunmetal, 20, area)
end

-- Zone 5: the Scrap Pit -------------------------------------------------------------------------

local function scrapPit(b: Builder)
	local area = MapKit.Group(b, "ScrapPit")
	local pit = v(0, 0, 880)
	MapKit.Cylinder(b, 4, 128, pit + v(0, -2, 0), P.ConcreteDark, Enum.Material.Concrete, area)
	MapKit.Cylinder(b, 0.3, 100, pit + v(0, 0.15, 0), P.Gunmetal, Enum.Material.DiamondPlate, area)
	Props.Ring(b, CFrame.new(pit + v(0, 0.35, 0)), 62, 0.4, 1.2, 48, P.Orange, Enum.Material.Neon, area)
	-- Girders holding the platform over the abyss.
	for index = 0, 5 do
		local angle = math.rad(index * 60)
		local out = v(math.cos(angle), 0, math.sin(angle))
		MapKit.Rod(
			b,
			pit + out * 50 + v(0, -3, 0),
			pit + out * 90 + v(0, -70, 0),
			4,
			P.DarkMetal,
			Enum.Material.Metal,
			area
		)
	end
	-- Scrap heaps for cover, and the Warden's throne of junk.
	for index = 0, 5 do
		local angle = math.rad(index * 60 + 30)
		Props.ScrapPile(b, pit + v(math.cos(angle) * 34, 0, math.sin(angle) * 34), 10, area)
	end
	local throne = pit + v(0, 0, 52)
	MapKit.Block(b, v(26, 4, 10), CFrame.new(throne + v(0, 2, 4)), P.DarkMetal, Enum.Material.CorrodedMetal, area)
	Props.ScrapPile(b, throne + v(-10, 4, 6), 12, area)
	Props.ScrapPile(b, throne + v(10, 4, 6), 12, area)
	for _, x in { -14, 14 } do
		Props.Fire(b, throne + v(x, 5, 2), 6, area)
		Props.Banner(b, throne + v(x, 4, 8), 20, v(0, 0, -1), RUST, P.Orange, area)
	end
	for index = 0, 3 do
		local angle = math.rad(index * 90 + 45)
		Props.Lamp(b, pit + v(math.cos(angle) * 58, 0, math.sin(angle) * 58), 14, P.Orange, area)
	end
	-- A salvage crane over the rim and chains hanging into the abyss.
	Props.Crane(b, pit + v(46, 0, 30), 30, 22, area)
	for index = 0, 7 do
		local angle = math.rad(index * 45 + 10)
		local edge = pit + v(math.cos(angle) * 63, 0, math.sin(angle) * 63)
		local chain = MapKit.Rod(b, edge, edge + v(0, -40 - index * 3, 0), 0.4, P.DarkMetal, Enum.Material.Metal, area)
		if chain then
			chain.CanCollide = false
		end
	end
	Props.Weather(b, v(0, 70, 880), v(150, 2, 150), "Snow", area)
end

function FirstLight.Build(): Model
	local b = MapKit.New("FirstLight")
	b.Model:SetAttribute("KillY", -60)
	b.Model:SetAttribute("DisplayName", "First Light")
	markers(b)
	terrain(b)
	crashSite(b)
	village(b)
	outpost(b)
	reactor(b)
	scrapPit(b)
	return MapKit.Finish(b)
end

return FirstLight
