--!strict
--[[
	CueController
	Draws the mission cues the server sends with WorldCue (MissionKit.Cue):

	  Portal     a rift opens where an enemy is about to step out
	  Dropship   a ship swoops in over the drop point and leaves again
	  Telegraph  a red warning circle that fills up until the slam lands
	  Shockwave  the slam: an expanding ring and a camera shake
	  SafeZone   a glowing circle (and light column) that protects you
	  Nova       the wipe blast: a white flash that fills the arena
	  Charge     a boss winding up (a growing glow)
	  Blink      a boss vanishing/appearing (teleports)
	  ShieldUp / ShieldBreak  a boss's immune bubble going up or shattering
	  GateOpen   a flash where a gate opens
	  Collapse   the ground rumbling before the floor gives way
	  BossIntro  the boss's name on screen
	  BossDeath  a chain of explosions and a second of slow motion
	  ChestDrop / AmmoDrop  a light column marking loot and ammo
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local EffectsController = require(script.Parent.EffectsController)
local HudController = require(script.Parent.HudController)

local CueController = {}

local player = Players.LocalPlayer
local folder: Folder
local shakeUntil = 0
local shakeStrength = 0

local RED = Color3.fromRGB(255, 60, 40)
local RIFT = Color3.fromRGB(255, 120, 40)
local SAFE = Color3.fromRGB(90, 255, 200)
local GOLD = Color3.fromRGB(255, 205, 90)

-- Helpers ---------------------------------------------------------------------------------

local function part(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	if shape then
		p.Shape = shape
	end
	p.CFrame = cframe
	p.Parent = folder
	return p
end

-- A flat disc lying on the ground (cylinders point along X, so tip it up).
local function disc(center: Vector3, radius: number, color: Color3, thickness: number?): Part
	return part(
		Vector3.new(thickness or 0.2, radius * 2, radius * 2),
		CFrame.new(center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.PartType.Cylinder
	)
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(instance, info, goal):Play()
end

local function fadeOut(p: BasePart, seconds: number, goal: { [string]: any }?)
	local properties: { [string]: any } = goal or {}
	properties.Transparency = 1
	tween(p, seconds, properties)
	task.delay(seconds + 0.05, function()
		p:Destroy()
	end)
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 2
	l.Parent = parent
end

local function distanceTo(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else 0
end

function CueController.Shake(strength: number, seconds: number)
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

local function shakeNear(position: Vector3, strength: number, seconds: number, range: number)
	local distance = distanceTo(position)
	if distance < range then
		CueController.Shake(strength * (1 - distance / range), seconds)
	end
end

-- Cues ------------------------------------------------------------------------------------

local function portal(position: Vector3, delay: number)
	local center = position + Vector3.new(0, 3.5, 0)
	local camera = Workspace.CurrentCamera
	local facing = if camera
		then Vector3.new(camera.CFrame.Position.X, center.Y, camera.CFrame.Position.Z)
		else center + Vector3.zAxis
	local frame = CFrame.lookAt(center, facing) * CFrame.Angles(0, math.rad(90), 0)
	local ring = part(Vector3.new(0.3, 0.5, 0.5), frame, RIFT, Enum.PartType.Cylinder)
	ring.Transparency = 0.2
	local core = part(Vector3.new(0.2, 0.3, 0.3), frame, Color3.fromRGB(40, 10, 60), Enum.PartType.Cylinder)
	core.Material = Enum.Material.ForceField
	light(ring, RIFT, 16, 3)
	tween(ring, 0.35, { Size = Vector3.new(0.3, 7, 7) }, Enum.EasingStyle.Back)
	tween(core, 0.35, { Size = Vector3.new(0.35, 6, 6) }, Enum.EasingStyle.Back)
	EffectsController.PlaySound(AssetIds.Sounds.Combat.Portal, center, 0.6)
	task.delay(math.max(0.4, delay), function()
		fadeOut(ring, 0.4, { Size = Vector3.new(0.3, 0.5, 0.5) })
		fadeOut(core, 0.4, { Size = Vector3.new(0.3, 0.5, 0.5) })
		local flash = part(Vector3.new(4, 4, 4), CFrame.new(center), RIFT, Enum.PartType.Ball)
		flash.Transparency = 0.3
		fadeOut(flash, 0.3, { Size = Vector3.new(9, 9, 9) })
	end)
end

local function dropship(position: Vector3, delay: number)
	local model = Instance.new("Model")
	model.Name = "Dropship"
	local root = part(Vector3.new(10, 3, 22), CFrame.new(), Color3.fromRGB(60, 58, 62))
	root.Material = Enum.Material.Metal
	root.Parent = model
	local function attach(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = part(size, offset, color, nil)
		p.Material = material
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	attach(Vector3.new(26, 1, 8), CFrame.new(0, 0.5, 3), Color3.fromRGB(80, 76, 80), Enum.Material.Metal)
	attach(Vector3.new(6, 2.5, 6), CFrame.new(0, 1.5, -9), Color3.fromRGB(45, 42, 44), Enum.Material.Metal)
	for _, x in { -10, 10 } do
		attach(Vector3.new(3, 3, 3), CFrame.new(x, 0, 6), RIFT, Enum.Material.Neon)
	end
	attach(Vector3.new(8, 0.4, 14), CFrame.new(0, -1.6, 2), RIFT, Enum.Material.Neon)
	model.PrimaryPart = root
	model.Parent = folder
	light(root, RIFT, 40, 2)

	local hover = position + Vector3.new(0, 34, 0)
	local approach = hover + Vector3.new(-260, 90, -120)
	local leave = hover + Vector3.new(280, 110, 140)
	local arrive = math.max(0.8, delay - 0.6)
	root.CFrame = CFrame.lookAt(approach, hover)
	tween(root, arrive, { CFrame = CFrame.lookAt(hover, hover + (hover - approach).Unit * Vector3.new(1, 0, 1)) })
	EffectsController.PlaySound(AssetIds.Sounds.Combat.Dropship, position, 0.8)
	task.delay(arrive, function()
		-- The drop: a light beam down to the ground.
		local beam = part(Vector3.new(4, 34, 4), CFrame.new(position + Vector3.new(0, 17, 0)), RIFT, nil)
		beam.Transparency = 0.6
		fadeOut(beam, 1.2)
		shakeNear(position, 0.4, 0.5, 120)
	end)
	task.delay(arrive + 1.4, function()
		tween(root, 3, { CFrame = CFrame.lookAt(leave, leave + (leave - hover).Unit) }, Enum.EasingStyle.Quad)
		task.delay(3.1, function()
			model:Destroy()
		end)
	end)
end

local function telegraph(center: Vector3, radius: number, windup: number)
	local edge = disc(center, radius, RED, 0.15)
	edge.Transparency = 0.55
	local fill = disc(center + Vector3.new(0, 0.05, 0), 0.5, RED, 0.2)
	fill.Transparency = 0.25
	tween(fill, windup, { Size = Vector3.new(0.2, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	task.delay(windup, function()
		edge:Destroy()
		fill:Destroy()
	end)
end

local function shockwave(center: Vector3, radius: number)
	local ring = disc(center, 1, Color3.fromRGB(255, 170, 90), 0.4)
	ring.Transparency = 0.1
	fadeOut(ring, 0.5, { Size = Vector3.new(0.4, radius * 2.4, radius * 2.4) })
	EffectsController.Explosion(center + Vector3.new(0, 1, 0), radius * 0.4, Color3.fromRGB(255, 150, 60))
	shakeNear(center, 1.2, 0.6, radius * 5)
	EffectsController.PlaySound(AssetIds.Sounds.Combat.BossSlam, center, 1)
end

local function safeZone(center: Vector3, radius: number, duration: number)
	local circle = disc(center, radius, SAFE, 0.25)
	circle.Transparency = 0.35
	local column = part(
		Vector3.new(60, radius * 2, radius * 2),
		CFrame.new(center + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		SAFE,
		Enum.PartType.Cylinder
	)
	column.Material = Enum.Material.ForceField
	column.Transparency = 0.5
	light(circle, SAFE, radius * 2, 3)
	task.delay(duration, function()
		fadeOut(circle, 0.4)
		fadeOut(column, 0.4)
	end)
end

local function nova(center: Vector3)
	local flash = part(Vector3.new(6, 6, 6), CFrame.new(center), Color3.new(1, 1, 1), Enum.PartType.Ball)
	flash.Transparency = 0.05
	fadeOut(flash, 0.9, { Size = Vector3.new(420, 420, 420) })
	CueController.Shake(2, 1.2)
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Brightness = 0.6
	correction.Parent = Lighting
	tween(correction, 0.9, { Brightness = 0 })
	task.delay(1, function()
		correction:Destroy()
	end)
end

local function charge(position: Vector3, windup: number)
	local glow = part(Vector3.new(1, 1, 1), CFrame.new(position), RIFT, Enum.PartType.Ball)
	glow.Transparency = 0.3
	light(glow, RIFT, 20, 3)
	tween(glow, windup, { Size = Vector3.new(7, 7, 7) })
	task.delay(windup, function()
		fadeOut(glow, 0.2, { Size = Vector3.new(10, 10, 10) })
	end)
end

local function blink(position: Vector3)
	local burst = part(
		Vector3.new(2, 2, 2),
		CFrame.new(position + Vector3.new(0, 4, 0)),
		Color3.fromRGB(170, 90, 255),
		Enum.PartType.Ball
	)
	burst.Transparency = 0.2
	fadeOut(burst, 0.45, { Size = Vector3.new(14, 14, 14) })
end

local function shield(position: Vector3, up: boolean)
	local color = if up then Color3.fromRGB(255, 200, 90) else Color3.fromRGB(255, 255, 255)
	local ball = part(Vector3.new(4, 4, 4), CFrame.new(position), color, Enum.PartType.Ball)
	ball.Material = Enum.Material.ForceField
	fadeOut(ball, 0.6, { Size = Vector3.new(24, 24, 24) })
	if not up then
		for _ = 1, 10 do
			local shard = part(Vector3.new(0.6, 0.6, 1.8), CFrame.new(position), color, nil)
			local direction = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5).Unit
			fadeOut(shard, 0.7, { CFrame = CFrame.lookAt(position + direction * 14, position + direction * 20) })
		end
		shakeNear(position, 0.6, 0.35, 150)
	end
end

local function column(position: Vector3, color: Color3, seconds: number)
	local beam = part(Vector3.new(1.5, 40, 1.5), CFrame.new(position + Vector3.new(0, 20, 0)), color, nil)
	beam.Transparency = 0.45
	light(beam, color, 18, 2)
	task.delay(seconds, function()
		fadeOut(beam, 0.6)
	end)
end

-- One second of slow motion: everything on your character slows, the
-- colours drain and the camera leans in, while the explosions bloom.
local function slowMotion(seconds: number)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local tracks: { AnimationTrack } = {}
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:AdjustSpeed(0.2)
			table.insert(tracks, track)
		end
	end
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Saturation = -0.7
	correction.Contrast = 0.25
	correction.Parent = Lighting
	local blur = Instance.new("BlurEffect")
	blur.Size = 6
	blur.Parent = Lighting
	local camera = Workspace.CurrentCamera
	if camera then
		local fov = camera.FieldOfView
		camera.FieldOfView = fov - 12
	end
	task.delay(seconds, function()
		for _, track in tracks do
			track:AdjustSpeed(1)
		end
		tween(correction, 0.6, { Saturation = 0, Contrast = 0 })
		tween(blur, 0.6, { Size = 0 })
		task.delay(0.65, function()
			correction:Destroy()
			blur:Destroy()
		end)
	end)
end

local function bossDeath(position: Vector3, name: string)
	slowMotion(1)
	EffectsController.PlaySound(AssetIds.Sounds.Combat.BossDeath, position, 1)
	-- Slow, swelling explosions while time crawls, then the big one.
	for index = 0, 4 do
		task.delay(index * 0.2, function()
			local offset = Vector3.new(math.random(-6, 6), math.random(0, 8), math.random(-6, 6))
			local burst = part(Vector3.new(2, 2, 2), CFrame.new(position + offset), RIFT, Enum.PartType.Ball)
			light(burst, RIFT, 30, 4)
			fadeOut(burst, 1.1, { Size = Vector3.new(16, 16, 16) })
		end)
	end
	task.delay(1, function()
		EffectsController.Explosion(position, 30, Color3.fromRGB(255, 190, 90))
		local flash = part(Vector3.new(6, 6, 6), CFrame.new(position), Color3.new(1, 0.9, 0.7), Enum.PartType.Ball)
		fadeOut(flash, 0.7, { Size = Vector3.new(90, 90, 90) })
		CueController.Shake(2.2, 1)
		HudController.ShowLocation(`{string.upper(name)} DEFEATED`, "Open the chest to claim your rewards")
	end)
end

-- Dispatch --------------------------------------------------------------------------------

local function onCue(kind: any, a: any, b: any, c: any)
	local at: Vector3? = if typeof(a) == "Vector3" then a else nil
	if at == nil then
		return
	end
	if kind == "Portal" then
		portal(at, tonumber(b) or 1)
	elseif kind == "Dropship" then
		dropship(at, tonumber(b) or 3)
	elseif kind == "Telegraph" then
		telegraph(at, tonumber(b) or 12, tonumber(c) or 1.5)
	elseif kind == "Shockwave" then
		shockwave(at, tonumber(b) or 12)
	elseif kind == "SafeZone" then
		safeZone(at, tonumber(b) or 10, tonumber(c) or 6)
	elseif kind == "Nova" then
		nova(at)
	elseif kind == "Charge" then
		charge(at, tonumber(b) or 1)
	elseif kind == "Blink" then
		blink(at)
	elseif kind == "ShieldUp" or kind == "ShieldBreak" then
		shield(at, kind == "ShieldUp")
	elseif kind == "GateOpen" then
		local ring = disc(at - Vector3.new(0, 2, 0), 3, Color3.fromRGB(120, 230, 255), 0.3)
		fadeOut(ring, 0.8, { Size = Vector3.new(0.3, 30, 30) })
		EffectsController.PlaySound(AssetIds.Sounds.Combat.GateOpen, at, 0.8)
	elseif kind == "Collapse" then
		CueController.Shake(0.5, tonumber(b) or 3)
		task.delay(tonumber(b) or 3, function()
			CueController.Shake(1.6, 2)
		end)
	elseif kind == "BossIntro" then
		HudController.ShowLocation(string.upper(tostring(b or "")), if type(c) == "string" then c else nil)
	elseif kind == "BossDeath" then
		bossDeath(at, tostring(b or "Boss"))
	elseif kind == "ChestDrop" then
		column(at, GOLD, 20)
	elseif kind == "AmmoDrop" then
		column(at, Color3.fromRGB(190, 90, 255), 3)
	end
end

function CueController.Init()
	folder = Instance.new("Folder")
	folder.Name = "MissionCues"
	folder.Parent = Workspace
	ClientNet.On("WorldCue", onCue)
end

function CueController.Start()
	-- Camera shake rides on top of the camera controller's frame.
	RunService:BindToRenderStep("LastLightShake", Enum.RenderPriority.Camera.Value + 5, function()
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		if camera == nil or now >= shakeUntil then
			shakeStrength = 0
			return
		end
		local fade = math.clamp((shakeUntil - now) / 0.4, 0, 1)
		local strength = shakeStrength * fade
		local x = (math.noise(now * 18, 0.5) * 2) * strength
		local y = (math.noise(0.5, now * 18) * 2) * strength
		camera.CFrame *= CFrame.Angles(math.rad(y), math.rad(x), 0)
	end)
end

return CueController
