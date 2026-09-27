--[[
	Proxy
	Wraps Lune's real Roblox Instances for tests that run engine-facing code.
	Lune validates property names and value types (what we want to test) but
	has no events (Activated, Triggered...) and few engine methods (PivotTo).
	A proxy forwards every property and method to the real Instance and
	returns a stub signal for members Lune doesn't implement; calling a stub
	(e.g. model:PivotTo(cf)) does nothing and returns another stub.

	  Proxy.Instance.new(className)  drop-in replacement for the Instance global
	  Proxy.Signal()                 a recordable signal: Connect / Fire / Wait
	  Proxy.Wrap(realInstance)       proxy for an existing real Instance
	  Proxy.Unwrap(proxy)            the real Instance behind a proxy
	  Proxy.Register(stub, real)     treat a hand-made stub table as `real`
	                                 when it's assigned to Parent
]]

local roblox = require("@lune/roblox")

local Proxy = {}

local proxies = setmetatable({}, { __mode = "k" })
local reals = setmetatable({}, { __mode = "k" })

function Proxy.Signal()
	local handlers = {}
	local signal = {}
	signal._handlers = handlers
	function signal.Connect(_, fn)
		table.insert(handlers, fn)
		return {
			Connected = true,
			Disconnect = function() end,
		}
	end
	signal.Once = signal.Connect
	function signal.Wait() end
	function signal.Fire(_, ...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return signal
end

local function stub()
	return setmetatable(Proxy.Signal(), {
		__call = function()
			return stub()
		end,
	})
end

function Proxy.Unwrap(value)
	return reals[value] or value
end

local wrap

local function proxyOf(real)
	local existing = proxies[real]
	if existing then
		return existing
	end
	local missing = {}
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "Position" and real:IsA("BasePart") then
				-- Derived (not serialized) in Roblox, so Lune doesn't know it.
				return real.CFrame.Position
			end
			local ok, value = pcall(function()
				return real[key]
			end)
			if not ok then
				missing[key] = missing[key] or stub()
				return missing[key]
			end
			if type(value) == "function" then
				return function(_, ...)
					local args = table.pack(...)
					for i = 1, args.n do
						args[i] = Proxy.Unwrap(args[i])
					end
					return wrap(value(real, table.unpack(args, 1, args.n)))
				end
			end
			return wrap(value)
		end,
		__newindex = function(_, key, value)
			local unwrapped = Proxy.Unwrap(value)
			if key == "Parent" and type(unwrapped) == "table" then
				return -- parented to a fake (VirtualGame) instance: not tracked
			end
			if key == "Position" and real:IsA("BasePart") then
				real.CFrame = real.CFrame.Rotation + unwrapped
				return
			end
			real[key] = unwrapped
		end,
		__tostring = function()
			return tostring(real)
		end,
	})
	proxies[real] = proxy
	reals[proxy] = real
	return proxy
end

wrap = function(value, ...)
	if typeof(value) == "Instance" then
		return proxyOf(value), ...
	elseif type(value) == "table" and reals[value] == nil and getmetatable(value) == nil then
		local list = {}
		for index, item in value do
			list[index] = if typeof(item) == "Instance" then proxyOf(item) else item
		end
		return list, ...
	end
	return value, ...
end

Proxy.Wrap = proxyOf

function Proxy.Register(stubTable, real)
	reals[stubTable] = real
end

Proxy.Instance = {
	new = function(className, parent)
		local real = roblox.Instance.new(className)
		local proxy = proxyOf(real)
		if parent then
			proxy.Parent = parent
		end
		return proxy
	end,
}

return Proxy
