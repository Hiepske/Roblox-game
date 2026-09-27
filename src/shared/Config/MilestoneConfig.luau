--!strict
--[[
	MilestoneConfig
	Weekly Powerful and Pinnacle reward sources. Each milestone pays out once
	per weekly reset (tracked in ProfileData.Weekly.ClaimedRewards).

	Track describes what counts toward Goal:
	  ActivityType  any completion of that activity type
	  ActivityId    completion of one specific activity
	  Difficulty    Nightfall difficulty id required
	  Encounter     a raid/dungeon encounter id
	  Event         patrol public event completions
	  Bounty        weekly bounty completions
	  Custom        a named rule implemented in code (e.g. Flawless)

	Reward.Kind is "Powerful" (with Tier 1-3) or "Pinnacle".
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type MilestoneDef = {
	Id: string,
	Name: string,
	Description: string,
	Goal: number,
	Track: {
		ActivityType: string?,
		ActivityId: string?,
		Difficulty: string?,
		Encounter: string?,
		Event: boolean?,
		Bounty: boolean?,
		-- Named rule implemented in code (e.g. "Flawless").
		Custom: string?,
	},
	Reward: { Kind: "Powerful" | "Pinnacle", Tier: number? },
	-- How many times the reward can be claimed per week (default 1).
	WeeklyLimit: number?,
}

local List: { MilestoneDef } = {
	{
		Id = "STRIKE_WEEKLY",
		Name = "Strike Commander",
		Description = "Complete 3 strikes.",
		Goal = 3,
		Track = { ActivityType = "Strike" },
		Reward = { Kind = "Powerful", Tier = 2 },
	},
	{
		Id = "PATROL_EVENTS",
		Name = "Frontier Duty",
		Description = "Complete 5 public events in patrol zones.",
		Goal = 5,
		Track = { Event = true },
		Reward = { Kind = "Powerful", Tier = 1 },
	},
	{
		Id = "PVP_WEEKLY",
		Name = "Proven",
		Description = "Complete 3 Proving Grounds matches.",
		Goal = 3,
		Track = { ActivityId = "PVP_PROVING_GROUNDS" },
		Reward = { Kind = "Powerful", Tier = 2 },
	},
	{
		Id = "WEEKLY_BOUNTIES",
		Name = "Contract Work",
		Description = "Complete weekly bounties. Each one pays out, up to 3 per week.",
		Goal = 1,
		Track = { Bounty = true },
		Reward = { Kind = "Powerful", Tier = 1 },
		WeeklyLimit = 3,
	},
	{
		Id = "NIGHTFALL_WEEKLY",
		Name = "Hollow Spire",
		Description = "Complete the weekly hardened strike on any difficulty.",
		Goal = 1,
		Track = { ActivityId = "NIGHTFALL" },
		Reward = { Kind = "Powerful", Tier = 3 },
	},
	{
		Id = "NIGHTFALL_LEGEND",
		Name = "Legend of the Hollow Spire",
		Description = "Complete the weekly hardened strike on Legend difficulty.",
		Goal = 1,
		Track = { ActivityId = "NIGHTFALL", Difficulty = "Legend" },
		Reward = { Kind = "Pinnacle" },
	},
	{
		Id = "DUNGEON_WEEKLY",
		Name = "Relic Hunter",
		Description = "Defeat Ysolde in the Sunken Reliquary.",
		Goal = 1,
		Track = { Encounter = "RELIQUARY_WARDEN" },
		Reward = { Kind = "Pinnacle" },
	},
	{
		Id = "RAID_ENCOUNTER_1",
		Name = "Vault: The Echo Chamber",
		Description = "Defeat Harrowmaw, the Echo Engine.",
		Goal = 1,
		Track = { Encounter = "THE_ECHO_CHAMBER" },
		Reward = { Kind = "Pinnacle" },
	},
	{
		Id = "RAID_ENCOUNTER_2",
		Name = "Vault: Hall of Mirrors",
		Description = "Complete the Hall of Mirrors.",
		Goal = 1,
		Track = { Encounter = "HALL_OF_MIRRORS" },
		Reward = { Kind = "Pinnacle" },
	},
	{
		Id = "RAID_ENCOUNTER_3",
		Name = "Vault: The Silent Core",
		Description = "Complete the Silent Core.",
		Goal = 1,
		Track = { Encounter = "THE_SILENT_CORE" },
		Reward = { Kind = "Pinnacle" },
	},
	{
		Id = "WEEKLY_CHALLENGE",
		Name = "Keeper's Challenge",
		Description = "Complete any strike, dungeon or raid encounter without anyone in your fireteam dying.",
		Goal = 1,
		Track = { Custom = "Flawless" },
		Reward = { Kind = "Pinnacle" },
	},
}

local ById: { [string]: MilestoneDef } = {}
for _, milestone in List do
	ById[milestone.Id] = milestone
end

return TableUtil.DeepFreeze({
	List = List,
	ById = ById,
})
