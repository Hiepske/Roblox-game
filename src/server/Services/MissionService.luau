--!strict
--[[
	MissionService
	The shared zone flow every playable activity runs (ActivityService owns
	the instance, players, deaths and rewards; this walks the content).

	For each zone in MissionRules.ZoneList(activity):
	  1. entering: the respawn checkpoint moves to the zone's checkpoint
	     (Checkpoint, or the marker CP_<zone Id>), the zone's name pops up
	     on everyone's screen (run attribute ZoneName) and its timer starts
	  2. its steps run in order (Missions/Steps: travel, waves, defend,
	     survive, destroy, interact, boss)
	  3. cleared: its time goes into the zone log (Studio debug HUD), its
	     gate opens (Gate, or Gate_<zone Id>) and a finished raid encounter
	     is recorded for rewards

	Also here:
	  * falling below the map's KillY attribute puts you back at the
	    checkpoint (jumping puzzles, ledges)
	  * laser traps (parts tagged LL_Laser): clients draw them sweeping and
	    blinking; the server works out where each one is from the same
	    timing (shared/World/Motion) and burns players inside
	  * loot chests (where the last boss fell, or the arena's Chest marker)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MissionRules = require(Shared.Activities.MissionRules)
local Motion = require(Shared.World.Motion)

local CharacterService = require(script.Parent.CharacterService)
local EnemyService = require(script.Parent.EnemyService)
local NetService = require(script.Parent.NetService)

local Missions = script.Parent.Parent.Missions
local Gates = require(Missions.Gates)
local MapMarkers = require(Missions.MapMarkers)
local MissionKit = require(Missions.MissionKit)
local RunTypes = require(Missions.RunTypes)
local Steps = require(Missions.Steps)

local MapBuilders = script.Parent.Parent.MapBuilders
local MapKit = require(MapBuilders.MapKit)
local Props = require(MapBuilders.Props)

type Run = RunTypes.Run

local MissionService = {}

-- Studs below the map's origin that count as "fell off" when the map has no KillY.
local DEFAULT_KILL_Y = -150

local function enterZone(run: Run, entry: MissionRules.ZoneEntry)
	local zone = entry.Zone
	local checkpoint = zone.Checkpoint
	if checkpoint == nil and MapMarkers.Find(run.Markers, `CP_{zone.Id}`) then
		checkpoint = `CP_{zone.Id}`
	end
	if checkpoint then
		run.Checkpoint = checkpoint
	end
	run.ZoneStartedAt = MissionKit.Now()
	MissionKit.SetAttr(run, "ZoneName", zone.Name)
	MissionKit.SetAttr(run, "ZoneIndex", run.ZoneIndex)
	MissionKit.SetAttr(run, "ZoneStartedAt", run.ZoneStartedAt)
end

local function clearZone(run: Run, entry: MissionRules.ZoneEntry)
	local zone = entry.Zone
	run.ZoneLog = MissionRules.AppendZoneLog(run.ZoneLog, zone.Name, MissionKit.Now() - run.ZoneStartedAt)
	MissionKit.SetAttr(run, "ZoneLog", run.ZoneLog)
	local gate = zone.Gate or `Gate_{zone.Id}`
	if not Gates.Open(run, gate) and zone.Gate then
		warn(`[MissionService] {run.Activity.Id}: gate {zone.Gate} missing`)
	end
	-- Last zone of a raid encounter: the encounter is cleared.
	local nextEntry = run.Zones[run.ZoneIndex + 1]
	local encounter = entry.Encounter
	if encounter and (nextEntry == nil or nextEntry.Encounter ~= encounter) then
		table.insert(run.Cleared, encounter)
		for _, player in run.Players do
			NetService.Notify(player, `Encounter complete: {encounter.Name}`, "Success")
		end
		run.OnEncounterCleared(encounter)
	end
end

-- Walks the zones from the run's current zone/step. Returns true when the
-- last zone is cleared (false if the run stopped first).
function MissionService.Run(run: Run, token: number): boolean
	MissionKit.SetAttr(run, "ZoneCount", #run.Zones)
	while MissionKit.IsActive(run, token) and run.ZoneIndex <= #run.Zones do
		local entry = run.Zones[run.ZoneIndex]
		local zone = entry.Zone
		if run.StepIndex == 1 then
			enterZone(run, entry)
		end
		while MissionKit.IsActive(run, token) and run.StepIndex <= #zone.Steps do
			MissionKit.SetAttr(run, "StepIndex", run.StepIndex)
			local done = Steps.Run(run, token, zone.Steps[run.StepIndex], zone)
			if not done or not MissionKit.IsActive(run, token) then
				return false
			end
			run.StepIndex += 1
		end
		if not MissionKit.IsActive(run, token) then
			return false
		end
		clearZone(run, entry)
		run.ZoneIndex += 1
		run.StepIndex = 1
	end
	return MissionKit.IsActive(run, token)
end

-- A wipe restarts the encounter (raid) or the zone the fireteam is in.
function MissionService.Rewind(run: Run)
	run.ZoneIndex = MissionRules.EncounterStart(run.Zones, math.min(run.ZoneIndex, #run.Zones))
	run.StepIndex = 1
end

-- Dev /skip: moves on to the next step.
function MissionService.SkipStep(run: Run)
	local entry = run.Zones[run.ZoneIndex]
	if entry == nil then
		return
	end
	run.StepIndex += 1
	if run.StepIndex > #entry.Zone.Steps then
		clearZone(run, entry)
		run.ZoneIndex += 1
		run.StepIndex = 1
	end
end

-- Dev /zone: jumps to zone `index` (gates of the zones before it open).
-- Returns the zone's checkpoint marker name.
function MissionService.JumpTo(run: Run, index: number): string
	local target = math.clamp(math.floor(index), 1, #run.Zones)
	for earlier = 1, target - 1 do
		local zone = run.Zones[earlier].Zone
		Gates.Open(run, zone.Gate or `Gate_{zone.Id}`)
	end
	run.ZoneIndex = target
	run.StepIndex = 1
	local zone = run.Zones[target].Zone
	local checkpoint = zone.Checkpoint
	if checkpoint == nil and MapMarkers.Find(run.Markers, `CP_{zone.Id}`) then
		checkpoint = `CP_{zone.Id}`
	end
	run.Checkpoint = checkpoint or run.Checkpoint
	return run.Checkpoint
end

-- Players who fell off the map go back to the checkpoint. Enemies that fell
-- die (so waves still finish); a falling boss is put back on its spawn.
function MissionService.CheckFalls(run: Run)
	if run.Status ~= "Active" then
		return
	end
	local killY = tonumber(run.Map:GetAttribute("KillY")) or DEFAULT_KILL_Y
	local floor = run.Origin.Y + killY
	for _, player in run.Players do
		local root = MissionKit.RootOf(player)
		if root and CharacterService.IsAlive(player) and root.Position.Y < floor then
			CharacterService.Teleport(player, MissionKit.MarkerCFrame(run, run.Checkpoint))
			NetService.Notify(player, "Back to the checkpoint", "Info")
		end
	end
	for _, enemy in EnemyService.GetEnemies(run.Id) do
		if enemy.Root.Position.Y < floor then
			local spawn = run.BossSpawn
			if enemy == run.Boss and spawn then
				EnemyService.Relocate(enemy, spawn + Vector3.new(0, 3, 0))
			else
				EnemyService.Kill(enemy)
			end
		end
	end
end

-- Laser traps ------------------------------------------------------------------------------

local function hazardsOf(run: Run): { RunTypes.Hazard }
	local cached = run.Hazards
	if cached then
		return cached
	end
	local list: { RunTypes.Hazard } = {}
	for _, descendant in run.Map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:HasTag("LL_Laser") then
			local offset = descendant:GetAttribute("MoveOffset")
			table.insert(list, {
				Part = descendant,
				Base = descendant.CFrame,
				Offset = if typeof(offset) == "Vector3" then offset else Vector3.zero,
				Period = tonumber(descendant:GetAttribute("MovePeriod")) or 10,
				Dwell = tonumber(descendant:GetAttribute("MoveDwell")) or 0,
				Phase = tonumber(descendant:GetAttribute("MovePhase")) or 0,
				BlinkPeriod = tonumber(descendant:GetAttribute("LaserPeriod")) or 0,
				BlinkOn = tonumber(descendant:GetAttribute("LaserOn")) or 0.5,
				BlinkPhase = tonumber(descendant:GetAttribute("LaserPhase")) or 0,
				Damage = tonumber(descendant:GetAttribute("Damage")) or 45,
			})
		end
	end
	run.Hazards = list
	return list
end

-- Where a laser is right now (it may sweep), or nil while it's blinked off.
function MissionService.HazardCFrame(hazard: RunTypes.Hazard, time: number): CFrame?
	if not Motion.LaserOn(hazard.BlinkPeriod, hazard.BlinkOn, hazard.BlinkPhase, time) then
		return nil
	end
	if hazard.Offset.Magnitude < 0.01 then
		return hazard.Base
	end
	return Motion.MoverCFrame(hazard.Base, hazard.Offset, hazard.Period, hazard.Dwell, hazard.Phase, time)
end

-- Burns players standing in a live laser (at most once every 0.8 s).
function MissionService.CheckHazards(run: Run)
	if run.Status ~= "Active" then
		return
	end
	local list = hazardsOf(run)
	if #list == 0 then
		return
	end
	local t = MissionKit.Now()
	for _, hazard in list do
		local cframe = MissionService.HazardCFrame(hazard, t)
		if cframe then
			local half = hazard.Part.Size / 2 + Vector3.new(1.2, 2.5, 1.2)
			for _, player in run.Players do
				local root = MissionKit.RootOf(player)
				if root and CharacterService.IsAlive(player) and t >= (run.HazardCooldown[player] or 0) then
					local offset = cframe:PointToObjectSpace(root.Position)
					if
						math.abs(offset.X) <= half.X
						and math.abs(offset.Y) <= half.Y
						and math.abs(offset.Z) <= half.Z
					then
						run.HazardCooldown[player] = t + 0.8
						CharacterService.DamagePlayer(player, hazard.Damage, "Laser")
						MissionKit.Cue(run, "LaserHit", root.Position)
					end
				end
			end
		end
	end
end

-- Chests ------------------------------------------------------------------------------------

-- A loot chest: at the current arena's "Chest" marker, else where the last
-- boss fell, else the checkpoint. `onClaim` runs when a run player opens it.
function MissionService.SpawnChest(run: Run, onClaim: (Player) -> (), name: string?): Model
	local marker = MissionKit.ArenaMarker(run, run.Arena, "Chest")
	local at = if marker
		then marker.CFrame - Vector3.new(0, marker.Size.Y / 2, 0)
		else run.ChestAt or (MissionKit.MarkerCFrame(run, run.Checkpoint) - Vector3.new(0, 3, 0))
	local builder = MapKit.New("RewardChest")
	local chest = Props.Chest(builder, at, "REWARDS", run.Map)
	chest.Name = name or "RewardChest"
	for _, descendant in chest:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant.Name = "ClaimRewards"
			descendant.ObjectText = "Rewards"
			descendant.Triggered:Connect(function(player: Player)
				if table.find(run.Players, player) then
					onClaim(player)
				end
			end)
		end
	end
	MissionKit.Cue(run, "ChestDrop", at.Position)
	return chest
end

function MissionService.Init() end

function MissionService.Start() end

return MissionService
