--!strict
--[[
	Hub: Haven Spire
	The social space players spawn in.

	  Plaza (center)        spawn pad, glowing rings, pillars
	  Director terminal (N) big holo console; click it or press E to open the Director
	  Merchant row (E)      one booth per VendorConfig vendor with a name tag
	  Shooting range (W)    three lanes with dummies at 15 / 30 / 55 studs
	  The Spire (far N)     the tower the hub is named after
	  Skyline (all around)  dark towers with lit windows

	Markers: HubSpawn, Dummy_1..3.
	Named parts: DirectorTerminal (has the ProximityPrompt/ClickDetectors).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VendorConfig = require(ReplicatedStorage.Shared.Config.VendorConfig)

local MapKit = require(script.Parent.MapKit)

local Hub = {}

local P = MapKit.Palette

local function buildPlaza(b: MapKit.Builder)
	-- Ground everything stands on, with invisible boundary walls.
	MapKit.Block(b, Vector3.new(720, 4, 720), CFrame.new(0, -2, 0), P.Ground, Enum.Material.Slate)
	local sides: { Vector3 } =
		{ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	for _, side in sides do
		local isX = side.X ~= 0
		MapKit.Part(b, {
			Name = "Boundary",
			Size = if isX then Vector3.new(4, 80, 720) else Vector3.new(720, 80, 4),
			CFrame = CFrame.new(side * 358 + Vector3.new(0, 40, 0)),
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
		})
	end

	-- Plaza disc with glowing rim and an inner ring around the spawn pad.
	MapKit.Cylinder(b, 0.4, 154, Vector3.new(0, 0.2, 0), P.Cyan, Enum.Material.Neon)
	MapKit.Cylinder(b, 0.6, 150, Vector3.new(0, 0.3, 0), P.Metal, Enum.Material.SmoothPlastic)
	MapKit.Cylinder(b, 0.64, 42, Vector3.new(0, 0.32, 0), P.Cyan, Enum.Material.Neon)
	MapKit.Cylinder(b, 0.66, 38, Vector3.new(0, 0.33, 0), P.MetalLight, Enum.Material.Metal)

	-- Radial light strips across the plaza.
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local middle = direction * 46 + Vector3.new(0, 0.66, 0)
		MapKit.Neon(b, Vector3.new(0.6, 0.05, 50), CFrame.lookAt(middle, middle + direction), P.Violet)
	end

	-- Spawn pad.
	local pad = Instance.new("SpawnLocation")
	pad.Name = "SpawnLocation"
	pad.Anchored = true
	pad.Neutral = true
	pad.Duration = 0
	pad.Size = Vector3.new(12, 1, 12)
	pad.CFrame = CFrame.new(0, 1.1, 0)
	pad.Color = P.Cyan
	pad.Material = Enum.Material.Glass
	pad.Transparency = 0.3
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	pad.Parent = b.Geometry
	MapKit.Light(pad, P.Cyan, 18, 1.5)

	MapKit.Marker(b, "HubSpawn", CFrame.lookAt(Vector3.new(0, 4, 12), Vector3.new(0, 4, -52)))

	-- Pillars around the rim.
	for i = 0, 11 do
		local angle = (i + 0.5) * math.pi / 6
		local position = Vector3.new(math.cos(angle) * 78, 0, math.sin(angle) * 78)
		-- Leave the west side open toward the range and the east toward the merchants.
		if math.abs(position.Z) > 20 then
			MapKit.Block(
				b,
				Vector3.new(3, 20, 3),
				CFrame.new(position + Vector3.new(0, 10, 0)),
				P.StoneDark,
				Enum.Material.Metal
			)
			MapKit.Neon(
				b,
				Vector3.new(3.2, 16, 0.3),
				CFrame.lookAt(position + Vector3.new(0, 10, 0), Vector3.new(0, 10, 0)) * CFrame.new(0, 0, -1.5),
				P.Cyan
			)
			local cap = MapKit.Ball(b, 2.5, position + Vector3.new(0, 21.5, 0), P.Violet, Enum.Material.Neon)
			MapKit.Light(cap, P.Violet, 16, 1)
		end
	end
end

local function buildDirectorTerminal(b: MapKit.Builder)
	local base = Vector3.new(0, 0.6, -52)
	MapKit.Cylinder(b, 0.8, 24, base + Vector3.new(0, 0.4, 0), P.Cyan, Enum.Material.Neon)
	MapKit.Cylinder(b, 1.2, 22, base + Vector3.new(0, 0.6, 0), P.StoneDark, Enum.Material.Metal)

	local console = MapKit.Part(b, {
		Name = "DirectorTerminal",
		Size = Vector3.new(12, 6, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 4.2, 0)),
		Color = P.Trim,
		Material = Enum.Material.Metal,
	})
	local screen = MapKit.Part(b, {
		Name = "DirectorScreen",
		Size = Vector3.new(11, 4.6, 0.3),
		CFrame = CFrame.new(base + Vector3.new(0, 5.1, 1.7)) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = P.Cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	MapKit.Sign(screen, "DIRECTOR", Enum.NormalId.Back, Color3.fromRGB(10, 30, 45))

	-- Floating holo-orb held by three light beams.
	local orbPosition = base + Vector3.new(0, 17, 0)
	local orb = MapKit.Part(b, {
		Name = "DirectorOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		CFrame = CFrame.new(orbPosition),
		Color = Color3.fromRGB(120, 210, 255),
		Material = Enum.Material.Neon,
	})
	MapKit.Light(orb, P.Cyan, 45, 3)
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		local foot = base + Vector3.new(math.cos(angle) * 9, 1.2, math.sin(angle) * 9)
		local middle = (foot + orbPosition) / 2
		MapKit.Neon(
			b,
			Vector3.new(0.4, 0.4, (orbPosition - foot).Magnitude),
			CFrame.lookAt(middle, orbPosition),
			P.Cyan
		)
	end
	for radius = 6, 10, 4 do
		local ring = MapKit.Part(b, {
			Name = "OrbRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 2, radius * 2),
			CFrame = CFrame.new(orbPosition) * CFrame.Angles(0, 0, math.rad(90)),
			Color = P.Violet,
			Material = Enum.Material.ForceField,
			CanCollide = false,
			CanQuery = false,
		})
		ring.Transparency = 0.3
	end
	MapKit.Billboard(orb, "DIRECTOR", "Press M, or walk up and press E", P.Cyan, 6)

	-- Interaction: the server connects these in WorldService.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenDirector"
	prompt.ActionText = "Open Director"
	prompt.ObjectText = "Star Chart"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	for _, part in { console, screen, orb } do
		local click = Instance.new("ClickDetector")
		click.Name = "OpenDirector"
		click.MaxActivationDistance = 80
		click.Parent = part
	end
end

local function buildVendor(b: MapKit.Builder, vendor: VendorConfig.VendorDef, position: Vector3, color: Color3)
	local facing = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	MapKit.Cylinder(b, 0.4, 13, position + Vector3.new(0, 0.2, 0), P.StoneDark, Enum.Material.Metal)
	MapKit.Cylinder(b, 0.3, 13.6, position + Vector3.new(0, 0.1, 0), color, Enum.Material.Neon)

	-- Counter between the vendor and the plaza.
	local counterCFrame = facing * CFrame.new(0, 1.9, -3.5)
	MapKit.Block(b, Vector3.new(7, 3, 1.6), counterCFrame, P.Trim, Enum.Material.Metal)
	MapKit.Neon(b, Vector3.new(7.1, 0.2, 1.7), counterCFrame * CFrame.new(0, 1.55, 0), color)

	-- NPC figure (placeholder art: replace with a real model later).
	local figure = facing * CFrame.new(0, 0, 0.5)
	local legs = MapKit.Block(b, Vector3.new(1.6, 2.6, 1), figure * CFrame.new(0, 1.7, 0), P.StoneDark)
	legs.Name = "VendorLegs"
	local torso =
		MapKit.Block(b, Vector3.new(2.4, 2.4, 1.3), figure * CFrame.new(0, 4.2, 0), color, Enum.Material.Metal)
	torso.Name = "Vendor_" .. vendor.Id
	local head = MapKit.Part(b, {
		Name = "VendorHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.7, 1.7, 1.7),
		CFrame = figure * CFrame.new(0, 6.3, 0),
		Color = P.MetalLight,
		Material = Enum.Material.Metal,
	})
	MapKit.Neon(b, Vector3.new(1.3, 0.3, 0.2), figure * CFrame.new(0, 6.4, -0.75), P.Cyan)
	MapKit.Block(b, Vector3.new(3.2, 0.6, 1.6), figure * CFrame.new(0, 5.3, 0), P.Trim, Enum.Material.Metal)
	MapKit.Billboard(head, vendor.Name, vendor.Title, color, 2.5)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Talk"
	prompt.ObjectText = vendor.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("VendorId", vendor.Id)
	prompt.Parent = torso
end

local function buildMerchantRow(b: MapKit.Builder)
	local colors =
		{ P.Amber, P.Violet, P.Red, P.Cyan, Color3.fromRGB(120, 255, 170), Color3.fromRGB(255, 120, 200), P.MetalLight }
	local vendors = VendorConfig.List
	local count = #vendors
	for index, vendor in vendors do
		local t = if count > 1 then (index - 1) / (count - 1) else 0.5
		local angle = math.rad(-55 + t * 110)
		local position = Vector3.new(math.cos(angle) * 100, 0, math.sin(angle) * 100)
		buildVendor(b, vendor, position, colors[(index - 1) % #colors + 1])
	end
	local sign = MapKit.Block(b, Vector3.new(1, 5, 30), CFrame.new(128, 14, 0), P.Trim, Enum.Material.Metal)
	MapKit.Sign(sign, "MERCHANT ROW", Enum.NormalId.Left, P.Amber)
	MapKit.Block(b, Vector3.new(1.2, 14, 1.2), CFrame.new(128, 7, -12), P.StoneDark)
	MapKit.Block(b, Vector3.new(1.2, 14, 1.2), CFrame.new(128, 7, 12), P.StoneDark)
end

local function buildRange(b: MapKit.Builder)
	-- Lane floor from the plaza edge westward.
	local startX, endX = -84, -190
	local length = startX - endX
	local centerX = (startX + endX) / 2
	MapKit.Block(b, Vector3.new(length, 0.6, 40), CFrame.new(centerX, 0.3, 0), P.StoneDark, Enum.Material.Metal)
	for _, z in { -6.7, 6.7 } do
		MapKit.Neon(b, Vector3.new(length, 0.05, 0.3), CFrame.new(centerX, 0.63, z), P.Amber)
	end
	-- Firing line barrier.
	MapKit.Block(b, Vector3.new(1.5, 2.6, 40), CFrame.new(startX - 1, 1.3, 0), P.Trim, Enum.Material.Metal)
	MapKit.Neon(b, Vector3.new(1.6, 0.2, 40), CFrame.new(startX - 1, 2.65, 0), P.Amber)
	-- Walls.
	MapKit.Block(b, Vector3.new(4, 30, 48), CFrame.new(endX - 2, 15, 0), P.StoneDark, Enum.Material.Metal)
	for _, z in { -22, 22 } do
		MapKit.Block(b, Vector3.new(length, 12, 2), CFrame.new(centerX, 6, z), P.StoneDark, Enum.Material.Metal)
		MapKit.Neon(b, Vector3.new(length, 0.3, 2.2), CFrame.new(centerX, 12.2, z), P.Amber)
	end
	for _, y in { 8, 16, 24 } do
		MapKit.Neon(b, Vector3.new(0.3, 0.6, 46), CFrame.new(endX, y, 0), P.Amber)
	end
	local sign = MapKit.Block(b, Vector3.new(1, 5, 34), CFrame.new(startX + 2, 16, 0), P.Trim, Enum.Material.Metal)
	MapKit.Sign(sign, "SHOOTING RANGE", Enum.NormalId.Right, P.Amber)
	MapKit.Block(b, Vector3.new(1.2, 16, 1.2), CFrame.new(startX + 2, 8, -14), P.StoneDark)
	MapKit.Block(b, Vector3.new(1.2, 16, 1.2), CFrame.new(startX + 2, 8, 14), P.StoneDark)

	-- Dummies at 15, 30 and 55 studs from the firing line, facing the shooter.
	local distances = { 15, 30, 55 }
	local lanes = { -13.4, 0, 13.4 }
	for index, distance in distances do
		local x = startX - 1 - distance
		local position = Vector3.new(x, 0.6, lanes[index])
		MapKit.Marker(b, `Dummy_{index}`, CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
		MapKit.Neon(b, Vector3.new(0.4, 0.05, 12), CFrame.new(x, 0.64, lanes[index]), P.Cyan)
		local plate = MapKit.Block(b, Vector3.new(0.4, 2, 6), CFrame.new(x + 7, 1.6, lanes[index] - 9), P.Trim)
		MapKit.Sign(plate, `{distance}m`, Enum.NormalId.Right, P.Cyan)
	end
end

local function buildSkyline(b: MapKit.Builder)
	-- The Spire: the tower the hub is named after.
	local spireBase = Vector3.new(0, 0, -260)
	MapKit.Block(
		b,
		Vector3.new(44, 260, 44),
		CFrame.new(spireBase + Vector3.new(0, 130, 0)),
		P.StoneDark,
		Enum.Material.Metal
	)
	MapKit.Cylinder(b, 60, 30, spireBase + Vector3.new(0, 290, 0), P.Metal, Enum.Material.Metal)
	local beacon = MapKit.Ball(b, 14, spireBase + Vector3.new(0, 330, 0), P.Cyan, Enum.Material.Neon)
	MapKit.Light(beacon, P.Cyan, 60, 4)
	for _, x in { -22.2, 22.2 } do
		MapKit.Neon(b, Vector3.new(0.4, 240, 2), CFrame.new(spireBase + Vector3.new(x, 125, 0)), P.Cyan)
	end

	-- Ring of skyline towers with lit windows (deterministic layout).
	local heights = { 90, 140, 70, 180, 110, 60, 150, 95, 130, 75, 170, 100, 85, 160, 120, 65 }
	for index, height in heights do
		local angle = (index / #heights) * math.pi * 2 + 0.2
		local radius = 300 + (index % 3) * 18
		local position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local width = 26 + (index % 4) * 6
		MapKit.Block(
			b,
			Vector3.new(width, height, width),
			CFrame.new(position + Vector3.new(0, height / 2, 0)),
			P.Trim,
			Enum.Material.Metal
		)
		local facing = CFrame.lookAt(position, Vector3.new(0, 0, 0))
		for row = 1, math.floor(height / 24) do
			MapKit.Neon(
				b,
				Vector3.new(width * 0.7, 1.2, 0.3),
				facing * CFrame.new(0, row * 22, -width / 2 - 0.1),
				if row % 2 == 0 then P.Cyan else P.Violet
			)
		end
	end
end

function Hub.Build(): Model
	local b = MapKit.New("Hub")
	buildPlaza(b)
	buildDirectorTerminal(b)
	buildMerchantRow(b)
	buildRange(b)
	buildSkyline(b)
	return MapKit.Finish(b)
end

return Hub
