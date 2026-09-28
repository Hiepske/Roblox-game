--!strict
--[[
	EnemyRigs
	Builds enemy characters in code.

	Each enemy type is an R15 rig from Players:CreateHumanoidModelFromDescriptionAsync
	(Roblox's default body, recolored in the faction's team colors), dressed with
	armor plates, glowing eyes, a role prop (rifle or blades) and scaled by
	EnemyDef.Scale. If the engine can't build an R15 rig, a blocky R6 rig is
	assembled from parts instead.

	One template is built per enemy type (the first spawn of a type yields
	briefly) and cloned for every spawn after that.

	Machines are built from parts instead (the model's "Rig" attribute tells
	EnemyService how to drive them; their root is anchored):
	  Drone   Flying role: a hovering orb with rotors and one big eye
	  Turret  Turret role: a swivelling gun on a tripod
	  Object  Object role: a generator/pylon with a glowing core (the core
	          is the crit spot)

	To use your own art: put a Model named after the enemy's EnemyDef.Model
	in ServerStorage.EnemyModels. It must contain a Humanoid, a
	HumanoidRootPart (PrimaryPart) and a Head (and a "Rig" attribute for
	machines).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)

type EnemyDef = EnemyConfig.EnemyDef

local EnemyRigs = {}

export type Palette = { Body: Color3, Armor: Color3, Accent: Color3 }

local PALETTES: { [string]: Palette } = {
	Rustborn = {
		Body = Color3.fromRGB(150, 78, 44),
		Armor = Color3.fromRGB(48, 42, 40),
		Accent = Color3.fromRGB(255, 120, 40),
	},
	Veiled = {
		Body = Color3.fromRGB(120, 128, 108),
		Armor = Color3.fromRGB(40, 44, 40),
		Accent = Color3.fromRGB(200, 255, 170),
	},
	Concord = {
		Body = Color3.fromRGB(96, 140, 160),
		Armor = Color3.fromRGB(34, 42, 50),
		Accent = Color3.fromRGB(120, 230, 255),
	},
	Training = {
		Body = Color3.fromRGB(196, 198, 204),
		Armor = Color3.fromRGB(70, 74, 86),
		Accent = Color3.fromRGB(90, 220, 255),
	},
}

local EYES: { [string]: Color3 } = {
	Minor = Color3.fromRGB(255, 110, 40),
	Major = Color3.fromRGB(255, 215, 60),
	Boss = Color3.fromRGB(255, 50, 50),
}

local templates: { [string]: Model } = {}

function EnemyRigs.PaletteFor(def: EnemyDef): Palette
	if def.Dummy then
		return PALETTES.Training
	end
	return PALETTES[def.Faction] or PALETTES.Rustborn
end

local function findPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function attach(
	model: Model,
	target: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.Massless = true
	part.Anchored = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = target.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function buildR15(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = palette.Body
	description.TorsoColor = palette.Armor
	description.LeftArmColor = palette.Body
	description.RightArmColor = palette.Body
	description.LeftLegColor = palette.Armor
	description.RightLegColor = palette.Armor
	return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1
	joint.Parent = part0
end

-- Fallback: a classic blocky R6 rig assembled from parts.
local function buildBlocky(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local model = Instance.new("Model")
	local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.Color = color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), palette.Body)
	root.Transparency = 1
	local torso = part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), palette.Armor)
	local head = part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0), palette.Body)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head
	local leftArm = part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), palette.Body)
	local rightArm = part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), palette.Body)
	local leftLeg = part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), palette.Armor)
	local rightLeg = part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), palette.Armor)

	-- Standard R6 joint offsets.
	motor(
		"RootJoint",
		root,
		torso,
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	motor(
		"Neck",
		torso,
		head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	motor(
		"Right Shoulder",
		torso,
		rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	motor(
		"Left Shoulder",
		torso,
		leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)
	motor(
		"Right Hip",
		torso,
		rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	motor(
		"Left Hip",
		torso,
		leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)

	local grip = Instance.new("Attachment")
	grip.Name = "RightGripAttachment"
	grip.CFrame = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	grip.Parent = rightArm

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function decorate(model: Model, def: EnemyDef)
	local palette = EnemyRigs.PaletteFor(def)
	local head = findPart(model, { "Head" })
	local torso = findPart(model, { "UpperTorso", "Torso" })
	local leftArm = findPart(model, { "LeftUpperArm", "Left Arm" })
	local rightArm = findPart(model, { "RightUpperArm", "Right Arm" })
	local leftHand = findPart(model, { "LeftHand", "Left Arm" })
	local rightHand = findPart(model, { "RightHand", "Right Arm" })

	-- Drop the default smiley and any avatar scripts that came with the rig.
	for _, descendant in model:GetDescendants() do
		local isFace = descendant:IsA("Decal") and descendant.Name == "face"
		if isFace or descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	if head then
		local eyeColor = if def.Dummy then palette.Accent else EYES[def.Tier] or EYES.Minor
		for _, x in { -0.22, 0.22 } do
			local eye = attach(
				model,
				head,
				"Eye",
				Vector3.new(0.22, 0.12, 0.08),
				CFrame.new(x * head.Size.X, 0.08 * head.Size.Y, -head.Size.Z / 2),
				eyeColor,
				Enum.Material.Neon
			)
			eye.CanQuery = true
		end
		attach(
			model,
			head,
			"Helmet",
			Vector3.new(head.Size.X * 1.05, head.Size.Y * 0.35, head.Size.Z * 1.05),
			CFrame.new(0, head.Size.Y * 0.4, 0),
			palette.Armor,
			Enum.Material.Metal
		)
		if def.Tier == "Boss" then
			for index = -1, 1 do
				attach(
					model,
					head,
					"Crown",
					Vector3.new(0.18, 0.7, 0.18),
					CFrame.new(index * 0.35, head.Size.Y * 0.85, 0) * CFrame.Angles(0, 0, index * 0.3),
					palette.Accent,
					Enum.Material.Neon
				)
			end
		end
	end

	if torso then
		attach(
			model,
			torso,
			"ChestPlate",
			Vector3.new(torso.Size.X * 0.9, torso.Size.Y * 0.6, 0.25),
			CFrame.new(0, torso.Size.Y * 0.1, -torso.Size.Z / 2 - 0.1),
			palette.Armor,
			Enum.Material.CorrodedMetal
		)
		attach(
			model,
			torso,
			"Stripe",
			Vector3.new(torso.Size.X * 0.92, 0.12, 0.27),
			CFrame.new(0, torso.Size.Y * 0.1, -torso.Size.Z / 2 - 0.12),
			palette.Accent,
			Enum.Material.Neon
		)
		if def.Shield then
			-- Shield generator backpack glowing with the shield's element.
			attach(
				model,
				torso,
				"ShieldPack",
				Vector3.new(torso.Size.X * 0.6, torso.Size.Y * 0.7, 0.5),
				CFrame.new(0, 0, torso.Size.Z / 2 + 0.25),
				palette.Armor,
				Enum.Material.Metal
			)
		end
	end

	local padSize = if def.Tier == "Minor" then Vector3.new(0.9, 0.35, 0.9) else Vector3.new(1.3, 0.5, 1.2)
	for _, arm in { leftArm, rightArm } do
		if arm then
			attach(
				model,
				arm,
				"ShoulderPad",
				padSize,
				CFrame.new(0, arm.Size.Y * 0.45, 0),
				palette.Armor,
				Enum.Material.CorrodedMetal
			)
		end
	end

	if def.Dummy then
		if torso then
			attach(
				model,
				torso,
				"Target",
				Vector3.new(0.9, 0.9, 0.1),
				CFrame.new(0, 0, -torso.Size.Z / 2 - 0.25),
				palette.Accent,
				Enum.Material.Neon
			)
		end
	elseif def.Role == "Melee" then
		for _, hand in { leftHand, rightHand } do
			if hand then
				attach(
					model,
					hand,
					"Blade",
					Vector3.new(0.12, 0.25, 1.6),
					CFrame.new(0, -hand.Size.Y / 2, -0.7),
					palette.Accent,
					Enum.Material.Neon
				)
			end
		end
	elseif rightHand then
		local rifle = attach(
			model,
			rightHand,
			"Rifle",
			Vector3.new(0.3, 0.4, 2.2),
			CFrame.new(0, -rightHand.Size.Y / 2, -0.8),
			palette.Armor,
			Enum.Material.Metal
		)
		attach(
			model,
			rifle,
			"RifleGlow",
			Vector3.new(0.32, 0.08, 1.6),
			CFrame.new(0, 0.12, -0.1),
			palette.Accent,
			Enum.Material.Neon
		)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Enemies"
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = true
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
	end

	model.Name = def.Name
	model:SetAttribute("EnemyId", def.Id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if def.Scale and def.Scale ~= 1 then
		model:ScaleTo(def.Scale)
	end
end

-- Machines ---------------------------------------------------------------------------

type PartSpec = {
	Name: string,
	Size: Vector3,
	Offset: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Shape: Enum.PartType?,
}

-- A part welded to `root` at root.CFrame * Offset.
local function machinePart(model: Model, root: BasePart, spec: PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Size = spec.Size
	part.Color = spec.Color
	part.Material = spec.Material
	if spec.Shape then
		part.Shape = spec.Shape
	end
	part.CanCollide = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = root.CFrame * spec.Offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function machineRoot(model: Model, size: Vector3): Part
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.CFrame = CFrame.new(0, size.Y / 2, 0)
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function finishMachine(model: Model, def: EnemyDef, rig: string)
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.Parent = model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Enemies"
			if descendant.Size.Magnitude < 3 then
				descendant.CastShadow = false
			end
		end
	end
	model.Name = def.Name
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("Rig", rig)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if def.Scale and def.Scale ~= 1 then
		model:ScaleTo(def.Scale)
	end
end

local function buildDrone(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local model = Instance.new("Model")
	local root = machineRoot(model, Vector3.new(2, 2, 2))
	machinePart(model, root, {
		Name = "Hull",
		Size = Vector3.new(2.4, 2.4, 2.4),
		Offset = CFrame.new(),
		Color = palette.Armor,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
	})
	-- The eye is the head (crit spot).
	machinePart(model, root, {
		Name = "Head",
		Size = Vector3.new(0.4, 1, 1),
		Offset = CFrame.new(0, 0.1, -1.05) * CFrame.Angles(0, math.rad(90), 0),
		Color = palette.Accent,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
	})
	for _, side in { -1, 1 } do
		machinePart(model, root, {
			Name = "Arm",
			Size = Vector3.new(1.6, 0.25, 0.4),
			Offset = CFrame.new(side * 1.8, 0.2, 0),
			Color = palette.Body,
			Material = Enum.Material.CorrodedMetal,
		})
		machinePart(model, root, {
			Name = "Rotor",
			Size = Vector3.new(0.12, 1.6, 1.6),
			Offset = CFrame.new(side * 2.6, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = palette.Accent,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
		})
	end
	machinePart(model, root, {
		Name = "Thruster",
		Size = Vector3.new(0.3, 0.9, 0.9),
		Offset = CFrame.new(0, -1.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = palette.Accent,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
	})
	local light = Instance.new("PointLight")
	light.Color = palette.Accent
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = root
	finishMachine(model, def, "Drone")
	return model
end

local function buildTurret(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local model = Instance.new("Model")
	local root = machineRoot(model, Vector3.new(3, 5, 3))
	for index = 0, 2 do
		local angle = index * math.pi * 2 / 3
		machinePart(model, root, {
			Name = "Leg",
			Size = Vector3.new(0.4, 3.2, 0.4),
			Offset = CFrame.new(math.cos(angle) * 1.1, -1.1, math.sin(angle) * 1.1)
				* CFrame.Angles(math.sin(angle) * 0.4, 0, -math.cos(angle) * 0.4),
			Color = palette.Armor,
			Material = Enum.Material.Metal,
		})
	end
	machinePart(model, root, {
		Name = "Pivot",
		Size = Vector3.new(0.6, 1.8, 1.8),
		Offset = CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = palette.Body,
		Material = Enum.Material.DiamondPlate,
		Shape = Enum.PartType.Cylinder,
	})
	machinePart(model, root, {
		Name = "Housing",
		Size = Vector3.new(2.2, 1.6, 2.6),
		Offset = CFrame.new(0, 1.8, 0),
		Color = palette.Armor,
		Material = Enum.Material.CorrodedMetal,
	})
	for _, side in { -0.5, 0.5 } do
		machinePart(model, root, {
			Name = "Barrel",
			Size = Vector3.new(2.6, 0.35, 0.35),
			Offset = CFrame.new(side, 1.8, -2.4) * CFrame.Angles(0, math.rad(90), 0),
			Color = palette.Armor,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
		})
	end
	-- The sensor is the head (crit spot).
	machinePart(model, root, {
		Name = "Head",
		Size = Vector3.new(0.9, 0.4, 0.2),
		Offset = CFrame.new(0, 2.1, -1.4),
		Color = palette.Accent,
		Material = Enum.Material.Neon,
	})
	finishMachine(model, def, "Turret")
	return model
end

local function buildObject(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local model = Instance.new("Model")
	local root = machineRoot(model, Vector3.new(4, 7, 4))
	machinePart(model, root, {
		Name = "Base",
		Size = Vector3.new(5, 1.2, 5),
		Offset = CFrame.new(0, -2.9, 0),
		Color = palette.Armor,
		Material = Enum.Material.DiamondPlate,
	})
	for _, x in { -1.5, 1.5 } do
		for _, z in { -1.5, 1.5 } do
			machinePart(model, root, {
				Name = "Strut",
				Size = Vector3.new(0.6, 5.4, 0.6),
				Offset = CFrame.new(x, 0, z),
				Color = palette.Body,
				Material = Enum.Material.Metal,
			})
		end
	end
	machinePart(model, root, {
		Name = "Cap",
		Size = Vector3.new(4.2, 0.8, 4.2),
		Offset = CFrame.new(0, 2.9, 0),
		Color = palette.Armor,
		Material = Enum.Material.Metal,
	})
	-- The glowing core: the crit spot.
	machinePart(model, root, {
		Name = "Head",
		Size = Vector3.new(2.2, 2.2, 2.2),
		Offset = CFrame.new(0, 0.3, 0),
		Color = palette.Accent,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
	})
	local light = Instance.new("PointLight")
	light.Color = palette.Accent
	light.Range = 14
	light.Brightness = 2
	light.Parent = root
	finishMachine(model, def, "Object")
	return model
end

-- Veiled objects are crystal growths instead of machines.
local function buildCrystal(def: EnemyDef): Model
	local palette = EnemyRigs.PaletteFor(def)
	local model = Instance.new("Model")
	local root = machineRoot(model, Vector3.new(4, 8, 4))
	machinePart(model, root, {
		Name = "Base",
		Size = Vector3.new(6, 1.6, 6),
		Offset = CFrame.new(0, -3.2, 0) * CFrame.Angles(0, math.rad(20), 0),
		Color = Color3.fromRGB(46, 50, 48),
		Material = Enum.Material.Slate,
	})
	for index = 0, 4 do
		local angle = index / 5 * math.pi * 2
		machinePart(model, root, {
			Name = "Shard",
			Size = Vector3.new(1.2, 5 + (index % 2) * 2, 1.2),
			Offset = CFrame.new(math.cos(angle) * 1.6, -0.5, math.sin(angle) * 1.6)
				* CFrame.Angles(math.sin(angle) * 0.35, angle, -math.cos(angle) * 0.35),
			Color = palette.Accent,
			Material = Enum.Material.Glass,
		})
	end
	-- The glowing heart is the head (crit spot).
	machinePart(model, root, {
		Name = "Head",
		Size = Vector3.new(1.8, 4.2, 1.8),
		Offset = CFrame.new(0, 0.6, 0),
		Color = palette.Accent,
		Material = Enum.Material.Neon,
	})
	local light = Instance.new("PointLight")
	light.Color = palette.Accent
	light.Range = 16
	light.Brightness = 2
	light.Parent = root
	finishMachine(model, def, "Object")
	return model
end

local MACHINES: { [string]: (EnemyDef) -> Model } = {
	Turret = buildTurret,
	Object = buildObject,
}

local function machineFor(def: EnemyDef): ((EnemyDef) -> Model)?
	if def.Role == "Flying" and def.Tier ~= "Boss" then
		return buildDrone
	end
	if def.Role == "Object" and def.Faction == "Veiled" then
		return buildCrystal
	end
	return MACHINES[def.Role]
end

local function customModel(def: EnemyDef): Model?
	local folder = ServerStorage:FindFirstChild("EnemyModels")
	local model = if folder then folder:FindFirstChild(def.Model) else nil
	if model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") and model.PrimaryPart then
		return model:Clone()
	end
	return nil
end

-- A fresh copy of the enemy's rig (built once per type, then cloned).
function EnemyRigs.Create(def: EnemyDef): Model
	local template: Model? = templates[def.Id]
	if template == nil then
		local model = customModel(def)
		local machine = machineFor(def)
		if model == nil and machine then
			model = machine(def)
		elseif model == nil then
			local ok, result = pcall(buildR15, def)
			if ok then
				model = result
			else
				warn(`[EnemyRigs] R15 rig failed for {def.Id} ({result}); using a blocky rig`)
				model = buildBlocky(def)
			end
			decorate(model :: Model, def)
		end
		templates[def.Id] = model :: Model
		return (model :: Model):Clone()
	end
	return template:Clone()
end

return EnemyRigs
