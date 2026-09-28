--!strict
--[[
	Props
	Reusable decoration built from parts: crates, containers, pipes, cables,
	antennas, banners, lamps, trees, benches, market stalls, NPC figures,
	ships, cranes, chests, city buildings and rings. Every prop is grouped
	into its own Model so repeated decoration stays tidy (and can be swapped
	for real art later by replacing the Model).

	Style: white/grey concrete, dark metal, orange and teal accent lights,
	neon strips. Randomness always comes from the builder's seeded Random,
	so maps are identical every time they're built.
]]

local MapKit = require(script.Parent.MapKit)

type Builder = MapKit.Builder

local Props = {}

local P = MapKit.Palette

local function group(b: Builder, name: string, parent: Instance?): Model
	return MapKit.Group(b, name, parent)
end

-- Crates, containers, barrels ---------------------------------------------------------

function Props.Crate(b: Builder, position: Vector3, size: Vector3?, color: Color3?, parent: Instance?): Model
	local crateSize = size or Vector3.new(4, 4, 4)
	local model = group(b, "Crate", parent)
	local body = MapKit.Block(
		b,
		crateSize,
		CFrame.new(position + Vector3.new(0, crateSize.Y / 2, 0)),
		color or P.Gunmetal,
		Enum.Material.DiamondPlate,
		model
	)
	-- Edge bands.
	MapKit.Part(b, {
		Name = "Band",
		Size = Vector3.new(crateSize.X + 0.1, 0.3, crateSize.Z + 0.1),
		CFrame = body.CFrame * CFrame.new(0, crateSize.Y / 2 - 0.4, 0),
		Color = P.Orange,
		Material = Enum.Material.Metal,
		CastShadow = false,
		Parent = model,
	})
	return model
end

-- A small random stack of crates around `position`.
function Props.CrateStack(b: Builder, position: Vector3, parent: Instance?): Model
	local model = group(b, "CrateStack", parent)
	local rng = b.Rng
	local count = rng:NextInteger(2, 4)
	for index = 1, count do
		local size = rng:NextInteger(3, 5)
		local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		local y = if index == count and count > 2 then 4 else 0
		Props.Crate(
			b,
			position + offset + Vector3.new(0, y, 0),
			Vector3.new(size, size, size),
			if rng:NextNumber() < 0.5 then P.Gunmetal else P.ConcreteDark,
			model
		)
	end
	return model
end

-- A ribbed cargo container (20 x 8.5 x 8) standing on `cframe` (base center).
function Props.Container(b: Builder, cframe: CFrame, color: Color3, parent: Instance?): Model
	local model = group(b, "Container", parent)
	local size = Vector3.new(8, 8.5, 20)
	local body = MapKit.Block(b, size, cframe * CFrame.new(0, size.Y / 2, 0), color, Enum.Material.CorrodedMetal, model)
	for index = -3, 3 do
		MapKit.Part(b, {
			Name = "Rib",
			Size = Vector3.new(size.X + 0.3, size.Y - 0.6, 0.4),
			CFrame = body.CFrame * CFrame.new(0, 0, index * 2.8),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	return model
end

function Props.Barrel(b: Builder, position: Vector3, color: Color3?, parent: Instance?): Part
	return MapKit.Cylinder(
		b,
		3.2,
		2.2,
		position + Vector3.new(0, 1.6, 0),
		color or P.Orange,
		Enum.Material.Metal,
		parent
	)
end

-- Pipes, cables, antennas ----------------------------------------------------------

-- A pipe run through `points` with joint collars.
function Props.Pipe(b: Builder, points: { Vector3 }, diameter: number, color: Color3?, parent: Instance?): Model
	local model = group(b, "Pipe", parent)
	for index = 1, #points - 1 do
		MapKit.Rod(b, points[index], points[index + 1], diameter, color or P.ConcreteDark, Enum.Material.Metal, model)
	end
	for _, point in points do
		MapKit.Ball(b, diameter * 1.25, point, P.DarkMetal, Enum.Material.Metal, model)
	end
	return model
end

-- A sagging cable between two points.
function Props.Cable(b: Builder, from: Vector3, to: Vector3, sag: number, parent: Instance?): Model
	local model = group(b, "Cable", parent)
	local segments = 6
	local last = from
	for index = 1, segments do
		local t = index / segments
		local point = from:Lerp(to, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		local rod = MapKit.Rod(b, last, point, 0.25, P.Black, Enum.Material.Plastic, model)
		if rod then
			rod.CanCollide = false
			rod.CanQuery = false
		end
		last = point
	end
	return model
end

function Props.Antenna(b: Builder, base: Vector3, height: number, parent: Instance?): Model
	local model = group(b, "Antenna", parent)
	MapKit.Rod(b, base, base + Vector3.new(0, height, 0), 0.6, P.Gunmetal, Enum.Material.Metal, model)
	for index = 1, 3 do
		local y = height * (0.45 + index * 0.15)
		local span = 4 - index
		MapKit.Rod(
			b,
			base + Vector3.new(-span, y, 0),
			base + Vector3.new(span, y, 0),
			0.25,
			P.Gunmetal,
			Enum.Material.Metal,
			model
		)
	end
	local tip =
		MapKit.Neon(b, Vector3.new(0.8, 0.8, 0.8), CFrame.new(base + Vector3.new(0, height + 0.4, 0)), P.Red, model)
	MapKit.Light(tip, P.Red, 10, 1)
	return model
end

-- Banners, lamps, signs ------------------------------------------------------------

-- A tall banner on a pole: cloth in `color` with a glowing emblem stripe.
function Props.Banner(
	b: Builder,
	base: Vector3,
	height: number,
	facing: Vector3,
	color: Color3,
	emblem: Color3,
	parent: Instance?
): Model
	local model = group(b, "Banner", parent)
	local look = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	MapKit.Rod(b, base, base + Vector3.new(0, height, 0), 0.5, P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Rod(
		b,
		(look * CFrame.new(-2.2, height - 0.5, -0.4)).Position,
		(look * CFrame.new(2.2, height - 0.5, -0.4)).Position,
		0.3,
		P.DarkMetal,
		Enum.Material.Metal,
		model
	)
	local clothHeight = height * 0.55
	local cloth = MapKit.Part(b, {
		Name = "Cloth",
		Size = Vector3.new(4, clothHeight, 0.2),
		CFrame = look * CFrame.new(0, height - 0.6 - clothHeight / 2, -0.5),
		Color = color,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = model,
	})
	MapKit.Neon(b, Vector3.new(1.2, clothHeight * 0.6, 0.05), cloth.CFrame * CFrame.new(0, 0.3, -0.13), emblem, model)
	MapKit.Wedge(
		b,
		Vector3.new(0.2, 1.4, 4),
		cloth.CFrame * CFrame.new(0, -clothHeight / 2 - 0.7, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)),
		color,
		Enum.Material.Fabric,
		model
	)
	return model
end

-- A street lamp with a warm light.
function Props.Lamp(b: Builder, base: Vector3, height: number?, color: Color3?, parent: Instance?): Model
	local model = group(b, "Lamp", parent)
	local lampHeight = height or 12
	MapKit.Rod(b, base, base + Vector3.new(0, lampHeight, 0), 0.5, P.DarkMetal, Enum.Material.Metal, model)
	MapKit.Block(
		b,
		Vector3.new(2.4, 0.5, 2.4),
		CFrame.new(base + Vector3.new(0, lampHeight + 0.2, 0)),
		P.DarkMetal,
		Enum.Material.Metal,
		model
	)
	local bulb = MapKit.Neon(
		b,
		Vector3.new(1.8, 0.3, 1.8),
		CFrame.new(base + Vector3.new(0, lampHeight - 0.15, 0)),
		color or Color3.fromRGB(255, 225, 180),
		model
	)
	MapKit.Light(bulb, color or Color3.fromRGB(255, 225, 180), 22, 1.4)
	return model
end

-- Glowing floor/wall strip.
function Props.Strip(b: Builder, from: Vector3, to: Vector3, color: Color3, parent: Instance?): Part?
	local offset = to - from
	if offset.Magnitude < 0.1 then
		return nil
	end
	return MapKit.Neon(b, Vector3.new(0.35, 0.2, offset.Magnitude), CFrame.lookAt((from + to) / 2, to), color, parent)
end

-- Plants -------------------------------------------------------------------------------

function Props.Tree(b: Builder, base: Vector3, height: number, parent: Instance?): Model
	local model = group(b, "Tree", parent)
	local rng = b.Rng
	MapKit.Rod(b, base, base + Vector3.new(0, height, 0), height * 0.08, P.Bark, Enum.Material.Wood, model)
	local canopy = height * 0.45
	for index = 1, 4 do
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.6), rng:NextNumber(-1, 1))
			* canopy
			* 0.5
		local ball = MapKit.Ball(
			b,
			canopy * rng:NextNumber(0.75, 1.1),
			base + Vector3.new(0, height, 0) + offset,
			if index % 2 == 0 then P.Leaf else P.LeafDark,
			Enum.Material.Grass,
			model
		)
		ball.CanCollide = false
	end
	return model
end

-- A concrete planter box with soil and a tree or bushes.
function Props.Planter(b: Builder, center: Vector3, size: Vector3, tree: boolean, parent: Instance?): Model
	local model = group(b, "Planter", parent)
	MapKit.Block(b, size, CFrame.new(center + Vector3.new(0, size.Y / 2, 0)), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(
		b,
		Vector3.new(size.X - 1, 0.4, size.Z - 1),
		CFrame.new(center + Vector3.new(0, size.Y + 0.1, 0)),
		Color3.fromRGB(70, 52, 40),
		Enum.Material.Ground,
		model
	)
	MapKit.Neon(
		b,
		Vector3.new(size.X + 0.1, 0.2, size.Z + 0.1),
		CFrame.new(center + Vector3.new(0, 0.5, 0)),
		P.Teal,
		model
	)
	if tree then
		Props.Tree(b, center + Vector3.new(0, size.Y, 0), 12 + b.Rng:NextNumber(0, 5), model)
	else
		for _ = 1, 3 do
			local offset =
				Vector3.new(b.Rng:NextNumber(-1, 1) * size.X * 0.3, 0, b.Rng:NextNumber(-1, 1) * size.Z * 0.3)
			local bush =
				MapKit.Ball(b, 3.2, center + Vector3.new(0, size.Y + 1, 0) + offset, P.Leaf, Enum.Material.Grass, model)
			bush.CanCollide = false
		end
	end
	return model
end

-- Furniture -----------------------------------------------------------------------------

function Props.Bench(b: Builder, cframe: CFrame, parent: Instance?): Model
	local model = group(b, "Bench", parent)
	MapKit.Block(b, Vector3.new(7, 0.5, 2), cframe * CFrame.new(0, 1.8, 0), P.Concrete, Enum.Material.Concrete, model)
	MapKit.Block(b, Vector3.new(7, 2, 0.4), cframe * CFrame.new(0, 3, 0.8), P.Concrete, Enum.Material.Concrete, model)
	for _, x in { -2.8, 2.8 } do
		MapKit.Block(
			b,
			Vector3.new(0.6, 1.8, 1.8),
			cframe * CFrame.new(x, 0.9, 0),
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
	end
	return model
end

function Props.Table(b: Builder, position: Vector3, parent: Instance?): Model
	local model = group(b, "Table", parent)
	MapKit.Cylinder(b, 0.3, 4, position + Vector3.new(0, 3, 0), P.White, Enum.Material.SmoothPlastic, model)
	MapKit.Cylinder(b, 3, 0.5, position + Vector3.new(0, 1.5, 0), P.DarkMetal, Enum.Material.Metal, model)
	for index = 0, 2 do
		local angle = index * math.pi * 2 / 3
		local seat = position + Vector3.new(math.cos(angle) * 3.4, 0, math.sin(angle) * 3.4)
		MapKit.Cylinder(b, 0.3, 1.8, seat + Vector3.new(0, 1.9, 0), P.Orange, Enum.Material.SmoothPlastic, model)
		MapKit.Cylinder(b, 1.9, 0.3, seat + Vector3.new(0, 0.95, 0), P.DarkMetal, Enum.Material.Metal, model)
	end
	return model
end

-- A parasol for café tables.
function Props.Parasol(b: Builder, position: Vector3, color: Color3, parent: Instance?): Model
	local model = group(b, "Parasol", parent)
	MapKit.Rod(b, position, position + Vector3.new(0, 8, 0), 0.25, P.DarkMetal, Enum.Material.Metal, model)
	for index = 0, 3 do
		local angle = index * math.pi / 2
		local cframe = CFrame.new(position + Vector3.new(0, 7.8, 0))
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, -0.6, -2.2)
		local wedge = MapKit.Wedge(b, Vector3.new(4.4, 1.2, 4.4), cframe, color, Enum.Material.Fabric, model)
		wedge.CanCollide = false
	end
	return model
end

-- Market stall: counter, posts and a sloped fabric awning. `cframe` is the
-- front-center of the counter at floor level, facing the customer.
function Props.Stall(b: Builder, cframe: CFrame, width: number, awning: Color3, parent: Instance?): Model
	local model = group(b, "Stall", parent)
	MapKit.Block(
		b,
		Vector3.new(width, 3.4, 2.5),
		cframe * CFrame.new(0, 1.7, 0),
		P.Concrete,
		Enum.Material.Concrete,
		model
	)
	MapKit.Neon(b, Vector3.new(width, 0.2, 0.1), cframe * CFrame.new(0, 3.2, -1.3), P.Orange, model)
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		MapKit.Block(
			b,
			Vector3.new(0.5, 10, 0.5),
			cframe * CFrame.new(x, 5, 3.5),
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
		MapKit.Block(
			b,
			Vector3.new(0.5, 8, 0.5),
			cframe * CFrame.new(x, 4, -1.2),
			P.DarkMetal,
			Enum.Material.Metal,
			model
		)
	end
	local cloth = MapKit.Wedge(
		b,
		Vector3.new(width + 1, 2, 6),
		cframe * CFrame.new(0, 9, 1.2) * CFrame.Angles(0, math.rad(180), 0),
		awning,
		Enum.Material.Fabric,
		model
	)
	cloth.CanCollide = true -- the rooftop jump path uses awnings
	-- Goods on the counter.
	for index = 1, math.floor(width / 3) do
		local x = -width / 2 + index * 3 - 1
		MapKit.Block(
			b,
			Vector3.new(1.4, 1, 1.4),
			cframe * CFrame.new(x, 3.9, 0.2),
			if index % 2 == 0 then P.Teal else P.Orange,
			Enum.Material.SmoothPlastic,
			model
		)
	end
	return model
end

-- Terminals, chests ----------------------------------------------------------------

-- A standing console with a glowing screen. `cframe` = base, facing the user.
function Props.Console(b: Builder, cframe: CFrame, color: Color3, parent: Instance?): Model
	local model = group(b, "Console", parent)
	local body =
		MapKit.Block(b, Vector3.new(4, 4, 2), cframe * CFrame.new(0, 2, 0), P.DarkMetal, Enum.Material.Metal, model)
	local screen = MapKit.Part(b, {
		Name = "Screen",
		Size = Vector3.new(3.6, 2.4, 0.3),
		CFrame = cframe * CFrame.new(0, 5, 0.4) * CFrame.Angles(math.rad(-20), 0, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	MapKit.Light(screen, color, 10, 1)
	model.PrimaryPart = body
	return model
end

-- A reward chest with an "Open" prompt. The server reads ChestId from the prompt.
function Props.Chest(b: Builder, cframe: CFrame, chestId: string, parent: Instance?): Model
	local model = group(b, "Chest_" .. chestId, parent)
	local base =
		MapKit.Block(b, Vector3.new(4, 2.2, 2.6), cframe * CFrame.new(0, 1.1, 0), P.Gold, Enum.Material.Metal, model)
	MapKit.Block(b, Vector3.new(4.1, 1, 2.7), cframe * CFrame.new(0, 2.6, 0), P.DarkMetal, Enum.Material.Metal, model)
	local glow = MapKit.Neon(b, Vector3.new(4.15, 0.25, 2.75), cframe * CFrame.new(0, 2.15, 0), P.Teal, model)
	MapKit.Light(glow, P.Teal, 12, 1.5)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenChest"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Cache"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ChestId", chestId)
	prompt.Parent = base
	model.PrimaryPart = base
	return model
end

-- People ---------------------------------------------------------------------------------

-- A simple block figure (vendor NPC) standing at `cframe` (feet), facing its
-- LookVector, with a name tag. Returns the model and its torso.
function Props.Npc(
	b: Builder,
	cframe: CFrame,
	name: string,
	title: string?,
	body: Color3,
	accent: Color3,
	parent: Instance?
): (Model, Part)
	local model = group(b, "Npc_" .. string.gsub(name, "%s", ""), parent)
	for _, x in { -0.55, 0.55 } do
		MapKit.Block(
			b,
			Vector3.new(0.9, 3, 1),
			cframe * CFrame.new(x, 1.5, 0),
			P.DarkMetal,
			Enum.Material.Fabric,
			model
		)
	end
	local torso =
		MapKit.Block(b, Vector3.new(2.2, 2.8, 1.2), cframe * CFrame.new(0, 4.4, 0), body, Enum.Material.Fabric, model)
	torso.Name = "Torso"
	MapKit.Neon(b, Vector3.new(0.3, 2.4, 0.05), cframe * CFrame.new(0.5, 4.4, -0.62), accent, model)
	for _, x in { -1.45, 1.45 } do
		MapKit.Block(b, Vector3.new(0.7, 2.7, 0.8), cframe * CFrame.new(x, 4.35, 0), body, Enum.Material.Fabric, model)
	end
	local head = MapKit.Block(
		b,
		Vector3.new(1.3, 1.4, 1.3),
		cframe * CFrame.new(0, 6.5, 0),
		Color3.fromRGB(205, 170, 140),
		Enum.Material.SmoothPlastic,
		model
	)
	head.Name = "Head"
	MapKit.Block(b, Vector3.new(1.45, 0.5, 1.45), cframe * CFrame.new(0, 7.3, 0.05), accent, Enum.Material.Metal, model)
	MapKit.Billboard(head, name, title, accent, 2.6)
	model.PrimaryPart = torso
	return model, torso
end

-- Vehicles and machinery -----------------------------------------------------------------

-- A small jumpship. `cframe` = center, nose along LookVector. `scale` 1 ≈ 22 studs long.
function Props.Ship(b: Builder, cframe: CFrame, scale: number, hull: Color3, accent: Color3, parent: Instance?): Model
	local model = group(b, "Ship", parent)
	local s = scale
	local body = MapKit.Block(b, Vector3.new(5, 3.2, 12) * s, cframe, hull, Enum.Material.Metal, model)
	MapKit.Wedge(
		b,
		Vector3.new(5, 3.2, 7) * s,
		cframe * CFrame.new(0, 0, -9.5 * s) * CFrame.Angles(0, math.rad(180), 0),
		hull,
		Enum.Material.Metal,
		model
	)
	MapKit.Part(b, {
		Name = "Canopy",
		Size = Vector3.new(3, 1.4, 5) * s,
		CFrame = cframe * CFrame.new(0, 2, -3 * s),
		Color = P.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		MapKit.Wedge(
			b,
			Vector3.new(0.6, 5, 10) * s,
			cframe * CFrame.new(side * 5 * s, -0.5 * s, 2 * s) * CFrame.Angles(0, 0, math.rad(side * 90)),
			hull:Lerp(Color3.new(0, 0, 0), 0.2),
			Enum.Material.Metal,
			model
		)
		MapKit.Cylinder(
			b,
			4 * s,
			2 * s,
			(cframe * CFrame.new(side * 3.2 * s, 0, 6.5 * s)).Position,
			P.DarkMetal,
			Enum.Material.Metal,
			model
		).CFrame = cframe
			* CFrame.new(side * 3.2 * s, 0, 6.5 * s)
			* CFrame.Angles(0, math.rad(90), 0)
		local glow = MapKit.Neon(
			b,
			Vector3.new(1.6, 1.6, 0.3) * s,
			cframe * CFrame.new(side * 3.2 * s, 0, 8.6 * s),
			accent,
			model
		)
		glow.Shape = Enum.PartType.Ball
	end
	MapKit.Neon(b, Vector3.new(0.3, 0.3, 11) * s, cframe * CFrame.new(0, 1.65 * s, 0), accent, model)
	model.PrimaryPart = body
	return model
end

-- A gantry crane: two legs and a beam with a hanging hook.
function Props.Crane(b: Builder, base: Vector3, height: number, span: number, parent: Instance?): Model
	local model = group(b, "Crane", parent)
	for _, x in { -span / 2, span / 2 } do
		MapKit.Block(
			b,
			Vector3.new(2, height, 2),
			CFrame.new(base + Vector3.new(x, height / 2, 0)),
			P.Orange,
			Enum.Material.Metal,
			model
		)
	end
	MapKit.Block(
		b,
		Vector3.new(span + 2, 2.5, 3),
		CFrame.new(base + Vector3.new(0, height + 1.25, 0)),
		P.Orange,
		Enum.Material.Metal,
		model
	)
	MapKit.Block(
		b,
		Vector3.new(3, 2, 3.6),
		CFrame.new(base + Vector3.new(span * 0.15, height - 0.9, 0)),
		P.DarkMetal,
		Enum.Material.Metal,
		model
	)
	local cable = MapKit.Rod(
		b,
		base + Vector3.new(span * 0.15, height - 2, 0),
		base + Vector3.new(span * 0.15, height * 0.45, 0),
		0.25,
		P.Black,
		Enum.Material.Metal,
		model
	)
	if cable then
		cable.CanCollide = false
	end
	MapKit.Block(
		b,
		Vector3.new(1.5, 1.2, 1.5),
		CFrame.new(base + Vector3.new(span * 0.15, height * 0.45 - 0.6, 0)),
		P.DarkMetal,
		Enum.Material.Metal,
		model
	)
	return model
end

-- Rocks, debris, buildings ---------------------------------------------------------------

function Props.Rock(b: Builder, position: Vector3, size: number, color: Color3?, parent: Instance?): Part
	local rng = b.Rng
	return MapKit.Part(b, {
		Name = "Rock",
		Size = Vector3.new(
			size * rng:NextNumber(0.8, 1.3),
			size * rng:NextNumber(0.5, 0.9),
			size * rng:NextNumber(0.8, 1.3)
		),
		CFrame = CFrame.new(position)
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
		Color = color or P.Stone,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

-- Scattered broken chunks on the ground in a circle.
function Props.Debris(
	b: Builder,
	center: Vector3,
	radius: number,
	count: number,
	color: Color3?,
	parent: Instance?
): Model
	local model = group(b, "Debris", parent)
	local rng = b.Rng
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, radius)
		local size = rng:NextNumber(0.6, 2.4)
		local piece = MapKit.Part(b, {
			Name = "Debris",
			Size = Vector3.new(size, size * 0.5, size * rng:NextNumber(0.6, 1.4)),
			CFrame = CFrame.new(
				center + Vector3.new(math.cos(angle) * distance, size * 0.2, math.sin(angle) * distance)
			) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6)),
			Color = color or P.ConcreteGrey,
			Material = Enum.Material.Concrete,
			CanCollide = false,
			Parent = model,
		})
		piece.CanQuery = false
	end
	return model
end

-- A low-poly city building. `ruined` tilts it and knocks the top off.
function Props.Building(
	b: Builder,
	base: Vector3,
	size: Vector3,
	color: Color3,
	ruined: boolean,
	parent: Instance?
): Model
	local model = group(b, "Building", parent)
	local rng = b.Rng
	local tilt = if ruined
		then CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
		else CFrame.new()
	local height = if ruined then size.Y * rng:NextNumber(0.5, 0.85) else size.Y
	local cframe = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 0.3), 0) * tilt
	local body = MapKit.Part(b, {
		Name = "Body",
		Size = Vector3.new(size.X, height, size.Z),
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Concrete,
		CastShadow = false,
		Parent = model,
	})
	body.CanQuery = false
	-- Window bands on two faces.
	local bands = math.floor(height / 12)
	for index = 1, bands do
		local y = -height / 2 + index * 12 - 4
		for _, face in { -1, 1 } do
			local strip = MapKit.Part(b, {
				Name = "Windows",
				Size = Vector3.new(size.X * 0.85, 2.5, 0.2),
				CFrame = cframe * CFrame.new(0, y, face * (size.Z / 2 + 0.05)),
				Color = if ruined then P.Black else Color3.fromRGB(60, 80, 100),
				Material = Enum.Material.Glass,
				CastShadow = false,
				Parent = model,
			})
			strip.CanCollide = false
			strip.CanQuery = false
		end
	end
	if not ruined and rng:NextNumber() < 0.3 then
		Props.Antenna(b, base + Vector3.new(0, height, 0), 10, model)
	end
	return model
end

-- A ring of `segments` blocks (landing pads, orbit rings). `axis` orients it:
-- the ring lies in the axis frame's XZ plane.
function Props.Ring(
	b: Builder,
	axis: CFrame,
	radius: number,
	thickness: number,
	width: number,
	segments: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance?
): Model
	local model = group(b, "Ring", parent)
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.2
	for index = 1, segments do
		local angle = (index / segments) * math.pi * 2
		local point = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		-- Facing the center, the local X axis runs along the ring.
		local cframe = axis * CFrame.lookAt(point, Vector3.zero)
		local segment = MapKit.Part(b, {
			Name = "Segment",
			Size = Vector3.new(chord, thickness, width),
			CFrame = cframe,
			Color = color,
			Material = material,
			CastShadow = false,
			Parent = model,
		})
		segment.CanCollide = false
		segment.CanQuery = false
	end
	return model
end

return Props
