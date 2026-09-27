local Shared = game.ReplicatedStorage.Shared
local ConfigValidator = require(Shared.ConfigValidator)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponTypeConfig = require(Shared.Config.WeaponTypeConfig)
local PerkConfig = require(Shared.Config.PerkConfig)
local ArmorConfig = require(Shared.Config.ArmorConfig)
local ActivityConfig = require(Shared.Config.ActivityConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ClassConfig = require(Shared.Config.ClassConfig)
local PowerConfig = require(Shared.Config.PowerConfig)
local AssetIds = require(Shared.Config.AssetIds)

describe("ConfigValidator", function()
	it("finds no problems in the shipped configs", function()
		local problems = ConfigValidator.Validate()
		if #problems > 0 then
			error("config problems:\n  " .. table.concat(problems, "\n  "))
		end
	end)
end)

describe("Content targets", function()
	it("has 41 weapons: 11 Rare, 12 Epic, 12 Legendary, 6 Exotic", function()
		local counts = { Rare = 0, Epic = 0, Legendary = 0, Exotic = 0 }
		for _, weapon in WeaponConfig.List do
			counts[weapon.Rarity] += 1
		end
		expect(#WeaponConfig.List).toBe(41)
		expect(counts.Rare).toBe(11)
		expect(counts.Epic).toBe(12)
		expect(counts.Legendary).toBe(12)
		expect(counts.Exotic).toBe(6)
	end)

	it("has at least one weapon of every weapon type", function()
		for _, typeId in WeaponTypeConfig.Order do
			local found = false
			for _, weapon in WeaponConfig.List do
				if weapon.Type == typeId then
					found = true
				end
			end
			expect(found).toBeTruthy()
		end
	end)

	it("has at least 20 trait perks and a signature perk per exotic", function()
		local traits, exoticSignatures = 0, 0
		for _, perk in PerkConfig.List do
			if perk.Column == "Trait1" or perk.Column == "Trait2" then
				traits += 1
			elseif perk.Column == "Exotic" then
				exoticSignatures += 1
			end
		end
		expect(traits).toBeAtLeast(20)
		expect(exoticSignatures).toBe(6)
	end)

	it("generates a 5-piece armor set per set plus exotic armor", function()
		local exotics = 0
		for _, armor in ArmorConfig.List do
			if armor.Rarity == "Exotic" then
				exotics += 1
				expect(armor.ClassRestriction ~= nil).toBeTruthy()
			end
		end
		expect(#ArmorConfig.List).toBe(#ArmorConfig.Sets * 5 + exotics)
		expect(ArmorConfig.ById.A_FRONTIER_HELMET.Name).toBe("Frontier Issue Helm")
	end)

	it("has 8+ story missions with rising recommended power from 350 to 440", function()
		local story = {}
		for _, activity in ActivityConfig.List do
			if activity.Type == "Story" then
				table.insert(story, activity)
			end
		end
		table.sort(story, function(a, b)
			return a.Order < b.Order
		end)
		expect(#story).toBeAtLeast(8)
		expect(story[1].RecommendedPower).toBe(PowerConfig.StartingPower)
		expect(story[#story].RecommendedPower).toBe(440)
		for i = 2, #story do
			expect(story[i].RecommendedPower).toBeAtLeast(story[i - 1].RecommendedPower)
			-- Each mission unlocks from the previous one.
			expect(story[i].Unlock.Story).toBe(story[i - 1].Id)
		end
	end)

	it("gives the raid three encounters and disables power in PvP", function()
		local raid = ActivityConfig.ById.RAID_VAULT_OF_ECHOES
		expect(#raid.Encounters).toBe(3)
		expect(raid.MaxPlayers).toBe(6)
		expect(ActivityConfig.ById.PVP_PROVING_GROUNDS.PowerEnabled).toBe(false)
	end)

	it("has three factions, each with minor, major, flying and boss enemies", function()
		local seen = {}
		for _, enemy in EnemyConfig.List do
			seen[enemy.Faction] = seen[enemy.Faction] or {}
			seen[enemy.Faction][enemy.Tier] = true
			if enemy.Flying then
				seen[enemy.Faction].Flying = true
			end
		end
		local factionCount = 0
		for factionId in EnemyConfig.Factions do
			factionCount += 1
			expect(seen[factionId].Minor).toBeTruthy()
			expect(seen[factionId].Major).toBeTruthy()
			expect(seen[factionId].Boss).toBeTruthy()
			expect(seen[factionId].Flying).toBeTruthy()
		end
		expect(factionCount).toBe(3)
	end)

	it("gives every class two elemental subclasses", function()
		expect(#ClassConfig.List).toBe(3)
		for _, class in ClassConfig.List do
			expect(#class.Subclasses).toBeAtLeast(2)
		end
	end)
end)

describe("Config immutability", function()
	it("freezes config tables so runtime code cannot rebalance by accident", function()
		expect(function()
			PowerConfig.SoftCap = 999
		end).toThrow()
		expect(function()
			WeaponConfig.ById.W_FRONTIER_STANDARD.Name = "Hacked"
		end).toThrow()
		expect(function()
			PowerConfig.PowerDelta.Points[1].Outgoing = 5
		end).toThrow()
	end)

	it("returns empty strings for placeholder asset ids", function()
		expect(AssetIds.Get(0)).toBe("")
		expect(AssetIds.Get(123)).toBe("rbxassetid://123")
		expect(AssetIds.IsPlaceholder(AssetIds.Sounds.UI.Click)).toBeTruthy()
	end)
end)
