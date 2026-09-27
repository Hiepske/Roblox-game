local Shared = game.ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local DamageMath = require(Shared.Combat.DamageMath)
local ElementConfig = require(Shared.Config.ElementConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemRoller = require(Shared.Items.ItemRoller)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponStats = require(Shared.Weapons.WeaponStats)
local WeaponTypeConfig = require(Shared.Config.WeaponTypeConfig)

local rng = VirtualGame.Random.new(99)

local function starter(slot)
	local defId = GameConfig.NewPlayer.StarterLoadout[slot]
	return ItemRoller.Roll(defId, 350, rng, "uid-" .. slot, 0, "Base")
end

describe("WeaponStats", function()
	it("matches the requested starter loadout", function()
		local kinetic = WeaponStats.Compute(starter("Kinetic"))
		expect(kinetic.Type).toBe("AutoRifle")
		expect(kinetic.Rpm).toBe(600)
		expect(kinetic.Magazine).toBe(36)
		expect(kinetic.Reserves).toBeNil() -- primary: infinite

		local energy = WeaponStats.Compute(starter("Energy"))
		expect(energy.Type).toBe("HandCannon")
		expect(energy.Slot).toBe("Energy")
		expect(energy.Rpm).toBe(140)
		expect(energy.Magazine).toBe(12)
		expect(energy.PrecisionMultiplier).toBeAtLeast(2)

		local heavy = WeaponStats.Compute(starter("Heavy"))
		expect(heavy.Type).toBe("RocketLauncher")
		expect(heavy.Magazine).toBe(1)
		expect(heavy.Reserves).toBe(WeaponTypeConfig.Types.RocketLauncher.Reserves)
		expect(heavy.Projectile.BlastRadius).toBeAtLeast(1)
	end)

	it("applies perk stat modifiers, masterwork and magazine scaling", function()
		local item = ItemRoller.Roll("W_HALCYON_VERDICT", 400, rng, "uid-x", 0, "Base")
		item.Perks = { "BARREL_LONG_RAIL", "MAG_EXTENDED", "SWIFT_RECHAMBER", "TEMPO_SURGE" }
		item.Masterwork = "Stability"
		local base = item.Stats
		local final = WeaponStats.FinalStats(item)
		expect(final.Range).toBe(math.min(100, base.Range + 10))
		expect(final.Handling).toBe(math.max(0, base.Handling - 5))
		expect(final.Stability).toBe(math.min(100, base.Stability + 10))
		local stats = WeaponStats.Compute(item)
		expect(stats.Magazine).toBe(math.floor(12 * 1.25))
	end)

	it("maps stats onto damage, reload and swap time", function()
		local item = ItemRoller.Roll("W_FRONTIER_STANDARD", 350, rng, "uid-y", 0, "Base")
		item.Stats.Impact = 50
		item.Stats.Reload = 50
		item.Stats.Handling = 50
		local stats = WeaponStats.Compute(item)
		local archetype = WeaponTypeConfig.Types.AutoRifle
		expect(stats.Damage).toBeNear(archetype.BaseDamage, 1e-9)
		expect(stats.ReloadTime).toBeNear(archetype.ReloadTime, 1e-9)
		expect(stats.SwapTime).toBeNear(archetype.SwapTime, 1e-9)
		item.Stats.Reload = 100
		expect(WeaponStats.Compute(item).ReloadTime).toBeNear(
			archetype.ReloadTime * CombatConfig.WeaponStats.ReloadScaleFast,
			1e-9
		)
	end)

	it("computes stats for every weapon in the game", function()
		for _, weapon in WeaponConfig.List do
			local item = ItemRoller.Roll(weapon.Id, 400, rng, "uid-" .. weapon.Id, 0, "Random")
			local stats = WeaponStats.Compute(item)
			expect(stats ~= nil).toBe(true)
			expect(stats.FireInterval).toBeNear(60 / stats.Rpm, 1e-9)
			expect(stats.Magazine).toBeAtLeast(1)
			expect(stats.Damage).toBeAtLeast(1)
		end
	end)
end)

describe("DamageMath", function()
	it("falls off linearly between start and end", function()
		expect(DamageMath.Falloff(10, 20, 40, 0.5)).toBe(1)
		expect(DamageMath.Falloff(30, 20, 40, 0.5)).toBeNear(0.75, 1e-9)
		expect(DamageMath.Falloff(100, 20, 40, 0.5)).toBe(0.5)
	end)

	it("applies precision only when the target has a crit spot", function()
		local stats = { Damage = 50, PrecisionMultiplier = 2, FalloffStart = 100, FalloffEnd = 200, FalloffMin = 0.5 }
		expect(DamageMath.HitDamage(stats, 10, false, 1.5)).toBe(50)
		expect(DamageMath.HitDamage(stats, 10, true, 1.5)).toBe(100)
		expect(DamageMath.HitDamage(stats, 10, true, 1)).toBe(50)
	end)

	it("weakens explosions toward the edge", function()
		expect(DamageMath.SplashDamage(100, 0, 10)).toBe(100)
		expect(DamageMath.SplashDamage(100, 10, 10)).toBeNear(100 * CombatConfig.Weapons.SplashEdgeMultiplier, 1e-9)
	end)

	it("breaks matching shields faster and carries overflow into health", function()
		local match = ElementConfig.Shields.MatchMultiplier
		local result = DamageMath.ApplyToTarget(100, 100, 500, "Flare", "Flare", false)
		-- 100 raw * match multiplier breaks a 100 shield using 100/match raw damage.
		expect(result.ShieldBroken).toBe(true)
		expect(result.Shield).toBe(0)
		expect(result.Health).toBeNear(500 - (100 - 100 / match), 1e-9)

		local partial = DamageMath.ApplyToTarget(10, 100, 500, "Kinetic", "Flare", false)
		expect(partial.Shield).toBeNear(100 - 10 * ElementConfig.Shields.KineticMultiplier, 1e-9)
		expect(partial.Health).toBe(500)
	end)

	it("ignores mismatched elements on shields in Match Game", function()
		local result = DamageMath.ApplyToTarget(100, 50, 500, "Storm", "Flare", true)
		expect(result.Shield).toBe(50)
		expect(result.Health).toBe(500)
		expect(DamageMath.ApplyToTarget(100, 50, 500, "Flare", "Flare", true).ShieldBroken).toBe(true)
	end)

	it("gives kinetic weapons a bonus against unshielded targets and never overkills", function()
		local result = DamageMath.ApplyToTarget(100, 0, 500, "Kinetic", nil, false)
		expect(result.Health).toBeNear(500 - 100 * ElementConfig.KineticUnshieldedBonus, 1e-9)
		expect(DamageMath.ApplyToTarget(1000, 0, 50, "Flare", nil, false).HealthDamage).toBe(50)
	end)
end)
