--!strict
--[[
	Motion
	The timing of client-animated map parts, shared so the server can tell
	where a moving part is without moving it (laser traps damage players on
	the server while clients draw the motion):

	  Progress(period, dwell, phase, time)  0..1 along a mover's path (it
	      waits `dwell` seconds at each end; smooth in between) and the rate
	  LaserOn(period, onFraction, phase, time)  whether a blinking laser is on
]]

local Motion = {}

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- 0..1 progress along a mover's path at `time`, and its rate (per second).
function Motion.Progress(period: number, dwell: number, phase: number, time: number): (number, number)
	local length = math.max(0.1, period)
	local half = length / 2
	local travel = math.max(0.05, half - dwell)
	local t = ((time / length + phase) % 1) * length
	if t < dwell then
		return 0, 0
	elseif t < half then
		local x = (t - dwell) / travel
		return smooth(x), 6 * x * (1 - x) / travel
	elseif t < half + dwell then
		return 1, 0
	end
	local x = (t - half - dwell) / travel
	return 1 - smooth(x), -6 * x * (1 - x) / travel
end

-- Where a mover part is at `time`, from its resting CFrame and attributes.
function Motion.MoverCFrame(
	base: CFrame,
	offset: Vector3,
	period: number,
	dwell: number,
	phase: number,
	time: number
): CFrame
	local progress = Motion.Progress(period, dwell, phase, time)
	return base + offset * progress
end

-- Blinking lasers are on for `onFraction` of every `period` seconds.
function Motion.LaserOn(period: number, onFraction: number, phase: number, time: number): boolean
	if period <= 0 then
		return true
	end
	local t = (time / period + phase) % 1
	return t < onFraction
end

return Motion
