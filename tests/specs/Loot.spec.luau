-- End-of-activity reward rules (LootService.AwardCompletion) with the
-- services it talks to replaced by small fakes.
local Shared = game.ReplicatedStorage.Shared
local Server = game.ServerScriptService
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local PowerMath = require(Shared.Power.PowerMath)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local TableUtil = require(Shared.Util.TableUtil)

local function signal()
	return {
		Connect = function()
			return {}
		end,
	}
end

local counter = 0
local function uid()
	counter += 1
	return "uid-" .. counter
end

local data
local sent = {}
local FakeData = {
	GetData = function()
		return data
	end,
	Set = function(_, path, value)
		TableUtil.SetPath(data, path, value)
	end,
	NewUid = uid,
	GiveItem = function(_, item)
		item.Location = "Inventory"
		data.Items[item.Uid] = item
		return true, "Inventory"
	end,
}
VirtualGame.Preload(Server.Services.DataService, FakeData)
VirtualGame.Preload(Server.Services.NetService, {
	FireClient = function(_, name, payload)
		table.insert(sent, { Name = name, Payload = payload })
	end,
	Notify = function() end,
})
VirtualGame.Preload(Server.Services.CharacterService, {})
VirtualGame.Preload(Server.Services.EnemyService, { EnemyKilled = signal() })
VirtualGame.Preload(Server.Services.WeaponService, {})
VirtualGame.Preload(Server.Services.WorldService, {})
VirtualGame.Services.Players = {}
VirtualGame.Services.RunService = { Heartbeat = signal() }

local LootService = require(Server.Services.LootService)

local function freshSave(power)
	data = ProfileTemplate.CreateNew(0, uid, VirtualGame.Random.new(1))
	for _, itemUid in data.Equipped do
		data.Items[itemUid].Power = power
	end
	sent = {}
end

local function complete(activityId, difficultyId)
	local activity = ActivityConfig.ById[activityId]
	local difficulty = ActivityRules.GetDifficulty(activity, difficultyId)
	local encounters = {}
	for _, encounter in activity.Encounters or {} do
		if encounter.Playable then
			table.insert(encounters, encounter)
		end
	end
	return LootService.AwardCompletion(nil, {
		Activity = activity,
		Difficulty = if difficultyId then difficulty else nil,
		Encounters = encounters,
		Title = activity.Name,
	})
end

describe("Activity rewards", function()
	it("story: 2-3 Rare/Epic drops at +0..+5 power and a loot screen", function()
		for _ = 1, 20 do
			freshSave(350)
			local awards = complete("STORY_01")
			expect(#awards >= 2 and #awards <= 3).toBe(true)
			-- Each drop is +0..+5 over the highest possible power at the time it
			-- rolls; earlier drops in the batch can nudge that up.
			local owned = {}
			for itemUid, item in data.Items do
				owned[itemUid] = item
			end
			for _, award in awards do
				owned[award.Item.Uid] = nil
			end
			for _, award in awards do
				local highest = PowerMath.HighestPossible(owned)
				expect(award.Item.Rarity == "Rare" or award.Item.Rarity == "Epic").toBe(true)
				expect(award.Item.Power >= highest and award.Item.Power <= highest + 5).toBe(true)
				expect(award.Reason).toBe("Drop")
				owned[award.Item.Uid] = award.Item
			end
			expect(sent[#sent].Name).toBe("LootAwarded")
			expect(sent[#sent].Payload.Screen).toBe(true)
		end
	end)

	it("Nightfall: Powerful the first time each week, Pinnacle at Legend", function()
		freshSave(460)
		local first = complete("NIGHTFALL", "Legend")
		local reasons = {}
		for _, award in first do
			reasons[award.Reason] = (reasons[award.Reason] or 0) + 1
		end
		expect(reasons.Powerful).toBe(1)
		expect(reasons.Pinnacle).toBe(1)
		for _, award in first do
			if award.Reason == "Powerful" then
				expect(award.Item.Power).toBe(465) -- tier 3: +5
			end
		end
		local second = complete("NIGHTFALL", "Legend")
		for _, award in second do
			expect(award.Reason ~= "Powerful" and award.Reason ~= "Pinnacle").toBe(true)
		end
	end)

	it("Nightfall Adept pays Powerful but no Pinnacle", function()
		freshSave(450)
		local awards = complete("NIGHTFALL", "Adept")
		local pinnacle = 0
		for _, award in awards do
			if award.Reason == "Pinnacle" then
				pinnacle += 1
			end
		end
		expect(pinnacle).toBe(0)
	end)

	it("raid: Pinnacle +1/+2 once per week, then a fallback drop", function()
		freshSave(495)
		local first = complete("RAID_VAULT_OF_ECHOES")
		local pinnacle = nil
		for _, award in first do
			if award.Reason == "Pinnacle" then
				pinnacle = award
			end
		end
		expect(pinnacle ~= nil).toBe(true)
		local highestBefore = 495
		expect(pinnacle.Item.Power >= highestBefore + 1 and pinnacle.Item.Power <= highestBefore + 2).toBe(true)
		-- Raid gear is Legendary, with the source's small Exotic chance.
		expect(pinnacle.Item.Rarity == "Legendary" or pinnacle.Item.Rarity == "Exotic").toBe(true)

		local second = complete("RAID_VAULT_OF_ECHOES")
		local drops = 0
		for _, award in second do
			expect(award.Reason ~= "Pinnacle").toBe(true)
			if award.Reason == "Drop" then
				drops += 1
			end
		end
		expect(drops).toBe(1)
	end)

	it("pinnacle rewards never exceed the pinnacle cap", function()
		freshSave(500)
		local awards = complete("RAID_VAULT_OF_ECHOES")
		for _, award in awards do
			expect(award.Item.Power <= 500).toBe(true)
		end
		expect(PowerMath.CharacterPower(data.Items, data.Equipped)).toBe(500)
	end)
end)
