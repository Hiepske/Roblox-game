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

describe("Weapon types", function()
	local function stats(defId)
		return WeaponStats.Compute(ItemRoller.Roll(defId, 350, rng, "uid-" .. defId, 0, "Base"))
	end

	it("gives every fire mode what it needs", function()
		expect(stats("W_DOORKICKER").Pellets).toBe(12)
		expect(stats("W_CADENCE_OF_IRON").BurstCount).toBe(3)
		local fusion = stats("W_LANTERN_COIL")
		expect(fusion.ChargeTime > 0).toBe(true)
		expect(fusion.Pellets > 1).toBe(true)
		expect(stats("W_MOTH_AND_EMBER").Projectile.Gravity > 0).toBe(true)
		expect(stats("W_SCRAPFIRE_TUBE").Projectile.Gravity).toBeNil()
		expect(stats("W_GROUNDSKEEPER").FireMode).toBe("Melee")
		expect(stats("W_SLOW_DAWN").AdsFov < 25).toBe(true)
	end)

	it("has at least 25 weapons covering every required type and tier", function()
		local types, rarities, slots = {}, {}, {}
		for _, weapon in WeaponConfig.List do
			types[weapon.Type] = true
			rarities[weapon.Rarity] = true
			slots[weapon.Slot] = true
		end
		expect(#WeaponConfig.List >= 25).toBe(true)
		for _, required in
			{
				"AutoRifle",
				"PulseRifle",
				"ScoutRifle",
				"HandCannon",
				"SMG",
				"Shotgun",
				"SniperRifle",
				"GrenadeLauncher",
				"RocketLauncher",
				"MachineGun",
				"Sword",
			}
		do
			expect(types[required]).toBe(true)
		end
		for _, rarity in { "Rare", "Epic", "Legendary", "Exotic" } do
			expect(rarities[rarity]).toBe(true)
		end
		for _, slot in { "Kinetic", "Energy", "Heavy" } do
			expect(slots[slot]).toBe(true)
		end
	end)

	it("gives the exotics their unique mechanics", function()
		expect(stats("W_WIDOWS_TALLY").Exotic.Kind).toBe("Explosion")
		expect(stats("W_STARFALL_CHORUS").Exotic.Kind).toBe("ClusterBomblets")
		expect(stats("W_PERPETUAL_ENGINE").Exotic.Kind).toBe("RpmRampAndChain")
		expect(stats("W_FRONTIER_STANDARD").Exotic).toBeNil()
	end)

	it("has a raid-exclusive set that drops nowhere else", function()
		local exclusive = 0
		for _, weapon in WeaponConfig.List do
			if #weapon.Sources == 1 and weapon.Sources[1] == "Raid" then
				exclusive += 1
			end
		end
		expect(exclusive >= 4).toBe(true)
	end)
end)
