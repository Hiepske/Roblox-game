--!strict
--[[
	ProfileStore
	Session-locked player data on top of DataStore UpdateAsync, in the spirit
	of ProfileService.

	Why session locking: a player hopping servers (teleporting to an activity,
	rejoining after a crash) can have two servers touching their data at once.
	Without a lock the slower server overwrites newer progress (rollbacks) or
	both servers keep items that were traded or dismantled (dupes).

	How it works
	  * Every record carries Meta.ActiveSession = the server that owns it.
	  * LoadAsync claims the lock with UpdateAsync. If another live server owns
	    it, we post Meta.ForceLoadSession ("please let go") and retry. The owner
	    sees the request on its next save, writes its data and releases.
	  * A lock that hasn't been refreshed for SessionStaleSeconds (crashed
	    server) is taken over, and after StealAfterAttempts retries we take the
	    lock regardless so a player is never stuck forever.
	  * Every save re-checks ownership inside UpdateAsync. A server that lost
	    its lock never writes again: the profile is marked released with reason
	    "SessionLost" and the game kicks the player from that server.

	Everything environmental (the DataStore, clock, wait, session id) is
	injected so the whole flow runs in unit tests against MockDataStore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local RECORD_FORMAT = 1

export type Session = {
	PlaceId: number,
	JobId: string,
	-- Random per server boot; JobId alone is "" in Studio.
	SessionId: string,
}

export type Meta = {
	ActiveSession: Session?,
	ForceLoadSession: Session?,
	LastUpdate: number,
	SessionLoadCount: number,
	CreatedAt: number,
}

export type Record = {
	FormatVersion: number,
	Data: any,
	Meta: Meta,
}

-- Anything with a Roblox-compatible UpdateAsync (DataStore or MockDataStore).
export type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any, any) -> ...any) -> ...any,
}

export type Settings = {
	LoadRetryDelay: number,
	StealAfterAttempts: number,
	MaxLoadAttempts: number,
	SessionStaleSeconds: number,
	MaxSaveAttempts: number,
	SaveRetryDelay: number,
}

export type LogLevel = "info" | "warn" | "error"

export type Options = {
	Store: StoreLike,
	Session: Session,
	Settings: Settings,
	Clock: () -> number,
	Wait: (seconds: number) -> (),
	-- Called before each DataStore request (e.g. to wait for request budget).
	BeforeRequest: (() -> ())?,
	-- Validates data before it is written; invalid data is never saved.
	Validate: ((data: any) -> (boolean, string?))?,
	Log: ((level: LogLevel, message: string) -> ())?,
}

export type ReleaseReason = "Released" | "SessionLost" | "ForceLoaded" | "ReleaseFailed"

export type Profile = {
	Key: string,
	-- The live data table. Mutate it freely; it is written on each save.
	Data: any,
	UserIds: { number },
	-- True if no record existed before this load (Data is nil).
	IsNew: boolean,
	LoadedAt: number,
	LastSavedAt: number,
	SessionLoadCount: number,
	-- Fires once when the profile stops being active, with the reason.
	Released: Signal.Signal<ReleaseReason>,

	IsActive: (self: Profile) -> boolean,
	-- Writes Data (and refreshes the lock). Returns (ok, errorReason).
	SaveAsync: (self: Profile) -> (boolean, string?),
	-- Final write + unlock. writeData = false unlocks without writing Data.
	ReleaseAsync: (self: Profile, writeData: boolean?) -> (boolean, string?),
}

export type ProfileStore = {
	LoadAsync: (
		self: ProfileStore,
		key: string,
		userIds: { number },
		isCancelled: (() -> boolean)?
	) -> (Profile?, string?),
	GetActiveProfile: (self: ProfileStore, key: string) -> Profile?,
	GetActiveProfiles: (self: ProfileStore) -> { Profile },
}

local ProfileStore = {}

local function isRecord(value: any): boolean
	return type(value) == "table"
		and type(value.Meta) == "table"
		and type(value.FormatVersion) == "number"
		and type(value.Meta.LastUpdate) == "number"
end

local function sameSession(a: Session?, b: Session?): boolean
	return a ~= nil and b ~= nil and a.SessionId == b.SessionId
end

local function defaultLog(level: LogLevel, message: string)
	if level == "info" then
		print(`[ProfileStore] {message}`)
	else
		warn(`[ProfileStore] {message}`)
	end
end

function ProfileStore.new(options: Options): ProfileStore
	local store = options.Store
	local session = options.Session
	local settings = options.Settings
	local clock = options.Clock
	local wait = options.Wait
	local log: (LogLevel, string) -> () = options.Log or defaultLog
	local beforeRequest = options.BeforeRequest
	local validate = options.Validate

	local activeProfiles: { [string]: Profile } = {}
	local loadingKeys: { [string]: boolean } = {}

	local function request()
		if beforeRequest then
			beforeRequest()
		end
	end

	local function newProfile(
		key: string,
		loaded: Record,
		userIds: { number },
		isNew: boolean,
		loadedAt: number
	): Profile
		local active = true
		local writing = false

		local profile = {} :: Profile
		profile.Key = key
		profile.Data = loaded.Data
		profile.UserIds = userIds
		profile.IsNew = isNew
		profile.LoadedAt = loadedAt
		profile.LastSavedAt = loadedAt
		profile.SessionLoadCount = loaded.Meta.SessionLoadCount
		profile.Released = Signal.new()

		local function deactivate(reason: ReleaseReason)
			if not active then
				return
			end
			active = false
			if activeProfiles[key] == profile then
				activeProfiles[key] = nil
			end
			log(if reason == "Released" then "info" else "warn", `{key} released ({reason})`)
			profile.Released:Fire(reason)
		end

		-- One write at a time per profile; a release waits for an autosave.
		local function write(release: boolean, writeData: boolean): (boolean, string?)
			while writing do
				wait(0.1)
			end
			if not active then
				return false, "NotActive"
			end
			writing = true

			if writeData and validate then
				local ok, err = validate(profile.Data)
				if not ok then
					log("error", `{key}: refusing to save invalid data: {err}`)
					if not release then
						writing = false
						return false, "InvalidData"
					end
					-- Still unlock on release, but keep the last good save.
					writeData = false
				end
			end

			local attempts = if release then settings.MaxSaveAttempts else 1
			local outcome: "Saved" | "Lost" | nil = nil
			local forceRequested = false
			local now = clock()

			for attempt = 1, attempts do
				now = clock()
				local lost = false
				forceRequested = false
				request()
				local ok, err = pcall(function()
					store:UpdateAsync(key, function(current: any)
						lost = false
						forceRequested = false
						if not isRecord(current) or not sameSession(current.Meta.ActiveSession, session) then
							lost = true
							return nil -- someone else owns it now: never write
						end
						local record = current :: Record
						if writeData then
							record.Data = profile.Data
						end
						record.Meta.LastUpdate = now
						forceRequested = record.Meta.ForceLoadSession ~= nil
						if release or forceRequested then
							record.Meta.ActiveSession = nil
						end
						return record, profile.UserIds
					end)
				end)
				if ok then
					outcome = if lost then "Lost" else "Saved"
					break
				end
				log("warn", `{key}: save attempt {attempt}/{attempts} failed: {err}`)
				if attempt < attempts then
					wait(settings.SaveRetryDelay * attempt)
				end
			end

			writing = false

			if outcome == nil then
				if release then
					-- Couldn't unlock; the lock goes stale and is taken over later.
					deactivate("ReleaseFailed")
				end
				return false, "DataStoreError"
			elseif outcome == "Lost" then
				deactivate("SessionLost")
				return false, "SessionLost"
			end

			profile.LastSavedAt = now
			if release then
				deactivate("Released")
			elseif forceRequested then
				deactivate("ForceLoaded")
			end
			return true, nil
		end

		function profile.IsActive(_: Profile): boolean
			return active
		end

		function profile.SaveAsync(_: Profile): (boolean, string?)
			return write(false, true)
		end

		function profile.ReleaseAsync(_: Profile, writeData: boolean?): (boolean, string?)
			return write(true, writeData ~= false)
		end

		return profile
	end

	local self = {} :: ProfileStore

	function self.GetActiveProfile(_: ProfileStore, key: string): Profile?
		return activeProfiles[key]
	end

	function self.GetActiveProfiles(_: ProfileStore): { Profile }
		local list = {}
		for _, profile in activeProfiles do
			table.insert(list, profile)
		end
		return list
	end

	function self.LoadAsync(
		_: ProfileStore,
		key: string,
		userIds: { number },
		isCancelled: (() -> boolean)?
	): (Profile?, string?)
		local function cancelled(): boolean
			return isCancelled ~= nil and isCancelled()
		end

		if loadingKeys[key] then
			return nil, "AlreadyLoading"
		end

		-- The same key may still be releasing on this server (fast rejoin).
		local waited = 0
		local maxWait = settings.LoadRetryDelay * settings.MaxLoadAttempts
		while activeProfiles[key] do
			if cancelled() then
				return nil, "Cancelled"
			elseif waited >= maxWait then
				return nil, "AlreadyLoaded"
			end
			wait(0.25)
			waited += 0.25
		end

		loadingKeys[key] = true
		local lastError = "LockTimeout"

		for attempt = 1, settings.MaxLoadAttempts do
			if cancelled() then
				loadingKeys[key] = nil
				return nil, "Cancelled"
			end

			local now = clock()
			local steal = attempt >= settings.StealAfterAttempts
			local outcome: "Acquired" | "Locked" | "Corrupt" = "Locked"
			local isNew = false
			local acquired: Record? = nil

			request()
			local ok, err = pcall(function()
				store:UpdateAsync(key, function(current: any)
					outcome = "Locked"
					isNew = false
					acquired = nil

					local record: Record
					if current == nil then
						isNew = true
						record = {
							FormatVersion = RECORD_FORMAT,
							Data = nil,
							Meta = {
								ActiveSession = nil,
								ForceLoadSession = nil,
								LastUpdate = now,
								SessionLoadCount = 0,
								CreatedAt = now,
							},
						}
					elseif isRecord(current) then
						record = current
					else
						-- Unknown shape: never overwrite something we don't understand.
						outcome = "Corrupt"
						return nil
					end

					local meta = record.Meta
					local owner = meta.ActiveSession
					local stale = (now - meta.LastUpdate) >= settings.SessionStaleSeconds
					if owner == nil or sameSession(owner, session) or stale or steal then
						meta.ActiveSession = session
						meta.ForceLoadSession = nil
						meta.LastUpdate = now
						meta.SessionLoadCount += 1
						outcome = "Acquired"
						acquired = record
						return record, userIds
					end

					-- Locked by a live server: ask it to release on its next save.
					if sameSession(meta.ForceLoadSession, session) then
						return nil -- request already posted, save a write
					end
					meta.ForceLoadSession = session
					return record, userIds
				end)
			end)

			if not ok then
				lastError = "DataStoreError"
				log("warn", `{key}: load attempt {attempt} failed: {err}`)
			elseif outcome == "Corrupt" then
				loadingKeys[key] = nil
				log("error", `{key}: stored value is not a profile record; refusing to load`)
				return nil, "CorruptRecord"
			elseif outcome == "Acquired" and acquired then
				local profile = newProfile(key, acquired, userIds, isNew, now)
				activeProfiles[key] = profile
				loadingKeys[key] = nil
				if steal and attempt > 1 then
					log("warn", `{key}: took over a session lock after {attempt} attempts`)
				end
				if cancelled() then
					-- Player left while we were loading: hand the lock straight back.
					profile:ReleaseAsync(false)
					return nil, "Cancelled"
				end
				return profile, nil
			else
				lastError = "LockTimeout"
			end

			if attempt < settings.MaxLoadAttempts then
				wait(settings.LoadRetryDelay)
			end
		end

		loadingKeys[key] = nil
		return nil, lastError
	end

	return self
end

return ProfileStore
