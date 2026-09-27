local Server = game.ServerScriptService
local MockDataStore = require(Server.Data.MockDataStore)
local ProfileStore = require(Server.Data.ProfileStore)
local TableUtil = require(game.ReplicatedStorage.Shared.Util.TableUtil)

local SETTINGS = {
	LoadRetryDelay = 4,
	StealAfterAttempts = 4,
	MaxLoadAttempts = 6,
	SessionStaleSeconds = 600,
	MaxSaveAttempts = 3,
	SaveRetryDelay = 1,
}

-- A fake server: its own session id, a shared clock, and a wait hook that
-- lets a test run "other server" code while this one is waiting.
local function makeServer(store, name, clock, onWait)
	return ProfileStore.new({
		Store = store,
		Session = { PlaceId = 1, JobId = name, SessionId = name },
		Settings = SETTINGS,
		Clock = function()
			return clock.now
		end,
		Wait = function(seconds)
			clock.now += seconds
			if onWait.fn then
				onWait.fn()
			end
		end,
		Validate = function(data)
			return TableUtil.ValidateDataStoreValue(data)
		end,
		Log = function() end,
	})
end

local function setup()
	local store = MockDataStore.new()
	local clock = { now = 1000 }
	local hooksA, hooksB = {}, {}
	local serverA = makeServer(store, "A", clock, hooksA)
	local serverB = makeServer(store, "B", clock, hooksB)
	return store, clock, serverA, serverB, hooksA, hooksB
end

describe("ProfileStore basics", function()
	it("creates a new record and locks it to the loading server", function()
		local store, _, serverA = setup()
		local profile = serverA:LoadAsync("Player_1", { 1 })
		expect(profile).toBeTruthy()
		expect(profile.IsNew).toBe(true)
		expect(profile.Data).toBeNil()
		local record = store:Peek("Player_1")
		expect(record.Meta.ActiveSession.SessionId).toBe("A")
		expect(record.Meta.SessionLoadCount).toBe(1)
	end)

	it("saves data and keeps the lock; release writes and unlocks", function()
		local store, _, serverA = setup()
		local profile = serverA:LoadAsync("Player_1", { 1 })
		profile.Data = { Coins = 5 }
		local ok = profile:SaveAsync()
		expect(ok).toBe(true)
		expect(store:Peek("Player_1").Data.Coins).toBe(5)
		expect(store:Peek("Player_1").Meta.ActiveSession.SessionId).toBe("A")

		local reason
		profile.Released:Connect(function(r)
			reason = r
		end)
		profile.Data.Coins = 9
		expect((profile:ReleaseAsync())).toBe(true)
		expect(reason).toBe("Released")
		expect(profile:IsActive()).toBe(false)
		local record = store:Peek("Player_1")
		expect(record.Data.Coins).toBe(9)
		expect(record.Meta.ActiveSession).toBeNil()
		-- A released profile can never write again.
		profile.Data.Coins = 1000
		local saved, err = profile:SaveAsync()
		expect(saved).toBe(false)
		expect(err).toBe("NotActive")
		expect(store:Peek("Player_1").Data.Coins).toBe(9)
	end)

	it("loads existing data back", function()
		local _, _, serverA, serverB = setup()
		local first = serverA:LoadAsync("Player_1", { 1 })
		first.Data = { Level = 3 }
		first:ReleaseAsync()
		local second = serverB:LoadAsync("Player_1", { 1 })
		expect(second.IsNew).toBe(false)
		expect(second.Data.Level).toBe(3)
		expect(second.SessionLoadCount).toBe(2)
	end)

	it("refuses a second load of an active key on the same server", function()
		local _, _, serverA = setup()
		expect(serverA:LoadAsync("Player_1", { 1 })).toBeTruthy()
		local again, reason = serverA:LoadAsync("Player_1", { 1 })
		expect(again).toBeNil()
		expect(reason).toBe("AlreadyLoaded")
	end)
end)

describe("Session locking", function()
	it("asks the owner to release, then loads its latest save (teleport case)", function()
		local store, _, serverA, serverB, _, hooksB = setup()
		local profileA = serverA:LoadAsync("Player_1", { 1 })
		profileA.Data = { Coins = 1 }
		profileA:SaveAsync()

		local reasonA
		profileA.Released:Connect(function(r)
			reasonA = r
		end)
		-- While B waits between attempts, A keeps playing and autosaves.
		hooksB.fn = function()
			if profileA:IsActive() then
				profileA.Data.Coins += 10
				profileA:SaveAsync()
			end
		end

		local profileB = serverB:LoadAsync("Player_1", { 1 })
		expect(profileB).toBeTruthy()
		expect(reasonA).toBe("ForceLoaded")
		expect(profileA:IsActive()).toBe(false)
		-- B sees A's final save, nothing is lost.
		expect(profileB.Data.Coins).toBe(11)
		expect(store:Peek("Player_1").Meta.ActiveSession.SessionId).toBe("B")
		expect(store:Peek("Player_1").Meta.ForceLoadSession).toBeNil()
	end)

	it("takes over from an unresponsive owner, which can then never overwrite", function()
		local store, _, serverA, serverB = setup()
		local profileA = serverA:LoadAsync("Player_1", { 1 })
		profileA.Data = { Items = 1 }
		profileA:SaveAsync()

		-- A never saves while B waits (a frozen server): B steals the lock.
		local profileB = serverB:LoadAsync("Player_1", { 1 })
		expect(profileB).toBeTruthy()
		expect(profileB.Data.Items).toBe(1)
		profileB.Data.Items = 2
		profileB:SaveAsync()

		-- A wakes up and tries to save stale data: rejected, marked lost.
		local reasonA
		profileA.Released:Connect(function(r)
			reasonA = r
		end)
		profileA.Data.Items = 999
		local ok, err = profileA:SaveAsync()
		expect(ok).toBe(false)
		expect(err).toBe("SessionLost")
		expect(reasonA).toBe("SessionLost")
		expect(store:Peek("Player_1").Data.Items).toBe(2)
		expect(store:Peek("Player_1").Meta.ActiveSession.SessionId).toBe("B")
	end)

	it("takes over a stale lock immediately (crashed server)", function()
		local store, clock, serverA, serverB = setup()
		serverA:LoadAsync("Player_1", { 1 })
		clock.now += SETTINGS.SessionStaleSeconds + 1
		local requestsBefore = store.RequestCount
		local profileB = serverB:LoadAsync("Player_1", { 1 })
		expect(profileB).toBeTruthy()
		expect(store.RequestCount - requestsBefore).toBe(1)
	end)

	it("never overwrites a value that is not a profile record", function()
		local store, _, serverA = setup()
		store:SetAsync("Player_1", "legacy string save")
		local profile, reason = serverA:LoadAsync("Player_1", { 1 })
		expect(profile).toBeNil()
		expect(reason).toBe("CorruptRecord")
		expect(store:Peek("Player_1")).toBe("legacy string save")
	end)
end)

describe("Failures", function()
	it("retries loads through DataStore errors", function()
		local store, _, serverA = setup()
		store:FailNext(2)
		local profile = serverA:LoadAsync("Player_1", { 1 })
		expect(profile).toBeTruthy()
	end)

	it("gives up after MaxLoadAttempts of errors", function()
		local store, _, serverA = setup()
		store:FailNext(100)
		local profile, reason = serverA:LoadAsync("Player_1", { 1 })
		expect(profile).toBeNil()
		expect(reason).toBe("DataStoreError")
	end)

	it("retries the release save", function()
		local store, _, serverA = setup()
		local profile = serverA:LoadAsync("Player_1", { 1 })
		profile.Data = { X = 1 }
		store:FailNext(SETTINGS.MaxSaveAttempts - 1)
		expect((profile:ReleaseAsync())).toBe(true)
		expect(store:Peek("Player_1").Data.X).toBe(1)
	end)

	it("reports ReleaseFailed when every release attempt fails", function()
		local store, _, serverA = setup()
		local profile = serverA:LoadAsync("Player_1", { 1 })
		local reason
		profile.Released:Connect(function(r)
			reason = r
		end)
		store:FailNext(SETTINGS.MaxSaveAttempts)
		local ok, err = profile:ReleaseAsync()
		expect(ok).toBe(false)
		expect(err).toBe("DataStoreError")
		expect(reason).toBe("ReleaseFailed")
		expect(profile:IsActive()).toBe(false)
	end)

	it("refuses to save data a DataStore would corrupt", function()
		local store, _, serverA = setup()
		local profile = serverA:LoadAsync("Player_1", { 1 })
		profile.Data = { Coins = 5 }
		profile:SaveAsync()
		profile.Data.Coins = 0 / 0 -- NaN
		local ok, err = profile:SaveAsync()
		expect(ok).toBe(false)
		expect(err).toBe("InvalidData")
		expect(store:Peek("Player_1").Data.Coins).toBe(5)
		expect(profile:IsActive()).toBe(true)
	end)

	it("hands the lock back if the player left during the load", function()
		local store, _, serverA = setup()
		local profile, reason = serverA:LoadAsync("Player_1", { 1 }, function()
			return store.RequestCount >= 1 -- "left" right after the lock was taken
		end)
		expect(profile).toBeNil()
		expect(reason).toBe("Cancelled")
		expect(store:Peek("Player_1").Meta.ActiveSession).toBeNil()
		expect(serverA:GetActiveProfile("Player_1")).toBeNil()
	end)
end)
