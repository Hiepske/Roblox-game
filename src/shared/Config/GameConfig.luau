--!strict
--[[
	GameConfig
	Game-wide settings: saving, inventory sizes, resets, new player setup,
	anti-exploit thresholds and developer tools.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local GameConfig = {
	Title = "LAST LIGHT",
	Version = "0.1.0",

	Data = {
		-- Changing StoreName starts everyone fresh (new DataStore).
		StoreName = "LastLight_Profiles_v1",
		KeyPrefix = "Player_",
		AutosaveInterval = 60,
		-- A session lock not refreshed for this long is considered dead.
		SessionStaleSeconds = 600,
		-- Loading someone else's locked profile: retry every LoadRetryDelay
		-- seconds; from attempt StealAfterAttempts on, take the lock anyway.
		LoadRetryDelay = 4,
		StealAfterAttempts = 8,
		MaxLoadAttempts = 12,
		MaxSaveAttempts = 3,
		SaveRetryDelay = 2,
		-- Seconds BindToClose waits for final saves (Roblox allows 30).
		ShutdownTimeout = 25,
		-- true = Studio always uses an in-memory store (nothing persists).
		-- false = Studio uses real DataStores when API access is enabled.
		UseMockInStudio = false,
	},

	Inventory = {
		-- Items per gear slot on the character, not counting the equipped one.
		SlotCapacity = 9,
		VaultCapacity = 200,
		PostmasterCapacity = 21,
	},

	Resets = {
		-- 0 = Sunday ... 6 = Saturday. Weekly reset: Tuesday 17:00 UTC.
		WeeklyWeekday = 2,
		HourUtc = 17,
	},

	NewPlayer = {
		Class = "Bulwark",
		Subclasses = { Bulwark = "Emberwall", Ranger = "Shadewalker", Mystic = "Sunweaver" } :: { [string]: string },
		Currencies = { Quanta = 1500, Alloy = 0, Fluxite = 0, Starglass = 0 } :: { [string]: number },
		-- Base-rolled at PowerConfig.StartingPower and equipped on first join.
		StarterLoadout = {
			Kinetic = "W_FRONTIER_STANDARD",
			Energy = "W_LAST_EMBER",
			Heavy = "W_SCRAPFIRE_TUBE",
			Helmet = "A_FRONTIER_HELMET",
			Arms = "A_FRONTIER_ARMS",
			Chest = "A_FRONTIER_CHEST",
			Legs = "A_FRONTIER_LEGS",
			ClassItem = "A_FRONTIER_CLASSITEM",
		} :: { [string]: string },
	},

	DefaultSettings = {
		MouseSensitivity = 0.5,
		AimSensitivityScale = 0.8,
		ControllerSensitivity = 0.5,
		FieldOfView = 70,
		InvertY = false,
		ShowDamageNumbers = true,
	},

	Security = {
		-- Suspicion points before a player is kicked; points decay over time.
		KickThreshold = 30,
		DecayPerSecond = 0.1,
		KickOnSuspicion = true,
	},

	Activities = {
		-- false: activities run as map copies far from the hub inside this server
		-- (works in Studio). true: each activity gets its own Reserved Server via
		-- TeleportService (needs a published game and AssetIds.Places filled in).
		USE_RESERVED_SERVERS = false,
		-- The raid is built for 6 but can be launched with this many for testing.
		RAID_MIN_PLAYERS = 1,
		-- Map copies are placed at X = InstanceSpacing * slot.
		InstanceSpacing = 5000,
		MaxInstances = 8,
		-- Seconds after the last zone before everyone returns to the hub (the
		-- loot chest can be opened until then; unopened rewards are sent anyway).
		ReturnToHubDelay = 30,
	},

	Debug = {
		-- Master switch for the developer panel, debug remotes and chat commands.
		Enabled = true,
		-- Anyone testing in Studio gets debug access.
		AllowInStudio = true,
		-- The experience owner (user-owned games) gets debug access in live servers.
		AllowGameOwner = true,
		-- UserIds with debug access in live servers. Keep this short.
		AdminUserIds = {} :: { number },
	},
}

return TableUtil.DeepFreeze(GameConfig)
