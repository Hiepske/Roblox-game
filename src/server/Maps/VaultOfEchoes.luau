--!strict
--[[
	Vault of Echoes, encounter 1: The Echo Chamber (raid, power 495).

	Layout (south to north, +Z):
	  Entry hall   z -40..25   PlayerStart
	  Chamber      z 25..175   150 x 150, boss dais in the middle
	    Zone_Chamber / Checkpoint_Chamber at the entrance
	    BossSpawn on the dais (the Echo Engine never moves)
	    Plate_1..3  echo plates, 48 studs from the dais at 120 degree spacing
	    Spawn_Adds_* along the walls
]]

local MapKit = require(script.Parent.MapKit)

local VaultOfEchoes = {}

local P = MapKit.Palette
local ECHO = Color3.fromRGB(110, 230, 255)

function VaultOfEchoes.Build(): Model
	local b = MapKit.New("VaultOfEchoes")

	-- Entry hall --------------------------------------------------------------------
	MapKit.Room(b, Vector3.new(0, 0, -7.5), 24, 65, {
		WallHeight = 20,
		WallThickness = 3,
		FloorColor = P.StoneDark,
		FloorMaterial = Enum.Material.Slate,
		WallColor = P.Stone,
		WallMaterial = Enum.Material.Slate,
		Openings = { North = 24 },
		TrimColor = ECHO,
	})
	MapKit.Marker(b, "PlayerStart", CFrame.lookAt(Vector3.new(0, 3, -30), Vector3.new(0, 3, 100)))
	for z = -30, 15, 15 do
		for _, x in { -10, 10 } do
			local crystal = MapKit.Part(b, {
				Name = "Crystal",
				Size = Vector3.new(1.2, 5, 1.2),
				CFrame = CFrame.new(x, 4, z) * CFrame.Angles(0, math.rad(45), math.rad(12)),
				Color = ECHO,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			MapKit.Light(crystal, ECHO, 14, 1)
		end
	end

	-- Chamber -----------------------------------------------------------------------
	local center = Vector3.new(0, 0, 100)
	MapKit.Room(b, center, 150, 150, {
		WallHeight = 34,
		WallThickness = 5,
		FloorColor = P.StoneDark,
		FloorMaterial = Enum.Material.Slate,
		WallColor = P.Stone,
		WallMaterial = Enum.Material.Slate,
		Openings = { South = 24 },
		TrimColor = ECHO,
	})
	MapKit.Zone(b, "Zone_Chamber", Vector3.new(0, 0, 36), 12)
	MapKit.Marker(b, "Checkpoint_Chamber", CFrame.lookAt(Vector3.new(0, 3, 38), center + Vector3.new(0, 3, 0)))

	-- Boss dais.
	MapKit.Cylinder(b, 4, 32, center + Vector3.new(0, 2, 0), P.Stone, Enum.Material.Slate)
	MapKit.Cylinder(b, 4.2, 34, center + Vector3.new(0, 1.9, 0), ECHO, Enum.Material.Neon)
	MapKit.Marker(b, "BossSpawn", CFrame.lookAt(center + Vector3.new(0, 4, 0), Vector3.new(0, 4, 30)))

	-- Echo plates at 120 degree spacing (Plate_1 faces the entrance).
	for index = 1, 3 do
		local angle = math.rad(180 + (index - 1) * 120)
		local position = center + Vector3.new(math.sin(angle) * 48, 0, math.cos(angle) * 48)
		MapKit.Cylinder(b, 0.3, 15, position + Vector3.new(0, 0.15, 0), P.StoneDark, Enum.Material.Slate)
		local plate = MapKit.Part(b, {
			Name = `Plate_{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 12, 12),
			CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = ECHO,
			Material = Enum.Material.Neon,
		})
		MapKit.Light(plate, ECHO, 20, 1.5)
		MapKit.Billboard(plate, `ECHO PLATE {index}`, "Stand here", ECHO, 4)
	end

	-- Pillars ringing the chamber.
	for index = 0, 7 do
		local angle = (index + 0.5) * math.pi / 4
		local position = center + Vector3.new(math.cos(angle) * 62, 0, math.sin(angle) * 62)
		MapKit.Block(
			b,
			Vector3.new(6, 34, 6),
			CFrame.new(position + Vector3.new(0, 17, 0)),
			P.Stone,
			Enum.Material.Slate
		)
		local glow = MapKit.Neon(b, Vector3.new(6.2, 0.5, 6.2), CFrame.new(position + Vector3.new(0, 26, 0)), ECHO)
		MapKit.Light(glow, ECHO, 22, 1.5)
	end
	-- Low cover near the plates.
	for index = 0, 5 do
		local angle = index * math.pi / 3 + math.pi / 6
		local position = center + Vector3.new(math.cos(angle) * 30, 0, math.sin(angle) * 30)
		MapKit.Block(
			b,
			Vector3.new(8, 3.5, 2),
			CFrame.lookAt(position + Vector3.new(0, 1.75, 0), center + Vector3.new(0, 1.75, 0)),
			P.Stone,
			Enum.Material.Slate
		)
	end

	local adds: { Vector3 } = {}
	for index = 0, 7 do
		local angle = index * math.pi / 4
		table.insert(adds, center + Vector3.new(math.cos(angle) * 68, 3, math.sin(angle) * 68))
	end
	MapKit.SpawnGroup(b, "Adds", adds, center)

	return MapKit.Finish(b)
end

return VaultOfEchoes
