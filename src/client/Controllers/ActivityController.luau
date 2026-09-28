--!strict
--[[
	ActivityController
	Tracks which activity run the local player is in (ActivityState remote)
	and applies that map's lighting preset. The live numbers for the HUD
	(objective, boss health, phase, timer, score) are attributes on the run's
	folder in ReplicatedStorage.LiveRuns, which GetFolder returns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingPresets = require(Shared:WaitForChild("World"):WaitForChild("LightingPresets"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

export type ActivityInfo = {
	InActivity: boolean,
	RunId: string?,
	ActivityId: string?,
	Name: string?,
	Type: string?,
	Difficulty: string?,
	Power: number?,
	Map: string,
	Modifiers: { { Name: string, Description: string } },
	Scored: boolean,
	Destination: string?,
	StartedAt: number?,
	-- The intro fly-over: from the start toward the first objective.
	Intro: IntroShot?,
}

export type IntroShot = { Start: Vector3, Target: Vector3 }

local ActivityController = {}

local current: ActivityInfo = { InActivity = false, Map = "Hub", Modifiers = {}, Scored = false }
local folder: Folder? = nil
local appliedMap: string? = nil

-- Fires with the new ActivityInfo whenever the player enters or leaves a run.
local changed: Signal.Signal<ActivityInfo> = Signal.new()
ActivityController.Changed = changed

function ActivityController.Get(): ActivityInfo
	return current
end

-- The run's live attribute folder (nil in the hub or while it replicates).
function ActivityController.GetFolder(): Folder?
	return folder
end

local function parseIntro(intro: any): IntroShot?
	if type(intro) ~= "table" or typeof(intro.Start) ~= "Vector3" or typeof(intro.Target) ~= "Vector3" then
		return nil
	end
	return { Start = intro.Start, Target = intro.Target }
end

local function parse(state: any): ActivityInfo
	local modifiers = {}
	if type(state.Modifiers) == "table" then
		for _, modifier in state.Modifiers do
			if type(modifier) == "table" then
				table.insert(
					modifiers,
					{ Name = tostring(modifier.Name), Description = tostring(modifier.Description) }
				)
			end
		end
	end
	return {
		InActivity = state.InActivity == true,
		RunId = if type(state.RunId) == "string" then state.RunId else nil,
		ActivityId = if type(state.ActivityId) == "string" then state.ActivityId else nil,
		Name = if type(state.Name) == "string" then state.Name else nil,
		Type = if type(state.Type) == "string" then state.Type else nil,
		Difficulty = if type(state.Difficulty) == "string" then state.Difficulty else nil,
		Power = if type(state.Power) == "number" then state.Power else nil,
		Map = if type(state.Map) == "string" then state.Map else "Hub",
		Modifiers = modifiers,
		Scored = state.Scored == true,
		Destination = if type(state.Destination) == "string" then state.Destination else nil,
		StartedAt = if type(state.StartedAt) == "number" then state.StartedAt else nil,
		Intro = parseIntro(state.Intro),
	}
end

function ActivityController.Init()
	ClientNet.On("ActivityState", function(state: any)
		if type(state) ~= "table" then
			return
		end
		local info = parse(state)
		current = info
		folder = nil
		if info.RunId then
			local live = ReplicatedStorage:WaitForChild("LiveRuns", 10)
			local found = if live then live:WaitForChild(info.RunId, 10) else nil
			if current ~= info then
				return -- a newer state arrived while waiting
			end
			folder = if found and found:IsA("Folder") then found else nil
		end
		if appliedMap ~= info.Map then
			appliedMap = info.Map
			LightingPresets.Apply(info.Map)
		end
		changed:Fire(info)
	end)
end

function ActivityController.Start() end

return ActivityController
