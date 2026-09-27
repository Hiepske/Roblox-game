--!strict
--[[
	Guard
	Tiny argument validators for remote payloads. Clients can send anything
	(wrong types, NaN, huge strings, extra arguments), so every ToServer
	remote declares a list of checks and NetService rejects mismatches
	before any game code runs.

	NetService.OnEvent("Equip", { Guard.Uid, Guard.OneOf({ "Kinetic", "Energy" }) }, handler)
]]

export type Check = (value: any) -> (boolean, string?)

local Guard = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Guard.String(maxLength: number, minLength: number?): Check
	local minLen = minLength or 0
	return function(value: any)
		if type(value) ~= "string" then
			return false, `expected string, got {typeof(value)}`
		end
		local len = #value
		if len < minLen or len > maxLength then
			return false, `string length {len} outside {minLen}..{maxLength}`
		end
		if utf8.len(value) == nil then
			return false, "string is not valid UTF-8"
		end
		return true, nil
	end
end

function Guard.Number(min: number, max: number): Check
	return function(value: any)
		if type(value) ~= "number" or not isFinite(value) then
			return false, "expected finite number"
		end
		if value < min or value > max then
			return false, `number {value} outside {min}..{max}`
		end
		return true, nil
	end
end

function Guard.Integer(min: number, max: number): Check
	local numberCheck = Guard.Number(min, max)
	return function(value: any)
		local ok, err = numberCheck(value)
		if not ok then
			return false, err
		end
		if value % 1 ~= 0 then
			return false, "expected integer"
		end
		return true, nil
	end
end

Guard.Boolean = function(value: any): (boolean, string?)
	if type(value) ~= "boolean" then
		return false, `expected boolean, got {typeof(value)}`
	end
	return true, nil
end :: Check

function Guard.OneOf(options: { string }): Check
	local allowed: { [string]: boolean } = {}
	for _, option in options do
		allowed[option] = true
	end
	return function(value: any)
		if type(value) ~= "string" or not allowed[value] then
			return false, `unexpected value {tostring(value)}`
		end
		return true, nil
	end
end

function Guard.Optional(check: Check): Check
	return function(value: any)
		if value == nil then
			return true, nil
		end
		return check(value)
	end
end

-- Item unique ids are GUIDs from HttpService:GenerateGUID(false).
Guard.Uid = function(value: any): (boolean, string?)
	if type(value) ~= "string" or #value ~= 36 then
		return false, "expected item uid"
	end
	if string.match(value, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") == nil then
		return false, "malformed item uid"
	end
	return true, nil
end :: Check

-- A finite Vector3 within `maxMagnitude` studs of the origin.
function Guard.Vector3(maxMagnitude: number): Check
	return function(value: any)
		if typeof(value) ~= "Vector3" then
			return false, `expected Vector3, got {typeof(value)}`
		end
		local v = value :: Vector3
		if not (isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)) then
			return false, "Vector3 has NaN or infinite components"
		end
		if v.Magnitude > maxMagnitude then
			return false, "Vector3 is too far away"
		end
		return true, nil
	end
end

-- Validates a packed argument list against `checks`. Extra arguments beyond
-- the declared checks are rejected too.
function Guard.Args(checks: { Check }, args: { n: number, [number]: any }): (boolean, string?)
	if args.n > #checks then
		return false, `expected at most {#checks} arguments, got {args.n}`
	end
	for index, check in checks do
		local ok, err = check(args[index])
		if not ok then
			return false, `argument #{index}: {err or "invalid"}`
		end
	end
	return true, nil
end

return Guard
