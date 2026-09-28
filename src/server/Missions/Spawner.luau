--!strict
--[[
	Spawner
	Brings a wave (ActivityConfig.WaveDef) into a run:

	  * counts grow with the fireteam (MissionRules.WaveList)
	  * spawn points come from the map's EnemySpawns/<folder> markers;
	    points no player can see (behind them or behind cover) and at least
	    CombatConfig.Missions.SpawnMinDistance away are used first
	  * Portal   a rift opens at each point and the enemy steps out of it
	             PortalDelay seconds later
	    Dropship a ship flies in over one point and drops the whole wave
	             after DropshipDelay seconds
	    Ambush   enemies appear at once, silently (out of sight)
	  * while enemies are on their way they count as Pending for the tag, so
	    step runners never finish a wave early
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local MissionRules = require(Shared.Activities.MissionRules)

local Services = script.Parent.Parent.Services
local EnemyService = require(Services.EnemyService)
local WorldService = require(Services.WorldService)
local MapMarkers = require(script.Parent.MapMarkers)
local MissionKit = require(script.Parent.MissionKit)
local RunTypes = require(script.Parent.RunTypes)

type Run = RunTypes.Run

local Spawner = {}

local rng = Random.new()
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

-- Can any living player see this spot right now? Also returns the distance
-- to the nearest player.
local function seenFrom(run: Run, position: Vector3): (boolean, number)
	local nearest = math.huge
	local seen = false
	sightParams.FilterDescendantsInstances = {
		WorldService.Folder("Enemies"),
		WorldService.Folder("Pickups"),
		table.unpack(WorldService.PlayerCharacters()),
	}
	for _, root in MissionKit.AliveRoots(run) do
		local offset = position - root.Position
		local distance = offset.Magnitude
		nearest = math.min(nearest, distance)
		if not seen and distance < 300 then
			local look = root.CFrame.LookVector
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local facing = flatOffset.Magnitude < 1
				or flatLook.Magnitude < 0.01
				or flatOffset.Unit:Dot(flatLook.Unit) > 0.25
			if facing then
				local eye = root.Position + Vector3.new(0, 1.5, 0)
				local target = position + Vector3.new(0, 3, 0)
				local hit = Workspace:Raycast(eye, target - eye, sightParams)
				if hit == nil or (hit.Position - target).Magnitude < 3 then
					seen = true
				end
			end
		end
	end
	return seen, nearest
end

-- Spawn points ordered best-first: hidden and far, far, hidden, the rest.
function Spawner.Rank(run: Run, points: { BasePart }): { BasePart }
	local minDistance = CombatConfig.Missions.SpawnMinDistance
	type Scored = { Point: BasePart, Score: number }
	local scored: { Scored } = {}
	for _, point in points do
		local seen, nearest = seenFrom(run, point.Position)
		local score = (if seen then 0 else 2) + (if nearest >= minDistance then 3 else 0) + rng:NextNumber()
		table.insert(scored, { Point = point, Score = score })
	end
	table.sort(scored, function(a: Scored, b: Scored): boolean
		return a.Score > b.Score
	end)
	local ranked: { BasePart } = {}
	for _, entry in scored do
		table.insert(ranked, entry.Point)
	end
	return ranked
end

local function addPending(run: Run, tag: string, amount: number)
	run.Pending[tag] = math.max(0, (run.Pending[tag] or 0) + amount)
end

-- Spawns one enemy (the pending count for `tag` is released either way).
local function arrive(run: Run, token: number, id: string, cframe: CFrame, tag: string)
	addPending(run, tag, -1)
	if MissionKit.IsActive(run, token) then
		EnemyService.Spawn(id, cframe, MissionKit.SpawnOptions(run, tag, true))
	end
end

local function jitter(radius: number): Vector3
	return Vector3.new(rng:NextNumber(-radius, radius), 0, rng:NextNumber(-radius, radius))
end

-- Brings in `wave` for `tag` from spawn folder `folder` (the wave's own
-- Spawns overrides it). Returns how many enemies are on their way.
function Spawner.SpawnWave(run: Run, token: number, wave: ActivityConfig.WaveDef, folder: string, tag: string): number
	local list = MissionRules.WaveList(wave, #run.Players)
	local source = wave.Spawns or folder
	local points = MapMarkers.SpawnPoints(run.Markers, source)
	if #points == 0 then
		warn(`[Spawner] {run.Activity.Id}: no spawn markers for "{source}"`)
		return 0
	end
	local total = 0
	for _, entry in list do
		total += entry.Count
	end
	if total == 0 then
		return 0
	end
	addPending(run, tag, total)
	local arrival = wave.Arrival or "Portal"
	local missions = CombatConfig.Missions
	local ranked = Spawner.Rank(run, points)

	if arrival == "Dropship" then
		local drop = ranked[1]
		local ground = drop.Position
		MissionKit.Cue(run, "Dropship", ground, missions.DropshipDelay)
		task.delay(missions.DropshipDelay, function()
			for _, entry in list do
				for _ = 1, entry.Count do
					arrive(run, token, entry.Id, drop.CFrame + jitter(6), tag)
				end
			end
		end)
		return total
	end

	-- Portal / Ambush: spread the wave over the best points.
	local cursor = 0
	local opened: { [BasePart]: boolean } = {}
	for _, entry in list do
		for _ = 1, entry.Count do
			cursor = cursor % #ranked + 1
			local point = ranked[cursor]
			local cframe = point.CFrame + jitter(2.5)
			if arrival == "Ambush" then
				arrive(run, token, entry.Id, cframe, tag)
			else
				if not opened[point] then
					opened[point] = true
					MissionKit.Cue(run, "Portal", point.Position, missions.PortalDelay)
				end
				task.delay(missions.PortalDelay + rng:NextNumber() * 0.4, arrive, run, token, entry.Id, cframe, tag)
			end
		end
	end
	return total
end

-- One enemy (objects like generators, pylons) at a marker, with a rift.
function Spawner.SpawnAt(run: Run, id: string, cframe: CFrame, tag: string, aggro: boolean): EnemyService.Enemy?
	return EnemyService.Spawn(id, cframe, MissionKit.SpawnOptions(run, tag, aggro))
end

return Spawner
