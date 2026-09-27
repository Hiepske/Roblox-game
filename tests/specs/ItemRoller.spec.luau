local Shared = game.ReplicatedStorage.Shared
local ArmorConfig = require(Shared.Config.ArmorConfig)
local ItemRoller = require(Shared.Items.ItemRoller)
local PerkConfig = require(Shared.Config.PerkConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local TableUtil = require(Shared.Util.TableUtil)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponTypeConfig = require(Shared.Config.WeaponTypeConfig)

local rng = VirtualGame.Random.new(12345)
local counter = 0
local function uid()
	counter += 1
	return string.format("00000000-0000-0000-0000-%012d", counter)
end

describe("Weapon rolls", function()
	it("keeps every stat inside base + bias + rarity roll range", function()
		for _, weapon in WeaponConfig.List do
			local archetype = WeaponTypeConfig.Types[weapon.Type]
			local roll = RarityConfig.Tiers[weapon.Rarity].WeaponStatRoll
			for _ = 1, 25 do
				local item = ItemRoller.RollWeapon(weapon, 400, rng, uid(), 0, "Random")
				for _, stat in WeaponTypeConfig.RolledStats do
					local expected = archetype.BaseStats[stat]
						+ (if weapon.StatBias then weapon.StatBias[stat] or 0 else 0)
					local value = item.Stats[stat]
					expect(value).toBeAtLeast(math.max(0, expected + roll.Min))
					expect(value).toBeAtMost(math.min(100, expected + roll.Max))
				end
			end
		end
	end)

	it("rolls the right perk layout for each rarity", function()
		for _, weapon in WeaponConfig.List do
			local tier = RarityConfig.Tiers[weapon.Rarity]
			for _ = 1, 10 do
				local item = ItemRoller.RollWeapon(weapon, 400, rng, uid(), 0, "Random")
				if weapon.FixedPerks then
					expect(item.Perks).toEqual(weapon.FixedPerks)
				elseif tier.WeaponPerkMode == "Random1" then
					expect(#item.Perks).toBe(1)
					local column = PerkConfig.ById[item.Perks[1]].Column
					expect(column == "Trait1" or column == "Trait2").toBeTruthy()
				else
					expect(#item.Perks).toBe(#tier.WeaponColumns)
					for index, column in tier.WeaponColumns do
						expect(PerkConfig.ById[item.Perks[index]].Column).toBe(column)
					end
				end
				for _, perkId in item.Perks do
					expect(PerkConfig.ById[perkId].AppliesTo).toContain(weapon.Type)
				end
				if tier.MasterworkOnDrop then
					expect(RarityConfig.MasterworkStats).toContain(item.Masterwork)
				else
					expect(item.Masterwork).toBeNil()
				end
			end
		end
	end)

	it("produces varied Legendary rolls (some good, some bad)", function()
		local weapon = WeaponConfig.ById.W_HALCYON_VERDICT
		local seen = {}
		local qualities = {}
		for _ = 1, 200 do
			local item = ItemRoller.RollWeapon(weapon, 400, rng, uid(), 0, "Random")
			seen[table.concat(item.Perks, "+")] = true
			table.insert(qualities, ItemRoller.RollQuality(item))
		end
		expect(TableUtil.Count(seen)).toBeAtLeast(20)
		table.sort(qualities)
		expect(qualities[1]).toBeAtMost(0.3)
		expect(qualities[#qualities]).toBeAtLeast(0.7)
	end)

	it("rolls deterministically in Base mode", function()
		local weapon = WeaponConfig.ById.W_FRONTIER_STANDARD
		local a = ItemRoller.RollWeapon(weapon, 350, rng, "a", 0, "Base")
		local b = ItemRoller.RollWeapon(weapon, 350, rng, "b", 0, "Base")
		expect(a.Stats).toEqual(b.Stats)
		expect(a.Perks).toEqual(b.Perks)
		expect(a.Stats.Impact).toBe(WeaponTypeConfig.Types.AutoRifle.BaseStats.Impact)
	end)

	it("clamps power into the valid range", function()
		local weapon = WeaponConfig.ById.W_FRONTIER_STANDARD
		expect(ItemRoller.RollWeapon(weapon, 9999, rng, uid(), 0, "Base").Power).toBe(500)
		expect(ItemRoller.RollWeapon(weapon, 401.9, rng, uid(), 0, "Base").Power).toBe(401)
	end)
end)

describe("Armor rolls", function()
	it("keeps totals within the rarity range and each stat within bounds", function()
		for _, armor in ArmorConfig.List do
			local total = RarityConfig.Tiers[armor.Rarity].ArmorTotal
			for _ = 1, 20 do
				local item = ItemRoller.RollArmor(armor, 400, rng, uid(), 0, "Random")
				local sum = 0
				for _, stat in ArmorConfig.StatOrder do
					local value = item.Stats[stat]
					expect(value).toBeAtLeast(ArmorConfig.StatMinPerPiece)
					expect(value).toBeAtMost(ArmorConfig.StatMaxPerPiece)
					sum += value
				end
				expect(sum).toBeAtLeast(total.Min)
				expect(sum).toBeAtMost(total.Max)
			end
		end
	end)

	it("gives exotic armor its signature perk", function()
		local item = ItemRoller.RollArmor(ArmorConfig.ById.A_EXO_QUICKSTEP, 400, rng, uid(), 0, "Random")
		expect(item.Perks).toEqual({ "EXA_QUICKSTEP" })
	end)

	it("spreads Base-mode points evenly", function()
		local item = ItemRoller.RollArmor(ArmorConfig.ById.A_FRONTIER_HELMET, 350, rng, uid(), 0, "Base")
		local low, high = math.huge, -math.huge
		for _, value in item.Stats do
			low = math.min(low, value)
			high = math.max(high, value)
		end
		expect(high - low).toBeAtMost(1)
	end)
end)

describe("God rolls", function()
	it("detects synergy pairs and requires a strong stat roll", function()
		local weapon = WeaponConfig.ById.W_HALCYON_VERDICT
		local item = ItemRoller.RollWeapon(weapon, 400, rng, uid(), 0, "Base")
		item.Perks = { "BARREL_STABILIZED", "MAG_DENSE", "SWIFT_RECHAMBER", "TEMPO_SURGE" }
		expect(ItemRoller.HasSynergy(item)).toBeTruthy()
		local roll = RarityConfig.Tiers.Legendary.WeaponStatRoll
		for _, stat in WeaponTypeConfig.RolledStats do
			item.Stats[stat] += roll.Max -- best possible roll
		end
		expect(ItemRoller.IsGodRoll(item)).toBeTruthy()
		item.Perks = { "BARREL_STABILIZED", "MAG_DENSE", "AUTO_CYCLE", "TEMPO_SURGE" }
		expect(ItemRoller.IsGodRoll(item)).toBeFalsy()
	end)

	it("returns nil for unknown def ids", function()
		expect(ItemRoller.Roll("NOPE", 400, rng, uid(), 0)).toBeNil()
	end)
end)
