--!strict
--[[
	Steps
	Runs one step of a zone (ActivityConfig.StepDef). Every runner returns
	true when the step is done and false when the run stopped (wipe,
	completion, everyone left).

	  Travel    reach the marker box Target
	  Waves     wave after wave: the next arrives when Advance of the current
	            one is down or after Timer seconds; done when all are dead
	  Defend    progress only while someone stands in Target; waves keep coming
	  Survive   stay alive for Duration seconds; waves keep coming
	  Destroy   destroy the objects spawned at Target_1..Count; waves keep coming
	  Interact  hold E at the console marker Target
	  Patrol    send enemies walking the Spawns points in a loop (done at once)
	  Boss      BossFight
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local MissionRules = require(Shared.Activities.MissionRules)

local Services = script.Parent.Parent.Services
local CharacterService = require(Services.CharacterService)
local EnemyService = require(Services.EnemyService)
local BossFight = require(script.Parent.BossFight)
local MapMarkers = require(script.Parent.MapMarkers)
local MissionKit = require(script.Parent.MissionKit)
local RunTypes = require(script.Parent.RunTypes)
local Spawner = require(script.Parent.Spawner)

type Run = RunTypes.Run
type StepDef = ActivityConfig.StepDef
type ZoneDef = ActivityConfig.ZoneDef
type WaveDef = ActivityConfig.WaveDef

local Steps = {}

local now = MissionKit.Now
local TICK = 0.2

-- Unique tag prefix for the current step (and wipe attempt).
local function stepTag(run: Run, token: number): string
	return `z{run.ZoneIndex}s{run.StepIndex}_{token}`
end

local function spawnsOf(step: StepDef, zone: ZoneDef): string
	return step.Spawns or zone.Id
end

-- Waves that keep coming during Defend/Survive/Destroy/Interact steps.
type Pressure = { Next: number, Index: number, Tag: string }

local function newPressure(run: Run, token: number): Pressure
	return { Next = now() + 2, Index = 0, Tag = `{stepTag(run, token)}_p` }
end

local function applyPressure(run: Run, token: number, step: StepDef, zone: ZoneDef, pressure: Pressure)
	local waves = step.Waves
	if waves == nil or #waves == 0 or now() < pressure.Next then
		return
	end
	pressure.Next = now() + (step.WaveInterval or CombatConfig.Missions.WaveInterval)
	if MissionKit.AliveInRun(run) >= CombatConfig.Missions.MaxAlive then
		return
	end
	pressure.Index = pressure.Index % #waves + 1
	Spawner.SpawnWave(run, token, waves[pressure.Index], spawnsOf(step, zone), pressure.Tag)
end

-- Travel ------------------------------------------------------------------------------

local function travel(run: Run, token: number, step: StepDef): boolean
	local zone = MissionKit.Marker(run, step.Target)
	if zone == nil then
		warn(`[Steps] Travel target {step.Target} missing`)
		return true
	end
	MissionKit.SetObjective(run, step.Text, nil, nil, zone.Position)
	while MissionKit.IsActive(run, token) do
		if #MissionKit.PlayersInZone(run, zone) > 0 then
			return true
		end
		task.wait(TICK)
	end
	return false
end

-- Waves --------------------------------------------------------------------------------

local function waves(run: Run, token: number, step: StepDef, zone: ZoneDef): boolean
	local list = (step.Waves or {}) :: { WaveDef }
	local base = stepTag(run, token)
	local total = MissionRules.StepSize(step, #run.Players)
	local advance = step.Advance or CombatConfig.Missions.Advance
	local timer = step.Timer or CombatConfig.Missions.WaveTimer
	local lastShown = ""

	local function show(index: number)
		local kills = math.min(MissionKit.KillsWithTag(run, base, true), total)
		local count = `{kills}/{total}`
		local text = if #list > 1 then `{step.Text}  ·  wave {index}/{#list}` else step.Text
		if count .. text ~= lastShown then
			lastShown = count .. text
			MissionKit.SetObjective(run, text, count, if total > 0 then kills / total else 1)
		end
	end

	for index, wave in list do
		-- Don't flood the arena.
		while MissionKit.IsActive(run, token) and MissionKit.AliveInRun(run) >= CombatConfig.Missions.MaxAlive do
			show(index)
			task.wait(TICK)
		end
		if not MissionKit.IsActive(run, token) then
			return false
		end
		local tag = `{base}_{index}`
		local size = Spawner.SpawnWave(run, token, wave, spawnsOf(step, zone), tag)
		MissionKit.SetAttr(run, "Wave", `{index}/{#list}`)
		local startedAt = now()
		local last = index == #list
		while MissionKit.IsActive(run, token) do
			show(index)
			if last then
				local remaining = MissionKit.AliveWithTag(run, base, true) + MissionKit.PendingWithTag(run, base, true)
				if remaining == 0 then
					break
				end
			else
				local down = run.Kills[tag] or 0
				if size == 0 or down >= size * advance or now() - startedAt >= timer then
					break
				end
			end
			task.wait(TICK)
		end
	end
	MissionKit.SetAttr(run, "Wave", "")
	if MissionKit.IsActive(run, token) then
		MissionKit.SetObjective(run, step.Text, `{total}/{total}`, 1)
		return true
	end
	return false
end

-- Defend / Survive ------------------------------------------------------------------------

local function hold(run: Run, token: number, step: StepDef, zone: ZoneDef, needZone: boolean): boolean
	local marker = if needZone then MissionKit.Marker(run, step.Target) else nil
	local hasMarker = marker ~= nil
	if needZone and not hasMarker then
		warn(`[Steps] Defend zone {step.Target} missing`)
		return true
	end
	local duration = step.Duration or 30
	local progress = 0
	local lastTick = now()
	local pressure = newPressure(run, token)
	local waypoint = if marker then marker.Position else nil
	MissionKit.SetObjective(run, step.Text, "0%", 0, waypoint)
	while MissionKit.IsActive(run, token) do
		local current = now()
		local dt = current - lastTick
		lastTick = current
		applyPressure(run, token, step, zone, pressure)
		local counting = if marker
			then #MissionKit.PlayersInZone(run, marker) > 0
			else #MissionKit.AlivePlayers(run) > 0
		if counting then
			progress += dt
		end
		local fraction = math.min(1, progress / duration)
		local suffix = if counting or not hasMarker then "" else "  (stand in the zone!)"
		MissionKit.SetObjective(run, step.Text, `{math.floor(fraction * 100)}%{suffix}`, fraction, waypoint)
		if progress >= duration then
			return true
		end
		task.wait(TICK)
	end
	return false
end

-- Destroy ------------------------------------------------------------------------------------

local function destroy(run: Run, token: number, step: StepDef, zone: ZoneDef): boolean
	local markers = MapMarkers.Numbered(run.Markers, step.Target or "")
	local wanted = math.min(step.Count or #markers, #markers)
	if wanted == 0 then
		warn(`[Steps] Destroy targets {step.Target}_n missing`)
		return true
	end
	local tag = `{stepTag(run, token)}_obj`
	local objects: { EnemyService.Enemy } = {}
	for index = 1, wanted do
		local marker = markers[index]
		MissionKit.Cue(run, "Portal", marker.Position, 0.5)
		local object = Spawner.SpawnAt(run, step.Enemy or "RUST_GENERATOR", marker.CFrame, tag, false)
		if object then
			table.insert(objects, object)
		end
	end
	local pressure = newPressure(run, token)
	while MissionKit.IsActive(run, token) do
		applyPressure(run, token, step, zone, pressure)
		local left: EnemyService.Enemy? = nil
		local destroyed = 0
		for _, object in objects do
			if object.Dead then
				destroyed += 1
			elseif left == nil then
				left = object
			end
		end
		MissionKit.SetObjective(
			run,
			step.Text,
			`{destroyed}/{#objects}`,
			destroyed / math.max(1, #objects),
			if left then left.Root.Position else nil
		)
		if left == nil then
			return true
		end
		task.wait(TICK)
	end
	return false
end

-- Interact ------------------------------------------------------------------------------------

local function interact(run: Run, token: number, step: StepDef, zone: ZoneDef): boolean
	local marker = MissionKit.Marker(run, step.Target)
	if marker == nil then
		warn(`[Steps] Interact target {step.Target} missing`)
		return true
	end
	local used = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MissionInteract"
	prompt.ActionText = step.Text
	prompt.ObjectText = "Console"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = step.Duration or 1.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = marker
	local connection = prompt.Triggered:Connect(function(player: Player)
		if table.find(run.Players, player) and CharacterService.IsAlive(player) then
			used = true
		end
	end)
	local pressure = newPressure(run, token)
	MissionKit.SetObjective(run, step.Text, nil, nil, marker.Position)
	while MissionKit.IsActive(run, token) and not used do
		applyPressure(run, token, step, zone, pressure)
		task.wait(TICK)
	end
	connection:Disconnect()
	prompt:Destroy()
	return used and MissionKit.IsActive(run, token)
end

-- Patrol ------------------------------------------------------------------------------------

local function patrol(run: Run, token: number, step: StepDef, zone: ZoneDef): boolean
	local points = MapMarkers.SpawnPoints(run.Markers, spawnsOf(step, zone))
	if #points == 0 then
		warn(`[Steps] Patrol route {spawnsOf(step, zone)} missing`)
		return true
	end
	local route: { Vector3 } = {}
	for _, point in points do
		table.insert(route, point.Position)
	end
	local tag = `{stepTag(run, token)}_patrol`
	local list: { string } = {}
	for _, wave in (step.Waves or {}) :: { WaveDef } do
		for _, entry in MissionRules.WaveList(wave, #run.Players) do
			for _ = 1, entry.Count do
				table.insert(list, entry.Id)
			end
		end
	end
	-- Spread the walkers out along the route.
	for index, id in list do
		local start = math.floor((index - 1) * #route / #list) % #route + 1
		local options = MissionKit.SpawnOptions(run, tag, false)
		options.Patrol = route
		options.PatrolStart = start % #route + 1
		EnemyService.Spawn(id, points[start].CFrame, options)
	end
	MissionKit.SetObjective(run, step.Text, nil, nil, nil)
	return MissionKit.IsActive(run, token)
end

-- Dispatch ------------------------------------------------------------------------------------

function Steps.Run(run: Run, token: number, step: StepDef, zone: ZoneDef): boolean
	local kind = step.Kind
	if kind == "Travel" then
		return travel(run, token, step)
	elseif kind == "Waves" then
		return waves(run, token, step, zone)
	elseif kind == "Defend" then
		return hold(run, token, step, zone, true)
	elseif kind == "Survive" then
		return hold(run, token, step, zone, false)
	elseif kind == "Destroy" then
		return destroy(run, token, step, zone)
	elseif kind == "Interact" then
		return interact(run, token, step, zone)
	elseif kind == "Patrol" then
		return patrol(run, token, step, zone)
	elseif kind == "Boss" then
		return BossFight.Run(run, token, step, spawnsOf(step, zone))
	end
	warn(`[Steps] Step kind {kind} isn't built; skipping`)
	return true
end

return Steps
