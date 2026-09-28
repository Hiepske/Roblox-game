--!strict
--[[
	DataService
	Owns every player's saved data for the lifetime of their session.

	  * Loads a session-locked profile on join (ProfileStore), migrates old
	    saves, fills new fields, repairs invalid data and applies resets.
	  * Autosaves every GameConfig.Data.AutosaveInterval seconds, saves and
	    releases on leave, and saves everyone on shutdown (BindToClose).
	  * Replicates data to the owning client: a full snapshot on load, then
	    path-based updates (DataChanged) whenever server code changes a value.

	Other services read data with GetData and change it through the helpers
	here (Set, AddCurrency, Spend, GiveItem, RemoveItem) so every change is
	validated and replicated. The client never writes data directly.

	In Studio without API access (or with GameConfig.Data.UseMockInStudio) an
	in-memory store is used and a warning explains that nothing persists.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Inventory = require(Shared.Items.Inventory)
local PowerMath = require(Shared.Power.PowerMath)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)

local Data = script.Parent.Parent.Data
local Migrations = require(Data.Migrations)
local MockDataStore = require(Data.MockDataStore)
local ProfileStore = require(Data.ProfileStore)
local ProfileTemplate = require(Data.ProfileTemplate)
local Resets = require(Data.Resets)

local NetService = require(script.Parent.NetService)

type ProfileData = Types.ProfileData
type ItemInstance = Types.ItemInstance

export type Backend = "DataStore" | "Mock"

local DataService = {}

-- Fired after a player's data is loaded, prepared and sent to their client.
local playerLoaded: Signal.Signal<Player, ProfileData> = Signal.new()
DataService.PlayerLoaded = playerLoaded
-- Fired right before a leaving player's profile is saved and released.
local playerReleasing: Signal.Signal<Player, ProfileData> = Signal.new()
DataService.PlayerReleasing = playerReleasing

local profiles: { [Player]: ProfileStore.Profile } = {}
local loadingPlayers: { [Player]: boolean } = {}
local playtimeMark: { [Player]: number } = {}
local store: ProfileStore.ProfileStore
local backend: Backend = "DataStore"
local shuttingDown = false
local loadsInFlight = 0

local function newUid(): string
	return HttpService:GenerateGUID(false)
end

-- Decides between real DataStores and the in-memory mock.
local function chooseBackend(): (ProfileStore.StoreLike, Backend, string?)
	if RunService:IsStudio() then
		if GameConfig.Data.UseMockInStudio then
			return MockDataStore.new(), "Mock", "GameConfig.Data.UseMockInStudio is enabled"
		end
		if game.PlaceId == 0 then
			return MockDataStore.new(), "Mock", "this place has not been published yet"
		end
		local ok, err = pcall(function()
			DataStoreService:GetDataStore("__LastLight_AccessCheck"):GetAsync("probe")
		end)
		if not ok then
			local message = tostring(err)
			if
				string.find(message, "403", 1, true)
				or string.find(message, "Studio", 1, true)
				or string.find(message, "API", 1, true)
			then
				return MockDataStore.new(), "Mock", "Studio access to API Services is disabled"
			end
		end
	end
	-- DataStore is an engine class, not a Luau table type, hence the cast.
	return DataStoreService:GetDataStore(GameConfig.Data.StoreName) :: any, "DataStore", nil
end

local function waitForBudget()
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 and waited < 10 do
		task.wait(0.5)
		waited += 0.5
	end
end

local function accountPlaytime(player: Player, data: ProfileData)
	local mark = playtimeMark[player]
	if mark then
		local now = os.clock()
		local seconds = math.floor(now - mark)
		data.Lifetime.PlaytimeSeconds += seconds
		playtimeMark[player] = now - (now - mark) % 1
		if seconds > 0 then
			-- No-op for a player who is leaving (their profile is already detached).
			DataService.Replicate(player, { "Lifetime", "PlaytimeSeconds" })
		end
	end
end

-- Migrates, reconciles, repairs and resets loaded data. Returns the ready
-- data, or nil plus a player-facing message if the save must not be used.
local function prepareData(profile: ProfileStore.Profile): (ProfileData?, string?)
	local now = os.time()
	local data: ProfileData

	if profile.IsNew or profile.Data == nil then
		data = ProfileTemplate.CreateNew(now, newUid, Random.new())
	elseif type(profile.Data) ~= "table" then
		warn(`[DataService] {profile.Key}: data is not a table`)
		return nil, "Your save data could not be read. Please contact support."
	else
		local raw = profile.Data :: { [string]: any }
		local migration = Migrations.Run(raw)
		if not migration.Ok then
			warn(`[DataService] {profile.Key}: {migration.Error}`)
			if migration.FromVersion > Migrations.CurrentVersion then
				return nil, "This server is running an older version of the game. Please rejoin."
			end
			return nil, "Your save data could not be upgraded. Please contact support."
		end
		TableUtil.Reconcile(raw, ProfileTemplate.Template :: any)
		data = raw :: any
		local fixes = ProfileTemplate.Sanitize(data)
		if #fixes > 0 then
			warn(`[DataService] {profile.Key}: repaired data: {table.concat(fixes, "; ")}`)
		end
		if not data.Flags.StarterLoadoutGranted then
			ProfileTemplate.GrantStarterLoadout(data, now, newUid, Random.new())
		end
		ProfileTemplate.UpgradeStarterWeapons(data, now, newUid, Random.new())
	end

	Resets.Apply(data, now, GameConfig.Resets)
	data.LastLoginAt = now
	data.LoginCount += 1
	data.Lifetime.HighestPower = math.max(data.Lifetime.HighestPower, (PowerMath.HighestPossible(data.Items)))

	profile.Data = data
	return data
end

local function onPlayerAdded(player: Player)
	-- PlayerAdded and the startup GetPlayers() loop can both fire for one player.
	if profiles[player] or loadingPlayers[player] or shuttingDown then
		return
	end

	loadingPlayers[player] = true
	loadsInFlight += 1
	local key = GameConfig.Data.KeyPrefix .. player.UserId
	local profile, reason = store:LoadAsync(key, { player.UserId }, function()
		return player.Parent ~= Players or shuttingDown
	end)
	loadsInFlight -= 1
	loadingPlayers[player] = nil

	if profile == nil then
		if reason ~= "Cancelled" and player.Parent == Players then
			player:Kick(`We couldn't load your data ({reason}). Please rejoin in a moment.`)
		end
		return
	end

	local data, failure = prepareData(profile)
	if data == nil then
		-- Unlock without writing so the stored save stays untouched.
		profile:ReleaseAsync(false)
		if player.Parent == Players then
			player:Kick(failure)
		end
		return
	end

	if player.Parent ~= Players or shuttingDown then
		profile:ReleaseAsync()
		return
	end

	profiles[player] = profile
	playtimeMark[player] = os.clock()

	profile.Released:Connect(function(releaseReason: ProfileStore.ReleaseReason)
		if profiles[player] ~= profile then
			return -- normal release after leaving
		end
		profiles[player] = nil
		if player.Parent == Players then
			if releaseReason == "SessionLost" or releaseReason == "ForceLoaded" then
				player:Kick("Your profile was opened on another server. Please rejoin.")
			else
				player:Kick("Your session ended unexpectedly. Please rejoin.")
			end
		end
	end)

	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataBackend", backend)
	NetService.FireClient(player, "DataSnapshot", data)
	playerLoaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profiles[player] = nil
	accountPlaytime(player, profile.Data)
	playtimeMark[player] = nil
	playerReleasing:Fire(player, profile.Data)
	profile:ReleaseAsync()
end

-- Weekly/daily resets for players who stay online across the boundary.
local function applyResetsLive(player: Player, data: ProfileData)
	local result = Resets.Apply(data, os.time(), GameConfig.Resets)
	if result.Weekly then
		DataService.Replicate(player, { "Weekly" })
		NetService.Notify(player, "Weekly reset: Powerful and Pinnacle rewards are available again.", "Info")
	end
	if result.Daily then
		DataService.Replicate(player, { "Daily" })
	end
	if result.BountiesExpired > 0 then
		DataService.Replicate(player, { "Bounties" })
	end
end

-- Lifecycle -------------------------------------------------------------------------

function DataService.Init()
	local dataStore, chosen, reason = chooseBackend()
	backend = chosen :: Backend
	if backend == "Mock" then
		warn(
			`[DataService] Using an in-memory store because {reason}. Data will NOT persist between sessions. `
				.. "To test saving, publish the place and enable Game Settings > Security > "
				.. "Enable Studio Access to API Services."
		)
	end

	store = ProfileStore.new({
		Store = dataStore,
		Session = {
			PlaceId = game.PlaceId,
			JobId = game.JobId,
			SessionId = newUid(),
		},
		Settings = {
			LoadRetryDelay = GameConfig.Data.LoadRetryDelay,
			StealAfterAttempts = GameConfig.Data.StealAfterAttempts,
			MaxLoadAttempts = GameConfig.Data.MaxLoadAttempts,
			SessionStaleSeconds = GameConfig.Data.SessionStaleSeconds,
			MaxSaveAttempts = GameConfig.Data.MaxSaveAttempts,
			SaveRetryDelay = GameConfig.Data.SaveRetryDelay,
		},
		Clock = function(): number
			return os.time()
		end,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
		BeforeRequest = if backend == "DataStore" then waitForBudget else nil,
		-- Catch unsaveable values early while developing.
		Validate = if RunService:IsStudio()
			then function(value: any): (boolean, string?)
				return TableUtil.ValidateDataStoreValue(value, "Data")
			end
			else nil,
	})

	NetService.OnInvoke("RequestSnapshot", {}, function(player: Player)
		local profile = profiles[player]
		return if profile then profile.Data else nil
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave + live resets. Each profile saves on its own schedule, so
	-- saves are naturally spread out instead of all firing at once.
	task.spawn(function()
		while not shuttingDown do
			task.wait(1)
			local now = os.time()
			for player, profile in profiles do
				if now - profile.LastSavedAt >= GameConfig.Data.AutosaveInterval then
					profile.LastSavedAt = now -- don't queue a second save while this one runs
					accountPlaytime(player, profile.Data)
					applyResetsLive(player, profile.Data)
					task.spawn(profile.SaveAsync, profile)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player, profile in profiles do
			profiles[player] = nil
			accountPlaytime(player, profile.Data)
			pending += 1
			task.spawn(function()
				profile:ReleaseAsync()
				pending -= 1
			end)
		end
		local deadline = os.clock() + GameConfig.Data.ShutdownTimeout
		while (pending > 0 or loadsInFlight > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Reading ------------------------------------------------------------------------------

-- The live data table for a loaded player (nil if not loaded). Treat it as
-- read-only outside DataService; change data through the helpers below.
function DataService.GetData(player: Player): ProfileData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Yields until the player's data is loaded, they leave, or `timeout` passes.
function DataService.WaitForData(player: Player, timeout: number?): ProfileData?
	local deadline = os.clock() + (timeout or 60)
	while profiles[player] == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.GetData(player)
end

function DataService.GetBackend(): Backend
	return backend
end

-- Writing + replication ------------------------------------------------------------------

-- Sends the current value at `path` to the owning client.
function DataService.Replicate(player: Player, path: { string })
	local profile = profiles[player]
	if profile then
		NetService.FireClient(player, "DataChanged", path, TableUtil.GetPath(profile.Data, path))
	end
end

-- Sets a nested value and replicates it. Returns false if not loaded.
function DataService.Set(player: Player, path: { string }, value: any): boolean
	local profile = profiles[player]
	if profile == nil or #path == 0 then
		return false
	end
	TableUtil.SetPath(profile.Data, path, value)
	NetService.FireClient(player, "DataChanged", path, value)
	return true
end

-- Adds (or with a negative amount, removes) currency. Fails rather than
-- going negative; clamps to the currency cap. Returns (ok, newBalance).
function DataService.AddCurrency(player: Player, currency: string, amount: number): (boolean, number?)
	local data = DataService.GetData(player)
	local def = EconomyConfig.Currencies[currency]
	if data == nil or def == nil or amount ~= amount or math.abs(amount) == math.huge then
		return false, nil
	end
	amount = math.floor(amount)
	local balance = data.Currencies[currency] or 0
	if balance + amount < 0 then
		return false, balance
	end
	local newBalance = math.min(balance + amount, def.Cap)
	DataService.Set(player, { "Currencies", currency }, newBalance)
	return true, newBalance
end

function DataService.CanAfford(player: Player, costs: { [string]: number }): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	for currency, amount in costs do
		if EconomyConfig.Currencies[currency] == nil or (data.Currencies[currency] or 0) < amount then
			return false
		end
	end
	return true
end

-- Deducts every cost or none of them.
function DataService.Spend(player: Player, costs: { [string]: number }): boolean
	if not DataService.CanAfford(player, costs) then
		return false
	end
	for currency, amount in costs do
		DataService.AddCurrency(player, currency, -amount)
	end
	return true
end

function DataService.NewUid(): string
	return newUid()
end

-- Adds a rolled item to the character, or the postmaster if the slot is
-- full. Returns (ok, location). Fails when both are full.
function DataService.GiveItem(player: Player, item: ItemInstance): (boolean, Types.ItemLocation?)
	local data = DataService.GetData(player)
	if data == nil or data.Items[item.Uid] ~= nil then
		return false, nil
	end
	local location = Inventory.ResolveDropLocation(data, item.Slot)
	if location == nil then
		return false, nil
	end
	item.Location = location :: Types.ItemLocation
	item.Seen = false
	DataService.Set(player, { "Items", item.Uid }, item)

	local highest = PowerMath.HighestPossible(data.Items)
	if highest > data.Lifetime.HighestPower then
		DataService.Set(player, { "Lifetime", "HighestPower" }, highest)
	end
	return true, location :: Types.ItemLocation
end

-- Removes an item (unequipping it first). Returns the removed item.
function DataService.RemoveItem(player: Player, uid: string): ItemInstance?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local item = data.Items[uid]
	if item == nil then
		return nil
	end
	for slot, equippedUid in data.Equipped do
		if equippedUid == uid then
			DataService.Set(player, { "Equipped", slot }, nil)
		end
	end
	DataService.Set(player, { "Items", uid }, nil)
	return item
end

-- Saves immediately (outside the autosave schedule).
function DataService.SaveNow(player: Player): (boolean, string?)
	local profile = profiles[player]
	if profile == nil then
		return false, "NotLoaded"
	end
	accountPlaytime(player, profile.Data)
	return profile:SaveAsync()
end

-- Developer tool: replaces the player's data with a brand-new save.
function DataService.ResetProfile(player: Player): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	local data = ProfileTemplate.CreateNew(os.time(), newUid, Random.new())
	Resets.Apply(data, os.time(), GameConfig.Resets)
	profile.Data = data
	NetService.FireClient(player, "DataSnapshot", data)
	return true
end

-- Developer tool: forces the next reset check to reset weekly/daily data.
function DataService.ExpireResets(player: Player): boolean
	local data = DataService.GetData(player)
	if data == nil then
		return false
	end
	data.Weekly.ResetAt = 0
	data.Daily.ResetAt = 0
	applyResetsLive(player, data)
	return true
end

return DataService
