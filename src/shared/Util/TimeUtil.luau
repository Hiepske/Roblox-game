--!strict
--[[
	TimeUtil
	Reset-boundary math in UTC unix seconds. Pure functions so both server
	(authoritative resets) and client (countdown timers) agree.
]]

local TimeUtil = {}

local DAY = 86400
local WEEK = 7 * DAY
-- 1970-01-01 was a Thursday; weekdays here use 0 = Sunday ... 6 = Saturday.
local EPOCH_WEEKDAY = 4

TimeUtil.DAY = DAY
TimeUtil.WEEK = WEEK

function TimeUtil.Weekday(timestamp: number): number
	return (timestamp // DAY + EPOCH_WEEKDAY) % 7
end

-- Most recent daily reset at or before `now`.
function TimeUtil.GetLastDailyReset(now: number, hourUtc: number): number
	local candidate = (now // DAY) * DAY + hourUtc * 3600
	if candidate > now then
		candidate -= DAY
	end
	return candidate
end

-- Most recent weekly reset (on `weekday` at `hourUtc`) at or before `now`.
function TimeUtil.GetLastWeeklyReset(now: number, weekday: number, hourUtc: number): number
	local today = now // DAY
	local daysSince = (TimeUtil.Weekday(now) - weekday) % 7
	local candidate = (today - daysSince) * DAY + hourUtc * 3600
	if candidate > now then
		candidate -= WEEK
	end
	return candidate
end

function TimeUtil.GetNextDailyReset(now: number, hourUtc: number): number
	return TimeUtil.GetLastDailyReset(now, hourUtc) + DAY
end

function TimeUtil.GetNextWeeklyReset(now: number, weekday: number, hourUtc: number): number
	return TimeUtil.GetLastWeeklyReset(now, weekday, hourUtc) + WEEK
end

-- "3d 4h", "4h 12m", "12m 5s", "9s"
function TimeUtil.FormatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = s // DAY
	local hours = (s % DAY) // 3600
	local minutes = (s % 3600) // 60
	local secs = s % 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return `{minutes}m {secs}s`
	end
	return `{secs}s`
end

return TimeUtil
