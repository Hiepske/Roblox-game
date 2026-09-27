--!strict
--[[
	DamageMath
	Pure damage formulas shared by the server (authoritative) and tests.

	Order of operations for a player hitting an enemy:
	  weapon damage (WeaponStats) * range falloff * precision (head, if the
	  enemy has a crit spot) * power-gap multiplier (PowerMath) * modifiers,
	  then ApplyToTarget splits it between the shield and health.
]]

local Config = script.Parent.Parent.Config
local CombatConfig = require(Config.CombatConfig)
local ElementConfig = require(Config.ElementConfig)

local DamageMath = {}

-- 1 up to `start` studs, falling linearly to `minMultiplier` at `finish`.
function DamageMath.Falloff(distance: number, start: number, finish: number, minMultiplier: number): number
	if distance <= start then
		return 1
	elseif distance >= finish or finish <= start then
		return minMultiplier
	end
	local t = (distance - start) / (finish - start)
	return 1 + (minMultiplier - 1) * t
end

export type HitStats = {
	Damage: number,
	PrecisionMultiplier: number,
	FalloffStart: number,
	FalloffEnd: number,
	FalloffMin: number,
}

-- Damage of one bullet before power scaling and shields.
function DamageMath.HitDamage(stats: HitStats, distance: number, precision: boolean, critSpot: number): number
	local damage = stats.Damage * DamageMath.Falloff(distance, stats.FalloffStart, stats.FalloffEnd, stats.FalloffMin)
	if precision and critSpot > 1 then
		damage *= stats.PrecisionMultiplier
	end
	return damage
end

-- Explosion damage at `distance` from the center of a blast of `radius`.
function DamageMath.SplashDamage(damage: number, distance: number, radius: number): number
	if radius <= 0 then
		return damage
	end
	local t = math.clamp(distance / radius, 0, 1)
	return damage * (1 + (CombatConfig.Weapons.SplashEdgeMultiplier - 1) * t)
end

-- How effective an element is against a shield of another element.
-- In "Match Game" only the matching element does anything.
function DamageMath.ShieldMultiplier(weaponElement: string, shieldElement: string, matchGame: boolean): number
	local shields = ElementConfig.Shields
	if weaponElement == shieldElement then
		return shields.MatchMultiplier
	elseif matchGame then
		return 0
	elseif weaponElement == "Kinetic" then
		return shields.KineticMultiplier
	end
	return shields.MismatchMultiplier
end

export type DamageResult = {
	Shield: number,
	Health: number,
	ShieldDamage: number,
	HealthDamage: number,
	ShieldBroken: boolean,
}

-- Applies `amount` raw damage to a target with a shield (of `shieldElement`)
-- and health. Damage beyond what breaks the shield carries into health.
function DamageMath.ApplyToTarget(
	amount: number,
	shield: number,
	health: number,
	weaponElement: string,
	shieldElement: string?,
	matchGame: boolean
): DamageResult
	local result: DamageResult = {
		Shield = shield,
		Health = health,
		ShieldDamage = 0,
		HealthDamage = 0,
		ShieldBroken = false,
	}
	local remaining = amount

	if shield > 0 and shieldElement then
		local multiplier = DamageMath.ShieldMultiplier(weaponElement, shieldElement, matchGame)
		if multiplier <= 0 then
			return result
		end
		local shieldDamage = remaining * multiplier
		if shieldDamage < shield then
			result.Shield = shield - shieldDamage
			result.ShieldDamage = shieldDamage
			return result
		end
		result.ShieldDamage = shield
		result.Shield = 0
		result.ShieldBroken = true
		remaining -= shield / multiplier
	end

	if remaining > 0 then
		local bonus = if weaponElement == "Kinetic" then ElementConfig.KineticUnshieldedBonus else 1
		local healthDamage = math.min(health, remaining * bonus)
		result.Health = health - healthDamage
		result.HealthDamage = healthDamage
	end
	return result
end

return DamageMath
