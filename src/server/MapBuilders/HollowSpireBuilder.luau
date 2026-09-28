--!strict
--[[
	Hollow Spire: Kaldrek's fortress (hardened strike, power 450-490).

	Layout (south to north, +Z):
	  Start platform  z -20..20     PlayerStart
	  Gate            z 20..60      Zone_Gate, Checkpoint_Gate
	  Arena 1         z 60..130     "Gate Hall", Spawn_Arena1_*, Door_1
	  Corridor        z 130..160    Checkpoint_Arena2
	  Arena 2         z 160..240    "Forge Line" with side catwalks, Spawn_Arena2_*, Door_2
	  Corridor        z 240..265    Checkpoint_Arena3
	  Arena 3         z 265..345    "Lift Hall", Zone_Lift (hold 30 s), Spawn_Arena3_*, Door_3
	  Corridor        z 345..370    Checkpoint_Boss
	  Boss arena      z 370..490    "Spire Crown", BossSpawn, Spawn_BossAdds_*
]]

local MapKit = require(script.Parent.MapKit)

local HollowSpire = {}

local IRON = Color3.fromRGB(46, 38, 40)
local IRON_LIGHT = Color3.fromRGB(78, 64, 62)
local EMBER = Color3.fromRGB(255, 90, 40)

local function arena(b: MapKit.Builder, centerZ: number, sizeX: number, sizeZ: number, openNorth: boolean)
	MapKit.Room(b, Vector3.new(0, 0, centerZ), sizeX, sizeZ, {
		WallHeight = 18,
		WallThickness = 4,
		FloorColor = IRON,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = IRON_LIGHT,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = if openNorth then { South = 20, North = 20 } else { South = 20 },
		TrimColor = EMBER,
	})
end

local function corridor(b: MapKit.Builder, fromZ: number, toZ: number)
	MapKit.Room(b, Vector3.new(0, 0, (fromZ + toZ) / 2), 20, toZ - fromZ, {
		WallHeight = 14,
		WallThickness = 3,
		FloorColor = IRON,
		FloorMaterial = Enum.Material.Metal,
		WallColor = IRON_LIGHT,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = { South = 20, North = 20 },
		TrimColor = EMBER,
	})
end

local function pillar(b: MapKit.Builder, position: Vector3, height: number)
	MapKit.Block(
		b,
		Vector3.new(5, height, 5),
		CFrame.new(position + Vector3.new(0, height / 2, 0)),
		IRON_LIGHT,
		Enum.Material.CorrodedMetal
	)
	local glow = MapKit.Neon(b, Vector3.new(5.2, 0.4, 5.2), CFrame.new(position + Vector3.new(0, height - 1, 0)), EMBER)
	MapKit.Light(glow, EMBER, 16, 1.5)
end

local function lavaChannel(b: MapKit.Builder, fromZ: number, toZ: number, x: number)
	local length = toZ - fromZ
	local channel = MapKit.Neon(b, Vector3.new(3, 0.1, length), CFrame.new(x, 0.05, (fromZ + toZ) / 2), EMBER)
	MapKit.Light(channel, EMBER, 14, 1)
end

function HollowSpire.Build(): Model
	local b = MapKit.New("HollowSpire")

	-- Start and gate --------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 0), 40, 40, {
		WallHeight = 10,
		WallThickness = 3,
		FloorColor = IRON,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = IRON_LIGHT,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = { North = 20 },
		TrimColor = EMBER,
	})
	MapKit.Marker(b, "PlayerStart", CFrame.lookAt(Vector3.new(0, 3, -10), Vector3.new(0, 3, 60)))
	corridor(b, 20, 60)
	for _, x in { -14, 14 } do
		MapKit.Block(b, Vector3.new(6, 26, 6), CFrame.new(x, 13, 58), IRON_LIGHT, Enum.Material.CorrodedMetal)
		local lamp = MapKit.Ball(b, 2.5, Vector3.new(x, 27, 58), EMBER, Enum.Material.Neon)
		MapKit.Light(lamp, EMBER, 26, 2)
	end
	MapKit.Zone(b, "Zone_Gate", Vector3.new(0, 0, 48), 10)
	MapKit.Marker(b, "Checkpoint_Gate", CFrame.lookAt(Vector3.new(0, 3, 52), Vector3.new(0, 3, 95)))

	-- Arena 1: Gate Hall ------------------------------------------------------------------
	arena(b, 95, 80, 70, true)
	for _, position in
		{
			Vector3.new(-22, 0, 80),
			Vector3.new(22, 0, 80),
			Vector3.new(-22, 0, 110),
			Vector3.new(22, 0, 110),
		}
	do
		pillar(b, position, 16)
	end
	MapKit.Crate(b, Vector3.new(0, 0, 90), Vector3.new(10, 4, 3))
	MapKit.SpawnGroup(b, "Arena1", {
		Vector3.new(-30, 3, 120),
		Vector3.new(-15, 3, 124),
		Vector3.new(0, 3, 122),
		Vector3.new(15, 3, 124),
		Vector3.new(30, 3, 120),
		Vector3.new(-32, 3, 100),
		Vector3.new(32, 3, 100),
		Vector3.new(-10, 3, 108),
		Vector3.new(10, 3, 108),
	}, Vector3.new(0, 3, 65))
	MapKit.Door(b, "Door_1", Vector3.new(20, 18, 2), CFrame.new(0, 9, 130))

	-- Arena 2: Forge Line -------------------------------------------------------------
	corridor(b, 130, 160)
	MapKit.Marker(b, "Checkpoint_Arena2", CFrame.lookAt(Vector3.new(0, 3, 138), Vector3.new(0, 3, 200)))
	arena(b, 200, 100, 80, true)
	lavaChannel(b, 164, 236, -12)
	lavaChannel(b, 164, 236, 12)
	-- Side catwalks with ramps.
	for _, x in { -38, 38 } do
		MapKit.Block(b, Vector3.new(20, 6, 60), CFrame.new(x, 3, 205), IRON_LIGHT, Enum.Material.DiamondPlate)
		MapKit.Wedge(b, Vector3.new(20, 6, 14), CFrame.new(x, 3, 168), IRON_LIGHT, Enum.Material.DiamondPlate)
		MapKit.Neon(b, Vector3.new(20.2, 0.3, 60), CFrame.new(x, 6.1, 205), EMBER)
	end
	MapKit.Crate(b, Vector3.new(0, 0, 185))
	MapKit.Crate(b, Vector3.new(-5, 0, 215), Vector3.new(4, 5, 4))
	MapKit.Crate(b, Vector3.new(6, 0, 222))
	MapKit.SpawnGroup(b, "Arena2", {
		Vector3.new(-38, 9, 225),
		Vector3.new(38, 9, 225),
		Vector3.new(-38, 9, 200),
		Vector3.new(38, 9, 200),
		Vector3.new(-20, 3, 232),
		Vector3.new(20, 3, 232),
		Vector3.new(0, 3, 235),
		Vector3.new(-6, 3, 228),
		Vector3.new(6, 3, 228),
		Vector3.new(0, 3, 205),
	}, Vector3.new(0, 3, 165))
	MapKit.Door(b, "Door_2", Vector3.new(20, 18, 2), CFrame.new(0, 9, 240))

	-- Arena 3: Lift Hall ------------------------------------------------------------------
	corridor(b, 240, 265)
	MapKit.Marker(b, "Checkpoint_Arena3", CFrame.lookAt(Vector3.new(0, 3, 248), Vector3.new(0, 3, 305)))
	arena(b, 305, 80, 80, true)
	MapKit.Cylinder(b, 0.6, 22, Vector3.new(0, 0.3, 305), EMBER, Enum.Material.Neon)
	MapKit.Cylinder(b, 0.7, 19, Vector3.new(0, 0.35, 305), IRON_LIGHT, Enum.Material.DiamondPlate)
	MapKit.Zone(b, "Zone_Lift", Vector3.new(0, 0, 305), 10)
	MapKit.ZoneRing(b, Vector3.new(0, 0.7, 305), 10, EMBER)
	for _, position in
		{
			Vector3.new(-25, 0, 285),
			Vector3.new(25, 0, 285),
			Vector3.new(-25, 0, 325),
			Vector3.new(25, 0, 325),
		}
	do
		pillar(b, position, 14)
	end
	MapKit.SpawnGroup(b, "Arena3", {
		Vector3.new(-35, 3, 340),
		Vector3.new(35, 3, 340),
		Vector3.new(-35, 3, 270),
		Vector3.new(35, 3, 270),
		Vector3.new(0, 3, 340),
		Vector3.new(-35, 3, 305),
		Vector3.new(35, 3, 305),
	}, Vector3.new(0, 3, 305))
	MapKit.Door(b, "Door_3", Vector3.new(20, 18, 2), CFrame.new(0, 9, 345))

	-- Boss arena: Spire Crown -------------------------------------------------------------
	corridor(b, 345, 370)
	MapKit.Marker(b, "Checkpoint_Boss", CFrame.lookAt(Vector3.new(0, 3, 352), Vector3.new(0, 3, 430)))
	arena(b, 430, 120, 120, false)
	MapKit.Block(b, Vector3.new(40, 4, 24), CFrame.new(0, 2, 468), IRON_LIGHT, Enum.Material.CorrodedMetal)
	MapKit.Wedge(b, Vector3.new(40, 4, 10), CFrame.new(0, 2, 451), IRON_LIGHT, Enum.Material.CorrodedMetal)
	local throne = MapKit.Neon(b, Vector3.new(40.2, 0.3, 24.2), CFrame.new(0, 4.1, 468), EMBER)
	MapKit.Light(throne, EMBER, 30, 2)
	MapKit.Marker(b, "BossSpawn", CFrame.lookAt(Vector3.new(0, 5, 470), Vector3.new(0, 5, 380)))
	for _, position in
		{
			Vector3.new(-35, 0, 400),
			Vector3.new(35, 0, 400),
			Vector3.new(-40, 0, 440),
			Vector3.new(40, 0, 440),
			Vector3.new(0, 0, 415),
		}
	do
		pillar(b, position, 18)
	end
	MapKit.SpawnGroup(b, "BossAdds", {
		Vector3.new(-50, 3, 480),
		Vector3.new(50, 3, 480),
		Vector3.new(-54, 3, 440),
		Vector3.new(54, 3, 440),
		Vector3.new(-30, 3, 482),
		Vector3.new(30, 3, 482),
		Vector3.new(-54, 3, 400),
		Vector3.new(54, 3, 400),
	}, Vector3.new(0, 3, 400))

	return MapKit.Finish(b)
end

return HollowSpire
