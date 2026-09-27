--[[
	TestKit
	A minimal describe/it/expect test framework for Lune.
]]

local TestKit = {}

local results = { passed = 0, failed = 0, failures = {} }
local stack = {}

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function show(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function TestKit.describe(name, fn)
	table.insert(stack, name)
	fn()
	table.remove(stack)
end

function TestKit.it(name, fn)
	local fullName = table.concat(stack, " > ") .. " > " .. name
	local ok, err = xpcall(fn, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName, err = err })
	end
end

function TestKit.expect(actual)
	local matchers = {}

	local function fail(message)
		error(message, 3)
	end

	function matchers.toBe(expected)
		if actual ~= expected then
			fail(`expected {show(expected)}, got {show(actual)}`)
		end
	end

	function matchers.toEqual(expected)
		if not deepEqual(actual, expected) then
			fail(`values are not deeply equal (got {show(actual)})`)
		end
	end

	function matchers.toBeNear(expected, epsilon)
		if math.abs(actual - expected) > (epsilon or 1e-6) then
			fail(`expected {expected} +/- {epsilon or 1e-6}, got {actual}`)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			fail(`expected a truthy value, got {show(actual)}`)
		end
	end

	function matchers.toBeFalsy()
		if actual then
			fail(`expected a falsy value, got {show(actual)}`)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			fail(`expected nil, got {show(actual)}`)
		end
	end

	function matchers.toBeAtLeast(n)
		if not (actual >= n) then
			fail(`expected >= {n}, got {show(actual)}`)
		end
	end

	function matchers.toBeAtMost(n)
		if not (actual <= n) then
			fail(`expected <= {n}, got {show(actual)}`)
		end
	end

	function matchers.toContain(item)
		if table.find(actual, item) == nil then
			fail(`expected list to contain {show(item)}`)
		end
	end

	function matchers.toThrow(pattern)
		local ok, err = pcall(actual)
		if ok then
			fail("expected function to throw")
		elseif pattern and not tostring(err):find(pattern, 1, true) then
			fail(`expected error containing {show(pattern)}, got {show(err)}`)
		end
	end

	return matchers
end

function TestKit.Results()
	return results
end

return TestKit
