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
	-- access (Studio, or listed in GameConfig.Debug.AdminUserIds).
	DebugCommand = {
		Kind = "Event",
		Direction = "ToServer",
		RateLimit = { Rate = 4, Burst = 8 },
	},
}

Remotes.Definitions = Definitions

return Remotes
