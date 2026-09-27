--!strict
--[[
	Signal
	A lightweight event object (like BindableEvent without Instance overhead).

	local changed = Signal.new() :: Signal.Signal<string, number>
	local connection = changed:Connect(function(name, value) ... end)
	changed:Fire("Quanta", 100)
	connection:Disconnect()

	Handlers run in their own threads (task.spawn), so one erroring or
	yielding handler never blocks the others or the code that fired.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	type Entry = { handler: (T...) -> (), connection: Connection }
	local entries: { Entry } = {}

	local function remove(connection: Connection)
		for index, entry in entries do
			if entry.connection == connection then
				table.remove(entries, index)
				return
			end
		end
	end

	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, handler: (T...) -> ()): Connection
		local connection = {} :: Connection
		connection.Connected = true
		function connection.Disconnect(conn: Connection)
			if conn.Connected then
				conn.Connected = false
				remove(conn)
			end
		end
		table.insert(entries, { handler = handler, connection = connection })
		return connection
	end

	function self.Once(signal: Signal<T...>, handler: (T...) -> ()): Connection
		local connection: Connection
		connection = signal:Connect(function(...: T...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		-- Snapshot so handlers can connect/disconnect while we iterate.
		local snapshot = table.clone(entries)
		for _, entry in snapshot do
			if entry.connection.Connected then
				task.spawn(entry.handler, ...)
			end
		end
	end

	function self.Wait(signal: Signal<T...>): T...
		local thread = coroutine.running()
		signal:Once(function(...: T...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.DisconnectAll(_: Signal<T...>)
		for _, entry in entries do
			entry.connection.Connected = false
		end
		table.clear(entries)
	end

	return self
end

return Signal
