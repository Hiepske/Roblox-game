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
local DamageMath = require(Shared.Combat.DamageMath)
local ElementConfig = require(Shared.Config.ElementConfig)
local PowerMath = require(Shared.Power.PowerMath)
local WeaponStats = require(Shared.Weapons.WeaponStats)

local CombatContext = require(script.Parent.Parent.Combat.CombatContext)
local EnemyService = require(script.Parent.EnemyService)
local NetService = require(script.Parent.NetService)

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

-- A validated hitscan bullet that struck `part`.
function CombatService.HitscanHit(
	player: Player,
	part: Instance,
	position: Vector3,
	distance: number,
	stats: WeaponStats.WeaponStats
)
	local enemy = EnemyService.FromPart(part)
	if enemy == nil then
		return
	end
	local precision = EnemyService.IsPrecisionPart(enemy, part)
	local damage = DamageMath.HitDamage(stats, distance, precision, enemy.Def.CritSpot)
	CombatService.DamageEnemy(player, enemy, damage, stats.Element, precision and enemy.Def.CritSpot > 1, position)
end

-- A rocket/grenade explosion at `position`.
function CombatService.Explode(player: Player, position: Vector3, stats: WeaponStats.WeaponStats)
	local projectile = stats.Projectile
	if projectile == nil then
		return
	end
	local instanceId = player:GetAttribute("InstanceId")
	for _, enemy in
		EnemyService.InRadius(
			position,
			projectile.BlastRadius,
			if type(instanceId) == "string" then instanceId else nil
		)
	do
		local distance = math.max(0, (enemy.Root.Position - position).Magnitude - enemy.Root.Size.X)
		local damage = DamageMath.SplashDamage(stats.Damage, distance, projectile.BlastRadius)
		CombatService.DamageEnemy(player, enemy, damage, stats.Element, false, enemy.Head.Position)
	end
end

function CombatService.Init() end
function CombatService.Start() end

return CombatService
