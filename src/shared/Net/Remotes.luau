--!strict
--[[
	Remotes
	Single source of truth for every RemoteEvent/RemoteFunction.

	The server creates these instances at startup (NetService) under
	ReplicatedStorage.Remotes; clients wait for them (ClientNet). Direction
	is enforced: a client firing a ToClient remote is flagged as suspicious,
	and RemoteFunctions are only ever invoked client -> server (the server
	never waits on a client).

	RateLimit is a token bucket per player: `Rate` requests per second with
	bursts up to `Burst`. Every ToServer remote must declare one.
]]

export type RemoteKind = "Event" | "Function" | "Unreliable"
export type Direction = "ToClient" | "ToServer"

export type RemoteDef = {
	Kind: RemoteKind,
	Direction: Direction,
	RateLimit: { Rate: number, Burst: number }?,
}

local Remotes = {}

Remotes.FolderName = "Remotes"

local Definitions: { [string]: RemoteDef } = {
	-- Player data replication (server -> client).
	DataSnapshot = { Kind = "Event", Direction = "ToClient" },
	DataChanged = { Kind = "Event", Direction = "ToClient" },

	-- Client asks for a fresh snapshot (e.g. after its UI reloads).
	RequestSnapshot = {
		Kind = "Function",
		Direction = "ToServer",
		RateLimit = { Rate = 0.5, Burst = 3 },
	},

	-- Toast-style messages for the player (server -> client).
	Notify = { Kind = "Event", Direction = "ToClient" },

	-- Developer tools. The server ignores these unless the player has debug
	-- access (Studio, the game owner, or GameConfig.Debug.AdminUserIds).
	DebugCommand = {
		Kind = "Event",
		Direction = "ToServer",
		RateLimit = { Rate = 4, Burst = 8 },
	},

	-- Weapons (client intents; the server validates everything) ---------------
	-- (slot, aimPoint: Vector3, shotId: number)
	WeaponFire = { Kind = "Event", Direction = "ToServer", RateLimit = { Rate = 25, Burst = 40 } },
	-- (slot)
	WeaponReload = { Kind = "Event", Direction = "ToServer", RateLimit = { Rate = 4, Burst = 8 } },
	-- (slot)
	WeaponSwitch = { Kind = "Event", Direction = "ToServer", RateLimit = { Rate = 8, Burst = 16 } },
	-- Server -> owner: magazines, reserves, active slot.
	WeaponState = { Kind = "Event", Direction = "ToClient" },

	-- Combat feedback and effects ---------------------------------------------------
	-- Server -> shooter: (position, amount, isPrecision, flags)
	CombatFeedback = { Kind = "Unreliable", Direction = "ToClient" },
	-- Server -> other clients: someone else's shot (origin, hitPosition, color)
	ShotEffect = { Kind = "Unreliable", Direction = "ToClient" },
	-- Server -> all: (id, origin, velocity, style)
	ProjectileSpawned = { Kind = "Event", Direction = "ToClient" },
	-- Server -> all: (id, position, exploded, radius)
	ProjectileEnded = { Kind = "Event", Direction = "ToClient" },
	-- Server -> everyone: (kind, ...) explosions, lightning arcs, singularities,
	-- sword slashes, spawn portals, boss telegraphs
	WorldEffect = { Kind = "Unreliable", Direction = "ToClient" },
	-- Server -> players in a run: (kind, ...) gameplay cues that must arrive:
	-- spawn rifts, dropships, boss telegraphs and safe zones, gates, boss death
	WorldCue = { Kind = "Event", Direction = "ToClient" },
	-- Server -> owner: alive/dead, respawn timer, revive state
	PlayerStatus = { Kind = "Event", Direction = "ToClient" },

	-- Activities --------------------------------------------------------------------
	-- Server -> players in an activity: objective tracker, timers, boss bar (nil in the hub)
	ActivityState = { Kind = "Event", Direction = "ToClient" },
	-- (activityId, difficultyId?) -> (ok, message)
	DirectorLaunch = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 1, Burst = 3 } },
	-- () -> list of running activities with room to join
	DirectorQuery = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 1, Burst = 4 } },
	-- (instanceId) -> (ok, message)
	DirectorJoin = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 1, Burst = 3 } },
	-- Leave the current activity and return to the hub.
	LeaveActivity = { Kind = "Event", Direction = "ToServer", RateLimit = { Rate = 1, Burst = 2 } },
	-- Server -> player: open the Director (terminal clicked)
	OpenDirector = { Kind = "Event", Direction = "ToClient" },
	-- Server -> player: open a screen, (menu, tab?) e.g. ("Inventory", "Vault")
	OpenMenu = { Kind = "Event", Direction = "ToClient" },

	-- Loot and inventory -------------------------------------------------------------
	-- Server -> player: (items, context) for toasts and the end-of-activity screen
	LootAwarded = { Kind = "Event", Direction = "ToClient" },
	-- (uid) -> (ok, message)
	EquipItem = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 5, Burst = 10 } },
	-- (uid) -> (ok, message)
	DismantleItem = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 5, Burst = 10 } },
	-- (uid) -> (ok, message)
	ToggleLock = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 5, Burst = 10 } },
	-- (uid, "Vault" | "Inventory") -> (ok, message)
	TransferItem = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 6, Burst = 15 } },
	-- (targetUid, fuelUid) -> (ok, message)
	InfuseItem = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 2, Burst = 4 } },
	-- (index 1-3) -> (ok, message)
	SaveLoadout = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 2, Burst = 4 } },
	ApplyLoadout = { Kind = "Function", Direction = "ToServer", RateLimit = { Rate = 1, Burst = 3 } },
	-- (uid): the player looked at a new item
	MarkSeen = { Kind = "Event", Direction = "ToServer", RateLimit = { Rate = 30, Burst = 60 } },
}

Remotes.Definitions = Definitions

return Remotes
