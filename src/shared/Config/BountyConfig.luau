--!strict
--[[
	BountyConfig
	Small daily/weekly tasks sold at the Bounty Board. Daily bounties expire
	at the daily reset, weekly ones at the weekly reset. Completing a weekly
	bounty also counts toward the WEEKLY_BOUNTIES milestone (Powerful T1).

	Objective.Kind values the progress tracker (Phase 7) understands:
	  Kills           Count kills, optionally filtered by Faction / WeaponType / AmmoType / Element
	  PrecisionKills  Count precision kills, optional WeaponType
	  AbilityKills    Count grenade/melee/super kills
	  Complete        Count completions of ActivityType
	  PublicEvents    Count public events
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type BountyDef = {
	Id: string,
	Name: string,
	Description: string,
	Cadence: "Daily" | "Weekly",
	Objective: {
		Kind: "Kills" | "PrecisionKills" | "AbilityKills" | "Complete" | "PublicEvents",
		Count: number,
		Faction: string?,
		WeaponType: string?,
		AmmoType: string?,
		Element: string?,
		ActivityType: string?,
	},
	XP: number,
	Cost: { [string]: number },
}

local List: { BountyDef } = {
	-- Daily ------------------------------------------------------------------------------
	{
		Id = "B_D_RUST_CULL",
		Name = "Rust Removal",
		Description = "Defeat 40 Rustborn.",
		Cadence = "Daily",
		Objective = { Kind = "Kills", Count = 40, Faction = "Rustborn" },
		XP = 4000,
		Cost = { Quanta = 500 },
	},
	{
		Id = "B_D_FOG_CLEAR",
		Name = "Clear the Fog",
		Description = "Defeat 40 Veiled.",
		Cadence = "Daily",
		Objective = { Kind = "Kills", Count = 40, Faction = "Veiled" },
		XP = 4000,
		Cost = { Quanta = 500 },
	},
	{
		Id = "B_D_DEBUG",
		Name = "Debugging",
		Description = "Defeat 40 Concord.",
		Cadence = "Daily",
		Objective = { Kind = "Kills", Count = 40, Faction = "Concord" },
		XP = 4000,
		Cost = { Quanta = 500 },
	},
	{
		Id = "B_D_HEADHUNTER",
		Name = "Steady Aim",
		Description = "Get 25 precision kills with Scout Rifles.",
		Cadence = "Daily",
		Objective = { Kind = "PrecisionKills", Count = 25, WeaponType = "ScoutRifle" },
		XP = 5000,
		Cost = { Quanta = 500 },
	},
	{
		Id = "B_D_FLARE",
		Name = "Burn Bright",
		Description = "Defeat 50 enemies with Flare damage.",
		Cadence = "Daily",
		Objective = { Kind = "Kills", Count = 50, Element = "Flare" },
		XP = 4000,
		Cost = { Quanta = 500 },
	},
	{
		Id = "B_D_ABILITIES",
		Name = "Power Within",
		Description = "Defeat 20 enemies with abilities.",
		Cadence = "Daily",
		Objective = { Kind = "AbilityKills", Count = 20 },
		XP = 4500,
		Cost = { Quanta = 500 },
	},

	-- Weekly -----------------------------------------------------------------------------
	{
		Id = "B_W_STRIKES",
		Name = "Strike Team",
		Description = "Complete 5 strikes.",
		Cadence = "Weekly",
		Objective = { Kind = "Complete", Count = 5, ActivityType = "Strike" },
		XP = 20000,
		Cost = { Quanta = 2500 },
	},
	{
		Id = "B_W_EVENTS",
		Name = "Public Servant",
		Description = "Complete 8 public events.",
		Cadence = "Weekly",
		Objective = { Kind = "PublicEvents", Count = 8 },
		XP = 20000,
		Cost = { Quanta = 2500 },
	},
	{
		Id = "B_W_HEAVY",
		Name = "Heavy Hitter",
		Description = "Defeat 150 enemies with heavy weapons.",
		Cadence = "Weekly",
		Objective = { Kind = "Kills", Count = 150, AmmoType = "Heavy" },
		XP = 20000,
		Cost = { Quanta = 2500 },
	},
	{
		Id = "B_W_STORY",
		Name = "Retrace the Signal",
		Description = "Complete 3 story missions.",
		Cadence = "Weekly",
		Objective = { Kind = "Complete", Count = 3, ActivityType = "Story" },
		XP = 18000,
		Cost = { Quanta = 2500 },
	},
}

local ById: { [string]: BountyDef } = {}
for _, bounty in List do
	ById[bounty.Id] = bounty
end

return TableUtil.DeepFreeze({
	List = List,
	ById = ById,
	-- Maximum bounties a player can hold at once.
	MaxActive = 12,
	-- How many of each cadence the board offers per reset.
	OfferedPerReset = { Daily = 4, Weekly = 3 },
})
