--!strict
--[[
	MapKit
	Small helpers for building maps out of parts in code.

	Every map is a Model with three folders:
	  Geometry  everything you can see and stand on
	  Markers   invisible, non-colliding parts the game reads by name:
	            PlayerStart, Checkpoint_*, Zone_* (size = zone), Spawn_<Group>_<n>,
	            BossSpawn, Dummy_<n>, HubSpawn...
	  Doors     parts named Door_* that objectives open
	The model's pivot is the origin, so ActivityService can place copies
	anywhere with PivotTo.
]]

local MapKit = {}

export type Builder = {
	Model: Model,
	Geometry: Folder,
	Markers: Folder,
	Doors: Folder,
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
}

function MapKit.New(name: string): Builder
	local model = Instance.new("Model")
	model.Name = name
	model.WorldPivot = CFrame.new()

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model

	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = model

	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = model

	return { Model = model, Geometry = geometry, Markers = markers, Doors = doors }
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
	part.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent or b.Geometry
	return part
end

-- Solid block.
function MapKit.Block(b: Builder, size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?): Part
	return MapKit.Part(b, { Size = size, CFrame = cframe, Color = color, Material = material })
end

-- Glowing strip that neither blocks movement nor bullets.
function MapKit.Neon(b: Builder, size: Vector3, cframe: CFrame, color: Color3): Part
	return MapKit.Part(b, {
		Name = "Neon",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
end

function MapKit.Wedge(b: Builder, size: Vector3, cframe: CFrame, color: Color3?, material: Enum.Material?): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color or MapKit.Palette.Metal
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = b.Geometry
	return wedge
end

-- Upright cylinder (axis along world Y) centered at `position`.
function MapKit.Cylinder(
	b: Builder,
	height: number,
	diameter: number,
	position: Vector3,
	color: Color3?,
	material: Enum.Material?
): Part
	return MapKit.Part(b, {
		Name = "Cylinder",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

function MapKit.Ball(b: Builder, diameter: number, position: Vector3, color: Color3?, material: Enum.Material?): Part
	return MapKit.Part(b, {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(position),
		Color = color,
		Material = material,
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
	material: Enum.Material?
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

-- Invisible, non-colliding marker read by game code.
function MapKit.Marker(b: Builder, name: string, cframe: CFrame, size: Vector3?): Part
	return MapKit.Part(b, {
		Name = name,
		Size = size or Vector3.new(4, 1, 4),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = b.Markers,
	})
end

-- A cylinder-ish zone: players within `radius` (and `height`) are "inside".
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
function MapKit.ZoneRing(b: Builder, position: Vector3, radius: number, color: Color3)
	local segments = 16
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local point = position + Vector3.new(math.cos(angle) * radius, 0.05, math.sin(angle) * radius)
		MapKit.Neon(
			b,
			Vector3.new(0.5, 0.1, radius * 0.35),
			CFrame.lookAt(point, position + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.rad(90), 0),
			color
		)
	end
end

-- Spawn markers named Spawn_<group>_<n> at the given positions.
function MapKit.SpawnGroup(b: Builder, group: string, positions: { Vector3 }, lookAt: Vector3?)
	for index, position in positions do
		local cframe = if lookAt
			then CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
			else CFrame.new(position)
		MapKit.Marker(b, `Spawn_{group}_{index}`, cframe)
	end
end

-- A door that an objective opens (named Door_<name> in the Doors folder).
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

-- Cover object.
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

function MapKit.Light(part: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 2
	light.Shadows = false
	light.Parent = part
	return light
end

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
	titleLabel.Size = UDim2.new(1, 0, 0.55, 0)
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
		subtitleLabel.Size = UDim2.new(1, 0, 0.35, 0)
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

function MapKit.Finish(b: Builder): Model
	return b.Model
end

return MapKit
