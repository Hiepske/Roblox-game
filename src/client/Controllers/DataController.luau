--!strict
--[[
	DataController
	The client's read-only replica of its own saved data. The server sends a
	full snapshot when data loads (and after a profile reset) and path-based
	changes afterwards; UI code reads from here and listens to Changed.

	local DataController = require(...)
	local data = DataController.WaitForData()
	DataController.Observe({ "Currencies" }, function() refresh() end)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local TableUtil = require(Shared:WaitForChild("Util"):WaitForChild("TableUtil"))
local Types = require(Shared:WaitForChild("Types"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

type ProfileData = Types.ProfileData

local DataController = {}

local data: ProfileData? = nil

-- Fires with (path, value) for every change; path is {} for a full snapshot.
local changed: Signal.Signal<{ string }, any> = Signal.new()
DataController.Changed = changed

local loaded: Signal.Signal<ProfileData> = Signal.new()
DataController.Loaded = loaded

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	local isFirst = data == nil
	data = snapshot
	changed:Fire({}, snapshot)
	if isFirst then
		loaded:Fire(snapshot)
	end
end

function DataController.Init()
	ClientNet.On("DataSnapshot", applySnapshot)
	ClientNet.On("DataChanged", function(path: any, value: any)
		if data == nil or type(path) ~= "table" then
			return
		end
		TableUtil.SetPath(data :: any, path, value)
		changed:Fire(path, value)
	end)
end

function DataController.Start()
	-- The snapshot event normally arrives on its own; asking covers the case
	-- where this script started after the server already sent it.
	task.spawn(function()
		while data == nil do
			local snapshot = ClientNet.Invoke("RequestSnapshot")
			if snapshot then
				applySnapshot(snapshot)
				break
			end
			task.wait(3)
		end
	end)
end

function DataController.GetData(): ProfileData?
	return data
end

function DataController.WaitForData(): ProfileData
	while data == nil do
		loaded:Wait()
	end
	return data :: ProfileData
end

-- Calls `callback(path, value)` for changes at or below `prefix`, and for
-- full snapshots. Returns the connection.
function DataController.Observe(prefix: { string }, callback: ({ string }, any) -> ())
	return changed:Connect(function(path: { string }, value: any)
		if #path == 0 then
			callback(path, value)
			return
		end
		for index, key in prefix do
			local part = path[index]
			if part == nil then
				break -- a change above the prefix (e.g. whole table replaced)
			elseif part ~= key then
				return
			end
		end
		callback(path, value)
	end)
end

return DataController
