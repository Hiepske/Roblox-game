--!strict
--[[
	WeaponModels
	Builds a simple gun model from parts for each weapon type and attaches
	it to the character's right hand.

	Model convention (matches Roblox Tool grips): the pivot is the grip, the
	barrel points along -Z (LookVector) and +Y is up. A "Muzzle" attachment
	sits at the barrel tip. Colors: dark body, rarity-colored accents and an
	element-colored glow strip.

	To use your own art, put a Model named after the weapon def's Model field
	in ServerStorage.WeaponModels with a PrimaryPart at the grip and a Muzzle
	attachment; it is used instead of the generated one. If a gun sits at the
	wrong angle in the hand, tweak GRIP_OFFSET.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local ElementConfig = require(Shared.Config.ElementConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)

local WeaponModels = {}

-- Applied on top of the hand's grip attachment.
local GRIP_OFFSET = CFrame.new(0, 0, 0)

local BODY = Color3.fromRGB(38, 40, 46)
local METAL = Color3.fromRGB(70, 74, 84)

type PieceSpec = {
	Size: Vector3,
	Offset: Vector3,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Name: string?,
}

local function piece(model: Model, grip: BasePart, spec: PieceSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.Name or "Piece"
	if spec.Shape then
		part.Shape = spec.Shape
	end
	part.Size = spec.Size
	part.Color = spec.Color
	part.Material = spec.Material or Enum.Material.Metal
	part.CFrame = grip.CFrame * CFrame.new(spec.Offset)
	if spec.Shape == Enum.PartType.Cylinder then
		-- Cylinders run along X; turn them to run along the barrel (Z).
		part.CFrame *= CFrame.Angles(0, math.rad(90), 0)
	end
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

-- Deterministic 0..1 values from a weapon id, so each gun of a type differs a little.
local function variation(id: string): (number, number, number)
	local h = 0
	for index = 1, #id do
		h = (h * 131 + string.byte(id, index)) % 1000003
	end
	return (h % 97) / 96, (h % 89) / 88, (h % 83) / 82
end

-- Pieces per weapon type: { body parts... }, muzzle offset. Barrel along -Z.
local function layout(weaponType: string, accent: Color3, glow: Color3, id: string): ({ PieceSpec }, Vector3)
	local va, vb, vc = variation(id)
	local long = 0.85 + va * 0.3 -- barrel length scale
	local grip: PieceSpec = { Size = Vector3.new(0.3, 0.7, 0.35), Offset = Vector3.new(0, -0.15, 0.05), Color = BODY }
	local pieces: { PieceSpec } = { grip }
	local function add(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
		table.insert(pieces, { Size = size, Offset = offset, Color = color, Material = material, Shape = shape })
	end
	local function strip(length: number, z: number, y: number)
		add(Vector3.new(0.06, 0.08, length), Vector3.new(0.2, y, z), glow, NEON)
	end

	if weaponType == "HandCannon" then
		add(Vector3.new(0.32, 0.45, 1.05), Vector3.new(0, 0.3, -0.3), METAL)
		add(Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.3, -0.3), accent, nil, CYL)
		add(Vector3.new(0.9 * long, 0.22, 0.22), Vector3.new(0, 0.42, -1.1 - 0.2 * long), BODY, nil, CYL)
		add(Vector3.new(0.12, 0.25, 0.18), Vector3.new(0, 0.62, 0.15), BODY)
		strip(0.9, -0.5, 0.45)
		return pieces, Vector3.new(0, 0.42, -1.6 - 0.5 * long)
	elseif weaponType == "Sidearm" then
		add(Vector3.new(0.28, 0.32, 1.0), Vector3.new(0, 0.3, -0.35), METAL)
		add(Vector3.new(0.26, 0.18, 0.4), Vector3.new(0, 0.1, -0.6), accent)
		strip(0.8, -0.4, 0.35)
		return pieces, Vector3.new(0, 0.32, -0.95)
	elseif weaponType == "SMG" then
		add(Vector3.new(0.36, 0.55, 1.3), Vector3.new(0, 0.3, -0.45), METAL)
		add(Vector3.new(0.5 * long, 0.2, 0.2), Vector3.new(0, 0.4, -1.3), BODY, nil, CYL)
		add(Vector3.new(0.24, 1.0, 0.3), Vector3.new(0, -0.35, -0.55), accent)
		add(Vector3.new(0.2, 0.45, 0.22), Vector3.new(0, 0.0, -1.0), BODY)
		add(Vector3.new(0.12, 0.3, 0.7), Vector3.new(0, 0.35, 0.55), BODY)
		strip(1.1, -0.45, 0.45)
		return pieces, Vector3.new(0, 0.4, -1.55 - 0.1 * long)
	elseif weaponType == "Shotgun" then
		add(Vector3.new(0.4, 0.55, 1.4), Vector3.new(0, 0.3, -0.4), METAL)
		add(Vector3.new(1.8 * long, 0.3, 0.3), Vector3.new(0, 0.42, -1.4 - 0.5 * long), BODY, nil, CYL)
		add(Vector3.new(1.2, 0.22, 0.22), Vector3.new(0, 0.18, -1.3), METAL, nil, CYL)
		add(Vector3.new(0.34, 0.34, 0.6), Vector3.new(0, 0.18, -1.45), accent)
		add(Vector3.new(0.34, 0.5, 1.1), Vector3.new(0, 0.2, 0.9), BODY)
		strip(1.2, -0.4, 0.5)
		return pieces, Vector3.new(0, 0.42, -2.3 - 0.9 * long)
	elseif weaponType == "SniperRifle" then
		add(Vector3.new(0.36, 0.5, 2.4), Vector3.new(0, 0.32, -0.7), METAL)
		add(Vector3.new(2.4 * long, 0.18, 0.18), Vector3.new(0, 0.4, -1.9 - 1.2 * long), BODY, nil, CYL)
		add(Vector3.new(1.6, 0.48, 0.48), Vector3.new(0, 0.9, -0.5), BODY, nil, CYL)
		add(Vector3.new(0.12, 0.5, 0.5), Vector3.new(0, 0.9, -1.35), accent, nil, CYL)
		add(Vector3.new(0.32, 0.55, 1.3), Vector3.new(0, 0.22, 1.0), BODY)
		add(Vector3.new(0.08, 0.7, 0.08), Vector3.new(0.18, -0.05, -2.2), METAL)
		add(Vector3.new(0.08, 0.7, 0.08), Vector3.new(-0.18, -0.05, -2.2), METAL)
		strip(1.8, -0.7, 0.45)
		return pieces, Vector3.new(0, 0.4, -3.1 - 2.4 * long)
	elseif weaponType == "ScoutRifle" then
		add(Vector3.new(0.34, 0.5, 2.5), Vector3.new(0, 0.32, -0.75), METAL)
		add(Vector3.new(1.4 * long, 0.18, 0.18), Vector3.new(0, 0.4, -2.0 - 0.7 * long), BODY, nil, CYL)
		add(Vector3.new(1.0, 0.36, 0.36), Vector3.new(0, 0.82, -0.5), BODY, nil, CYL)
		add(Vector3.new(0.26, 0.6, 0.35), Vector3.new(0, -0.1, -0.9), accent)
		add(Vector3.new(0.28, 0.45, 1.0), Vector3.new(0, 0.22, 0.95), BODY)
		strip(1.8, -0.8, 0.45)
		return pieces, Vector3.new(0, 0.4, -2.7 - 1.4 * long)
	elseif weaponType == "PulseRifle" then
		add(Vector3.new(0.42, 0.7, 2.0), Vector3.new(0, 0.35, -0.55), METAL)
		add(Vector3.new(0.8 * long, 0.22, 0.22), Vector3.new(0, 0.45, -1.9), BODY, nil, CYL)
		for index = 0, 2 do
			add(Vector3.new(0.44, 0.08, 0.14), Vector3.new(0, 0.55, -1.2 + index * 0.3), glow, NEON)
		end
		add(Vector3.new(0.28, 0.7, 0.4), Vector3.new(0, -0.2, -0.8), accent)
		add(Vector3.new(0.3, 0.5, 0.9), Vector3.new(0, 0.3 - vb * 0.1, 0.9), BODY)
		return pieces, Vector3.new(0, 0.45, -2.3 - 0.4 * long)
	elseif weaponType == "FusionRifle" then
		add(Vector3.new(0.45, 0.65, 2.0), Vector3.new(0, 0.35, -0.5), METAL)
		for index = 0, 2 do
			add(Vector3.new(0.14, 0.62, 0.62), Vector3.new(0, 0.4, -1.55 - index * 0.28), glow, NEON, CYL)
		end
		add(Vector3.new(0.5, 0.3, 0.3), Vector3.new(0, 0.4, -2.3), BODY, nil, CYL)
		add(Vector3.new(0.36, 0.4, 0.5), Vector3.new(0, 0.0, -0.2), accent)
		add(Vector3.new(0.3, 0.5, 0.9), Vector3.new(0, 0.3, 0.9), BODY)
		return pieces, Vector3.new(0, 0.4, -2.6)
	elseif weaponType == "GrenadeLauncher" then
		add(Vector3.new(0.4, 0.5, 1.4), Vector3.new(0, 0.35, -0.3), METAL)
		add(Vector3.new(0.8, 0.95, 0.95), Vector3.new(0, 0.35, -1.0), accent, nil, CYL)
		add(Vector3.new(1.0 * long, 0.55, 0.55), Vector3.new(0, 0.45, -1.9), BODY, nil, CYL)
		add(Vector3.new(0.3, 0.5, 1.0), Vector3.new(0, 0.25, 0.8), BODY)
		strip(1.0, -0.4, 0.62)
		return pieces, Vector3.new(0, 0.45, -2.4 - 0.5 * long)
	elseif weaponType == "RocketLauncher" then
		add(Vector3.new(0.3, 0.7, 0.35), Vector3.new(0, -0.15, 0.1), BODY)
		add(Vector3.new(3.6, 0.8, 0.8), Vector3.new(0, 0.55, -0.6), METAL, nil, CYL)
		add(Vector3.new(0.3, 0.9, 0.9), Vector3.new(0, 0.55, -2.4), accent, nil, CYL)
		add(Vector3.new(0.3, 0.9, 0.9), Vector3.new(0, 0.55, 1.2), accent, nil, CYL)
		add(Vector3.new(0.25, 0.3, 0.6), Vector3.new(-0.5, 0.75, -0.4), BODY)
		add(Vector3.new(0.06, 0.1, 2.6), Vector3.new(0.42, 0.6, -0.6), glow, NEON)
		return pieces, Vector3.new(0, 0.55, -2.6)
	elseif weaponType == "MachineGun" then
		add(Vector3.new(0.5, 0.7, 2.6), Vector3.new(0, 0.35, -0.7), METAL)
		add(Vector3.new(1.6 * long, 0.42, 0.42), Vector3.new(0, 0.45, -2.3 - 0.4 * long), BODY, nil, CYL)
		add(Vector3.new(0.5, 0.6, 0.6), Vector3.new(0.45, 0.1, -0.6), accent)
		add(Vector3.new(0.1, 0.35, 0.9), Vector3.new(0, 0.9, -0.6), BODY)
		add(Vector3.new(0.34, 0.5, 1.1), Vector3.new(0, 0.25, 1.0), BODY)
		add(Vector3.new(0.08, 0.8, 0.08), Vector3.new(0.2, -0.05, -2.3), METAL)
		add(Vector3.new(0.08, 0.8, 0.08), Vector3.new(-0.2, -0.05, -2.3), METAL)
		strip(2.0, -0.7, 0.72)
		return pieces, Vector3.new(0, 0.45, -3.1 - 1.2 * long)
	elseif weaponType == "Sword" then
		local blade = 3.0 + vc * 0.8
		return {
			{ Size = Vector3.new(0.25, 0.25, 0.9), Offset = Vector3.new(0, 0, 0.1), Color = BODY },
			{ Size = Vector3.new(0.9, 0.2, 0.25), Offset = Vector3.new(0, 0, -0.4), Color = accent },
			{
				Size = Vector3.new(0.14, 0.38, blade),
				Offset = Vector3.new(0, 0, -0.5 - blade / 2),
				Color = glow,
				Material = NEON,
			},
			{
				Size = Vector3.new(0.05, 0.42, blade * 0.95),
				Offset = Vector3.new(0, 0, -0.5 - blade / 2),
				Color = METAL,
			},
		},
			Vector3.new(0, 0, -0.6 - blade)
	end
	-- Auto rifles.
	add(Vector3.new(0.36, 0.6, 2.2), Vector3.new(0, 0.35, -0.6), METAL)
	add(Vector3.new(1.1 * long, 0.2, 0.2), Vector3.new(0, 0.45, -2.2), BODY, nil, CYL)
	add(Vector3.new(0.28, 0.75, 0.4), Vector3.new(0, -0.15, -0.9), accent)
	add(Vector3.new(0.3, 0.45, 0.9), Vector3.new(0, 0.25, 0.9), BODY)
	add(Vector3.new(0.18, 0.22, 0.5), Vector3.new(0, 0.75, -0.5 - vb * 0.3), accent)
	strip(1.6, -0.6, 0.45)
	return pieces, Vector3.new(0, 0.45, -2.8 - 0.5 * long)
end

local function custom(modelName: string): Model?
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local model = if folder then folder:FindFirstChild(modelName) else nil
	if model and model:IsA("Model") and model.PrimaryPart then
		return model:Clone()
	end
	return nil
end

function WeaponModels.Build(defId: string): Model?
	local def = WeaponConfig.ById[defId]
	if def == nil then
		return nil
	end
	local provided = custom(def.Model)
	if provided then
		provided.Name = "Weapon"
		return provided
	end

	local model = Instance.new("Model")
	model.Name = "Weapon"
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.2, 0.2, 0.2)
	grip.Transparency = 1
	grip.Massless = true
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.CFrame = CFrame.new()
	grip.Parent = model
	model.PrimaryPart = grip

	local accent = RarityConfig.Tiers[def.Rarity].Color
	local element = ElementConfig.Elements[def.Element]
	local glow = if element then element.Color else accent
	local pieces, muzzleOffset = layout(def.Type, accent, glow, def.Id)
	for _, spec in pieces do
		piece(model, grip, spec)
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = muzzleOffset
	muzzle.Parent = grip
	return model
end

-- Welds `model` into the character's right hand (or right arm for R6).
function WeaponModels.Attach(character: Model, model: Model): boolean
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return false
	end
	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local target = if gripAttachment and gripAttachment:IsA("Attachment")
		then gripAttachment.WorldCFrame
		else hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	model:PivotTo(target * GRIP_OFFSET)
	local grip = model.PrimaryPart
	if grip == nil then
		return false
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = grip
	weld.Parent = grip
	model.Parent = character
	return true
end

return WeaponModels
