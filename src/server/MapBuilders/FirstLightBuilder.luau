--!strict
--[[
	First Light: a ruined Rustborn outpost on Veyra (story mission, power 350).

	Layout (south to north, +Z):
	  Landing zone  z -35..35   PlayerStart
	  Canyon        z 35..135   rock walls, cover
	  Outpost gate  z ~130      Zone_Outpost, Checkpoint_Outpost
	  Courtyard     z 135..255  walled yard with cover; Spawn_Courtyard_*, Spawn_CourtyardBack_*
	  Terminal      z 255..305  Zone_Terminal (hold 20 s); Door_Terminal at its entrance
	  Boss arena    z 305..415  BossSpawn, Spawn_BossAdds_*; Door_Boss at its entrance
]]

local MapKit = require(script.Parent.MapKit)

local FirstLight = {}

local P = MapKit.Palette

local function rock(b: MapKit.Builder, position: Vector3, size: Vector3, angle: number)
	MapKit.Block(
		b,
		size,
		CFrame.new(position + Vector3.new(0, size.Y / 2 - 0.5, 0)) * CFrame.Angles(0, angle, 0.08),
		P.Rock,
		Enum.Material.Rock
	)
end

local function brokenPillar(b: MapKit.Builder, position: Vector3, height: number)
	MapKit.Block(
		b,
		Vector3.new(4, height, 4),
		CFrame.new(position + Vector3.new(0, height / 2, 0)),
		P.SandDark,
		Enum.Material.Sandstone
	)
	MapKit.Neon(b, Vector3.new(4.2, 0.3, 4.2), CFrame.new(position + Vector3.new(0, height * 0.6, 0)), P.Amber)
end

function FirstLight.Build(): Model
	local b = MapKit.New("FirstLight")

	-- Landing zone ---------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 0), 70, 70, {
		WallHeight = 20,
		WallThickness = 4,
		FloorColor = P.Sand,
		FloorMaterial = Enum.Material.Sand,
		WallColor = P.Rock,
		WallMaterial = Enum.Material.Rock,
		Openings = { North = 30 },
	})
	MapKit.Marker(b, "PlayerStart", CFrame.lookAt(Vector3.new(0, 3, -20), Vector3.new(0, 3, 40)))
	MapKit.Marker(b, "Checkpoint_Start", CFrame.lookAt(Vector3.new(0, 3, -20), Vector3.new(0, 3, 40)))
	-- A crashed skiff to set the scene.
	MapKit.Block(
		b,
		Vector3.new(14, 4, 26),
		CFrame.new(-18, 2, -8) * CFrame.Angles(0.1, 0.4, 0.15),
		P.Metal,
		Enum.Material.CorrodedMetal
	)
	MapKit.Wedge(
		b,
		Vector3.new(14, 4, 8),
		CFrame.new(-12, 2.5, 7) * CFrame.Angles(0.1, 0.4, 0.15),
		P.Metal,
		Enum.Material.CorrodedMetal
	)
	local beacon = MapKit.Ball(b, 2, Vector3.new(-18, 6, -8), P.Amber, Enum.Material.Neon)
	MapKit.Light(beacon, P.Amber, 20, 2)
	rock(b, Vector3.new(20, 0, 15), Vector3.new(8, 6, 7), 0.3)
	rock(b, Vector3.new(24, 0, -18), Vector3.new(6, 9, 6), 0.8)

	-- Canyon ---------------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 85), 30, 100, {
		WallHeight = 18,
		WallThickness = 4,
		FloorColor = P.Sand,
		FloorMaterial = Enum.Material.Sand,
		WallColor = P.Rock,
		WallMaterial = Enum.Material.Rock,
		Openings = { North = 30, South = 30 },
	})
	rock(b, Vector3.new(-9, 0, 60), Vector3.new(5, 4, 5), 0.5)
	rock(b, Vector3.new(8, 0, 88), Vector3.new(6, 5, 4), 1.1)
	MapKit.Crate(b, Vector3.new(-7, 0, 108))
	MapKit.Crate(b, Vector3.new(6, 0, 118), Vector3.new(4, 3, 6))

	-- Outpost gate -------------------------------------------------------------------
	for _, x in { -18, 18 } do
		MapKit.Block(b, Vector3.new(8, 22, 8), CFrame.new(x, 11, 132), P.SandDark, Enum.Material.Sandstone)
		local lamp = MapKit.Ball(b, 2, Vector3.new(x, 23, 132), P.Amber, Enum.Material.Neon)
		MapKit.Light(lamp, P.Amber, 24, 2)
	end
	MapKit.Block(b, Vector3.new(44, 4, 6), CFrame.new(0, 21, 132), P.Rust, Enum.Material.CorrodedMetal)
	MapKit.Zone(b, "Zone_Outpost", Vector3.new(0, 0, 140), 14)
	MapKit.Marker(b, "Checkpoint_Outpost", CFrame.lookAt(Vector3.new(0, 3, 140), Vector3.new(0, 3, 200)))

	-- Courtyard ------------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 195), 120, 120, {
		WallHeight = 12,
		WallThickness = 3,
		FloorColor = P.SandDark,
		FloorMaterial = Enum.Material.Sandstone,
		WallColor = P.Sand,
		WallMaterial = Enum.Material.Sandstone,
		Openings = { South = 30, North = 20 },
		TrimColor = P.Amber,
	})
	-- Cover: crates, low walls and broken pillars.
	local cover = {
		Vector3.new(-30, 0, 170),
		Vector3.new(28, 0, 165),
		Vector3.new(-12, 0, 200),
		Vector3.new(15, 0, 210),
		Vector3.new(-38, 0, 225),
		Vector3.new(40, 0, 232),
	}
	for index, position in cover do
		if index % 2 == 0 then
			MapKit.Crate(b, position)
		else
			MapKit.Block(
				b,
				Vector3.new(14, 4, 2),
				CFrame.new(position + Vector3.new(0, 2, 0)),
				P.SandDark,
				Enum.Material.Sandstone
			)
		end
	end
	brokenPillar(b, Vector3.new(-45, 0, 190), 9)
	brokenPillar(b, Vector3.new(45, 0, 195), 6)
	brokenPillar(b, Vector3.new(0, 0, 180), 7)
	MapKit.SpawnGroup(b, "Courtyard", {
		Vector3.new(-45, 3, 245),
		Vector3.new(-25, 3, 240),
		Vector3.new(0, 3, 238),
		Vector3.new(25, 3, 240),
		Vector3.new(45, 3, 245),
		Vector3.new(-50, 3, 215),
		Vector3.new(50, 3, 215),
		Vector3.new(-20, 3, 225),
		Vector3.new(20, 3, 225),
		Vector3.new(0, 3, 215),
	}, Vector3.new(0, 3, 150))
	MapKit.SpawnGroup(b, "CourtyardBack", {
		Vector3.new(-8, 3, 250),
		Vector3.new(8, 3, 250),
	}, Vector3.new(0, 3, 150))
	MapKit.Door(b, "Door_Terminal", Vector3.new(20, 12, 2), CFrame.new(0, 6, 255))

	-- Terminal building ------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 280), 60, 50, {
		WallHeight = 14,
		WallThickness = 3,
		FloorColor = P.Metal,
		FloorMaterial = Enum.Material.DiamondPlate,
		WallColor = P.Rust,
		WallMaterial = Enum.Material.CorrodedMetal,
		-- The courtyard and the arena provide the south and north walls.
		Openings = { South = 60, North = 60 },
		TrimColor = P.Cyan,
	})
	MapKit.Marker(b, "Checkpoint_Terminal", CFrame.lookAt(Vector3.new(0, 3, 262), Vector3.new(0, 3, 290)))
	local console = MapKit.Block(b, Vector3.new(6, 5, 3), CFrame.new(0, 2.5, 292), P.Trim, Enum.Material.Metal)
	console.Name = "Terminal"
	local screen = MapKit.Neon(b, Vector3.new(5, 3, 0.3), CFrame.new(0, 3.5, 290.4), P.Cyan)
	MapKit.Light(screen, P.Cyan, 18, 2)
	MapKit.Zone(b, "Zone_Terminal", Vector3.new(0, 0, 284), 10)
	MapKit.ZoneRing(b, Vector3.new(0, 0, 284), 10, P.Cyan)
	MapKit.Crate(b, Vector3.new(-18, 0, 272), Vector3.new(6, 4, 3))
	MapKit.Crate(b, Vector3.new(18, 0, 272), Vector3.new(6, 4, 3))
	MapKit.SpawnGroup(b, "Terminal", {
		Vector3.new(-25, 3, 260),
		Vector3.new(25, 3, 260),
		Vector3.new(-25, 3, 300),
		Vector3.new(25, 3, 300),
		Vector3.new(-12, 3, 300),
		Vector3.new(12, 3, 300),
	}, Vector3.new(0, 3, 284))

	-- Boss arena ------------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, 360), 110, 110, {
		WallHeight = 16,
		WallThickness = 4,
		FloorColor = P.SandDark,
		FloorMaterial = Enum.Material.Sandstone,
		WallColor = P.Rust,
		WallMaterial = Enum.Material.CorrodedMetal,
		Openings = { South = 20 },
		TrimColor = P.Red,
	})
	MapKit.Door(b, "Door_Boss", Vector3.new(20, 14, 2), CFrame.new(0, 7, 305))
	MapKit.Marker(b, "Checkpoint_Boss", CFrame.lookAt(Vector3.new(0, 3, 300), Vector3.new(0, 3, 360)))
	-- Raised platform for the captain at the far end.
	MapKit.Block(b, Vector3.new(34, 3, 18), CFrame.new(0, 1.5, 396), P.Rust, Enum.Material.CorrodedMetal)
	-- Ramp up to the platform (a wedge rises toward its +Z end).
	MapKit.Wedge(b, Vector3.new(34, 3, 8), CFrame.new(0, 1.5, 383), P.Rust, Enum.Material.CorrodedMetal)
	MapKit.Marker(b, "BossSpawn", CFrame.lookAt(Vector3.new(0, 4, 396), Vector3.new(0, 4, 320)))
	for _, position in
		{
			Vector3.new(-30, 0, 335),
			Vector3.new(30, 0, 335),
			Vector3.new(-20, 0, 365),
			Vector3.new(20, 0, 365),
		}
	do
		brokenPillar(b, position, 10)
	end
	MapKit.Crate(b, Vector3.new(-40, 0, 355))
	MapKit.Crate(b, Vector3.new(40, 0, 355))
	MapKit.SpawnGroup(b, "BossAdds", {
		Vector3.new(-45, 3, 400),
		Vector3.new(45, 3, 400),
		Vector3.new(-48, 3, 370),
		Vector3.new(48, 3, 370),
		Vector3.new(-30, 3, 405),
		Vector3.new(30, 3, 405),
	}, Vector3.new(0, 3, 330))

	return MapKit.Finish(b)
end

return FirstLight
