--!strict
--[[
	EnemyService
	Spawns enemies, runs their AI, applies damage to them and handles death.

	AI (server-side finite-state machine, CombatConfig.Enemies.TickInterval):
	  Idle    no target in range
	  Alert   just noticed a player (short pause, turns to face them)
	  Chase   walks toward the target (PathfindingService when there is no
	          line of sight, direct MoveTo when there is)
	  Attack  in range with line of sight: ranged enemies strafe and fire
	          dodgeable projectiles, melee enemies wind up and swing
	  Cover   ranged enemies that get hurt below half health dash to a spot
	          the target can't see, then come back out
	Roles with their own brains: Flying drones circle and strafe their target
	(moved every frame), Snipers paint you with a red laser before a
	high-damage shot, Turrets swivel and fire bursts, Objects (generators,
	pylons) do nothing but soak damage.
	Targets are players in the same activity instance (player attribute
	"InstanceId", nil in the hub).

	Health, shields and damage live here (not on the Humanoid) so shields,
	immunity phases and dummies are easy. Health and damage are scaled by the
	activity's recommended power when spawned (ActivityService passes
	HealthScale/DamageScale); the power gap is applied per hit by CombatService.
]]

local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AssetIds = require(Shared.Config.AssetIds)
local CombatConfig = require(Shared.Config.CombatConfig)
local DamageMath = require(Shared.Combat.DamageMath)
local ElementConfig = require(Shared.Config.ElementConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local Signal = require(Shared.Util.Signal)

local EnemyRigs = require(script.Parent.Parent.Enemies.EnemyRigs)
local CharacterService = require(script.Parent.CharacterService)
local ProjectileService = require(script.Parent.ProjectileService)
local WorldService = require(script.Parent.WorldService)

type EnemyDef = EnemyConfig.EnemyDef

export type AIState = "Idle" | "Alert" | "Chase" | "Attack" | "Cover"

export type Enemy = {
	Id: number,
	Def: EnemyDef,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Head: BasePart,
	Health: number,
	MaxHealth: number,
	Shield: number,
	MaxShield: number,
	ShieldElement: string?,
	InstanceId: string?,
	Tag: string?,
	DamageScale: number,
	AggroRange: number,
	IsBoss: boolean,
	Immune: boolean,
	Enraged: boolean,
	Dead: boolean,
	-- Who landed the killing blow (nil for falls and despawns).
	Killer: Player?,
	-- AI
	State: AIState,
	Target: Player?,
	LastSeen: number,
	AlertUntil: number,
	NextAttack: number,
	NextThink: number,
	NextStrafe: number,
	WindupUntil: number?,
	CoverUntil: number,
	CoverReadyAt: number,
	LastDamagedAt: number,
	Path: { Vector3 }?,
	PathJumps: { boolean }?,
	PathIndex: number,
	PathGoal: Vector3?,
	PathComputing: boolean,
	NextPathAt: number,
	-- Boss scripts pause the AI (special attacks, teleports) until this os.clock().
	BusyUntil: number,
	-- Damage can't take health below this (boss immune-phase thresholds; 0 = off).
	HealthFloor: number,
	-- "Humanoid" | "Drone" | "Turret" | "Object" (EnemyRigs)
	Rig: string,
	-- Drones: where they're flying to, and which way they circle.
	FlyGoal: Vector3?,
	OrbitAngle: number,
	OrbitDirection: number,
	-- Snipers: the laser (dot part at the aim point) while winding up.
	Laser: { Dot: BasePart, Beam: Beam, Aim: Vector3, LockAt: number, FireAt: number }?,
	-- Turrets: bolts left in the current burst.
	BurstLeft: number,
	-- Patrols: the route and the point walked to next.
	Patrol: { Vector3 }?,
	PatrolIndex: number,
	-- Visuals
	Bar: { Gui: BillboardGui, Health: Frame, Shield: Frame, Label: TextLabel? }?,
	Bubble: BasePart?,
	Tracks: { Idle: AnimationTrack?, Walk: AnimationTrack? },
}

export type SpawnOptions = {
	InstanceId: string?,
	Tag: string?,
	HealthScale: number?,
	DamageScale: number?,
	-- Hardened strike "Overcharged Shields": fraction of health added as shield.
	ExtraShields: number?,
	-- Hunt players across the whole map instead of waiting for them.
	Aggro: boolean?,
	-- Walk these points in a loop until someone comes close (patrols),
	-- starting from PatrolStart.
	Patrol: { Vector3 }?,
	PatrolStart: number?,
}

export type DamageInfo = {
	Element: string,
	MatchGame: boolean?,
	Attacker: Player?,
}

export type DamageResult = {
	Dealt: number,
	-- "Immune" | "Shield" | "ShieldBreak" | "Kill"
	Flag: string?,
	Killed: boolean,
	ShieldBroken: boolean,
}

local EnemyService = {}

local enemyKilled: Signal.Signal<Enemy, Player?> = Signal.new()
EnemyService.EnemyKilled = enemyKilled
local enemyDamaged: Signal.Signal<Enemy> = Signal.new()
EnemyService.EnemyDamaged = enemyDamaged

local enemies: { [number]: Enemy } = {}
local byModel: { [Model]: Enemy } = {}
local nextId = 0
local rng = Random.new()
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local BAR_COLORS = {
	Minor = Color3.fromRGB(225, 60, 60),
	Major = Color3.fromRGB(245, 200, 60),
	Boss = Color3.fromRGB(245, 200, 60),
}

-- Helpers ---------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function characterRoot(player: Player): BasePart?
	local character = CharacterService.GetCharacter(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function refreshFilters()
	local exclude: { Instance } = { WorldService.Folder("Enemies"), WorldService.Folder("Pickups") }
	losParams.FilterDescendantsInstances = exclude
	local groundExclude = table.clone(exclude)
	for _, character in WorldService.PlayerCharacters() do
		table.insert(groundExclude, character)
	end
	groundParams.FilterDescendantsInstances = groundExclude
end

-- Can `enemy` see `targetRoot`? Blocked by map geometry, not by other enemies.
local function hasLineOfSight(enemy: Enemy, targetRoot: BasePart): boolean
	local origin = enemy.Head.Position
	local offset = targetRoot.Position + Vector3.new(0, 1, 0) - origin
	local result = Workspace:Raycast(origin, offset, losParams)
	if result == nil then
		return true
	end
	local character = targetRoot.Parent
	return character ~= nil and result.Instance:IsDescendantOf(character)
end

-- Ground height below a point (nil over a hole).
local function groundAt(position: Vector3): Vector3?
	local result = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), groundParams)
	return if result then result.Position else nil
end

local function face(enemy: Enemy, target: Vector3)
	local root = enemy.Root
	local look = flat(target - root.Position)
	if look.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	local frame = CFrame.lookAt(Vector3.zero, direction)
	return (frame * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

function EnemyService.PlayerFromPart(part: Instance): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Health bar ---------------------------------------------------------------------

local function createBar(enemy: Enemy)
	local def = enemy.Def
	local tierScale = EnemyConfig.Tiers[def.Tier].BarScale
	local scale = def.Scale or 1
	local showName = def.Tier ~= "Minor" or def.Dummy == true

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = enemy.Head
	gui.Size = UDim2.fromScale(3.2 * tierScale, if showName then 1.3 else 0.5)
	gui.StudsOffset = Vector3.new(0, 1.6 * scale + 0.6, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position = UDim2.fromScale(0, 1)
	back.Size = UDim2.fromScale(1, if showName then 0.3 else 0.8)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Health"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_COLORS[def.Tier] or BAR_COLORS.Minor
	fill.BorderSizePixel = 0
	fill.Parent = back

	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.AnchorPoint = Vector2.new(0, 1)
	shield.Position = UDim2.fromScale(0, 0)
	shield.Size = UDim2.fromScale(0, 0.5)
	local element = if enemy.ShieldElement then ElementConfig.Elements[enemy.ShieldElement] else nil
	shield.BackgroundColor3 = if element then element.Color else Color3.new(1, 1, 1)
	shield.BorderSizePixel = 0
	shield.Parent = back

	local label: TextLabel? = nil
	if showName then
		local text = Instance.new("TextLabel")
		text.Name = "Name"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 0.55)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.4
		text.Text = if def.Title then `{def.Name}  ·  {def.Title}` else def.Name
		text.Parent = gui
		label = text
	end

	gui.Parent = enemy.Head
	enemy.Bar = { Gui = gui, Health = fill, Shield = shield, Label = label }
end

local function updateBar(enemy: Enemy)
	local bar = enemy.Bar
	if bar == nil then
		return
	end
	bar.Health.Size = UDim2.fromScale(math.clamp(enemy.Health / enemy.MaxHealth, 0, 1), 1)
	local shieldFraction = if enemy.MaxShield > 0 then math.clamp(enemy.Shield / enemy.MaxShield, 0, 1) else 0
	bar.Shield.Size = UDim2.fromScale(shieldFraction, 0.6)
	bar.Health.BackgroundTransparency = if enemy.Immune then 0.6 else 0
	if bar.Label then
		local def = enemy.Def
		local base = if def.Title then `{def.Name}  ·  {def.Title}` else def.Name
		bar.Label.Text = if enemy.Immune then `{base}  [IMMUNE]` else base
	end
end

-- Animation --------------------------------------------------------------------------

local function setupAnimations(enemy: Enemy)
	local humanoid = enemy.Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local set = if humanoid.RigType == Enum.HumanoidRigType.R15 then AssetIds.Animations.R15 else AssetIds.Animations.R6
	local function load(id: number): AnimationTrack?
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{id}`
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		return if ok then track else nil
	end
	enemy.Tracks.Idle = load(set.Idle)
	enemy.Tracks.Walk = load(set.Walk)
	if enemy.Tracks.Idle then
		enemy.Tracks.Idle.Looped = true
		enemy.Tracks.Idle:Play()
	end
	if enemy.Tracks.Walk then
		enemy.Tracks.Walk.Looped = true
	end
	humanoid.Running:Connect(function(speed: number)
		local walk = enemy.Tracks.Walk
		if walk == nil or enemy.Dead then
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.15)
			end
			walk:AdjustSpeed(math.clamp(speed / 14, 0.6, 1.6))
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

-- Spawning --------------------------------------------------------------------------

function EnemyService.Spawn(defId: string, cframe: CFrame, options: SpawnOptions?): Enemy?
	local def = EnemyConfig.ById[defId]
	if def == nil then
		warn(`[EnemyService] Unknown enemy {defId}`)
		return nil
	end
	local opts: SpawnOptions = options or {}
	local live = 0
	for _ in enemies do
		live += 1
	end
	if live >= EnemyConfig.AI.MaxActivePerServer and not def.Dummy then
		warn("[EnemyService] Enemy cap reached; spawn skipped")
		return nil
	end

	local model = EnemyRigs.Create(def)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if humanoid == nil or root == nil or not root:IsA("BasePart") or head == nil or not head:IsA("BasePart") then
		warn(`[EnemyService] Rig for {defId} is missing Humanoid/HumanoidRootPart/Head`)
		model:Destroy()
		return nil
	end

	-- Stand on the ground under the requested spot, facing the same way.
	model:PivotTo(CFrame.new(0, 0, 0))
	local boxCFrame, boxSize = model:GetBoundingBox()
	local rootAboveFeet = root.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	local ground = groundAt(cframe.Position) or cframe.Position
	local look = flat(cframe.LookVector)
	local rig = tostring(model:GetAttribute("Rig") or "Humanoid")
	local lift = if rig == "Drone" then CombatConfig.Enemies.DroneHover else 0
	local position = Vector3.new(cframe.Position.X, ground.Y + rootAboveFeet + 0.2 + lift, cframe.Position.Z)
	model:PivotTo(if look.Magnitude > 0.01 then CFrame.lookAt(position, position + look) else CFrame.new(position))

	local healthScale = opts.HealthScale or 1
	local maxHealth = def.Health * healthScale
	local shieldAmount = if def.Shield then def.Shield.Amount * healthScale else 0
	local shieldElement: string? = if def.Shield then def.Shield.Element else nil
	local extra = opts.ExtraShields or 0
	if extra > 0 and not def.Dummy then
		if shieldAmount > 0 then
			shieldAmount *= 1 + extra
		else
			shieldAmount = maxHealth * extra
			shieldElement = "Flare"
		end
	end

	nextId += 1
	local enemy: Enemy = {
		Id = nextId,
		Def = def,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = head,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Shield = shieldAmount,
		MaxShield = shieldAmount,
		ShieldElement = shieldElement,
		InstanceId = opts.InstanceId,
		Tag = opts.Tag,
		DamageScale = opts.DamageScale or 1,
		AggroRange = if opts.Aggro then 600 else def.Behavior.AggroRange,
		IsBoss = def.Tier == "Boss",
		Immune = false,
		Enraged = false,
		Dead = false,
		Killer = nil,
		State = "Idle",
		Target = nil,
		LastSeen = 0,
		AlertUntil = 0,
		NextAttack = os.clock() + 1 + rng:NextNumber(),
		NextThink = 0,
		NextStrafe = 0,
		WindupUntil = nil,
		CoverUntil = 0,
		CoverReadyAt = 0,
		LastDamagedAt = 0,
		Path = nil,
		PathJumps = nil,
		PathIndex = 1,
		PathGoal = nil,
		PathComputing = false,
		NextPathAt = 0,
		BusyUntil = 0,
		HealthFloor = 0,
		Rig = rig,
		FlyGoal = nil,
		OrbitAngle = rng:NextNumber() * math.pi * 2,
		OrbitDirection = if rng:NextNumber() < 0.5 then -1 else 1,
		Laser = nil,
		BurstLeft = 0,
		Patrol = opts.Patrol,
		PatrolIndex = opts.PatrolStart or 1,
		Bar = nil,
		Bubble = nil,
		Tracks = {},
	}

	humanoid.WalkSpeed = def.MoveSpeed
	humanoid.AutoRotate = def.MoveSpeed > 0 and rig == "Humanoid"
	if def.Dummy or def.MoveSpeed <= 0 or rig ~= "Humanoid" then
		root.Anchored = true
	end
	model.Parent = WorldService.Folder("Enemies")
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	enemies[enemy.Id] = enemy
	byModel[model] = enemy
	createBar(enemy)
	updateBar(enemy)
	if rig == "Humanoid" then
		setupAnimations(enemy)
	end
	return enemy
end

-- Damage and death ------------------------------------------------------------------

function EnemyService.FromPart(part: Instance): Enemy?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local enemy = byModel[model]
		if enemy then
			return if enemy.Dead then nil else enemy
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Headshots: the head and anything welded to it (eyes, helmet).
function EnemyService.IsPrecisionPart(enemy: Enemy, part: Instance): boolean
	return part == enemy.Head or part.Name == "Eye" or part.Name == "Helmet" or part.Name == "Crown"
end

local function clearLaser(enemy: Enemy)
	local laser = enemy.Laser
	if laser then
		laser.Dot:Destroy()
		enemy.Laser = nil
	end
end

local function dissolve(enemy: Enemy)
	local palette = EnemyRigs.PaletteFor(enemy.Def)
	clearLaser(enemy)
	if enemy.Bubble then
		enemy.Bubble:Destroy()
		enemy.Bubble = nil
	end
	enemy.Humanoid.Health = 0
	if enemy.Bar then
		enemy.Bar.Gui:Destroy()
		enemy.Bar = nil
	end
	for _, descendant in enemy.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Anchored = false
		end
	end
	task.delay(0.9, function()
		for _, descendant in enemy.Model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Transparency < 1 then
				descendant.Material = Enum.Material.Neon
				descendant.Color = palette.Accent
				TweenService:Create(descendant, TweenInfo.new(0.9), { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(2, function()
		enemy.Model:Destroy()
	end)
end

local function kill(enemy: Enemy, killer: Player?)
	if enemy.Dead then
		return
	end
	enemy.Dead = true
	enemy.Killer = killer
	enemies[enemy.Id] = nil
	byModel[enemy.Model] = nil
	enemyKilled:Fire(enemy, killer)
	dissolve(enemy)
end

function EnemyService.ApplyDamage(enemy: Enemy, amount: number, info: DamageInfo): DamageResult
	if enemy.Dead or amount <= 0 then
		return { Dealt = 0, Flag = nil, Killed = false, ShieldBroken = false }
	end
	if enemy.Immune then
		return { Dealt = 0, Flag = "Immune", Killed = false, ShieldBroken = false }
	end

	local result = DamageMath.ApplyToTarget(
		amount,
		enemy.Shield,
		enemy.Health,
		info.Element,
		enemy.ShieldElement,
		info.MatchGame == true
	)
	enemy.Shield = result.Shield
	enemy.Health = if enemy.HealthFloor > 0 then math.max(enemy.HealthFloor, result.Health) else result.Health
	enemy.LastDamagedAt = os.clock()
	if info.Attacker and enemy.Target == nil and enemy.InstanceId == info.Attacker:GetAttribute("InstanceId") then
		enemy.Target = info.Attacker
	end

	local flag: string? = if result.ShieldBroken
		then "ShieldBreak"
		elseif result.ShieldDamage > 0 then "Shield"
		elseif amount > 0 and result.HealthDamage == 0 and enemy.Shield > 0 then "Resisted"
		else nil

	if enemy.Def.Dummy then
		-- Dummies never die; they heal after a pause (see the Heartbeat loop).
		enemy.Health = math.max(1, enemy.Health)
	end
	updateBar(enemy)
	enemyDamaged:Fire(enemy)

	local killed = false
	if enemy.Health <= 0 then
		killed = true
		flag = "Kill"
		kill(enemy, info.Attacker)
	end
	return {
		Dealt = result.ShieldDamage + result.HealthDamage,
		Flag = flag,
		Killed = killed,
		ShieldBroken = result.ShieldBroken,
	}
end

-- Immune enemies take no damage. Bosses also show a shield bubble.
function EnemyService.SetImmune(enemy: Enemy, immune: boolean)
	enemy.Immune = immune
	updateBar(enemy)
	if not enemy.IsBoss or enemy.Dead then
		return
	end
	if immune and enemy.Bubble == nil then
		local _, size = enemy.Model:GetBoundingBox()
		local diameter = math.max(size.X, size.Y, size.Z) * 1.3
		local bubble = Instance.new("Part")
		bubble.Name = "ImmuneBubble"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.new(diameter, diameter, diameter)
		bubble.Material = Enum.Material.ForceField
		bubble.Color = EnemyRigs.PaletteFor(enemy.Def).Accent
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.Massless = true
		bubble.CastShadow = false
		bubble.CFrame = enemy.Root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = enemy.Root
		weld.Part1 = bubble
		weld.Parent = bubble
		bubble.Parent = enemy.Model
		enemy.Bubble = bubble
	elseif not immune and enemy.Bubble then
		enemy.Bubble:Destroy()
		enemy.Bubble = nil
	end
end

-- Pauses the AI (movement and normal attacks) for `seconds` (boss scripts).
function EnemyService.SetBusy(enemy: Enemy, seconds: number)
	enemy.BusyUntil = os.clock() + seconds
	enemy.WindupUntil = nil
	clearLaser(enemy)
	if enemy.Def.MoveSpeed > 0 and enemy.Rig == "Humanoid" then
		enemy.Humanoid:MoveTo(enemy.Root.Position)
	end
end

-- Kills an enemy outright (it fell off the map). Counts as a kill without a killer.
function EnemyService.Kill(enemy: Enemy)
	kill(enemy, nil)
end

-- Damage can't take the enemy's health below `floor` (0 turns it off).
function EnemyService.SetHealthFloor(enemy: Enemy, floor: number)
	enemy.HealthFloor = math.max(0, floor)
end

-- Jumps in an arc onto `landing` (a ground point) over `duration` seconds. Yields.
function EnemyService.Leap(enemy: Enemy, landing: Vector3, duration: number)
	if enemy.Dead then
		return
	end
	local root = enemy.Root
	local start = root.Position
	local ground = groundAt(start)
	local rise = if ground then start.Y - ground.Y else 3
	local finish = landing + Vector3.new(0, rise, 0)
	local look = flat(finish - start)
	local wasAnchored = root.Anchored
	root.Anchored = true
	enemy.Path = nil
	local steps = math.max(4, math.floor(duration / 0.05))
	for step = 1, steps do
		if enemy.Dead then
			return
		end
		local t = step / steps
		local position = start:Lerp(finish, t) + Vector3.new(0, math.sin(t * math.pi) * 16, 0)
		enemy.Model:PivotTo(
			if look.Magnitude > 0.1 then CFrame.lookAt(position, position + look) else CFrame.new(position)
		)
		task.wait(duration / steps)
	end
	root.Anchored = wasAnchored
end

-- Moves an enemy instantly (teleports, boss leaps).
function EnemyService.Relocate(enemy: Enemy, cframe: CFrame)
	if enemy.Dead then
		return
	end
	enemy.Path = nil
	enemy.FlyGoal = nil
	enemy.Model:PivotTo(cframe)
end

export type VolleySpec = {
	-- Where each bolt is aimed.
	Targets: { Vector3 },
	Damage: number,
	Speed: number?,
	-- Degrees of random spread per bolt.
	Spread: number?,
	Style: string?,
}

-- Fires one bolt at each target position from the enemy's head.
function EnemyService.FireVolley(enemy: Enemy, spec: VolleySpec)
	if enemy.Dead then
		return
	end
	local def = enemy.Def
	local origin = enemy.Head.Position
	local speed = spec.Speed or (if def.Projectile then def.Projectile.Speed else 90)
	local palette = EnemyRigs.PaletteFor(def)
	for _, target in spec.Targets do
		local direction = spreadDirection((target - origin).Unit, spec.Spread or 0)
		ProjectileService.Spawn({
			Origin = origin,
			Velocity = direction * speed,
			MaxDistance = math.max(200, (target - origin).Magnitude * 1.5),
			Style = spec.Style or "BossOrb",
			Color = palette.Accent,
			Exclude = { WorldService.Folder("Enemies"), WorldService.Folder("Pickups") },
			OnHit = function(result: RaycastResult?)
				if result then
					local player = EnemyService.PlayerFromPart(result.Instance)
					if player then
						CharacterService.DamagePlayer(player, spec.Damage, def.Name)
					end
				end
			end,
		})
	end
end

function EnemyService.SetEnraged(enemy: Enemy, enraged: boolean)
	enemy.Enraged = enraged
end

-- Removes an enemy without a kill (activity cleanup). Fires no signal.
function EnemyService.Despawn(enemy: Enemy)
	if enemy.Dead then
		return
	end
	enemy.Dead = true
	enemies[enemy.Id] = nil
	byModel[enemy.Model] = nil
	dissolve(enemy)
end

function EnemyService.DespawnInstance(instanceId: string)
	for _, enemy in enemies do
		if enemy.InstanceId == instanceId then
			EnemyService.Despawn(enemy)
		end
	end
end

function EnemyService.GetEnemies(instanceId: string?): { Enemy }
	local list = {}
	for _, enemy in enemies do
		if enemy.InstanceId == instanceId then
			table.insert(list, enemy)
		end
	end
	return list
end

-- Living enemies within `radius` of `position` (optionally in one instance).
function EnemyService.InRadius(position: Vector3, radius: number, instanceId: string?): { Enemy }
	local list = {}
	for _, enemy in enemies do
		if
			enemy.InstanceId == instanceId
			and (enemy.Root.Position - position).Magnitude <= radius + enemy.Root.Size.X
		then
			table.insert(list, enemy)
		end
	end
	return list
end

-- AI ------------------------------------------------------------------------------

local function acquireTarget(enemy: Enemy, now: number): (Player?, BasePart?)
	local current = enemy.Target
	if current and current.Parent == Players and current:GetAttribute("InstanceId") == enemy.InstanceId then
		local root = characterRoot(current)
		if root and now - enemy.LastSeen < EnemyConfig.AI.LoseTargetAfter + 4 then
			return current, root
		end
	end
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDistance = enemy.AggroRange
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InstanceId") == enemy.InstanceId then
			local root = characterRoot(player)
			if root then
				local distance = (root.Position - enemy.Root.Position).Magnitude
				if distance < bestDistance then
					best, bestRoot, bestDistance = player, root, distance
				end
			end
		end
	end
	enemy.Target = best
	if best then
		enemy.LastSeen = now
	end
	return best, bestRoot
end

local function moveTo(enemy: Enemy, point: Vector3)
	if enemy.Def.MoveSpeed > 0 then
		enemy.Humanoid:MoveTo(point)
	end
end

local function stop(enemy: Enemy)
	if enemy.Def.MoveSpeed > 0 then
		enemy.Humanoid:MoveTo(enemy.Root.Position)
	end
end

local function computePath(enemy: Enemy, goal: Vector3)
	enemy.PathComputing = true
	task.spawn(function()
		local scale = enemy.Def.Scale or 1
		local path = PathfindingService:CreatePath({
			AgentRadius = 2 * scale,
			AgentHeight = 5 * scale,
			AgentCanJump = true,
			WaypointSpacing = 6,
		})
		local ok = pcall(function()
			path:ComputeAsync(enemy.Root.Position, goal)
		end)
		enemy.PathComputing = false
		if enemy.Dead then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			local points: { Vector3 } = {}
			local jumps: { boolean } = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
				table.insert(jumps, waypoint.Action == Enum.PathWaypointAction.Jump)
			end
			enemy.Path = points
			enemy.PathJumps = jumps
			enemy.PathIndex = math.min(2, #points)
			enemy.PathGoal = goal
		else
			enemy.Path = nil
			enemy.PathJumps = nil
		end
	end)
end

-- Moves toward `goal`: straight at it when visible and close, otherwise along a path.
local function navigate(enemy: Enemy, goal: Vector3, canSee: boolean, now: number)
	if enemy.Def.MoveSpeed <= 0 then
		return
	end
	local distance = (goal - enemy.Root.Position).Magnitude
	if canSee and distance < 45 then
		enemy.Path = nil
		moveTo(enemy, goal)
		return
	end
	local stale = enemy.Path == nil
		or now >= enemy.NextPathAt
		or (enemy.PathGoal ~= nil and ((enemy.PathGoal :: Vector3) - goal).Magnitude > 10)
	if stale and not enemy.PathComputing then
		enemy.NextPathAt = now + 1.5
		computePath(enemy, goal)
	end
	local path = enemy.Path
	if path then
		local waypoint = path[enemy.PathIndex]
		if waypoint and (flat(waypoint) - flat(enemy.Root.Position)).Magnitude < 3 then
			enemy.PathIndex += 1
			waypoint = path[enemy.PathIndex]
		end
		if waypoint then
			moveTo(enemy, waypoint)
			local jumps = enemy.PathJumps
			if jumps and jumps[enemy.PathIndex] then
				enemy.Humanoid.Jump = true
			end
			return
		end
	end
	moveTo(enemy, goal)
end

-- A nearby spot the target can't see, or nil.
local function findCover(enemy: Enemy, targetRoot: BasePart): Vector3?
	local origin = enemy.Root.Position
	local eye = targetRoot.Position + Vector3.new(0, 1.5, 0)
	local start = rng:NextInteger(0, 7)
	for i = 0, 7 do
		local angle = (start + i) * math.pi / 4
		local distance = 10 + rng:NextNumber() * (EnemyConfig.AI.CoverSearchRadius - 10)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local ground = groundAt(candidate)
		if ground and math.abs(ground.Y - (origin.Y - 3)) < 6 then
			local chest = ground + Vector3.new(0, 2.5, 0)
			local blocked = Workspace:Raycast(eye, chest - eye, losParams)
			if blocked and (blocked.Position - chest).Magnitude > 2 then
				return ground
			end
		end
	end
	return nil
end

local function fire(enemy: Enemy, targetRoot: BasePart)
	local def = enemy.Def
	local origin = enemy.Head.Position + enemy.Root.CFrame.LookVector * (1.2 * (def.Scale or 1))
	local aim = targetRoot.Position + Vector3.new(0, 0.6, 0)
	local base = (aim - origin).Unit
	local tuning = CombatConfig.Enemies
	local spread = tuning.AimSpreadDegrees[def.Tier] or 4
	local speed = if def.Projectile then def.Projectile.Speed else 100
	local damage = def.Damage * enemy.DamageScale
	local count = if enemy.IsBoss then tuning.BossVolley.Count else 1
	local palette = EnemyRigs.PaletteFor(def)
	for index = 1, count do
		local yaw = math.rad((index - (count + 1) / 2) * tuning.BossVolley.SpreadDegrees)
		local direction =
			spreadDirection((CFrame.Angles(0, yaw, 0) * CFrame.new(Vector3.zero, base)).LookVector, spread)
		ProjectileService.Spawn({
			Origin = origin,
			Velocity = direction * speed,
			MaxDistance = def.AttackRange * 1.6,
			Style = if enemy.IsBoss then "BossOrb" else "EnemyBolt",
			Color = palette.Accent,
			Exclude = { WorldService.Folder("Enemies"), WorldService.Folder("Pickups") },
			OnHit = function(result: RaycastResult?)
				if result then
					local player = EnemyService.PlayerFromPart(result.Instance)
					if player then
						CharacterService.DamagePlayer(player, damage, def.Name)
					end
				end
			end,
		})
	end
end

local function thinkRanged(enemy: Enemy, targetRoot: BasePart, distance: number, canSee: boolean, now: number)
	local def = enemy.Def
	if canSee and distance <= def.AttackRange then
		enemy.State = "Attack"
		enemy.Humanoid.AutoRotate = false
		face(enemy, targetRoot.Position)
		if now >= enemy.NextAttack then
			fire(enemy, targetRoot)
			local cooldown = def.AttackCooldown
				* (if enemy.Enraged then CombatConfig.Enemies.EnragedCooldownScale else 1)
			enemy.NextAttack = now + cooldown * (0.9 + rng:NextNumber() * 0.3)
		end
		-- Keep a comfortable distance, strafing sideways in between.
		local preferred = def.Behavior.PreferredRange
		local toTarget = flat(targetRoot.Position - enemy.Root.Position).Unit
		if distance > preferred + 12 then
			moveTo(enemy, enemy.Root.Position + toTarget * 8)
		elseif distance < preferred - 12 then
			moveTo(enemy, enemy.Root.Position - toTarget * 8)
		elseif now >= enemy.NextStrafe then
			enemy.NextStrafe = now + 1.4 + rng:NextNumber()
			local side = Vector3.new(-toTarget.Z, 0, toTarget.X) * (if rng:NextNumber() < 0.5 then -1 else 1)
			local point = enemy.Root.Position + side * (6 + rng:NextNumber() * 5)
			if groundAt(point) then
				moveTo(enemy, point)
			end
		end
	else
		enemy.State = "Chase"
		enemy.Humanoid.AutoRotate = true
		navigate(enemy, targetRoot.Position, canSee, now)
	end
end

local function thinkMelee(
	enemy: Enemy,
	target: Player,
	targetRoot: BasePart,
	distance: number,
	canSee: boolean,
	now: number
)
	local def = enemy.Def
	local windup = enemy.WindupUntil
	if windup then
		face(enemy, targetRoot.Position)
		if now >= windup then
			enemy.WindupUntil = nil
			enemy.NextAttack = now + def.AttackCooldown
			if distance <= def.AttackRange + 2.5 then
				CharacterService.DamagePlayer(target, def.Damage * enemy.DamageScale, def.Name)
			end
		end
		return
	end
	if distance <= def.AttackRange and now >= enemy.NextAttack then
		enemy.State = "Attack"
		enemy.WindupUntil = now + CombatConfig.Enemies.MeleeWindup
		stop(enemy)
		return
	end
	enemy.State = "Chase"
	enemy.Humanoid.AutoRotate = true
	navigate(enemy, targetRoot.Position, canSee, now)
end

-- Drones: circle the target at PreferredRange, hovering above it, and strafe it.
local function thinkDrone(enemy: Enemy, targetRoot: BasePart, distance: number, canSee: boolean, now: number)
	local def = enemy.Def
	enemy.OrbitAngle += enemy.OrbitDirection * 0.35
	local radius = def.Behavior.PreferredRange
	local hover = CombatConfig.Enemies.DroneHover
	local center = targetRoot.Position
	local goal = center + Vector3.new(math.cos(enemy.OrbitAngle) * radius, hover, math.sin(enemy.OrbitAngle) * radius)
	-- Don't fly into walls: if the way is blocked, climb instead.
	local here = enemy.Root.Position
	local blocked = Workspace:Raycast(here, goal - here, losParams)
	if blocked and blocked.Instance.CanCollide then
		enemy.OrbitDirection = -enemy.OrbitDirection
		goal = here + Vector3.new(0, 6, 0)
	end
	enemy.FlyGoal = goal
	if canSee and distance <= def.AttackRange and now >= enemy.NextAttack then
		enemy.State = "Attack"
		fire(enemy, targetRoot)
		enemy.NextAttack = now + def.AttackCooldown * (0.8 + rng:NextNumber() * 0.5)
	else
		enemy.State = "Chase"
	end
end

-- Drones glide toward their goal every frame (they're anchored).
local function flyStep(enemy: Enemy, dt: number)
	local goal = enemy.FlyGoal
	local root = enemy.Root
	local here = root.Position
	local target = enemy.Target
	local targetRoot = if target then characterRoot(target) else nil
	local lookAt = if targetRoot then targetRoot.Position else here + root.CFrame.LookVector
	local bob = Vector3.new(0, math.sin(os.clock() * 2 + enemy.Id) * 0.04, 0)
	local nextPosition = here + bob
	if goal then
		local offset = goal - here
		local step = enemy.Def.MoveSpeed * dt
		nextPosition = if offset.Magnitude <= step then goal else here + offset.Unit * step
	end
	local flatLook = flat(lookAt - nextPosition)
	if flatLook.Magnitude < 0.1 then
		flatLook = flat(root.CFrame.LookVector)
	end
	root.CFrame = CFrame.lookAt(nextPosition, nextPosition + flatLook)
end

-- Snipers: a red laser tracks the target, locks for a moment, then fires.
local function thinkSniper(enemy: Enemy, targetRoot: BasePart, distance: number, canSee: boolean, now: number)
	local def = enemy.Def
	local tuning = CombatConfig.Enemies
	local laser = enemy.Laser
	if laser then
		enemy.State = "Attack"
		face(enemy, laser.Aim)
		if now < laser.LockAt then
			if canSee then
				laser.Aim = targetRoot.Position + Vector3.new(0, 0.8, 0)
			elseif now - enemy.LastSeen > 0.6 then
				clearLaser(enemy)
				return
			end
		else
			laser.Beam.Width0 = 0.3
			laser.Beam.Width1 = 0.3
		end
		laser.Dot.CFrame = CFrame.new(laser.Aim)
		if now >= laser.FireAt then
			local aim = laser.Aim
			clearLaser(enemy)
			EnemyService.FireVolley(enemy, {
				Targets = { aim + (aim - enemy.Head.Position).Unit * 4 },
				Damage = def.Damage * enemy.DamageScale,
				Speed = if def.Projectile then def.Projectile.Speed else 600,
				Style = "EnemyBolt",
			})
			enemy.NextAttack = now + def.AttackCooldown * (0.9 + rng:NextNumber() * 0.3)
		end
		return
	end
	if canSee and distance <= def.AttackRange then
		enemy.State = "Attack"
		enemy.Humanoid.AutoRotate = false
		stop(enemy)
		face(enemy, targetRoot.Position)
		if now >= enemy.NextAttack then
			local aim = targetRoot.Position + Vector3.new(0, 0.8, 0)
			local dot = Instance.new("Part")
			dot.Name = "LaserDot"
			dot.Shape = Enum.PartType.Ball
			dot.Size = Vector3.new(0.5, 0.5, 0.5)
			dot.Color = Color3.fromRGB(255, 30, 30)
			dot.Material = Enum.Material.Neon
			dot.Anchored = true
			dot.CanCollide = false
			dot.CanQuery = false
			dot.CanTouch = false
			dot.CastShadow = false
			dot.CFrame = CFrame.new(aim)
			local a0 = Instance.new("Attachment")
			a0.Name = "LaserOrigin"
			a0.Parent = enemy.Head
			local a1 = Instance.new("Attachment")
			a1.Parent = dot
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 40, 40))
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Width0 = 0.12
			beam.Width1 = 0.12
			beam.FaceCamera = true
			beam.Transparency = NumberSequence.new(0.15)
			beam.Parent = dot
			dot.Parent = WorldService.Folder("Enemies")
			dot.Destroying:Connect(function()
				a0:Destroy()
			end)
			enemy.Laser = {
				Dot = dot :: BasePart,
				Beam = beam,
				Aim = aim,
				LockAt = now + tuning.SniperWindup - tuning.SniperLock,
				FireAt = now + tuning.SniperWindup,
			}
		end
	else
		enemy.State = "Chase"
		enemy.Humanoid.AutoRotate = true
		navigate(enemy, targetRoot.Position, canSee, now)
	end
end

-- Turrets: swivel toward the target and fire bursts.
local function thinkTurret(enemy: Enemy, targetRoot: BasePart, distance: number, canSee: boolean, now: number)
	local def = enemy.Def
	face(enemy, targetRoot.Position)
	if not canSee or distance > def.AttackRange then
		enemy.State = "Alert"
		enemy.BurstLeft = 0
		return
	end
	enemy.State = "Attack"
	if now < enemy.NextAttack then
		return
	end
	if enemy.BurstLeft <= 0 then
		enemy.BurstLeft = CombatConfig.Enemies.TurretBurst
	end
	fire(enemy, targetRoot)
	enemy.BurstLeft -= 1
	enemy.NextAttack = if enemy.BurstLeft > 0 then now + 0.13 else now + def.AttackCooldown
end

local function think(enemy: Enemy, now: number)
	if now < enemy.BusyUntil then
		return
	end
	local target, targetRoot = acquireTarget(enemy, now)
	local route = enemy.Patrol
	if (target == nil or targetRoot == nil) and route and #route > 0 and enemy.Rig == "Humanoid" then
		-- Nobody close: walk the patrol route.
		enemy.State = "Idle"
		clearLaser(enemy)
		local point = route[enemy.PatrolIndex] or route[1]
		if (flat(point) - flat(enemy.Root.Position)).Magnitude < 4 then
			enemy.PatrolIndex = enemy.PatrolIndex % #route + 1
			point = route[enemy.PatrolIndex]
		end
		enemy.Humanoid.AutoRotate = true
		moveTo(enemy, point)
		return
	end
	if target == nil or targetRoot == nil then
		if enemy.State ~= "Idle" then
			enemy.State = "Idle"
			clearLaser(enemy)
			enemy.FlyGoal = nil
			stop(enemy)
		end
		return
	end

	local distance = (targetRoot.Position - enemy.Root.Position).Magnitude
	local canSee = hasLineOfSight(enemy, targetRoot)
	if canSee then
		enemy.LastSeen = now
	end

	if enemy.State == "Idle" then
		enemy.State = "Alert"
		enemy.AlertUntil = now + EnemyConfig.AI.AlertDelay
	end
	if enemy.State == "Alert" then
		face(enemy, targetRoot.Position)
		if now < enemy.AlertUntil then
			return
		end
		enemy.State = "Chase"
	end

	local role = enemy.Def.Role
	if enemy.Rig == "Drone" then
		thinkDrone(enemy, targetRoot, distance, canSee, now)
		return
	elseif role == "Turret" then
		thinkTurret(enemy, targetRoot, distance, canSee, now)
		return
	elseif role == "Sniper" and enemy.Laser then
		thinkSniper(enemy, targetRoot, distance, canSee, now)
		return
	end

	if enemy.State == "Cover" then
		if now < enemy.CoverUntil then
			return
		end
		enemy.State = "Chase"
	end

	local def = enemy.Def
	if
		def.Behavior.UsesCover
		and now >= enemy.CoverReadyAt
		and now - enemy.LastDamagedAt < 1
		and enemy.Health / enemy.MaxHealth < EnemyConfig.AI.CoverWhenHealthBelow
	then
		enemy.CoverReadyAt = now + 10
		local cover = findCover(enemy, targetRoot)
		if cover then
			enemy.State = "Cover"
			enemy.CoverUntil = now + EnemyConfig.AI.CoverDuration
			enemy.Humanoid.AutoRotate = true
			moveTo(enemy, cover)
			return
		end
	end

	if def.Role == "Melee" then
		thinkMelee(enemy, target, targetRoot, distance, canSee, now)
	elseif def.Role == "Sniper" then
		thinkSniper(enemy, targetRoot, distance, canSee, now)
	else
		thinkRanged(enemy, targetRoot, distance, canSee, now)
	end
end

-- Lifecycle -----------------------------------------------------------------------

function EnemyService.Init()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Enemies")
	end)
	PhysicsService:CollisionGroupSetCollidable("Enemies", "Enemies", false)
end

function EnemyService.Start()
	refreshFilters()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(refreshFilters)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(refreshFilters)
	end

	local interval = CombatConfig.Enemies.TickInterval
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for _, enemy in enemies do
			if enemy.Rig == "Drone" and not enemy.Dead and now >= enemy.BusyUntil then
				flyStep(enemy, dt)
			end
			if enemy.Def.Role == "Object" then
				continue
			elseif enemy.Def.Dummy then
				if
					(enemy.Health < enemy.MaxHealth or enemy.Shield < enemy.MaxShield)
					and now - enemy.LastDamagedAt > CombatConfig.Enemies.DummyRegenDelay
				then
					enemy.Health = enemy.MaxHealth
					enemy.Shield = enemy.MaxShield
					updateBar(enemy)
				end
			elseif not enemy.Dead and now >= enemy.NextThink then
				enemy.NextThink = now + interval * (0.8 + rng:NextNumber() * 0.4)
				local ok, err = pcall(think :: any, enemy, now)
				if not ok then
					warn(`[EnemyService] AI error for {enemy.Def.Id}: {err}`)
				end
			end
		end
	end)
end

return EnemyService
