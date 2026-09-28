-- Pure rules of the zone flow: zone lists, fireteam scaling, wave sizes,
-- map requirements and the zone timing log.
local Shared = game.ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local BossConfig = require(Shared.Config.BossConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local MissionRules = require(Shared.Activities.MissionRules)

describe("Zone lists", function()
	it("walks a mission's zones in order", function()
		local list = MissionRules.ZoneList(ActivityConfig.ById.STORY_01)
		expect(list[1].Zone.Id).toBe("CrashSite")
		expect(list[#list].Zone.Steps[1].Kind).toBe("Boss")
		expect(list[1].Encounter).toBeNil()
	end)

	it("restarts a raid wipe at the encounter's first zone", function()
		local encounterA = { Id = "A" }
		local encounterB = { Id = "B" }
		local list = {
			{ Zone = { Id = "1" }, Encounter = encounterA },
			{ Zone = { Id = "2" }, Encounter = encounterA },
			{ Zone = { Id = "3" }, Encounter = encounterB },
			{ Zone = { Id = "4" }, Encounter = encounterB },
			{ Zone = { Id = "5" } },
		}
		expect(MissionRules.EncounterStart(list, 2)).toBe(1)
		expect(MissionRules.EncounterStart(list, 4)).toBe(3)
		expect(MissionRules.EncounterStart(list, 3)).toBe(3)
		expect(MissionRules.EncounterStart(list, 5)).toBe(5)
	end)
end)

describe("Fireteam scaling", function()
	it("grows waves with each extra player, never below one of each", function()
		local per = CombatConfig.PartyScaling.CountPerExtraPlayer
		expect(MissionRules.ScaledCount(6, 1)).toBe(6)
		expect(MissionRules.ScaledCount(6, 3)).toBe(math.floor(6 * (1 + 2 * per) + 0.5))
		expect(MissionRules.ScaledCount(1, 1)).toBe(1)
		expect(MissionRules.ScaledCount(0, 3)).toBe(0)
		expect(MissionRules.ScaledCount(10, 6) > MissionRules.ScaledCount(10, 3)).toBe(true)
	end)

	it("scales bosses harder than regular enemies", function()
		expect(MissionRules.HealthScale(1, true)).toBe(1)
		expect(MissionRules.HealthScale(1, false)).toBe(1)
		expect(MissionRules.HealthScale(3, true) > MissionRules.HealthScale(3, false)).toBe(true)
		expect(MissionRules.HealthScale(6, true)).toBe(1 + 5 * CombatConfig.PartyScaling.BossHealthPerExtraPlayer)
	end)

	it("lists wave enemies in a fixed order with scaled counts", function()
		local wave = { Enemies = { RUST_SCRAPPER = 3, RUST_GUNNER = 4 } }
		local list = MissionRules.WaveList(wave, 1)
		expect(list[1].Id).toBe("RUST_GUNNER")
		expect(list[2].Id).toBe("RUST_SCRAPPER")
		expect(MissionRules.WaveSize(wave, 1)).toBe(7)
		expect(MissionRules.WaveSize(wave, 3) > 7).toBe(true)
	end)
end)

describe("Map requirements", function()
	it("names the markers, spawns and gates a mission needs", function()
		local kinds = {}
		for _, need in MissionRules.Requirements(ActivityConfig.ById.STORY_01) do
			kinds[need.Kind .. ":" .. need.Name] = true
		end
		expect(kinds["Marker:PlayerStart"]).toBe(true)
		expect(kinds["Marker:Wreck"]).toBe(true)
		expect(kinds["Spawns:CrashSite"]).toBe(true)
		expect(kinds["Spawns:VillageRoofs"]).toBe(true)
		expect(kinds["Marker:Uplink"]).toBe(true)
		expect(kinds["Numbered:Regulator"]).toBe(true)
		expect(kinds["Spawns:ScrapPit"]).toBe(true)
		expect(kinds["Marker:BossSpawn"]).toBe(true)
	end)

	it("keeps every boss between 15 and 30 captains of health", function()
		for _, boss in BossConfig.List do
			local multiple = EnemyConfig.ById[boss.Enemy].Health / EnemyConfig.CaptainHealth
			expect(multiple >= 15 and multiple <= 30).toBe(true)
		end
	end)
end)

describe("Zone log", function()
	it("round-trips zone times and formats clocks", function()
		local log = MissionRules.AppendZoneLog("", "Crash Site", 71.6)
		log = MissionRules.AppendZoneLog(log, "The Village; West=1", 125)
		local entries = MissionRules.ParseZoneLog(log)
		expect(#entries).toBe(2)
		expect(entries[1].Name).toBe("Crash Site")
		expect(entries[1].Seconds).toBe(72)
		expect(entries[2].Seconds).toBe(125)
		expect(MissionRules.FormatTime(125)).toBe("2:05")
		expect(MissionRules.FormatTime(5)).toBe("0:05")
	end)
end)
