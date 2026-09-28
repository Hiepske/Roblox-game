--!strict
--[[
	EffectsController
	Client-side visuals: tracers, muzzle flashes, impacts, explosions,
	projectiles (drawn locally from the server's ProjectileSpawned events so
	they move smoothly) and floating damage numbers (white for body hits,
	yellow for precision hits). Parts are pooled to avoid garbage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

local EffectsController = {}

local folder: Folder
local pool: { Part } = {}
local numberAnchors: { Part } = {}

type Visual = { Parts: { BasePart }, Position: Vector3, Velocity: Vector3, Gravity: number, Born: number }
local projectiles: { [number]: Visual } = {}

local COLORS = {
	Body = Color3.fromRGB(255, 255, 255),
	Precision = Color3.fromRGB(255, 214, 60),
	Immune = Color3.fromRGB(150, 150, 160),
	Shield = Color3.fromRGB(170, 225, 255),
}

local function takePart(): Part
	local part = table.remove(pool)
	if part == nil then
		local created = Instance.new("Part")
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.CastShadow = false
		created.Material = Enum.Material.Neon
		created.TopSurface = Enum.SurfaceType.Smooth
		created.BottomSurface = Enum.SurfaceType.Smooth
		part = created
	end
	local chosen = part :: Part
	chosen.Shape = Enum.PartType.Block
	chosen.Transparency = 0
	chosen.Parent = folder
	return chosen
end

local function releasePart(part: Part)
	for _, child in part:GetChildren() do
		child:Destroy()
	end
	part.Parent = nil
	if #pool < 200 then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

local function fadeAndRelease(part: Part, duration: number, goal: { [string]: any }?)
	local properties: { [string]: any } = goal or {}
	properties.Transparency = 1
	TweenService:Create(part, TweenInfo.new(duration), properties):Play()
	task.delay(duration + 0.02, releasePart, part)
end

-- Plays a sound if its asset id has been filled in (placeholders are 0).
function EffectsController.PlaySound(id: number, at: Vector3?, volume: number?)
	if AssetIds.IsPlaceholder(id) then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = AssetIds.Get(id)
	sound.Volume = volume or 0.6
	if at then
		local anchor = takePart()
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.CFrame = CFrame.new(at)
		sound.Parent = anchor
		sound:Play()
		task.delay(3, releasePart, anchor)
	else
		sound.Parent = SoundService
		sound:Play()
		task.delay(3, function()
			sound:Destroy()
		end)
	end
end

function EffectsController.Tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local part = takePart()
	part.Color = color
	part.Size = Vector3.new(0.08, 0.08, length)
	part.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	part.Transparency = 0.15
	fadeAndRelease(part, 0.08)
end

function EffectsController.MuzzleFlash(position: Vector3, color: Color3)
	local part = takePart()
	part.Shape = Enum.PartType.Ball
	part.Color = color
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 3
	light.Parent = part
	fadeAndRelease(part, 0.06, { Size = Vector3.new(0.2, 0.2, 0.2) })
end

function EffectsController.Impact(position: Vector3, color: Color3?)
	local part = takePart()
	part.Shape = Enum.PartType.Ball
	part.Color = color or Color3.fromRGB(255, 230, 180)
	part.Size = Vector3.new(0.35, 0.35, 0.35)
	part.CFrame = CFrame.new(position)
	fadeAndRelease(part, 0.15, { Size = Vector3.new(0.9, 0.9, 0.9) })
end

function EffectsController.Explosion(position: Vector3, radius: number, color: Color3?)
	local part = takePart()
	part.Shape = Enum.PartType.Ball
	part.Color = color or Color3.fromRGB(255, 150, 60)
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = radius * 3
	light.Brightness = 4
	light.Parent = part
	fadeAndRelease(part, 0.35, { Size = Vector3.new(radius * 2, radius * 2, radius * 2) })
	EffectsController.PlaySound(AssetIds.Sounds.Combat.Explosion, position, 0.8)
end

-- A jagged lightning arc between two points.
function EffectsController.Arc(from: Vector3, to: Vector3, color: Color3)
	local segments = 5
	local last = from
	for index = 1, segments do
		local t = index / segments
		local point = from:Lerp(to, t)
		if index < segments then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2
		end
		local length = (point - last).Magnitude
		if length > 0.05 then
			local part = takePart()
			part.Color = color
			part.Size = Vector3.new(0.18, 0.18, length)
			part.CFrame = CFrame.lookAt(last, point) * CFrame.new(0, 0, -length / 2)
			fadeAndRelease(part, 0.25)
		end
		last = point
	end
end

-- A dark, pulsing well that shrinks away after `duration` seconds.
function EffectsController.Singularity(position: Vector3, radius: number, duration: number)
	local core = takePart()
	core.Shape = Enum.PartType.Ball
	core.Color = Color3.fromRGB(120, 60, 220)
	core.Material = Enum.Material.ForceField
	core.Size = Vector3.new(1, 1, 1)
	core.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Color = core.Color
	light.Range = radius * 2
	light.Brightness = 3
	light.Parent = core
	TweenService:Create(core, TweenInfo.new(0.3), { Size = Vector3.new(radius * 2, radius * 2, radius * 2) }):Play()
	task.delay(math.max(0.3, duration - 0.4), function()
		fadeAndRelease(core, 0.4, { Size = Vector3.new(0.5, 0.5, 0.5) })
	end)
end

-- A sword slash: a fan of glowing blades in front of `origin`.
function EffectsController.Slash(origin: CFrame, range: number, color: Color3)
	for index = -2, 2 do
		local part = takePart()
		part.Color = color
		part.Size = Vector3.new(0.15, 0.4, range * 0.8)
		part.CFrame = origin * CFrame.Angles(0, math.rad(index * 18), 0) * CFrame.new(0, 1, -range * 0.45)
		part.Transparency = 0.2
		fadeAndRelease(part, 0.18)
	end
end

-- Floating damage number at a world position.
function EffectsController.DamageNumber(position: Vector3, amount: number, precision: boolean, flag: string?)
	local anchor = table.remove(numberAnchors)
	if anchor == nil then
		local created = Instance.new("Part")
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.CanTouch = false
		created.Transparency = 1
		created.Size = Vector3.new(0.1, 0.1, 0.1)
		local gui = Instance.new("BillboardGui")
		gui.Name = "Number"
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(140, 44)
		gui.LightInfluence = 0
		gui.MaxDistance = 250
		gui.Parent = created
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
		anchor = created
	end
	local part = anchor :: Part
	local gui = part:FindFirstChild("Number") :: BillboardGui
	local label = gui:FindFirstChild("Text") :: TextLabel

	local jitter = Vector3.new((math.random() - 0.5) * 1.2, math.random() * 0.6, (math.random() - 0.5) * 1.2)
	part.CFrame = CFrame.new(position + jitter)
	part.Parent = folder
	gui.StudsOffset = Vector3.new(0, 1, 0)
	local big = precision or flag == "Kill"
	gui.Size = if big then UDim2.fromOffset(170, 54) else UDim2.fromOffset(130, 40)
	if flag == "Immune" then
		label.Text = "IMMUNE"
		label.TextColor3 = COLORS.Immune
	elseif flag == "Resisted" then
		label.Text = "RESIST"
		label.TextColor3 = COLORS.Immune
	else
		label.Text = tostring(amount)
		label.TextColor3 = if precision then COLORS.Precision elseif flag == "Shield" then COLORS.Shield else COLORS.Body
	end
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3

	TweenService:Create(gui, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3.2, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.85, function()
		part.Parent = nil
		table.insert(numberAnchors, part)
	end)
end

-- The muzzle position of a character's equipped weapon model.
function EffectsController.MuzzleOf(character: Model?): Vector3?
	local weapon = if character then character:FindFirstChild("Weapon") else nil
	if weapon == nil then
		return nil
	end
	local muzzle = weapon:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return nil
end

-- Projectiles ------------------------------------------------------------------------

local function projectileVisual(style: string, color: Color3): { BasePart }
	local parts: { BasePart } = {}
	local core = takePart()
	core.Color = color
	if style == "Rocket" then
		core.Size = Vector3.new(0.45, 0.45, 1.6)
		core.Material = Enum.Material.Metal
		core.Color = Color3.fromRGB(70, 74, 84)
		local flame = takePart()
		flame.Shape = Enum.PartType.Ball
		flame.Color = color
		flame.Size = Vector3.new(0.7, 0.7, 0.7)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12
		light.Brightness = 2
		light.Parent = flame
		table.insert(parts, core)
		table.insert(parts, flame)
		return parts
	end
	core.Shape = Enum.PartType.Ball
	if style == "Grenade" then
		core.Material = Enum.Material.Metal
		core.Color = Color3.fromRGB(60, 64, 72)
		core.Size = Vector3.new(0.8, 0.8, 0.8)
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = 8
		glow.Parent = core
		table.insert(parts, core)
		return parts
	end
	local size = if style == "BossOrb" then 1.8 elseif style == "Bomblet" then 0.5 else 0.7
	core.Size = Vector3.new(size, size, size)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if style == "BossOrb" then 14 else 7
	light.Brightness = 2
	light.Parent = core
	table.insert(parts, core)
	return parts
end

local function placeVisual(visual: Visual)
	local velocity = visual.Velocity
	local frame = if velocity.Magnitude > 0
		then CFrame.lookAt(visual.Position, visual.Position + velocity)
		else CFrame.new(visual.Position)
	visual.Parts[1].CFrame = frame
	if visual.Parts[2] then
		visual.Parts[2].CFrame = frame * CFrame.new(0, 0, 0.9)
	end
end

local function endProjectile(id: number)
	local visual = projectiles[id]
	if visual then
		projectiles[id] = nil
		for _, part in visual.Parts do
			if part:IsA("Part") then
				part.Material = Enum.Material.Neon
				releasePart(part)
			end
		end
	end
end

function EffectsController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace

	ClientNet.On(
		"ProjectileSpawned",
		function(id: any, origin: any, velocity: any, style: any, color: any, gravity: any)
			if type(id) ~= "number" or typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
				return
			end
			local visual: Visual = {
				Parts = projectileVisual(
					tostring(style),
					if typeof(color) == "Color3" then color else Color3.new(1, 0.5, 0.2)
				),
				Position = origin,
				Velocity = velocity,
				Gravity = if type(gravity) == "number" then gravity else 0,
				Born = os.clock(),
			}
			projectiles[id] = visual
			placeVisual(visual)
			if style == "Rocket" or style == "BossOrb" then
				EffectsController.PlaySound(AssetIds.Sounds.Combat.EnemyFire, origin, 0.4)
			end
		end
	)

	ClientNet.On("ProjectileEnded", function(id: any, position: any, radius: any)
		if type(id) ~= "number" then
			return
		end
		local visual = projectiles[id]
		local color = if visual and visual.Parts[2]
			then visual.Parts[2].Color
			elseif visual then visual.Parts[1].Color
			else nil
		endProjectile(id)
		if typeof(position) == "Vector3" then
			if type(radius) == "number" and radius > 0 then
				EffectsController.Explosion(position, radius, color)
			else
				EffectsController.Impact(position, color)
			end
		end
	end)

	ClientNet.On("WorldEffect", function(kind: any, a: any, b: any, c: any)
		local tint = if typeof(c) == "Color3" then c else Color3.fromRGB(255, 180, 90)
		if kind == "Explosion" and typeof(a) == "Vector3" then
			EffectsController.Explosion(a, tonumber(b) or 6, tint)
		elseif kind == "Arc" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			EffectsController.Arc(a, b, tint)
		elseif kind == "Singularity" and typeof(a) == "Vector3" then
			EffectsController.Singularity(a, tonumber(b) or 10, tonumber(c) or 3)
		elseif kind == "Slash" and typeof(a) == "CFrame" then
			EffectsController.Slash(a, tonumber(b) or 10, tint)
		end
	end)

	ClientNet.On("ShotEffect", function(userId: any, hitPosition: any, color: any)
		if type(userId) ~= "number" or typeof(hitPosition) ~= "Vector3" then
			return
		end
		local shooter = Players:GetPlayerByUserId(userId)
		local muzzle = if shooter then EffectsController.MuzzleOf(shooter.Character) else nil
		if muzzle then
			local tint = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
			EffectsController.Tracer(muzzle, hitPosition, tint)
			EffectsController.MuzzleFlash(muzzle, tint)
		end
	end)

	ClientNet.On("CombatFeedback", function(position: any, amount: any, precision: any, flag: any)
		if typeof(position) == "Vector3" and type(amount) == "number" then
			EffectsController.DamageNumber(
				position,
				amount,
				precision == true,
				if type(flag) == "string" then flag else nil
			)
		end
	end)
end

function EffectsController.Start()
	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for id, visual in projectiles do
			if visual.Gravity ~= 0 then
				visual.Velocity -= Vector3.new(0, visual.Gravity * dt, 0)
			end
			visual.Position += visual.Velocity * dt
			placeVisual(visual)
			if now - visual.Born > 10 then
				endProjectile(id)
			end
		end
	end)
end

return EffectsController
