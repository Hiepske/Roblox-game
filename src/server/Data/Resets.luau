--!strict
--[[
	Resets
	Applies weekly/daily resets to a player's data: clears claimed Powerful and
	Pinnacle rewards and milestone progress at the weekly reset, daily claims
	at the daily reset, and removes expired bounties.

	Called when data loads and periodically for players who stay online
	across a reset boundary.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeUtil = require(ReplicatedStorage.Shared.Util.TimeUtil)
local Types = require(ReplicatedStorage.Shared.Types)

export type ResetConfig = { WeeklyWeekday: number, HourUtc: number }

export type ResetResult = {
	Weekly: boolean,
	Daily: boolean,
	BountiesExpired: number,
}

local Resets = {}

function Resets.Apply(data: Types.ProfileData, now: number, config: ResetConfig): ResetResult
	local result = { Weekly = false, Daily = false, BountiesExpired = 0 }

	local weekStart = TimeUtil.GetLastWeeklyReset(now, config.WeeklyWeekday, config.HourUtc)
	if data.Weekly.ResetAt < weekStart then
		data.Weekly = {
			ResetAt = weekStart,
			ClaimedRewards = {},
			MilestoneProgress = {},
		}
		result.Weekly = true
	end

	local dayStart = TimeUtil.GetLastDailyReset(now, config.HourUtc)
	if data.Daily.ResetAt < dayStart then
		data.Daily = {
			ResetAt = dayStart,
			ClaimedRewards = {},
		}
		result.Daily = true
	end

	local active = data.Bounties.Active
	for index = #active, 1, -1 do
		if active[index].ExpiresAt <= now then
			table.remove(active, index)
			result.BountiesExpired += 1
		end
	end

	return result
end

return Resets
