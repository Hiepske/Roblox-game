--!strict
--[[
	MapKit
	Helpers for building maps out of parts (and Terrain) in code.

	Every map is a Model with these folders:
	  Geometry  everything you can see and stand on (props are grouped into
	            Models so repeated decoration stays tidy in the Explorer)
	  Markers   invisible, non-colliding parts the game reads by name, in
	            sub-folders: Spawns, Checkpoints, EnemySpawns/<Zone>,
	            Objectives, BossArena, Exit (and Areas/Range in the hub).
	            Game logic only uses markers, so moving one in Studio moves
	            the gameplay with it. Names are unique within a map.
	  Gates     zone gates (doors, shield walls, bridges) named Gate_<Zone>
	  Doors     Phase 2 doors named Door_* (older maps)
	  Terrain   terrain "recipe" parts (see below)

	Terrain can't live inside a Model, so builders don't write Terrain
	directly. MapKit.TerrainBlock/Ball/Cylinder/Wedge add invisible recipe
	parts (attribute TerrainShape + TerrainMaterial) to the Terrain folder;
	MapKit.ApplyTerrain(model) turns them into real terrain with
	Terrain:FillBlock/FillBall/FillCylinder/FillWedge wherever the model is,
	and MapKit.ClearTerrain(model) removes it again. That keeps maps
	deterministic, cloneable per activity instance, and editable in Studio
	(move or resize a recipe part to reshape the terrain).

	The model's pivot is the origin, so ActivityService can place copies
	anywhere with PivotTo. Everything is anchored; small details don't cast
	shadows.
]]

local MapKit = {}

export type Builder = {
	Model: Model,
	Geometry: Folder,
	Markers: Folder,
	Doors: Folder,
	Gates: Folder,
	Terrain: Folder,
	Rng: Random,
}

MapKit.Palette = {
	Ground = Color3.fromRGB(28, 30, 38),
	Metal = Color3.fromRGB(52, 56, 68),
	MetalLight = Color3.fromRGB(88, 94, 110),
	Trim = Color3.fromRGB(20, 22, 28),
	Cyan = Color3.fromRGB(90, 220, 255),
	Violet = Color3.fromRGB(170, 110, 255),
	Amber = Color3.fromRGB(255, 170, 60),
	Red = Color3.fromRGB(255, 80, 60),
	Sand = Color3.fromRGB(176, 142, 104),
	SandDark = Color3.fromRGB(128, 98, 72),
	Rust = Color3.fromRGB(150, 78, 44),
	Rock = Color3.fromRGB(110, 90, 78),
	Stone = Color3.fromRGB(70, 78, 92),
	StoneDark = Color3.fromRGB(40, 46, 58),
	-- Clean sci-fi style guide (Phase 3).
	Concrete = Color3.fromRGB(214, 214, 208),
	ConcreteGrey = Color3.fromRGB(160, 162, 160),
	ConcreteDark = Color3.fromRGB(112, 114, 116),
	DarkMetal = Color3.fromRGB(46, 50, 58),
	Gunmetal = Color3.fromRGB(78, 84, 94),
	Orange = Color3.fromRGB(255, 140, 50),
	Teal = Color3.fromRGB(60, 220, 210),
	White = Color3.fromRGB(240, 240, 236),
	Glass = Color3.fromRGB(170, 215, 235),
	Leaf = Color3.fromRGB(96, 140, 70),
	LeafDark = Color3.fromRGB(62, 104, 52),
	Bark = Color3.fromRGB(96, 72, 54),
	Gold = Color3.fromRGB(214, 170, 78),
	Black = Color3.fromRGB(22, 22, 26),
}

-- Details smaller than this (largest side, studs) don't cast shadows.
local SMALL_DETAIL = 3

local function nameSeed(name: string): number
	local seed = 7
	for index = 1, #name do
		seed = (seed * 31 + string.byte(name, index)) % 2147483647
	end
	return seed
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- A new map. The random generator is seeded from the name (or `seed`), so
-- the same builder always produces the same map.
function MapKit.New(name: string, seed: number?): Builder
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = CFrame.new()
	return {
		Model = model,
		Geometry = newFolder("Geometry", model),
		Markers = newFolder("Markers", model),
		Doors = newFolder("Doors", model),
		Gates = newFolder("Gates", model),
		Terrain = newFolder("Terrain", model),
		Rng = Random.new(seed or nameSeed(name)),
	}
end

export type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	Shape: Enum.PartType?,
	Parent: Instance?,
	CastShadow: boolean?,
	Reflectance: number?,
}

function MapKit.Part(b: Builder, props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name or "Part"
	part.Anchored = true
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color or MapKit.Palette.Metal
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	local size = props.Size
	local small = math.max(size.X, size.Y, size.Z) < SMALL_DETAIL
	part.CastShadow = if props.CastShadow == nil then not small else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent or b.Geometry
	return part
end

-- Solid block.
function MapKit.Block(
	b: Builder,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): Part
	return MapKit.Part(b, { Size = size, CFrame = cframe, Color = color, Material = material, Parent = parent })
end

-- Glowing strip that neither blocks movement nor bullets.
function MapKit.Neon(b: Builder, size: Vector3, cframe: CFrame, color: Color3, parent: Instance?): Part
	return MapKit.Part(b, {
		Name = "Neon",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
end

function MapKit.Wedge(
	b: Builder,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color or MapKit.Palette.Metal
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.CastShadow = math.max(size.X, size.Y, size.Z) >= SMALL_DETAIL
	wedge.Parent = parent or b.Geometry
	return wedge
end

-- Upright cylinder (axis along world Y) centered at `position`.
function MapKit.Cylinder(
	b: Builder,
	height: number,
	diameter: number,
	position: Vector3,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): Part
	return MapKit.Part(b, {
		Name = "Cylinder",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- A cylinder between two points (pipes, poles, cables, beams).
function MapKit.Rod(
	b: Builder,
	from: Vector3,
	to: Vector3,
	diameter: number,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): Part?
	local offset = to - from
	local length = offset.Magnitude
	if length < 0.05 then
		return nil
	end
	-- Cylinders run along their X axis.
	local cframe = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	return MapKit.Part(b, {
		Name = "Rod",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.Metal,
		Parent = parent,
	})
end

function MapKit.Ball(
	b: Builder,
	diameter: number,
	position: Vector3,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): Part
	return MapKit.Part(b, {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(position),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- A wall standing on the ground between two points (Y of `from` = its base).
function MapKit.Wall(
	b: Builder,
	from: Vector3,
	to: Vector3,
	height: number,
	thickness: number,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): Part?
	local flatTo = Vector3.new(to.X, from.Y, to.Z)
	local length = (flatTo - from).Magnitude
	if length < 0.1 then
		return nil
	end
	local middle = (from + flatTo) / 2 + Vector3.new(0, height / 2, 0)
	return MapKit.Part(b, {
		Name = "Wall",
		Size = Vector3.new(thickness, height, length),
		CFrame = CFrame.lookAt(middle, middle + (flatTo - from).Unit),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- An invisible wall players can't pass (bullets and clicks go through).
function MapKit.Barrier(b: Builder, from: Vector3, to: Vector3, height: number): Part?
	local flatTo = Vector3.new(to.X, from.Y, to.Z)
	local length = (flatTo - from).Magnitude
	if length < 0.1 then
		return nil
	end
	local middle = (from + flatTo) / 2 + Vector3.new(0, height / 2, 0)
	return MapKit.Part(b, {
		Name = "Barrier",
		Size = Vector3.new(1, height, length),
		CFrame = CFrame.lookAt(middle, middle + (flatTo - from).Unit),
		Transparency = 1,
		CanQuery = false,
		CastShadow = false,
	})
end

export type RoomOptions = {
	WallHeight: number,
	WallThickness: number?,
	FloorThickness: number?,
	FloorColor: Color3?,
	WallColor: Color3?,
	FloorMaterial: Enum.Material?,
	WallMaterial: Enum.Material?,
	-- Gap widths per side ("North" = -Z, "South" = +Z, "East" = +X, "West" = -X).
	Openings: { [string]: number }?,
	NoFloor: boolean?,
	TrimColor: Color3?,
	-- Adds a ceiling at WallHeight.
	Roof: boolean?,
	RoofColor: Color3?,
	RoofMaterial: Enum.Material?,
}

-- A rectangular room: floor top at center.Y, walls around, with centered gaps.
function MapKit.Room(b: Builder, center: Vector3, sizeX: number, sizeZ: number, options: RoomOptions)
	local thickness = options.WallThickness or 2
	local floorThickness = options.FloorThickness or 2
	if not options.NoFloor then
		MapKit.Block(
			b,
			Vector3.new(sizeX, floorThickness, sizeZ),
			CFrame.new(center - Vector3.new(0, floorThickness / 2, 0)),
			options.FloorColor or MapKit.Palette.Ground,
			options.FloorMaterial
		)
	end
	if options.Roof then
		MapKit.Block(
			b,
			Vector3.new(sizeX + thickness * 2, 2, sizeZ + thickness * 2),
			CFrame.new(center + Vector3.new(0, options.WallHeight + 1, 0)),
			options.RoofColor or options.WallColor,
			options.RoofMaterial or options.WallMaterial
		)
	end

	local halfX, halfZ = sizeX / 2, sizeZ / 2
	local openings = options.Openings or {}
	local sides: { { Name: string, A: Vector3, B: Vector3 } } = {
		{ Name = "North", A = Vector3.new(-halfX, 0, -halfZ), B = Vector3.new(halfX, 0, -halfZ) },
		{ Name = "South", A = Vector3.new(-halfX, 0, halfZ), B = Vector3.new(halfX, 0, halfZ) },
		{ Name = "West", A = Vector3.new(-halfX, 0, -halfZ), B = Vector3.new(-halfX, 0, halfZ) },
		{ Name = "East", A = Vector3.new(halfX, 0, -halfZ), B = Vector3.new(halfX, 0, halfZ) },
	}
	for _, side in sides do
		local a, c = center + side.A, center + side.B
		local gap = openings[side.Name]
		if gap and gap > 0 then
			local middle = (a + c) / 2
			local direction = (c - a).Unit
			MapKit.Wall(
				b,
				a,
				middle - direction * gap / 2,
				options.WallHeight,
				thickness,
				options.WallColor,
				options.WallMaterial
			)
			MapKit.Wall(
				b,
				middle + direction * gap / 2,
				c,
				options.WallHeight,
				thickness,
				options.WallColor,
				options.WallMaterial
			)
		else
			MapKit.Wall(b, a, c, options.WallHeight, thickness, options.WallColor, options.WallMaterial)
		end
		if options.TrimColor then
			local length = (c - a).Magnitude
			local middle = (a + c) / 2 + Vector3.new(0, options.WallHeight + 0.15, 0)
			MapKit.Neon(
				b,
				Vector3.new(thickness + 0.2, 0.3, length),
				CFrame.lookAt(middle, middle + (c - a).Unit),
				options.TrimColor
			)
		end
	end
end

-- Straight stairs from `bottom` (floor level at the first step) up to `top`
-- (floor level after the last step), `width` wide. Returns the step count.
function MapKit.Stairs(
	b: Builder,
	bottom: Vector3,
	top: Vector3,
	width: number,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): number
	local rise = top.Y - bottom.Y
	local flat = Vector3.new(top.X - bottom.X, 0, top.Z - bottom.Z)
	local run = flat.Magnitude
	if run < 0.1 or math.abs(rise) < 0.1 then
		return 0
	end
	local steps = math.max(1, math.ceil(math.abs(rise) / 1.2))
	local stepRise = rise / steps
	local stepRun = run / steps
	local direction = flat.Unit
	local group = parent or b.Geometry
	for index = 1, steps do
		-- Each step is a block from the base up to its tread height.
		local height = math.abs(stepRise) * index
		local base = math.min(bottom.Y, top.Y)
		local along = if rise > 0 then (index - 0.5) * stepRun else (steps - index + 0.5) * stepRun
		local center = bottom + direction * along
		MapKit.Part(b, {
			Name = "Step",
			Size = Vector3.new(width, height, stepRun + 0.02),
			CFrame = CFrame.lookAt(
				Vector3.new(center.X, base + height / 2, center.Z),
				Vector3.new(center.X, base + height / 2, center.Z) + direction
			),
			Color = color,
			Material = material,
			Parent = group,
		})
	end
	return steps
end

-- A walkable ramp (wedge) rising from `bottom` to `top`.
function MapKit.Ramp(
	b: Builder,
	bottom: Vector3,
	top: Vector3,
	width: number,
	color: Color3?,
	material: Enum.Material?,
	parent: Instance?
): WedgePart?
	local rise = top.Y - bottom.Y
	local flat = Vector3.new(top.X - bottom.X, 0, top.Z - bottom.Z)
	local run = flat.Magnitude
	if run < 0.1 or rise <= 0 then
		return nil
	end
	-- A WedgePart rises toward its -Z face... it slopes up toward +Z local.
	local center = Vector3.new((bottom.X + top.X) / 2, bottom.Y + rise / 2, (bottom.Z + top.Z) / 2)
	local cframe = CFrame.lookAt(center, center - flat.Unit)
	return MapKit.Wedge(b, Vector3.new(width, rise, run), cframe, color, material, parent)
end

-- Railing along a line: posts, two rails and an invisible barrier above so
-- players can't jump over it.
function MapKit.Railing(
	b: Builder,
	from: Vector3,
	to: Vector3,
	height: number?,
	color: Color3?,
	barrierHeight: number?,
	parent: Instance?
): Model
	local railHeight = height or 3.5
	local model = Instance.new("Model")
	model.Name = "Railing"
	model.Parent = parent or b.Geometry
	local flatTo = Vector3.new(to.X, from.Y, to.Z)
	local length = (flatTo - from).Magnitude
	if length < 0.1 then
		return model
	end
	local direction = (flatTo - from).Unit
	local posts = math.max(1, math.floor(length / 6))
	local metal = color or MapKit.Palette.Gunmetal
	for index = 0, posts do
		local point = from + direction * (length * index / posts)
		MapKit.Part(b, {
			Name = "Post",
			Size = Vector3.new(0.4, railHeight, 0.4),
			CFrame = CFrame.new(point + Vector3.new(0, railHeight / 2, 0)),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	for _, y in { railHeight, railHeight * 0.5 } do
		local middle = (from + flatTo) / 2 + Vector3.new(0, y, 0)
		MapKit.Part(b, {
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = CFrame.lookAt(middle, middle + direction),
			Color = metal,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	local barrier = MapKit.Barrier(b, from, to, barrierHeight or 14)
	if barrier then
		barrier.Parent = model
	end
	return model
end

-- A light source part (optionally invisible) with a PointLight.
function MapKit.Light(part: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 2
	light.Shadows = false
	light.Parent = part
	return light
end

function MapKit.SpotLight(part: BasePart, color: Color3, range: number, angle: number, face: Enum.NormalId): SpotLight
	local light = Instance.new("SpotLight")
	light.Color = color
	light.Range = range
	light.Angle = angle
	light.Face = face
	light.Brightness = 3
	light.Shadows = false
	light.Parent = part
	return light
end

-- Markers -------------------------------------------------------------------------------

-- The marker folder at `path` ("EnemySpawns/Zone1"), created as needed.
function MapKit.MarkerFolder(b: Builder, path: string?): Folder
	local current = b.Markers
	if path == nil or path == "" then
		return current
	end
	for _, name in string.split(path, "/") do
		local existing = current:FindFirstChild(name)
		if existing and existing:IsA("Folder") then
			current = existing
		else
			current = newFolder(name, current)
		end
	end
	return current
end

-- Invisible, non-colliding marker read by game code. `name` may include a
-- folder path: MapKit.Marker(b, "Checkpoints/CP_Zone2", cframe).
function MapKit.Marker(b: Builder, name: string, cframe: CFrame, size: Vector3?): Part
	local parts = string.split(name, "/")
	local leaf = table.remove(parts) :: string
	local folder = MapKit.MarkerFolder(b, table.concat(parts, "/"))
	return MapKit.Part(b, {
		Name = leaf,
		Size = size or Vector3.new(4, 1, 4),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = folder,
	})
end

-- A box zone marker: players inside the box (radius sideways, `height` up
-- from `position`) are "inside".
function MapKit.Zone(b: Builder, name: string, position: Vector3, radius: number, height: number?): Part
	local zoneHeight = height or 16
	return MapKit.Marker(
		b,
		name,
		CFrame.new(position + Vector3.new(0, zoneHeight / 2, 0)),
		Vector3.new(radius * 2, zoneHeight, radius * 2)
	)
end

-- A ring of glowing floor tiles showing a zone's edge.
function MapKit.ZoneRing(b: Builder, position: Vector3, radius: number, color: Color3, parent: Instance?)
	local segments = 16
	local group = parent
	if group == nil then
		local model = Instance.new("Model")
		model.Name = "ZoneRing"
		model.Parent = b.Geometry
		group = model
	end
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local point = position + Vector3.new(math.cos(angle) * radius, 0.05, math.sin(angle) * radius)
		MapKit.Neon(
			b,
			Vector3.new(0.5, 0.1, radius * 0.35),
			CFrame.lookAt(point, position + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.rad(90), 0),
			color,
			group
		)
	end
end

-- Spawn markers named Spawn_<group>_<n> (Phase 2 layout; newer maps use
-- MapKit.EnemySpawns).
function MapKit.SpawnGroup(b: Builder, group: string, positions: { Vector3 }, lookAt: Vector3?)
	for index, position in positions do
		local cframe = if lookAt
			then CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
			else CFrame.new(position)
		MapKit.Marker(b, `Spawn_{group}_{index}`, cframe)
	end
end

-- Enemy spawn markers in Markers/EnemySpawns/<folder>, named <folder>_<n>,
-- each facing `lookAt`.
function MapKit.EnemySpawns(b: Builder, folder: string, positions: { Vector3 }, lookAt: Vector3?)
	for index, position in positions do
		local cframe = if lookAt
			then CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
			else CFrame.new(position)
		MapKit.Marker(b, `EnemySpawns/{folder}/{folder}_{index}`, cframe)
	end
end

-- Doors and gates ------------------------------------------------------------------------

-- A Phase 2 door that an objective opens (named Door_<name> in Doors).
function MapKit.Door(b: Builder, name: string, size: Vector3, cframe: CFrame, color: Color3?): Part
	local door = MapKit.Part(b, {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color or MapKit.Palette.Red,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		Parent = b.Doors,
	})
	return door
end

export type GateStyle = "Door" | "Shield" | "Bridge"

-- A zone gate named Gate_<zone>. MissionService opens it when the zone is
-- cleared: a Door slides up into the ceiling, a Shield fades away, and a
-- Bridge (built retracted and non-solid) extends and becomes solid.
function MapKit.Gate(b: Builder, zone: string, style: GateStyle, size: Vector3, cframe: CFrame, color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = `Gate_{zone}`
	model:SetAttribute("GateStyle", style)
	model.Parent = b.Gates
	local accent = color or MapKit.Palette.Orange
	if style == "Door" then
		local slab = MapKit.Part(b, {
			Name = "Slab",
			Size = size,
			CFrame = cframe,
			Color = MapKit.Palette.DarkMetal,
			Material = Enum.Material.DiamondPlate,
			Parent = model,
		})
		MapKit.Neon(b, Vector3.new(size.X * 0.9, 0.4, size.Z + 0.1), cframe, accent, model)
		model.PrimaryPart = slab
	elseif style == "Shield" then
		local wall = MapKit.Part(b, {
			Name = "Field",
			Size = size,
			CFrame = cframe,
			Color = accent,
			Material = Enum.Material.ForceField,
			Transparency = 0.1,
			CanQuery = false,
			Parent = model,
		})
		model.PrimaryPart = wall
	else
		local deck = MapKit.Part(b, {
			Name = "Deck",
			Size = size,
			CFrame = cframe,
			Color = MapKit.Palette.Gunmetal,
			Material = Enum.Material.Metal,
			Transparency = 0.85,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
		MapKit.Neon(
			b,
			Vector3.new(0.3, 0.2, size.Z),
			cframe * CFrame.new(size.X / 2 - 0.2, size.Y / 2, 0),
			accent,
			model
		)
		MapKit.Neon(
			b,
			Vector3.new(0.3, 0.2, size.Z),
			cframe * CFrame.new(-size.X / 2 + 0.2, size.Y / 2, 0),
			accent,
			model
		)
		model.PrimaryPart = deck
	end
	return model
end

-- Moving parts ---------------------------------------------------------------------------

-- Marks a part as moving between its position and position + offset
-- (elevators, raid platforms). Clients animate it by server time, so riders
-- are carried smoothly: it travels for (period/2 - dwell) and waits `dwell`
-- seconds at each end. `phase` (0..1) offsets it in the cycle.
function MapKit.Mover(part: BasePart, offset: Vector3, period: number, dwell: number?, phase: number?)
	part:SetAttribute("MoveOffset", offset)
	part:SetAttribute("MovePeriod", period)
	part:SetAttribute("MoveDwell", dwell or 0)
	part:SetAttribute("MovePhase", phase or 0)
	part:AddTag("LL_Mover")
end

-- Terrain recipes ------------------------------------------------------------------------

local function recipe(b: Builder, shape: string, size: Vector3, cframe: CFrame, material: Enum.Material): Part
	local part = MapKit.Part(b, {
		Name = `T_{material.Name}`,
		Size = size,
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = b.Terrain,
	})
	part.CanTouch = false
	part:SetAttribute("TerrainShape", shape)
	part:SetAttribute("TerrainMaterial", material.Name)
	-- Recipes run in the order they were written (caves: fill rock, carve
	-- Air, refill floors), whatever order a cloned folder lists them in.
	part:SetAttribute("TerrainOrder", #b.Terrain:GetChildren())
	return part
end

function MapKit.TerrainBlock(b: Builder, cframe: CFrame, size: Vector3, material: Enum.Material): Part
	return recipe(b, "Block", size, cframe, material)
end

function MapKit.TerrainBall(b: Builder, center: Vector3, radius: number, material: Enum.Material): Part
	return recipe(b, "Ball", Vector3.new(radius * 2, radius * 2, radius * 2), CFrame.new(center), material)
end

-- Upright cylinder: its axis is the CFrame's Y axis.
function MapKit.TerrainCylinder(
	b: Builder,
	cframe: CFrame,
	height: number,
	radius: number,
	material: Enum.Material
): Part
	return recipe(b, "Cylinder", Vector3.new(radius * 2, height, radius * 2), cframe, material)
end

-- A wedge sloping like a WedgePart with the same CFrame and size.
function MapKit.TerrainWedge(b: Builder, cframe: CFrame, size: Vector3, material: Enum.Material): Part
	return recipe(b, "Wedge", size, cframe, material)
end

local TILE = 512

-- Splits big axis-aligned blocks so each Fill call stays small.
local function fillBlock(terrain: Terrain, cframe: CFrame, size: Vector3, material: Enum.Material)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local axisAligned = math.abs(r00 - 1) < 1e-3
		and math.abs(r11 - 1) < 1e-3
		and math.abs(r22 - 1) < 1e-3
		and math.abs(r01) + math.abs(r02) + math.abs(r10) + math.abs(r12) + math.abs(r20) + math.abs(r21) < 1e-3
	if not axisAligned or (size.X <= TILE and size.Z <= TILE) then
		terrain:FillBlock(cframe, size, material)
		return
	end
	local countX = math.ceil(size.X / TILE)
	local countZ = math.ceil(size.Z / TILE)
	local tileX, tileZ = size.X / countX, size.Z / countZ
	local corner = cframe.Position - Vector3.new(size.X / 2, 0, size.Z / 2)
	for ix = 0, countX - 1 do
		for iz = 0, countZ - 1 do
			local center = corner + Vector3.new((ix + 0.5) * tileX, 0, (iz + 0.5) * tileZ)
			terrain:FillBlock(CFrame.new(center), Vector3.new(tileX, size.Y, tileZ), material)
		end
	end
end

local function applyRecipes(model: Instance, override: Enum.Material?)
	local folder = model:FindFirstChild("Terrain")
	if folder == nil then
		return
	end
	local terrain = (game:GetService("Workspace") :: Workspace).Terrain
	local recipes = folder:GetChildren()
	table.sort(recipes, function(a: Instance, b: Instance): boolean
		return (tonumber(a:GetAttribute("TerrainOrder")) or 0) < (tonumber(b:GetAttribute("TerrainOrder")) or 0)
	end)
	local count = 0
	for _, part in recipes do
		if part:IsA("BasePart") then
			local shape = part:GetAttribute("TerrainShape")
			local materialName = part:GetAttribute("TerrainMaterial")
			local ok, material = pcall(function()
				return (Enum.Material :: any)[materialName]
			end)
			local fill: Enum.Material = override or (if ok and material then material else Enum.Material.Rock)
			local done, err = pcall(function()
				if shape == "Ball" then
					terrain:FillBall(part.Position, part.Size.X / 2, fill)
				elseif shape == "Cylinder" then
					terrain:FillCylinder(part.CFrame, part.Size.Y, part.Size.X / 2, fill)
				elseif shape == "Wedge" then
					terrain:FillWedge(part.CFrame, part.Size, fill)
				else
					fillBlock(terrain, part.CFrame, part.Size, fill)
				end
			end)
			if not done then
				warn(`[MapKit] terrain {part.Name} failed: {err}`)
			end
			count += 1
			if count % 25 == 0 then
				task.wait() -- big maps: don't hold the server for too long
			end
		end
	end
end

-- After a map copy is moved by `offset` (activity instances), moves the
-- world-space centers its client-animated props spin and fly around.
function MapKit.ShiftMotion(model: Instance, offset: Vector3)
	for _, descendant in model:GetDescendants() do
		for _, attribute in { "SpinCenter", "FlightCenter" } do
			local value = descendant:GetAttribute(attribute)
			if typeof(value) == "Vector3" then
				descendant:SetAttribute(attribute, value + offset)
			end
		end
	end
end

-- Turns a map's terrain recipes into real Terrain where the model is now.
-- Yields between batches.
function MapKit.ApplyTerrain(model: Instance)
	applyRecipes(model, nil)
end

-- Removes the terrain a map's recipes created (fills them with Air).
function MapKit.ClearTerrain(model: Instance)
	applyRecipes(model, Enum.Material.Air)
end

-- Labels ---------------------------------------------------------------------------------

-- Floating name tag (vendors, signs).
function MapKit.Billboard(
	parent: BasePart,
	title: string,
	subtitle: string?,
	color: Color3?,
	offset: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(240, 60)
	gui.StudsOffset = Vector3.new(0, offset or 3, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = parent

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.55)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color or Color3.new(1, 1, 1)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = title
	titleLabel.Parent = gui

	if subtitle then
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Position = UDim2.fromScale(0, 0.58)
		subtitleLabel.Size = UDim2.fromScale(1, 0.35)
		subtitleLabel.Font = Enum.Font.Gotham
		subtitleLabel.TextScaled = true
		subtitleLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
		subtitleLabel.TextStrokeTransparency = 0.6
		subtitleLabel.Text = subtitle
		subtitleLabel.Parent = gui
	end
	return gui
end

-- Text painted on a part's face.
function MapKit.Sign(part: BasePart, text: string, face: Enum.NormalId, color: Color3?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
	return gui
end

-- Cover object (Phase 2 maps; newer maps use Props.Crate).
function MapKit.Crate(b: Builder, position: Vector3, size: Vector3?, color: Color3?): Part
	local crateSize = size or Vector3.new(5, 4, 5)
	return MapKit.Block(
		b,
		crateSize,
		CFrame.new(position + Vector3.new(0, crateSize.Y / 2, 0)),
		color or MapKit.Palette.MetalLight,
		Enum.Material.DiamondPlate
	)
end

-- A named sub-model under Geometry for grouping props.
function MapKit.Group(b: Builder, name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent or b.Geometry
	return model
end

function MapKit.Finish(b: Builder): Model
	return b.Model
end

-- Counts the BaseParts in a map (the performance budget is ~15k).
function MapKit.CountParts(model: Instance): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return MapKit
