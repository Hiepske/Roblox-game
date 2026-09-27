local Shared = game.ReplicatedStorage.Shared
local Guard = require(Shared.Net.Guard)
local RateLimiter = require(Shared.Util.RateLimiter)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local TimeUtil = require(Shared.Util.TimeUtil)

describe("TableUtil", function()
	it("deep copies without sharing references", function()
		local original = { a = { b = { 1, 2 } } }
		local copy = TableUtil.DeepCopy(original)
		copy.a.b[1] = 99
		expect(original.a.b[1]).toBe(1)
		expect(TableUtil.DeepEqual(TableUtil.DeepCopy(original), original)).toBe(true)
	end)

	it("reconciles missing keys without overwriting", function()
		local target = { keep = 1, nested = { a = 1 } }
		TableUtil.Reconcile(target, { keep = 2, added = 3, nested = { a = 9, b = 2 } })
		expect(target.keep).toBe(1)
		expect(target.added).toBe(3)
		expect(target.nested.a).toBe(1)
		expect(target.nested.b).toBe(2)
	end)

	it("gets and sets nested paths", function()
		local root = {}
		TableUtil.SetPath(root, { "Currencies", "Quanta" }, 10)
		expect(TableUtil.GetPath(root, { "Currencies", "Quanta" })).toBe(10)
		TableUtil.SetPath(root, { "Currencies", "Quanta" }, nil)
		expect(root.Currencies.Quanta).toBeNil()
		expect(TableUtil.GetPath(root, { "Missing", "Deeper" })).toBeNil()
	end)

	it("rejects values a DataStore cannot store", function()
		local ok = TableUtil.ValidateDataStoreValue({ a = 1, b = { 1, 2, 3 }, c = "text", d = true })
		expect(ok).toBe(true)
		local cases = {
			{ n = 0 / 0 },
			{ n = math.huge },
			{ f = function() end },
			{ [1] = "a", key = "mixed" },
			{ [1] = "a", [3] = "hole" },
		}
		for _, case in cases do
			expect((TableUtil.ValidateDataStoreValue(case))).toBe(false)
		end
		local cyclic = {}
		cyclic.self = cyclic
		expect((TableUtil.ValidateDataStoreValue(cyclic))).toBe(false)
	end)
end)

describe("Guard", function()
	it("validates strings", function()
		local check = Guard.String(5)
		expect((check("abc"))).toBe(true)
		expect((check("abcdef"))).toBe(false)
		expect((check(5))).toBe(false)
	end)

	it("rejects NaN, infinity and out-of-range numbers", function()
		local check = Guard.Number(0, 10)
		expect((check(5))).toBe(true)
		expect((check(0 / 0))).toBe(false)
		expect((check(math.huge))).toBe(false)
		expect((check(11))).toBe(false)
		expect((Guard.Integer(0, 10)(2.5))).toBe(false)
	end)

	it("validates enums, optionals and uids", function()
		local oneOf = Guard.OneOf({ "Kinetic", "Energy" })
		expect((oneOf("Energy"))).toBe(true)
		expect((oneOf("Heavy"))).toBe(false)
		expect((Guard.Optional(oneOf)(nil))).toBe(true)
		expect((Guard.Uid("0A1B2C3D-0000-4000-8000-0123456789AB"))).toBe(true)
		expect((Guard.Uid("not-a-uid"))).toBe(false)
	end)

	it("rejects extra arguments", function()
		local checks = { Guard.String(10) }
		expect((Guard.Args(checks, table.pack("ok")))).toBe(true)
		expect((Guard.Args(checks, table.pack("ok", "extra")))).toBe(false)
		expect((Guard.Args(checks, table.pack(123)))).toBe(false)
	end)
end)

describe("RateLimiter", function()
	it("allows a burst, refills over time, and tracks keys separately", function()
		local now = 0
		local limiter = RateLimiter.new(2, 3, function()
			return now
		end)
		expect(limiter:Check("a")).toBe(true)
		expect(limiter:Check("a")).toBe(true)
		expect(limiter:Check("a")).toBe(true)
		expect(limiter:Check("a")).toBe(false)
		expect(limiter:Check("b")).toBe(true)
		now = 0.5 -- one token back at 2/s
		expect(limiter:Check("a")).toBe(true)
		expect(limiter:Check("a")).toBe(false)
		now = 100 -- never more than the burst
		for _ = 1, 3 do
			expect(limiter:Check("a")).toBe(true)
		end
		expect(limiter:Check("a")).toBe(false)
	end)
end)

describe("Signal", function()
	it("connects, fires, disconnects and supports Once", function()
		local signal = Signal.new()
		local total = 0
		local connection = signal:Connect(function(n)
			total += n
		end)
		signal:Once(function(n)
			total += n * 100
		end)
		signal:Fire(1)
		signal:Fire(1)
		expect(total).toBe(102)
		connection:Disconnect()
		signal:Fire(1)
		expect(total).toBe(102)
	end)
end)

describe("TimeUtil", function()
	local SUNDAY = 1790467200 -- 2026-09-27 00:00 UTC
	local TUESDAY = 1790640000 -- 2026-09-29 00:00 UTC

	it("knows the weekday", function()
		expect(TimeUtil.Weekday(SUNDAY)).toBe(0)
		expect(TimeUtil.Weekday(TUESDAY)).toBe(2)
	end)

	it("finds the last and next weekly reset (Tuesday 17:00 UTC)", function()
		local lastTuesday = TUESDAY - 7 * 86400 + 17 * 3600
		expect(TimeUtil.GetLastWeeklyReset(SUNDAY, 2, 17)).toBe(lastTuesday)
		expect(TimeUtil.GetNextWeeklyReset(SUNDAY, 2, 17)).toBe(TUESDAY + 17 * 3600)
		-- Tuesday before and after 17:00.
		expect(TimeUtil.GetLastWeeklyReset(TUESDAY + 16 * 3600, 2, 17)).toBe(lastTuesday)
		expect(TimeUtil.GetLastWeeklyReset(TUESDAY + 17 * 3600, 2, 17)).toBe(TUESDAY + 17 * 3600)
	end)

	it("finds the last daily reset", function()
		expect(TimeUtil.GetLastDailyReset(SUNDAY + 3600, 17)).toBe(SUNDAY - 7 * 3600)
		expect(TimeUtil.GetLastDailyReset(SUNDAY + 18 * 3600, 17)).toBe(SUNDAY + 17 * 3600)
	end)

	it("formats durations", function()
		expect(TimeUtil.FormatDuration(9)).toBe("9s")
		expect(TimeUtil.FormatDuration(125)).toBe("2m 5s")
		expect(TimeUtil.FormatDuration(3 * 3600 + 120)).toBe("3h 2m")
		expect(TimeUtil.FormatDuration(2 * 86400 + 5 * 3600)).toBe("2d 5h")
	end)
end)
