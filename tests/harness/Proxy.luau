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
	Models also get simple versions of GetPivot, PivotTo and GetBoundingBox
	(axis-aligned, from their parts), which Lune doesn't have.
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

-- A do-nothing stand-in: callable, connectable, and any member of it is
-- another stub (e.g. an AnimationTrack from a stubbed LoadAnimation).
local function stub()
	return setmetatable(Proxy.Signal(), {
		__call = function()
			return stub()
		end,
		__index = function(self, key)
			local child = stub()
			rawset(self, key, child)
			return child
		end,
	})
end

function Proxy.Unwrap(value)
	return reals[value] or value
end

local wrap

local function baseParts(model)
	local list = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function pivotOf(model)
	local primary = model.PrimaryPart
	if primary then
		return primary.CFrame
	end
	local parts = baseParts(model)
	return if #parts > 0 then parts[1].CFrame else roblox.CFrame.new()
end

-- Engine methods Lune lacks, for Models.
local MODEL_METHODS = {
	GetPivot = function(real)
		return pivotOf(real)
	end,
	PivotTo = function(real, target)
		local delta = target * pivotOf(real):Inverse()
		for _, part in baseParts(real) do
			part.CFrame = delta * part.CFrame
		end
	end,
	GetBoundingBox = function(real)
		local parts = baseParts(real)
		if #parts == 0 then
			return roblox.CFrame.new(), roblox.Vector3.zero
		end
		local low = parts[1].CFrame.Position
		local high = low
		for _, part in parts do
			local half = part.Size / 2
			local position = part.CFrame.Position
			low = low:Min(position - half)
			high = high:Max(position + half)
		end
		return roblox.CFrame.new((low + high) / 2), high - low
	end,
}

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
			local modelMethod = MODEL_METHODS[key]
			if modelMethod and real:IsA("Model") then
				return function(_, ...)
					local args = table.pack(...)
					for i = 1, args.n do
						args[i] = Proxy.Unwrap(args[i])
					end
					return modelMethod(real, table.unpack(args, 1, args.n))
				end
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
