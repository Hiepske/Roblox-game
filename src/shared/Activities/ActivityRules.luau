--!strict
--[[
	ActivityRules
	Shared rules for launching activities, used by the Director UI (to show
	locks and modifiers) and by the server (to enforce them):
	  * which activities are playable
	  * unlock requirements (story completion, power)
	  * difficulty selection and recommended power
	  * this week's hardened strike modifiers (deterministic from the reset
	    time, so every server and client agrees without talking)
	  * the flattened objective list (top-level objectives, or the playable
	    encounters' objectives for raids)
]]

local Shared = script.Parent.Parent
local ActivityConfig = require(Shared.Config.ActivityConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PowerMath = require(Shared.Power.PowerMath)
local TimeUtil = require(Shared.Util.TimeUtil)
local Types = require(Shared.Types)

type ActivityDef = ActivityConfig.ActivityDef
type DifficultyDef = ActivityConfig.DifficultyDef

local ActivityRules = {}

local WEEKLY_MODIFIER_COUNT = 2

function ActivityRules.Playable(): { ActivityDef }
	local list: { ActivityDef } = {}
	for _, activity in ActivityConfig.List do
		if activity.Playable then
			table.insert(list, activity)
		end
	end
	table.sort(list, function(a: ActivityDef, b: ActivityDef): boolean
		return a.Order < b.Order
	end)
	return list
end

-- The chosen difficulty, or the first one, or nil if the activity has none.
function ActivityRules.GetDifficulty(activity: ActivityDef, difficultyId: string?): DifficultyDef?
	local difficulties = activity.Difficulties
	if difficulties == nil or #difficulties == 0 then
		return nil
	end
	for _, difficulty in difficulties do
		if difficulty.Id == difficultyId then
			return difficulty
		end
	end
	return difficulties[1]
end

function ActivityRules.RecommendedPower(activity: ActivityDef, difficultyId: string?): number
	local difficulty = ActivityRules.GetDifficulty(activity, difficultyId)
	return if difficulty then difficulty.RecommendedPower else activity.RecommendedPower
end

-- (unlocked, reason shown to the player when locked)
function ActivityRules.CheckUnlock(data: Types.ProfileData, activity: ActivityDef): (boolean, string?)
	if not activity.Playable then
		return false, "Not available yet"
	end
	local unlock = activity.Unlock
	if unlock then
		if unlock.Story and not data.Progress.StoryCompleted[unlock.Story] then
			local mission = ActivityConfig.ById[unlock.Story]
			return false, `Complete "{if mission then mission.Name else unlock.Story}" first`
		end
		if unlock.Power then
			local power = PowerMath.CharacterPower(data.Items, data.Equipped)
			if power < unlock.Power then
				return false, `Requires power {unlock.Power} (you have {power})`
			end
		end
	end
	return true, nil
end

-- Minimum fireteam size to launch (the raid uses GameConfig's testing value).
function ActivityRules.MinPlayers(activity: ActivityDef): number
	if activity.Type == "Raid" then
		return GameConfig.Activities.RAID_MIN_PLAYERS
	end
	return activity.MinPlayers
end

-- Deterministic pseudo-random pick of this week's modifier ids.
function ActivityRules.WeeklyModifiers(now: number): { string }
	local resets = GameConfig.Resets
	local weekStart = TimeUtil.GetLastWeeklyReset(now, resets.WeeklyWeekday, resets.HourUtc)
	local ids: { string } = {}
	for id in ActivityConfig.NightfallModifiers do
		table.insert(ids, id)
	end
	table.sort(ids)

	local state = (weekStart // TimeUtil.WEEK) % 2147483647 + 1
	local picked: { string } = {}
	for _ = 1, math.min(WEEKLY_MODIFIER_COUNT, #ids) do
		state = (state * 48271) % 2147483647
		local index = state % #ids + 1
		table.insert(picked, ids[index])
		table.remove(ids, index)
	end
	return picked
end

export type ModifierEffects = {
	EnemyHealth: number,
	EnemyDamage: number,
	AmmoDrops: number,
	ExtraShields: number,
	MatchGame: boolean,
	-- element -> extra damage fraction for player weapons of that element
	Surges: { [string]: number },
}

function ActivityRules.CombineModifiers(ids: { string }): ModifierEffects
	local effects: ModifierEffects = {
		EnemyHealth = 1,
		EnemyDamage = 1,
		AmmoDrops = 1,
		ExtraShields = 0,
		MatchGame = false,
		Surges = {},
	}
	for _, id in ids do
		local modifier = ActivityConfig.NightfallModifiers[id]
		if modifier then
			effects.EnemyHealth *= modifier.EnemyHealth or 1
			effects.EnemyDamage *= modifier.EnemyDamage or 1
			effects.AmmoDrops *= modifier.AmmoDrops or 1
			effects.ExtraShields += modifier.ExtraShields or 0
			effects.MatchGame = effects.MatchGame or modifier.MatchGame == true
			if modifier.Surge then
				effects.Surges[modifier.Surge] = (effects.Surges[modifier.Surge] or 0) + (modifier.SurgeBonus or 0)
			end
		end
	end
	return effects
end

-- Modifiers active for a launch: hardened strikes use the weekly pick.
function ActivityRules.ModifiersFor(activity: ActivityDef, now: number): { string }
	if activity.Type == "Nightfall" then
		return ActivityRules.WeeklyModifiers(now)
	end
	return {}
end

export type ObjectiveEntry = {
	Objective: ActivityConfig.ObjectiveDef,
	-- Set when the objective belongs to a raid/dungeon encounter.
	Encounter: ActivityConfig.EncounterDef?,
}

-- Every objective the runner walks through, in order.
function ActivityRules.ObjectiveList(activity: ActivityDef): { ObjectiveEntry }
	local list: { ObjectiveEntry } = {}
	for _, objective in activity.Objectives or {} :: { ActivityConfig.ObjectiveDef } do
		table.insert(list, { Objective = objective })
	end
	for _, encounter in activity.Encounters or {} :: { ActivityConfig.EncounterDef } do
		if encounter.Playable then
			for _, objective in encounter.Objectives do
				table.insert(list, { Objective = objective, Encounter = encounter })
			end
		end
	end
	return list
end

return ActivityRules
