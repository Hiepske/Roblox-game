--!strict
--[[
	CombatService
	The damage pipeline for players hitting enemies. WeaponService calls it
	for hitscan hits and rocket explosions after validating the shot.

	damage = weapon damage (WeaponStats) * range falloff * precision (headshot)
	         * power-gap multiplier (PowerMath, via CombatContext)
	         * surge modifiers * damage buffs (raid Echo Resonance)
	then EnemyService splits it between shield and health. Matching-element
	shield breaks burst and damage nearby enemies. The shooter gets a
	CombatFeedback event for hit markers and floating damage numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local DamageMath = require(Shared.Combat.DamageMath)
local ElementConfig = require(Shared.Config.ElementConfig)
local PowerMath = require(Shared.Power.PowerMath)
local WeaponStats = require(Shared.Weapons.WeaponStats)

local CombatContext = require(script.Parent.Parent.Combat.CombatContext)
local EnemyService = require(script.Parent.EnemyService)
local NetService = require(script.Parent.NetService)
local ProjectileService = require(script.Parent.ProjectileService)
local WorldService = require(script.Parent.WorldService)

local CombatService = {}

local function outgoingMultiplier(player: Player, element: string): (number, CombatContext.Context)
	local context = CombatContext.Get(player)
	local outgoing = PowerMath.CombatMultipliers({
		CharacterPower = context.CharacterPower,
		ArtifactLevel = context.ArtifactLevel,
		ActivityPower = context.ActivityPower,
		PowerEnabled = context.PowerEnabled,
		DeltaCap = context.DeltaCap,
	})
	local surge = if context.Effects then context.Effects.Surges[element] or 0 else 0
	return outgoing * (1 + surge) * context.DamageBuff, context
end

-- Deals already-computed weapon damage to an enemy and reports it to the shooter.
function CombatService.DamageEnemy(
	player: Player,
	enemy: EnemyService.Enemy,
	amount: number,
	element: string,
	precision: boolean,
	position: Vector3
): EnemyService.DamageResult
	local multiplier, context = outgoingMultiplier(player, element)
	local matchGame = context.Effects ~= nil and context.Effects.MatchGame
	local result = EnemyService.ApplyDamage(enemy, amount * multiplier, {
		Element = element,
		MatchGame = matchGame,
		Attacker = player,
	})
	NetService.FireClient(player, "CombatFeedback", position, math.floor(result.Dealt + 0.5), precision, result.Flag)

	if result.ShieldBroken and enemy.ShieldElement == element then
		-- Matching-element shield break: a burst that hurts nearby enemies.
		local burst = ElementConfig.Shields.BreakBurst
		for _, other in EnemyService.InRadius(enemy.Root.Position, burst.Radius, enemy.InstanceId) do
			if other ~= enemy then
				local splash = EnemyService.ApplyDamage(other, burst.Damage * multiplier, {
					Element = element,
					MatchGame = matchGame,
					Attacker = player,
				})
				if splash.Dealt > 0 then
					NetService.FireClient(
						player,
						"CombatFeedback",
						other.Head.Position,
						math.floor(splash.Dealt + 0.5),
						false,
						splash.Flag
					)
				end
			end
		end
	end
	return result
end

local function instanceOf(player: Player): string?
	local instanceId = player:GetAttribute("InstanceId")
	return if type(instanceId) == "string" then instanceId else nil
end

local function elementColor(element: string): Color3
	local def = ElementConfig.Elements[element]
	return if def then def.Color else Color3.new(1, 1, 1)
end

-- Sends a visual effect to everyone (explosions, arcs, singularities, slashes).
function CombatService.Effect(kind: string, ...: any)
	NetService.FireAllClients("WorldEffect", kind, ...)
end

-- A validated hitscan bullet that struck `part`. Returns the enemy hit (if
-- any) and the damage result.
function CombatService.HitscanHit(
	player: Player,
	part: Instance,
	position: Vector3,
	distance: number,
	stats: WeaponStats.WeaponStats
): (EnemyService.Enemy?, EnemyService.DamageResult?)
	local enemy = EnemyService.FromPart(part)
	if enemy == nil then
		return nil, nil
	end
	local precision = EnemyService.IsPrecisionPart(enemy, part)
	local damage = DamageMath.HitDamage(stats, distance, precision, enemy.Def.CritSpot)
	local result =
		CombatService.DamageEnemy(player, enemy, damage, stats.Element, precision and enemy.Def.CritSpot > 1, position)
	return enemy, result
end

-- Living enemies near `position` in the player's activity instance.
function CombatService.Nearby(player: Player, position: Vector3, radius: number): { EnemyService.Enemy }
	return EnemyService.InRadius(position, radius, instanceOf(player))
end

-- Damages every enemy near `position` (splash falls off toward the edge).
function CombatService.ExplodeAt(
	player: Player,
	position: Vector3,
	radius: number,
	damage: number,
	element: string,
	showEffect: boolean?
)
	if showEffect then
		CombatService.Effect("Explosion", position, radius, elementColor(element))
	end
	for _, enemy in EnemyService.InRadius(position, radius, instanceOf(player)) do
		local distance = math.max(0, (enemy.Root.Position - position).Magnitude - enemy.Root.Size.X)
		CombatService.DamageEnemy(
			player,
			enemy,
			DamageMath.SplashDamage(damage, distance, radius),
			element,
			false,
			enemy.Head.Position
		)
	end
end

-- Choir of Cinders: bomblets fly at up to `count` nearby enemies (or spread out).
local function clusterBomblets(
	player: Player,
	position: Vector3,
	stats: WeaponStats.WeaponStats,
	exotic: WeaponStats.ExoticEffect
)
	local targets = EnemyService.InRadius(position, exotic.Radius, instanceOf(player))
	local color = elementColor(stats.Element)
	local count = math.floor(exotic.Value)
	for index = 1, count do
		local target = targets[(index - 1) % math.max(1, #targets) + 1]
		local aim = if target
			then target.Root.Position
			else position + Vector3.new(
				math.cos(index * 1.05) * exotic.Radius * 0.6,
				-2,
				math.sin(index * 1.05) * exotic.Radius * 0.6
			)
		local origin = position + Vector3.new(0, 3, 0)
		local direction = aim - origin
		local speed = 70
		ProjectileService.Spawn({
			Origin = origin,
			Velocity = direction.Unit * speed + Vector3.new(0, 12, 0),
			MaxDistance = exotic.Radius * 2.5,
			Style = "Bomblet",
			Color = color,
			Exclude = WorldService.PlayerCharacters(),
			BlastRadius = 5,
			Gravity = 40,
			OnHit = function(_result: RaycastResult?, hitPosition: Vector3)
				CombatService.ExplodeAt(player, hitPosition, 5, stats.Damage * 0.3, stats.Element, false)
			end,
		})
	end
end

-- A rocket/grenade explosion at `position`.
function CombatService.Explode(player: Player, position: Vector3, stats: WeaponStats.WeaponStats)
	local projectile = stats.Projectile
	if projectile == nil then
		return
	end
	CombatService.ExplodeAt(player, position, projectile.BlastRadius, stats.Damage, stats.Element, false)
	local exotic = stats.Exotic
	if exotic and exotic.Kind == "ClusterBomblets" then
		clusterBomblets(player, position, stats, exotic)
	end
end

-- Lightning arcs from `source` to up to `count` other enemies nearby.
function CombatService.Chain(
	player: Player,
	source: EnemyService.Enemy,
	radius: number,
	damage: number,
	element: string,
	count: number
)
	local from = source.Root.Position
	local hits = 0
	for _, enemy in EnemyService.InRadius(from, radius, source.InstanceId) do
		if enemy ~= source and hits < count then
			hits += 1
			CombatService.Effect("Arc", from, enemy.Root.Position, elementColor(element))
			CombatService.DamageEnemy(player, enemy, damage, element, false, enemy.Head.Position)
		end
	end
end

-- Collapse Point: a field that damages enemies inside it every half second.
function CombatService.Singularity(
	player: Player,
	position: Vector3,
	radius: number,
	damagePerTick: number,
	element: string,
	duration: number
)
	CombatService.Effect("Singularity", position, radius, duration)
	local instanceId = instanceOf(player)
	task.spawn(function()
		local ticks = math.floor(duration / 0.5)
		for _ = 1, ticks do
			task.wait(0.5)
			for _, enemy in EnemyService.InRadius(position, radius, instanceId) do
				CombatService.DamageEnemy(player, enemy, damagePerTick, element, false, enemy.Head.Position)
			end
		end
	end)
end

-- A sword swing: every enemy in front of `origin` within reach takes a hit.
-- Returns how many enemies were hit.
function CombatService.Melee(player: Player, origin: CFrame, stats: WeaponStats.WeaponStats): number
	local arc = math.cos(math.rad(CombatConfig.Weapons.MeleeArc))
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z)
	look = if look.Magnitude > 0 then look.Unit else Vector3.new(0, 0, -1)
	CombatService.Effect("Slash", origin, stats.MaxRange, elementColor(stats.Element))
	local hits = 0
	for _, enemy in EnemyService.InRadius(origin.Position, stats.MaxRange, instanceOf(player)) do
		local offset = enemy.Root.Position - origin.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude < 3 or flat.Unit:Dot(look) >= arc then
			hits += 1
			CombatService.DamageEnemy(player, enemy, stats.Damage, stats.Element, false, enemy.Head.Position)
		end
	end
	return hits
end

function CombatService.Init() end
function CombatService.Start() end

return CombatService
