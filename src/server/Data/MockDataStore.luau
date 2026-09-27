--!strict
--[[
	MockDataStore
	In-memory stand-in for a Roblox DataStore. Used in Studio when API access
	is disabled (nothing persists between sessions) and by the unit tests.

	It deep-copies values on the way in and out, just like real DataStores
	serialize to JSON, so code can't accidentally rely on shared references.
	Values that a real DataStore would reject (NaN, functions, mixed tables)
	raise an error here too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)

export type MockDataStore = {
	GetAsync: (self: MockDataStore, key: string) -> any,
	SetAsync: (self: MockDataStore, key: string, value: any) -> (),
	UpdateAsync: (self: MockDataStore, key: string, transform: (any, any) -> ...any) -> any,
	RemoveAsync: (self: MockDataStore, key: string) -> any,
	-- Test hooks ---------------------------------------------------------------
	-- The next `count` requests raise an error (simulates DataStore outages).
	FailNext: (self: MockDataStore, count: number) -> (),
	-- Raw access to what is "on disk" (already copied).
	Peek: (self: MockDataStore, key: string) -> any,
	RequestCount: number,
}

local MockDataStore = {}

function MockDataStore.new(): MockDataStore
	local storage: { [string]: any } = {}
	local failures = 0

	local self = {} :: MockDataStore
	self.RequestCount = 0

	local function beginRequest()
		self.RequestCount += 1
		if failures > 0 then
			failures -= 1
			error("MockDataStore: simulated request failure")
		end
	end

	local function store(key: string, value: any)
		if value ~= nil then
			local ok, err = TableUtil.ValidateDataStoreValue(value, key)
			if not ok then
				error(`MockDataStore: cannot store value: {err}`)
			end
		end
		storage[key] = TableUtil.DeepCopy(value)
	end

	function self.GetAsync(_: MockDataStore, key: string): any
		beginRequest()
		return TableUtil.DeepCopy(storage[key])
	end

	function self.SetAsync(_: MockDataStore, key: string, value: any)
		beginRequest()
		store(key, value)
	end

	function self.UpdateAsync(_: MockDataStore, key: string, transform: (any, any) -> ...any): any
		beginRequest()
		local newValue = transform(TableUtil.DeepCopy(storage[key]), nil)
		if newValue == nil then
			-- Returning nil cancels the write, like the real API.
			return nil
		end
		store(key, newValue)
		return TableUtil.DeepCopy(newValue)
	end

	function self.RemoveAsync(_: MockDataStore, key: string): any
		beginRequest()
		local old = storage[key]
		storage[key] = nil
		return old
	end

	function self.FailNext(_: MockDataStore, count: number)
		failures = count
	end

	function self.Peek(_: MockDataStore, key: string): any
		return TableUtil.DeepCopy(storage[key])
	end

	return self
end

return MockDataStore
