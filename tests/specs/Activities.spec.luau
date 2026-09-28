local Shared = game.ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local GameConfig = require(Shared.Config.GameConfig)
local LootConfig = require(Shared.Config.LootConfig)
local LootRoller = require(Shared.Items.LootRoller)
local PowerMath = require(Shared.Power.PowerMath)
local ProfileTemplate = require(game.ServerScriptService.Data.ProfileTemplate)
local TableUtil = require(Shared.Util.TableUtil)
local TimeUtil = require(Shared.Util.TimeUtil)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local ArmorConfig = require(Shared.Config.ArmorConfig)

local counter = 0
local function uid()
	counter += 1
	return string.format("00000000-0000-0000-0000-%012d", counter)
end

local NOW = 1790467200
local rng = VirtualGame.Random.new(5)

local function newProfile()
	return ProfileTemplate.CreateNew(NOW, uid, VirtualGame.Random.new(1))
end

local function setPower(data, power)
	for _, item in data.Items do
		item.Power = power
	end
end

describe("Playable activities", function()
	it("offers a story mission, a hardened strike and a raid", function()
		local types = {}
		for _, activity in ActivityRules.Playable() do
			table.insert(types, activity.Type)
		end
		expect(types).toEqual({ "Story", "Nightfall", "Raid" })
	end)

	it("locks the hardened strike until First Light is done", function()
		local data = newProfile()
		local nightfall = ActivityConfig.ById.NIGHTFALL
		local ok, reason = ActivityRules.CheckUnlock(data, nightfall)
		expect(ok).toBe(false)
		expect(reason:find("First Light", 1, true) ~= nil).toBe(true)
		data.Progress.StoryCompleted.STORY_01 = true
		expect((ActivityRules.CheckUnlock(data, nightfall))).toBe(true)
	end)

	it("locks the raid below power 480", function()
		local data = newProfile()
		local raid = ActivityConfig.ById.RAID_VAULT_OF_ECHOES
		expect((ActivityRules.CheckUnlock(data, raid))).toBe(false)
		setPower(data, 480)
		expect(PowerMath.CharacterPower(data.Items, data.Equipped)).toBe(480)
		expect((ActivityRules.CheckUnlock(data, raid))).toBe(true)
		expect(ActivityRules.MinPlayers(raid)).toBe(GameConfig.Activities.RAID_MIN_PLAYERS)
	end)

	it("resolves difficulties and their recommended power", function()
		local nightfall = ActivityConfig.ById.NIGHTFALL
		expect(ActivityRules.RecommendedPower(nightfall, "Adept")).toBe(450)
		expect(ActivityRules.RecommendedPower(nightfall, "Hero")).toBe(470)
		expect(ActivityRules.RecommendedPower(nightfall, "Legend")).toBe(490)
		expect(ActivityRules.GetDifficulty(nightfall, "Nope").Id).toBe("Adept")
		expect(ActivityRules.RecommendedPower(ActivityConfig.ById.STORY_01)).toBe(350)
	end)

	it("flattens raid encounters into zones, skipping unbuilt ones", function()
		local MissionRules = require(game.ReplicatedStorage.Shared.Activities.MissionRules)
		local list = MissionRules.ZoneList(ActivityConfig.ById.RAID_VAULT_OF_ECHOES)
		expect(#list).toBe(1)
		expect(list[1].Encounter.Id).toBe("THE_ECHO_CHAMBER")
		expect(list[1].Zone.Steps[2].Boss).toBe("HARROWMAW")
		expect(#MissionRules.ZoneList(ActivityConfig.ById.STORY_01)).toBe(4)
	end)
end)

describe("Weekly modifiers", function()
	it("picks two distinct modifiers that stay fixed within a week", function()
		local picks = ActivityRules.WeeklyModifiers(NOW)
		expect(#picks).toBe(2)
		expect(picks[1] ~= picks[2]).toBe(true)
		expect(ActivityRules.WeeklyModifiers(NOW + 3600)).toEqual(picks)
		for _, id in picks do
			expect(ActivityConfig.NightfallModifiers[id] ~= nil).toBe(true)
		end
	end)

	it("changes across weeks", function()
		local seen = {}
		for week = 0, 11 do
			seen[table.concat(ActivityRules.WeeklyModifiers(NOW + week * TimeUtil.WEEK), "+")] = true
		end
		expect(TableUtil.Count(seen)).toBeAtLeast(4)
	end)

	it("combines modifier effects", function()
		local effects = ActivityRules.CombineModifiers({ "IRONHIDE", "MATCH_GAME", "FLARE_SURGE" })
		expect(effects.EnemyHealth).toBeNear(1.3, 1e-9)
		expect(effects.MatchGame).toBe(true)
		expect(effects.Surges.Flare).toBeNear(0.25, 1e-9)
		expect(ActivityRules.CombineModifiers({}).EnemyDamage).toBe(1)
	end)
end)

describe("LootRoller", function()
	it("rolls only Rare/Epic when a story reward overrides rarities", function()
		for _ = 1, 100 do
			local item = LootRoller.RollItem("Story", 360, "World", nil, rng, uid(), NOW, "Bulwark", {
				Rarities = { Rare = 60, Epic = 40 },
				NoExotic = true,
			})
			expect(item.Rarity == "Rare" or item.Rarity == "Epic").toBe(true)
			expect(item.Power).toBeAtLeast(360)
			expect(item.Power).toBeAtMost(365)
		end
	end)

	it("gives pinnacle rewards +1/+2 near the cap", function()
		for _ = 1, 50 do
			local item = LootRoller.RollItem("Raid", 495, "Pinnacle", nil, rng, uid(), NOW, "Ranger")
			expect(item.Power).toBeAtLeast(496)
			expect(item.Power).toBeAtMost(497)
		end
	end)

	it("never drops another class's exotic armor", function()
		for _ = 1, 50 do
			for _, defId in LootRoller.ExoticCandidates("Mystic") do
				local armor = ArmorConfig.ById[defId]
				if armor then
					expect(armor.ClassRestriction == nil or armor.ClassRestriction == "Mystic").toBe(true)
				end
			end
		end
	end)

	it("draws raid-exclusive drops only from raid gear", function()
		for _ = 1, 60 do
			local defId = LootRoller.RollDefId("Raid", rng, "Bulwark", { ExclusiveOnly = true, Rarity = "Legendary" })
			local def = WeaponConfig.ById[defId] or ArmorConfig.ById[defId]
			expect(table.find(def.Sources, "Raid") ~= nil).toBe(true)
			expect(def.Rarity).toBe("Legendary")
		end
	end)

	it("can roll something from every loot source", function()
		for sourceId in LootConfig.Sources do
			for _ = 1, 20 do
				expect(LootRoller.RollDefId(sourceId, rng, "Bulwark") ~= nil).toBe(true)
			end
		end
	end)
end)
