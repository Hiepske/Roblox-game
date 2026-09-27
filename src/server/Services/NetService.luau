--!strict
--[[
	NetService
	Creates every remote from Shared.Net.Remotes and is the only place that
	listens to client traffic. Each ToServer handler is wrapped with:
	  * a per-player token bucket rate limit (from the remote's definition)
	  * argument validation (Guard checks; extra arguments are rejected)
	  * error isolation (a throwing handler never breaks the remote)
	Anything suspicious (bad arguments, spam, firing server->client remotes)
	adds suspicion points; past GameConfig.Security.KickThreshold the player
	is kicked. Points decay over time so honest lag spikes never add up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Guard = require(Shared.Net.Guard)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)

local NetService = {}

local events: { [string]: RemoteEvent } = {}
local unreliableEvents: { [string]: UnreliableRemoteEvent } = {}
local functions: { [string]: RemoteFunction } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local suspicion: { [Player]: { Score: number, UpdatedAt: number } } = {}

local function definition(name: string): Remotes.RemoteDef
	local def = Remotes.Definitions[name]
	assert(def, `Unknown remote {name}`)
	return def
end

-- Adds suspicion points to a player; kicks past the threshold.
function NetService.Flag(player: Player, points: number, reason: string)
	local security = GameConfig.Security
	local now = os.clock()
	local entry = suspicion[player]
	if entry == nil then
		entry = { Score = 0, UpdatedAt = now }
		suspicion[player] = entry
	end
	entry.Score = math.max(0, entry.Score - (now - entry.UpdatedAt) * security.DecayPerSecond) + points
	entry.UpdatedAt = now
	warn(`[NetService] {player.Name} ({player.UserId}) flagged +{points}: {reason} (score {math.floor(entry.Score)})`)
	if security.KickOnSuspicion and entry.Score >= security.KickThreshold then
		player:Kick("Disconnected: unexpected network activity.")
	end
end

-- Returns false (and flags lightly) when the player is over the rate limit.
local function allow(player: Player, name: string): boolean
	local limiter = limiters[name]
	if limiter and not limiter:Check(player) then
		NetService.Flag(player, 0.5, `rate limit on {name}`)
		return false
	end
	return true
end

function NetService.Init()
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FolderName

	for name, def in Remotes.Definitions do
		if def.Direction == "ToServer" then
			assert(def.RateLimit, `ToServer remote {name} must declare a RateLimit`)
		end
		if def.Kind == "Function" then
			assert(def.Direction == "ToServer", `RemoteFunction {name} must be ToServer (never invoke clients)`)
		end
		if def.RateLimit then
			limiters[name] = RateLimiter.new(def.RateLimit.Rate, def.RateLimit.Burst)
		end

		if def.Kind == "Function" then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			-- Until a handler is registered, invocations get nothing back.
			remote.OnServerInvoke = function(player: Player)
				allow(player, name)
				return nil
			end
			remote.Parent = folder
			functions[name] = remote
		elseif def.Kind == "Unreliable" then
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = folder
			unreliableEvents[name] = remote
			if def.Direction == "ToClient" then
				remote.OnServerEvent:Connect(function(player: Player)
					NetService.Flag(player, 5, `fired server->client remote {name}`)
				end)
			end
		else
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
			events[name] = remote
			if def.Direction == "ToClient" then
				remote.OnServerEvent:Connect(function(player: Player)
					NetService.Flag(player, 5, `fired server->client remote {name}`)
				end)
			end
		end
	end

	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player: Player)
		suspicion[player] = nil
		for _, limiter in limiters do
			limiter:Remove(player)
		end
	end)
end

-- Handles a client -> server event. `checks` validates each argument.
function NetService.OnEvent(name: string, checks: { Guard.Check }, handler: (Player, ...any) -> ())
	local def = definition(name)
	assert(def.Direction == "ToServer", `{name} is not a ToServer remote`)
	local remote: RemoteEvent | UnreliableRemoteEvent
	if def.Kind == "Unreliable" then
		remote = unreliableEvents[name]
	else
		remote = events[name]
	end
	assert(remote, `{name} is not an event (did NetService.Init run?)`)

	local function onEvent(player: Player, ...: any)
		if not allow(player, name) then
			return
		end
		local ok, err = Guard.Args(checks, table.pack(...))
		if not ok then
			NetService.Flag(player, 1, `{name}: {err}`)
			return
		end
		local success, handlerError = pcall(handler :: any, player, ...)
		if not success then
			warn(`[NetService] {name} handler error: {handlerError}`)
		end
	end

	if def.Kind == "Unreliable" then
		(remote :: UnreliableRemoteEvent).OnServerEvent:Connect(onEvent)
	else
		(remote :: RemoteEvent).OnServerEvent:Connect(onEvent)
	end
end

-- Handles a client -> server function call. Invalid calls return nil.
function NetService.OnInvoke(name: string, checks: { Guard.Check }, handler: (Player, ...any) -> ...any)
	local def = definition(name)
	assert(def.Kind == "Function", `{name} is not a RemoteFunction`)
	local remote = functions[name]
	assert(remote, `{name} was not created (did NetService.Init run?)`)

	remote.OnServerInvoke = function(player: Player, ...: any): ...any
		if not allow(player, name) then
			return nil
		end
		local ok, err = Guard.Args(checks, table.pack(...))
		if not ok then
			NetService.Flag(player, 1, `{name}: {err}`)
			return nil
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(`[NetService] {name} handler error: {results[2]}`)
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

function NetService.FireClient(player: Player, name: string, ...: any)
	local def = definition(name)
	assert(def.Direction == "ToClient", `{name} is not a ToClient remote`)
	if def.Kind == "Unreliable" then
		unreliableEvents[name]:FireClient(player, ...)
	else
		events[name]:FireClient(player, ...)
	end
end

function NetService.FireAllClients(name: string, ...: any)
	local def = definition(name)
	assert(def.Direction == "ToClient", `{name} is not a ToClient remote`)
	if def.Kind == "Unreliable" then
		unreliableEvents[name]:FireAllClients(...)
	else
		events[name]:FireAllClients(...)
	end
end

-- Convenience for toast messages. Kind: "Info" | "Success" | "Warning" | "Error".
function NetService.Notify(player: Player, message: string, kind: string?)
	NetService.FireClient(player, "Notify", message, kind or "Info")
end

return NetService
