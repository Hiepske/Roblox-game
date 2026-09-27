local Shared = game.ReplicatedStorage.Shared
local PowerMath = require(Shared.Power.PowerMath)
local PowerConfig = require(Shared.Config.PowerConfig)

local nextUid = 0
local function item(slot, power, rarity, location)
	nextUid += 1
	return {
		Uid = string.format("uid-%03d", nextUid),
		DefId = "TEST",
		Kind = if table.find(PowerConfig.WeaponSlots, slot) then "Weapon" else "Armor",
		Slot = slot,
		Rarity = rarity or "Legendary",
		Power = power,
		Stats = {},
		Perks = {},
		Location = location or "Inventory",
		Locked = false,
		AcquiredAt = 0,
	}
end

-- A full set of eight items at the given powers (by slot order).
local function loadout(powers)
	local items, equipped = {}, {}
	for index, slot in PowerMath.AllSlots do
		local it_ = item(slot, powers[index] or powers[1])
		items[it_.Uid] = it_
		equipped[slot] = it_.Uid
	end
	return items, equipped
end

describe("CharacterPower", function()
	it("is the floor of the average of all eight slots", function()
		local items, equipped = loadout({ 350, 351, 352, 353, 354, 355, 356, 357 })
		-- sum 2828 / 8 = 353.5 -> 353
		expect(PowerMath.CharacterPower(items, equipped)).toBe(353)
	end)

	it("counts an empty slot as zero", function()
		local items, equipped = loadout({ 400 })
		equipped.Heavy = nil
		expect(PowerMath.CharacterPower(items, equipped)).toBe(350) -- 2800 / 8
	end)
end)

describe("HighestPossible", function()
	it("uses the best item per slot, including the vault", function()
		local items = loadout({ 400 })
		local vaulted = item("Helmet", 440, "Legendary", "Vault")
		items[vaulted.Uid] = vaulted
		local power, picks = PowerMath.HighestPossible(items)
		expect(power).toBe(405) -- (400 * 7 + 440) / 8
		expect(picks.Helmet).toBe(vaulted.Uid)
	end)

	it("allows only one exotic weapon and one exotic armor piece", function()
		local items = loadout({ 400 })
		local exoticKinetic = item("Kinetic", 430, "Exotic")
		local exoticHeavy = item("Heavy", 440, "Exotic")
		local exoticHelmet = item("Helmet", 420, "Exotic")
		local exoticChest = item("Chest", 410, "Exotic")
		for _, extra in { exoticKinetic, exoticHeavy, exoticHelmet, exoticChest } do
			items[extra.Uid] = extra
		end
		local power, picks = PowerMath.HighestPossible(items)
		-- Best exotic weapon (+40 on Heavy) and best exotic armor (+20 on Helmet).
		expect(power).toBe((400 * 8 + 40 + 20) // 8)
		expect(picks.Heavy).toBe(exoticHeavy.Uid)
		expect(picks.Helmet).toBe(exoticHelmet.Uid)
		expect(picks.Kinetic ~= exoticKinetic.Uid).toBeTruthy()
		expect(picks.Chest ~= exoticChest.Uid).toBeTruthy()
	end)

	it("uses an exotic when it is the only item in a slot", function()
		local items = loadout({ 400 })
		for uid, it_ in items do
			if it_.Slot == "Heavy" then
				items[uid] = nil
			end
		end
		local exotic = item("Heavy", 380, "Exotic")
		items[exotic.Uid] = exotic
		local power, picks = PowerMath.HighestPossible(items)
		expect(picks.Heavy).toBe(exotic.Uid)
		expect(power).toBe((400 * 7 + 380) // 8)
	end)
end)

describe("RollDropPower", function()
	local rng = VirtualGame.Random.new(7)

	local function range(highest, kind, tier)
		local low, high = math.huge, -math.huge
		for _ = 1, 400 do
			local power = PowerMath.RollDropPower(highest, kind, tier, rng)
			low = math.min(low, power)
			high = math.max(high, power)
		end
		return low, high
	end

	it("rolls world drops at +0..+5 below the soft cap", function()
		local low, high = range(350, "World")
		expect(low).toBe(350)
		expect(high).toBe(355)
	end)

	it("never lets world drops pass the soft cap", function()
		local low, high = range(448, "World")
		expect(low).toBe(448)
		expect(high).toBe(PowerConfig.SoftCap)
	end)

	it("drops world loot at current power above the soft cap", function()
		local low, high = range(470, "World")
		expect(low).toBe(470)
		expect(high).toBe(470)
	end)

	it("gives Powerful rewards +3/+4/+5 by tier, capped at the powerful cap", function()
		expect((range(455, "Powerful", 1))).toBe(458)
		expect((range(455, "Powerful", 2))).toBe(459)
		expect((range(455, "Powerful", 3))).toBe(460)
		expect((range(488, "Powerful", 3))).toBe(PowerConfig.PowerfulCap)
		expect((range(PowerConfig.PowerfulCap, "Powerful", 3))).toBe(PowerConfig.PowerfulCap)
	end)

	it("gives Pinnacle rewards +1/+2 past the powerful cap, never above 500", function()
		local low, high = range(492, "Pinnacle")
		expect(low).toBe(493)
		expect(high).toBe(494)
		local capLow, capHigh = range(499, "Pinnacle")
		expect(capLow).toBe(500)
		expect(capHigh).toBe(500)
		expect((range(500, "Pinnacle"))).toBe(500)
	end)

	it("makes Pinnacle rewards at least a top-tier Powerful below the powerful cap", function()
		local low, high = range(460, "Pinnacle")
		expect(low).toBe(465)
		expect(high).toBe(465)
		-- Just under the cap a pinnacle can still step over it by its own +1/+2.
		local nearLow, nearHigh = range(489, "Pinnacle")
		expect(nearLow).toBe(490)
		expect(nearHigh).toBe(491)
	end)
end)

describe("Combat scaling", function()
	it("returns 1/1 at delta 0 and clamps at the curve ends", function()
		local out0, in0 = PowerMath.DeltaMultipliers(0)
		expect(out0).toBe(1)
		expect(in0).toBe(1)
		local points = PowerConfig.PowerDelta.Points
		local outLow, inLow = PowerMath.DeltaMultipliers(-500)
		expect(outLow).toBe(points[1].Outgoing)
		expect(inLow).toBe(points[1].Incoming)
		local outHigh = PowerMath.DeltaMultipliers(500)
		expect(outHigh).toBe(points[#points].Outgoing)
	end)

	it("interpolates between points", function()
		-- Halfway between -10 (0.82) and -5 (0.91).
		local out = PowerMath.DeltaMultipliers(-7.5)
		expect(out).toBeNear(0.865, 1e-9)
	end)

	it("punishes being far under-powered", function()
		local out, incoming = PowerMath.CombatMultipliers({
			CharacterPower = 440,
			ArtifactLevel = 0,
			ActivityPower = 470,
			PowerEnabled = true,
		})
		expect(out).toBeAtMost(0.5)
		expect(incoming).toBeAtLeast(2)
	end)

	it("adds artifact levels to combat power and respects the delta cap", function()
		local out = PowerMath.CombatMultipliers({
			CharacterPower = 490,
			ArtifactLevel = 10,
			ActivityPower = 490,
			PowerEnabled = true,
		})
		expect(out).toBeNear(1.06, 1e-9) -- delta +10
		local capped = PowerMath.CombatMultipliers({
			CharacterPower = 490,
			ArtifactLevel = 10,
			ActivityPower = 490,
			PowerEnabled = true,
			DeltaCap = 0,
		})
		expect(capped).toBe(1)
	end)

	it("ignores power entirely when the activity disables it", function()
		local out, incoming = PowerMath.CombatMultipliers({
			CharacterPower = 350,
			ArtifactLevel = 0,
			ActivityPower = 500,
			PowerEnabled = false,
		})
		expect(out).toBe(1)
		expect(incoming).toBe(1)
	end)

	it("scales enemies with activity power", function()
		local health, damage = PowerMath.ActivityEnemyScale(PowerConfig.ActivityScaling.ReferencePower)
		expect(health).toBe(1)
		expect(damage).toBe(1)
		local raidHealth = PowerMath.ActivityEnemyScale(500)
		expect(raidHealth).toBeNear(1.6, 1e-9)
	end)
end)

describe("Misc", function()
	it("reports progression stages", function()
		expect(PowerMath.Stage(350)).toBe("SoftCap")
		expect(PowerMath.Stage(450)).toBe("Powerful")
		expect(PowerMath.Stage(490)).toBe("Pinnacle")
		expect(PowerMath.Stage(500)).toBe("Max")
	end)

	it("keeps the higher power when infusing", function()
		expect(PowerMath.InfusedPower(420, 455)).toBe(455)
		expect(PowerMath.InfusedPower(460, 455)).toBe(460)
	end)

	it("computes artifact XP per level", function()
		expect(PowerMath.ArtifactXpForLevel(1)).toBe(PowerConfig.Artifact.BaseXp)
		expect(PowerMath.ArtifactXpForLevel(3)).toBe(PowerConfig.Artifact.BaseXp + 2 * PowerConfig.Artifact.XpGrowth)
		expect(PowerMath.ArtifactBonus(PowerConfig.Artifact.MaxLevel + 50)).toBe(
			PowerConfig.Artifact.MaxLevel * PowerConfig.Artifact.PowerPerLevel
		)
	end)
end)
