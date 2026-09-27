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

-- Pieces per archetype family: { body parts..., muzzle offset }.
local function layout(weaponType: string, accent: Color3, glow: Color3): ({ PieceSpec }, Vector3)
	if weaponType == "HandCannon" or weaponType == "Sidearm" then
		return {
			{ Size = Vector3.new(0.3, 0.7, 0.35), Offset = Vector3.new(0, -0.15, 0.05), Color = BODY },
			{ Size = Vector3.new(0.32, 0.42, 1.2), Offset = Vector3.new(0, 0.35, -0.45), Color = METAL },
			{
				Size = Vector3.new(0.45, 0.45, 0.45),
				Offset = Vector3.new(0, 0.33, -0.35),
				Color = accent,
				Shape = Enum.PartType.Cylinder,
			},
			{
				Size = Vector3.new(0.9, 0.2, 0.2),
				Offset = Vector3.new(0, 0.42, -1.4),
				Color = BODY,
				Shape = Enum.PartType.Cylinder,
			},
			{
				Size = Vector3.new(0.06, 0.08, 1.0),
				Offset = Vector3.new(0.17, 0.45, -0.6),
				Color = glow,
				Material = Enum.Material.Neon,
			},
		},
			Vector3.new(0, 0.42, -1.9)
	elseif weaponType == "RocketLauncher" or weaponType == "GrenadeLauncher" then
		return {
			{ Size = Vector3.new(0.3, 0.7, 0.35), Offset = Vector3.new(0, -0.15, 0.1), Color = BODY },
			{
				Size = Vector3.new(3.6, 0.8, 0.8),
				Offset = Vector3.new(0, 0.55, -0.6),
				Color = METAL,
				Shape = Enum.PartType.Cylinder,
			},
			{
				Size = Vector3.new(0.3, 0.9, 0.9),
				Offset = Vector3.new(0, 0.55, -2.4),
				Color = accent,
				Shape = Enum.PartType.Cylinder,
			},
			{
				Size = Vector3.new(0.3, 0.9, 0.9),
				Offset = Vector3.new(0, 0.55, 1.2),
				Color = accent,
				Shape = Enum.PartType.Cylinder,
			},
			{ Size = Vector3.new(0.25, 0.3, 0.6), Offset = Vector3.new(-0.5, 0.75, -0.4), Color = BODY },
			{
				Size = Vector3.new(0.06, 0.1, 2.6),
				Offset = Vector3.new(0.42, 0.6, -0.6),
				Color = glow,
				Material = Enum.Material.Neon,
			},
		},
			Vector3.new(0, 0.55, -2.6)
	elseif weaponType == "Sword" then
		return {
			{ Size = Vector3.new(0.25, 0.25, 0.9), Offset = Vector3.new(0, 0, 0.1), Color = BODY },
			{ Size = Vector3.new(0.8, 0.2, 0.2), Offset = Vector3.new(0, 0, -0.4), Color = accent },
			{
				Size = Vector3.new(0.12, 0.35, 3.2),
				Offset = Vector3.new(0, 0, -2.1),
				Color = glow,
				Material = Enum.Material.Neon,
			},
		},
			Vector3.new(0, 0, -3.7)
	elseif weaponType == "SniperRifle" or weaponType == "ScoutRifle" or weaponType == "MachineGun" then
		return {
			{ Size = Vector3.new(0.3, 0.7, 0.35), Offset = Vector3.new(0, -0.15, 0.05), Color = BODY },
			{ Size = Vector3.new(0.36, 0.55, 2.6), Offset = Vector3.new(0, 0.35, -0.8), Color = METAL },
			{
				Size = Vector3.new(2.0, 0.18, 0.18),
				Offset = Vector3.new(0, 0.45, -3.0),
				Color = BODY,
				Shape = Enum.PartType.Cylinder,
			},
			{ Size = Vector3.new(0.3, 0.45, 1.1), Offset = Vector3.new(0, 0.25, 0.9), Color = BODY },
			{
				Size = Vector3.new(0.9, 0.28, 0.28),
				Offset = Vector3.new(0, 0.85, -0.6),
				Color = accent,
				Shape = Enum.PartType.Cylinder,
			},
			{
				Size = Vector3.new(0.06, 0.1, 2.0),
				Offset = Vector3.new(0.19, 0.4, -0.8),
				Color = glow,
				Material = Enum.Material.Neon,
			},
		},
			Vector3.new(0, 0.45, -4.0)
	end
	-- Auto rifles, pulse rifles, SMGs, shotguns, fusion rifles.
	return {
		{ Size = Vector3.new(0.3, 0.7, 0.35), Offset = Vector3.new(0, -0.15, 0.05), Color = BODY },
		{ Size = Vector3.new(0.36, 0.6, 2.2), Offset = Vector3.new(0, 0.35, -0.6), Color = METAL },
		{
			Size = Vector3.new(1.1, 0.2, 0.2),
			Offset = Vector3.new(0, 0.45, -2.2),
			Color = BODY,
			Shape = Enum.PartType.Cylinder,
		},
		{ Size = Vector3.new(0.28, 0.75, 0.4), Offset = Vector3.new(0, -0.15, -0.9), Color = accent },
		{ Size = Vector3.new(0.3, 0.45, 0.9), Offset = Vector3.new(0, 0.25, 0.9), Color = BODY },
		{ Size = Vector3.new(0.18, 0.22, 0.5), Offset = Vector3.new(0, 0.75, -0.5), Color = accent },
		{
			Size = Vector3.new(0.06, 0.1, 1.6),
			Offset = Vector3.new(0.19, 0.4, -0.6),
			Color = glow,
			Material = Enum.Material.Neon,
		},
	},
		Vector3.new(0, 0.45, -2.8)
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
	local pieces, muzzleOffset = layout(def.Type, accent, glow)
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
