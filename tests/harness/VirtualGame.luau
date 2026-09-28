--[[
	VirtualGame
	A tiny stand-in for the Roblox DataModel so game modules can be unit
	tested with Lune, outside Studio.

	It mirrors default.project.json by reading src/ with Rojo's file rules
	(folders, *.luau ModuleScripts, *.server.luau / *.client.luau scripts,
	init.luau folders) into fake Instances, and provides a `require` that
	accepts those fake ModuleScripts. Every module runs in an environment
	with `script`, `game`, `require` and the few Roblox globals the pure
	modules need (Color3, Random, task, ...).

	Only modules that avoid engine services (or receive them injected) can
	run here; that is exactly the logic worth unit testing.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local VirtualGame = {}

-- Instance proxies for engine-facing tests (see Proxy.luau).
VirtualGame.Proxy = require("./Proxy")

-- Fake Instances --------------------------------------------------------------

local Methods = {}
local InstanceMeta = {}

InstanceMeta.__index = function(self, key)
	local method = Methods[key]
	if method then
		return method
	end
	local child = rawget(self, "_children")[key]
	if child then
		return child
	end
	error(`{key} is not a valid member of {rawget(self, "Name")}`, 2)
end

InstanceMeta.__tostring = function(self)
	return rawget(self, "Name")
end

local function newInstance(name, className, parent)
	local instance = setmetatable({
		Name = name,
		ClassName = className,
		Parent = parent,
		_children = {},
		_order = {},
		_attributes = {},
	}, InstanceMeta)
	if parent then
		assert(parent._children[name] == nil, `duplicate child {name} under {parent.Name}`)
		parent._children[name] = instance
		table.insert(parent._order, instance)
	end
	return instance
end

function Methods.FindFirstChild(self, name)
	return self._children[name]
end

function Methods.WaitForChild(self, name)
	local child = self._children[name]
	if child == nil then
		error(`Infinite yield: {name} never appears under {self:GetFullName()}`, 2)
	end
	return child
end

function Methods.GetChildren(self)
	return table.clone(self._order)
end

function Methods.IsA(self, className)
	return self.ClassName == className
end

function Methods.GetFullName(self)
	local parts = {}
	local node = self
	while node and node.ClassName ~= "DataModel" do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

function Methods.GetAttribute(self, name)
	return self._attributes[name]
end

function Methods.SetAttribute(self, name, value)
	self._attributes[name] = value
end

function Methods.GetService(self, name)
	local service = self._children[name] or VirtualGame.Services[name]
	if service == nil then
		error(`VirtualGame has no service {name} (inject a mock in VirtualGame.Services)`, 2)
	end
	return service
end

-- Deterministic stand-in for Roblox's Random (Park-Miller LCG).
local FakeRandom = {}
FakeRandom.__index = FakeRandom

function FakeRandom.new(seed)
	local state = math.floor(seed or (os.clock() * 1e6)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ _state = state }, FakeRandom)
end

function FakeRandom:_next()
	self._state = (self._state * 48271) % 2147483647
	return self._state
end

function FakeRandom:NextNumber(min, max)
	local unit = (self:_next() - 1) / 2147483646
	if min ~= nil then
		return min + unit * (max - min)
	end
	return unit
end

function FakeRandom:NextInteger(min, max)
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

VirtualGame.Random = FakeRandom

-- Building the tree from disk --------------------------------------------------

local function join(a, b)
	return a .. "/" .. b
end

local function scriptInfo(fileName)
	if fileName:match("%.server%.luau$") then
		return fileName:gsub("%.server%.luau$", ""), "Script"
	elseif fileName:match("%.client%.luau$") then
		return fileName:gsub("%.client%.luau$", ""), "LocalScript"
	elseif fileName:match("%.luau$") then
		return fileName:gsub("%.luau$", ""), "ModuleScript"
	end
	return nil, nil
end

local function loadDirectory(path, instance)
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local full = join(path, entry)
		if fs.isDir(full) then
			local className, source, sourcePath = "Folder", nil, nil
			for _, initName in { "init.luau", "init.server.luau", "init.client.luau" } do
				local initPath = join(full, initName)
				if fs.isFile(initPath) then
					local _, initClass = scriptInfo(initName)
					className, source, sourcePath = initClass, fs.readFile(initPath), initPath
				end
			end
			local child = newInstance(entry, className, instance)
			rawset(child, "_source", source)
			rawset(child, "_path", sourcePath or full)
			loadDirectory(full, child)
		elseif not entry:match("^init%.") then
			local name, className = scriptInfo(entry)
			if name then
				local child = newInstance(name, className, instance)
				rawset(child, "_source", fs.readFile(full))
				rawset(child, "_path", full)
			elseif entry:match("%.model%.json$") then
				local decoded = require("@lune/serde").decode("json", fs.readFile(full))
				newInstance(entry:gsub("%.model%.json$", ""), decoded.className or decoded.ClassName, instance)
			end
		end
	end
end

-- Services tests may swap in (Players, RunService, HttpService, ...).
VirtualGame.Services = {}

local game = newInstance("game", "DataModel", nil)
local replicatedStorage = newInstance("ReplicatedStorage", "ReplicatedStorage", game)
local shared = newInstance("Shared", "Folder", replicatedStorage)
loadDirectory("src/shared", shared)
local serverScriptService = newInstance("ServerScriptService", "ServerScriptService", game)
loadDirectory("src/server", serverScriptService)
local starterPlayer = newInstance("StarterPlayer", "StarterPlayer", game)
local starterPlayerScripts = newInstance("StarterPlayerScripts", "StarterPlayerScripts", starterPlayer)
loadDirectory("src/client", starterPlayerScripts)
local starterGui = newInstance("StarterGui", "StarterGui", game)
loadDirectory("src/gui", starterGui)

VirtualGame.game = game

-- require for fake ModuleScripts -----------------------------------------------

local cache = {}
local loading = {}
local extraGlobals = {}

local function baseEnvironment()
	local env = {
		game = game,
		workspace = nil,
		Random = FakeRandom,
		Color3 = roblox.Color3,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		task = task,
	}
	for key, value in extraGlobals do
		env[key] = value
	end
	return env
end

local virtualRequire

local function loadChunk(source, debugName, env)
	return luau.load(source, { debugName = debugName, environment = env })
end

virtualRequire = function(target)
	if type(target) == "string" then
		return require(target)
	end
	assert(getmetatable(target) == InstanceMeta, "require expects a ModuleScript")
	assert(target.ClassName == "ModuleScript", `{target:GetFullName()} is a {target.ClassName}, not a ModuleScript`)
	local cached = cache[target]
	if cached then
		return cached.value
	end
	if loading[target] then
		error(`Cyclic require of {target:GetFullName()}`, 2)
	end
	loading[target] = true
	local env = baseEnvironment()
	env.script = target
	env.require = virtualRequire
	local results = table.pack(loadChunk(rawget(target, "_source"), rawget(target, "_path"), env)())
	loading[target] = nil
	if results.n ~= 1 then
		error(`{target:GetFullName()} returned {results.n} values; modules must return exactly one`, 2)
	end
	cache[target] = { value = results[1] }
	return results[1]
end

VirtualGame.require = virtualRequire

-- Makes `require(moduleScript)` return `value` (e.g. a fake network layer).
function VirtualGame.Preload(moduleScript, value)
	cache[moduleScript] = { value = value }
end

-- Adds globals visible to modules loaded after this call (e.g. test mocks).
function VirtualGame.SetGlobal(name, value)
	extraGlobals[name] = value
end

-- Runs a test file with the virtual environment plus `extra` globals.
function VirtualGame.RunFile(path, extra)
	local env = baseEnvironment()
	env.require = virtualRequire
	env.script = nil
	for key, value in extra do
		env[key] = value
	end
	loadChunk(fs.readFile(path), path, env)()
end

-- Clears the module cache and mocked globals so each spec file starts fresh.
function VirtualGame.ResetModules()
	table.clear(cache)
	table.clear(extraGlobals)
end

return VirtualGame
