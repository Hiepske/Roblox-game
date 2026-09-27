--!strict
--[[
	ActivityService
	Runs story missions, the hardened strike (Nightfall) and raid encounters.

	Instances ("runs"): with GameConfig.Activities.USE_RESERVED_SERVERS off
	(the default, so everything works in Studio), each launch clones the
	activity's map Model from ServerStorage.Activities into Workspace.Instances
	at X = InstanceSpacing * slot, moves the fireteam there, and deletes it
	afterwards. With the flag on (and place ids in AssetIds.Places) launches
	teleport to a reserved server instead; that server reads the teleport data
	and runs the activity the same way (see launchReserved / Start).

	Objective runner: walks ActivityRules.ObjectiveList(activity) in order.
	  Travel  reach the zone marker
	  Defeat  kill everything spawned from the objective's Spawns
	  Defend  keep someone inside the zone for Duration seconds; waves arrive
	  Boss    Standard (adds at a health threshold), ImmuneAdds (immune while
	          its bodyguard lives), EchoPlates (raid: plates -> damage phase,
	          adds, enrage)
	Completing an objective moves the checkpoint and opens its door.

	Deaths (CharacterService resolver):
	  hub                respawn after CombatConfig.Respawn.Hub seconds
	  story / Nightfall  respawn at the last checkpoint
	  raid, solo         respawn after Respawn.RaidSolo seconds
	  raid, fireteam     wait for a revive (hold E at the ghost); everyone
	                     dead = wipe, the encounter restarts

	Live state for the HUD is kept as attributes on a Folder per run in
	ReplicatedStorage.LiveRuns (objective text/progress, boss health, phase,
	timer, score). ActivityState tells a client which run folder is theirs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local AssetIds = require(Shared.Config.AssetIds)
local CombatConfig = require(Shared.Config.CombatConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Guard = require(Shared.Net.Guard)
local PowerMath = require(Shared.Power.PowerMath)

local CharacterService = require(script.Parent.CharacterService)
local CombatContext = require(script.Parent.Parent.Combat.CombatContext)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local LootService = require(script.Parent.LootService)
local NetService = require(script.Parent.NetService)
local WeaponService = require(script.Parent.WeaponService)
local WorldService = require(script.Parent.WorldService)

type ActivityDef = ActivityConfig.ActivityDef
type DifficultyDef = ActivityConfig.DifficultyDef
type ObjectiveDef = ActivityConfig.ObjectiveDef
type EncounterDef = ActivityConfig.EncounterDef
type Enemy = EnemyService.Enemy

export type RunStatus = "Active" | "Wiped" | "Complete" | "Closed"

type Ghost = { Part: BasePart, Position: Vector3 }

export type Run = {
	Id: string,
	Slot: number,
	Activity: ActivityDef,
	Difficulty: DifficultyDef?,
	Power: number,
	Modifiers: { string },
	Effects: ActivityRules.ModifierEffects,
	Map: Model,
	Origin: Vector3,
	Markers: { [string]: BasePart },
	Folder: Folder,
	Players: { Player },
	Objectives: { ActivityRules.ObjectiveEntry },
	Index: number,
	Status: RunStatus,
	Checkpoint: string,
	StartedAt: number,
	Score: number,
	Deaths: number,
	-- Bumped when the runner must stop (wipe restart, close).
	Token: number,
	-- Kills per spawn tag, counted by onEnemyKilled.
	Kills: { [string]: number },
	Boss: Enemy?,
	DamageBuff: number,
	Ghosts: { [Player]: Ghost },
	Cleared: { EncounterDef },
}

local ActivityService = {}

local runs: { [string]: Run } = {}
local runOfPlayer: { [Player]: Run } = {}
local slotsInUse: { [number]: boolean } = {}
local nextRunId = 0
local rng = Random.new()
local liveFolder: Folder

-- Helpers ---------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function isActive(run: Run, token: number): boolean
	return run.Status == "Active" and run.Token == token
end

local function playerPower(player: Player): number
	local data = DataService.GetData(player)
	return if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
end

local function rootOf(player: Player): BasePart?
	local character = CharacterService.GetCharacter(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function alivePlayers(run: Run): { Player }
	local list: { Player } = {}
	for _, player in run.Players do
		if CharacterService.IsAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function setAttr(run: Run, name: string, value: any)
	if run.Status ~= "Closed" then
		run.Folder:SetAttribute(name, value)
	end
end

local function markerCFrame(run: Run, name: string?): CFrame
	local marker = if name then run.Markers[name] else nil
	marker = marker or run.Markers.PlayerStart
	if marker then
		return marker.CFrame + Vector3.new(0, 1.5, 0)
	end
	return CFrame.new(run.Origin + Vector3.new(0, 6, 0))
end

-- Is anyone alive standing inside a Zone_* marker (a box sized by MapKit.Zone)?
local function playersInZone(run: Run, zone: BasePart): { Player }
	local inside: { Player } = {}
	local half = zone.Size / 2
	for _, player in run.Players do
		local root = rootOf(player)
		if root then
			local offset = zone.CFrame:PointToObjectSpace(root.Position)
			local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
			if horizontal <= half.X and math.abs(offset.Y) <= half.Y + 4 then
				table.insert(inside, player)
			end
		end
	end
	return inside
end

-- Health and damage scaling for enemies spawned in this run.
local function spawnOptions(run: Run, tag: string, aggro: boolean): EnemyService.SpawnOptions
	local healthScale, damageScale = PowerMath.ActivityEnemyScale(run.Power)
	local extraPlayers = math.max(0, #run.Players - 1)
	return {
		InstanceId = run.Id,
		Tag = tag,
		HealthScale = healthScale
			* run.Effects.EnemyHealth
			* (1 + extraPlayers * CombatConfig.PartyScaling.HealthPerExtraPlayer),
		DamageScale = damageScale * run.Effects.EnemyDamage,
		ExtraShields = run.Effects.ExtraShields,
		Aggro = aggro,
	}
end

local function spawnMarkers(run: Run, group: string): { BasePart }
	local list: { BasePart } = {}
	local index = 1
	while run.Markers[`Spawn_{group}_{index}`] do
		table.insert(list, run.Markers[`Spawn_{group}_{index}`])
		index += 1
	end
	return list
end

-- Spawns a list of { Id, Count } at a spawn group's markers. Returns how many spawned.
local function spawnWave(
	run: Run,
	group: string,
	enemies: { { Id: string, Count: number } },
	tag: string,
	aggro: boolean
): number
	local markers = spawnMarkers(run, group)
	if #markers == 0 then
		warn(`[ActivityService] {run.Activity.Id}: no markers for spawn group {group}`)
		return 0
	end
	local spawned = 0
	local cursor = rng:NextInteger(1, #markers)
	for _, entry in enemies do
		for _ = 1, entry.Count do
			local marker = markers[cursor]
			cursor = cursor % #markers + 1
			local jitter = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			local enemy = EnemyService.Spawn(entry.Id, marker.CFrame + jitter, spawnOptions(run, tag, aggro))
			if enemy then
				spawned += 1
			end
		end
	end
	return spawned
end

local function aliveWithTag(run: Run, tag: string): number
	local count = 0
	for _, enemy in EnemyService.GetEnemies(run.Id) do
		if enemy.Tag == tag then
			count += 1
		end
	end
	return count
end

local function openDoor(run: Run, name: string)
	local doors = run.Map:FindFirstChild("Doors")
	local door = if doors then doors:FindFirstChild(name) else nil
	if door and door:IsA("BasePart") then
		door.CanCollide = false
		door.CanQuery = false
		door.Transparency = 1
	end
end

-- Client sync ------------------------------------------------------------------------

local function modifierList(run: Run): { { Name: string, Description: string } }
	local list = {}
	for _, id in run.Modifiers do
		local modifier = ActivityConfig.NightfallModifiers[id]
		if modifier then
			table.insert(list, { Name = modifier.Name, Description = modifier.Description })
		end
	end
	return list
end

local function sendState(player: Player)
	local run = runOfPlayer[player]
	if run == nil then
		NetService.FireClient(player, "ActivityState", { InActivity = false, Map = "Hub" })
		return
	end
	NetService.FireClient(player, "ActivityState", {
		InActivity = true,
		RunId = run.Id,
		ActivityId = run.Activity.Id,
		Name = run.Activity.Name,
		Type = run.Activity.Type,
		Difficulty = if run.Difficulty then run.Difficulty.Name else nil,
		Power = run.Power,
		Map = run.Activity.Map or "Hub",
		Modifiers = modifierList(run),
		Scored = run.Activity.Scored == true,
	})
end

local function setObjective(run: Run, text: string, count: string?, progress: number?, waypoint: Vector3?)
	setAttr(run, "ObjectiveText", text)
	setAttr(run, "ObjectiveCount", count or "")
	setAttr(run, "ObjectiveProgress", progress or -1)
	setAttr(run, "HasWaypoint", waypoint ~= nil)
	if waypoint then
		setAttr(run, "Waypoint", waypoint)
	end
end

local function syncBoss(run: Run)
	local boss = run.Boss
	if boss == nil or boss.Dead then
		setAttr(run, "BossActive", false)
		return
	end
	setAttr(run, "BossActive", true)
	setAttr(run, "BossName", boss.Def.Name)
	setAttr(run, "BossTitle", boss.Def.Title or "")
	setAttr(run, "BossHealth", boss.Health)
	setAttr(run, "BossMaxHealth", boss.MaxHealth)
	setAttr(run, "BossShield", boss.Shield)
	setAttr(run, "BossMaxShield", boss.MaxShield)
	setAttr(run, "BossImmune", boss.Immune)
end

local function setPhase(run: Run, text: string?, endsAt: number?)
	setAttr(run, "Phase", text or "")
	setAttr(run, "PhaseEndsAt", endsAt or 0)
end

-- Objectives ------------------------------------------------------------------------

local function runTravel(run: Run, token: number, objective: ObjectiveDef): boolean
	local zone: BasePart? = run.Markers[objective.Target or ""]
	if zone == nil then
		warn(`[ActivityService] Travel target {objective.Target} missing`)
		return true
	end
	setObjective(run, objective.Text, nil, nil, zone.Position)
	while isActive(run, token) do
		if #playersInZone(run, zone) > 0 then
			return true
		end
		task.wait(0.25)
	end
	return false
end

local function runDefeat(run: Run, token: number, objective: ObjectiveDef, index: number): boolean
	local tag = `obj{index}_{token}`
	local spawns = (objective.Spawns or {}) :: { ActivityConfig.SpawnDef }
	local expected = 0
	local pending = 0
	for _, spawn in spawns do
		for _, entry in spawn.Enemies do
			expected += entry.Count
		end
	end
	run.Kills[tag] = 0
	setObjective(run, objective.Text, `0/{expected}`)

	for _, spawn in spawns do
		local count = 0
		for _, entry in spawn.Enemies do
			count += entry.Count
		end
		local function doSpawn()
			if not isActive(run, token) then
				return
			end
			local spawned = spawnWave(run, spawn.Group, spawn.Enemies, tag, spawn.Delay ~= nil)
			expected -= count - spawned
		end
		if spawn.Delay then
			pending += 1
			task.delay(spawn.Delay, function()
				doSpawn()
				pending -= 1
			end)
		else
			doSpawn()
		end
	end

	local lastShown = -1
	while isActive(run, token) do
		local kills = run.Kills[tag] or 0
		if kills ~= lastShown then
			lastShown = kills
			setObjective(
				run,
				objective.Text,
				`{math.min(kills, expected)}/{expected}`,
				if expected > 0 then kills / expected else 1
			)
		end
		if pending == 0 and kills >= expected then
			return true
		end
		task.wait(0.2)
	end
	return false
end

local function runDefend(run: Run, token: number, objective: ObjectiveDef, index: number): boolean
	local zone: BasePart? = run.Markers[objective.Target or ""]
	if zone == nil then
		warn(`[ActivityService] Defend zone {objective.Target} missing`)
		return true
	end
	local tag = `obj{index}_{token}`
	local duration = objective.Duration or 20
	local interval = objective.WaveInterval or 8
	local maxAlive = objective.MaxAlive or 8
	local progress = 0
	local nextWave = 0
	local lastTick = now()
	setObjective(run, objective.Text, "0%", 0, zone.Position)
	while isActive(run, token) do
		local current = now()
		local dt = current - lastTick
		lastTick = current
		if current >= nextWave then
			nextWave = current + interval
			if aliveWithTag(run, tag) < maxAlive then
				for _, spawn in (objective.Spawns or {}) :: { ActivityConfig.SpawnDef } do
					spawnWave(run, spawn.Group, spawn.Enemies, tag, true)
				end
			end
		end
		local inside = #playersInZone(run, zone)
		if inside > 0 then
			progress += dt
		end
		local fraction = math.min(1, progress / duration)
		local suffix = if inside > 0 then "" else "  (stand in the zone!)"
		setObjective(run, objective.Text, `{math.floor(fraction * 100)}%{suffix}`, fraction, zone.Position)
		if progress >= duration then
			return true
		end
		task.wait(0.2)
	end
	return false
end

-- Boss mechanics ------------------------------------------------------------------

local function addsMechanics(def: EnemyConfig.EnemyDef): { EnemyConfig.MechanicDef }
	local list: { EnemyConfig.MechanicDef } = {}
	for _, mechanic in def.Mechanics or {} :: { EnemyConfig.MechanicDef } do
		if mechanic.Kind == "Adds" and mechanic.Enemies then
			table.insert(list, mechanic)
		end
	end
	return list
end

local function findMechanic(def: EnemyConfig.EnemyDef, kind: string): EnemyConfig.MechanicDef?
	for _, mechanic in def.Mechanics or {} :: { EnemyConfig.MechanicDef } do
		if mechanic.Kind == kind then
			return mechanic
		end
	end
	return nil
end

-- Kills everyone and restarts the current raid encounter (forward-declared).
local wipe: (run: Run, reason: string) -> ()

local function runEchoPlates(run: Run, token: number, objective: ObjectiveDef, boss: Enemy)
	local raid = CombatConfig.Raid
	local plates: { BasePart } = {}
	for plateIndex = 1, 3 do
		local plate = run.Map:FindFirstChild(`Plate_{plateIndex}`, true)
		if plate and plate:IsA("BasePart") then
			table.insert(plates, plate)
		end
	end
	local baseColors: { [BasePart]: Color3 } = {}
	for _, plate in plates do
		baseColors[plate] = plate.Color
	end

	local adds = addsMechanics(boss.Def)[1]
	local enrage = findMechanic(boss.Def, "Enrage")
	local damagePhase = findMechanic(boss.Def, "DamagePhase")
	local phaseSeconds = if damagePhase and damagePhase.Duration then damagePhase.Duration else raid.DamagePhaseSeconds
	local enrageAt = now() + (if enrage and enrage.AfterSeconds then enrage.AfterSeconds else raid.EnrageSeconds)
	setAttr(run, "EnrageAt", enrageAt)

	local phase = "Immune"
	local charge = 0
	local phaseEndsAt = 0
	local nextAdds = now() + raid.AddsInterval * 0.6
	local lastTick = now()
	EnemyService.SetImmune(boss, true)
	syncBoss(run)

	while isActive(run, token) and not boss.Dead do
		local current = now()
		local dt = current - lastTick
		lastTick = current
		local solo = #run.Players <= 1
		local required = if solo then 1 else math.min(#plates, #run.Players)
		local chargeSeconds = if solo then raid.SoloPlateHoldSeconds else raid.PlateChargeSeconds

		-- Which plates have a living Keeper standing on them?
		local held = 0
		for _, plate in plates do
			local occupied = false
			for _, player in run.Players do
				local root = rootOf(player)
				if root then
					local offset = root.Position - plate.Position
					if Vector2.new(offset.X, offset.Z).Magnitude <= plate.Size.Y / 2 + 1 and math.abs(offset.Y) < 8 then
						occupied = true
						break
					end
				end
			end
			if occupied then
				held += 1
			end
			plate.Color = if occupied then Color3.fromRGB(255, 255, 255) else baseColors[plate]
		end

		if phase == "Immune" then
			if held >= required then
				charge += dt
			else
				charge = math.max(0, charge - dt * 2)
			end
			setAttr(run, "Charge", math.min(1, charge / chargeSeconds))
			local what = if solo then "Hold an echo plate" else `Hold {required} echo plates at once`
			setPhase(run, `{what} ({held}/{required})`, nil)
			if charge >= chargeSeconds then
				phase = "Damage"
				charge = 0
				phaseEndsAt = now() + phaseSeconds
				run.DamageBuff = raid.DamageBuff
				EnemyService.SetImmune(boss, false)
				setAttr(run, "Charge", 0)
				setPhase(run, "ECHO RESONANCE: damage the Engine!", phaseEndsAt)
				syncBoss(run)
			end
		elseif now() >= phaseEndsAt then
			phase = "Immune"
			run.DamageBuff = 1
			EnemyService.SetImmune(boss, true)
			syncBoss(run)
		end

		if adds and adds.Enemies and current >= nextAdds then
			nextAdds = current + raid.AddsInterval
			if aliveWithTag(run, "raidAdds") < 10 then
				spawnWave(run, objective.AddsGroup or "Adds", adds.Enemies, "raidAdds", true)
			end
		end

		if now() >= enrageAt then
			setPhase(run, "ENRAGE: the Echo Engine overloads!", nil)
			EnemyService.SetEnraged(boss, true)
			task.wait(1.5)
			if isActive(run, token) and not boss.Dead then
				wipe(run, "The Echo Engine overloaded")
			end
			break
		end
		task.wait(0.2)
	end

	run.DamageBuff = 1
	if run.Status == "Closed" then
		return -- map and live folder are gone
	end
	for _, plate in plates do
		plate.Color = baseColors[plate]
	end
	setAttr(run, "Charge", 0)
	setAttr(run, "EnrageAt", 0)
	setPhase(run, nil, nil)
end

local function runBoss(run: Run, token: number, objective: ObjectiveDef): boolean
	local def = EnemyConfig.ById[objective.Enemy or ""]
	if def == nil then
		warn(`[ActivityService] Unknown boss {objective.Enemy}`)
		return true
	end
	local marker = run.Markers[objective.Target or "BossSpawn"] or run.Markers.BossSpawn
	local at = if marker then marker.CFrame else CFrame.new(run.Origin)
	local options = spawnOptions(run, "boss", false)
	if run.Activity.Type == "Raid" then
		-- Raid health is tuned for a full fireteam of six.
		local players = math.max(1, #run.Players)
		options.HealthScale = (options.HealthScale or 1)
			/ (1 + math.max(0, players - 1) * CombatConfig.PartyScaling.HealthPerExtraPlayer)
			* math.clamp(players / CombatConfig.Raid.DesignPlayers, 1 / CombatConfig.Raid.DesignPlayers, 1)
	end
	local boss = EnemyService.Spawn(def.Id, at, options)
	if boss == nil then
		return true
	end
	run.Boss = boss
	setObjective(run, objective.Text, nil, nil, nil)
	syncBoss(run)

	local mechanic = objective.Mechanic or "Standard"
	if mechanic == "EchoPlates" then
		runEchoPlates(run, token, objective, boss)
	else
		local fired: { [number]: boolean } = {}
		local immuneTag: string? = nil
		local immune = findMechanic(def, "Immune")
		while isActive(run, token) and not boss.Dead do
			local fraction = boss.Health / boss.MaxHealth
			for mechanicIndex, adds in addsMechanics(def) do
				if not fired[mechanicIndex] and fraction <= (adds.AtHealth or 0.5) and adds.Enemies then
					fired[mechanicIndex] = true
					local tag = `bossAdds{mechanicIndex}_{token}`
					spawnWave(run, objective.AddsGroup or "BossAdds", adds.Enemies, tag, true)
					if mechanic == "ImmuneAdds" and immune and immuneTag == nil then
						immuneTag = tag
						EnemyService.SetImmune(boss, true)
						setPhase(run, immune.Break or "Defeat the bodyguard", nil)
						syncBoss(run)
					end
				end
			end
			if immuneTag and boss.Immune and aliveWithTag(run, immuneTag) == 0 then
				EnemyService.SetImmune(boss, false)
				setPhase(run, nil, nil)
				syncBoss(run)
			end
			task.wait(0.25)
		end
		setPhase(run, nil, nil)
	end

	run.Boss = nil
	syncBoss(run)
	return isActive(run, token) and boss.Dead
end

-- Runner ----------------------------------------------------------------------------

local complete: (run: Run) -> ()

local function runObjectives(run: Run, token: number)
	while isActive(run, token) and run.Index <= #run.Objectives do
		local entry = run.Objectives[run.Index]
		local objective = entry.Objective
		setAttr(run, "ObjectiveIndex", run.Index)
		local done = false
		if objective.Kind == "Travel" then
			done = runTravel(run, token, objective)
		elseif objective.Kind == "Defeat" then
			done = runDefeat(run, token, objective, run.Index)
		elseif objective.Kind == "Defend" then
			done = runDefend(run, token, objective, run.Index)
		elseif objective.Kind == "Boss" then
			done = runBoss(run, token, objective)
		else
			warn(`[ActivityService] Objective kind {objective.Kind} isn't built yet; skipping`)
			done = true
		end
		if not done or not isActive(run, token) then
			return
		end

		if objective.Checkpoint then
			run.Checkpoint = objective.Checkpoint
		end
		if objective.Door then
			openDoor(run, objective.Door)
		end
		-- Last objective of a raid encounter: the encounter is cleared.
		local nextEntry = run.Objectives[run.Index + 1]
		if entry.Encounter and (nextEntry == nil or nextEntry.Encounter ~= entry.Encounter) then
			table.insert(run.Cleared, entry.Encounter)
			for _, player in run.Players do
				NetService.Notify(player, `Encounter complete: {entry.Encounter.Name}`, "Success")
			end
		end
		run.Index += 1
	end
	if isActive(run, token) then
		complete(run)
	end
end

local function startRunner(run: Run)
	run.Token += 1
	task.spawn(runObjectives, run, run.Token)
end

-- Joining and leaving ---------------------------------------------------------------

local function removeGhost(run: Run, player: Player)
	local ghost = run.Ghosts[player]
	if ghost then
		ghost.Part:Destroy()
		run.Ghosts[player] = nil
	end
end

local function closeRun(run: Run)
	if run.Status == "Closed" then
		return
	end
	run.Status = "Closed"
	run.Token += 1
	EnemyService.DespawnInstance(run.Id)
	LootService.ClearInstance(run.Id)
	for player in run.Ghosts do
		removeGhost(run, player)
	end
	run.Map:Destroy()
	run.Folder:Destroy()
	slotsInUse[run.Slot] = nil
	runs[run.Id] = nil
end

-- Moves a player back to the hub (or just forgets them when they left the game).
local function removePlayer(player: Player, returnToHub: boolean)
	local run = runOfPlayer[player]
	if run == nil then
		return
	end
	runOfPlayer[player] = nil
	local index = table.find(run.Players, player)
	if index then
		table.remove(run.Players, index)
	end
	removeGhost(run, player)
	if player.Parent == Players then
		player:SetAttribute("InstanceId", nil)
		sendState(player)
		if returnToHub then
			if CharacterService.IsAlive(player) then
				CharacterService.Teleport(player, WorldService.GetHubSpawn())
				CharacterService.HealFull(player)
			else
				task.spawn(CharacterService.Spawn, player, WorldService.GetHubSpawn())
			end
			WeaponService.ResetAmmo(player)
		end
	end
	if #run.Players == 0 then
		closeRun(run)
	elseif run.Activity.Type == "Raid" and run.Status == "Active" and #alivePlayers(run) == 0 then
		wipe(run, "Fireteam wiped")
	end
end

local function addPlayer(run: Run, player: Player)
	removePlayer(player, false)
	table.insert(run.Players, player)
	runOfPlayer[player] = run
	player:SetAttribute("InstanceId", run.Id)
	sendState(player)
	WeaponService.ResetAmmo(player)
	local target = markerCFrame(run, run.Checkpoint)
	if CharacterService.IsAlive(player) then
		CharacterService.Teleport(player, target)
		CharacterService.HealFull(player)
	else
		task.spawn(CharacterService.Spawn, player, target)
	end
end

-- Completion, wipes and revives -----------------------------------------------------

complete = function(run: Run)
	run.Status = "Complete"
	run.Token += 1
	local elapsed = now() - run.StartedAt
	local title = run.Activity.Name
	if run.Difficulty then
		title ..= ` ({run.Difficulty.Name})`
	end
	if run.Activity.Scored then
		local score = CombatConfig.Score
		local bonus = math.max(0, score.ParSeconds - elapsed) * score.PointsPerSecondUnderPar
		run.Score += math.floor(bonus)
		setAttr(run, "Score", run.Score)
	end
	local returnAt = now() + GameConfig.Activities.ReturnToHubDelay
	setAttr(run, "Status", "Complete")
	setAttr(run, "ReturnAt", returnAt)
	setAttr(run, "Elapsed", elapsed)
	setObjective(run, "Activity complete", nil, nil, nil)
	EnemyService.DespawnInstance(run.Id)

	for _, player in table.clone(run.Players) do
		local data = DataService.GetData(player)
		if data then
			local activity = run.Activity
			if activity.Type == "Story" then
				DataService.Set(player, { "Progress", "StoryCompleted", activity.Id }, true)
			end
			DataService.Set(
				player,
				{ "Progress", "ActivityClears", activity.Id },
				(data.Progress.ActivityClears[activity.Id] or 0) + 1
			)
			DataService.Set(player, { "Lifetime", "ActivitiesCompleted" }, data.Lifetime.ActivitiesCompleted + 1)
			local ok, err = pcall(LootService.AwardCompletion, player, {
				Activity = activity,
				Difficulty = run.Difficulty,
				Encounters = run.Cleared,
				Title = title,
			})
			if not ok then
				warn(`[ActivityService] Rewards failed for {player.Name}: {err}`)
			end
		end
	end

	task.delay(GameConfig.Activities.ReturnToHubDelay, function()
		for _, player in table.clone(run.Players) do
			removePlayer(player, true)
		end
		closeRun(run)
	end)
end

wipe = function(run: Run, reason: string)
	if run.Status ~= "Active" then
		return
	end
	run.Status = "Wiped"
	run.Token += 1
	setAttr(run, "Status", "Wiped")
	setPhase(run, `{reason}. Restarting the encounter...`, now() + CombatConfig.Respawn.RaidWipe)
	for _, player in run.Players do
		if CharacterService.IsAlive(player) then
			CharacterService.Kill(player)
		end
		CharacterService.SendStatus(player, {
			Alive = false,
			RespawnAt = now() + CombatConfig.Respawn.RaidWipe,
			Message = `{reason}. The encounter restarts.`,
		})
	end
	task.delay(CombatConfig.Respawn.RaidWipe, function()
		if (run.Status :: RunStatus) ~= "Wiped" then
			return
		end
		EnemyService.DespawnInstance(run.Id)
		for player in run.Ghosts do
			removeGhost(run, player)
		end
		run.Boss = nil
		run.DamageBuff = 1
		syncBoss(run)
		setPhase(run, nil, nil)
		run.Status = "Active"
		setAttr(run, "Status", "Active")
		for _, player in run.Players do
			WeaponService.ResetAmmo(player)
			task.spawn(CharacterService.Spawn, player, markerCFrame(run, run.Checkpoint))
		end
		-- Give everyone a moment to load in before the encounter starts again.
		task.wait(2)
		if run.Status == "Active" then
			startRunner(run)
		end
	end)
end

local function revive(run: Run, target: Player, reviver: Player)
	local ghost = run.Ghosts[target]
	if ghost == nil or run.Status ~= "Active" or runOfPlayer[target] ~= run then
		return
	end
	removeGhost(run, target)
	NetService.Notify(target, `Revived by {reviver.DisplayName}`, "Success")
	NetService.Notify(reviver, `You revived {target.DisplayName}`, "Success")
	task.spawn(CharacterService.Spawn, target, CFrame.new(ghost.Position + Vector3.new(0, 3, 0)))
end

local function makeGhost(run: Run, player: Player, position: Vector3)
	removeGhost(run, player)
	local part = Instance.new("Part")
	part.Name = `Ghost_{player.Name}`
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.Color = Color3.fromRGB(120, 220, 255)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.25
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Position = position + Vector3.new(0, 1, 0)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 12
	light.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = CombatConfig.Respawn.ReviveHoldSeconds
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(reviver: Player)
		if reviver ~= player and runOfPlayer[reviver] == run and CharacterService.IsAlive(reviver) then
			revive(run, player, reviver)
		end
	end)
	part.Parent = run.Map
	run.Ghosts[player] = { Part = part, Position = position }
end

local function onDeath(player: Player, position: Vector3): CharacterService.DeathPolicy
	local respawn = CombatConfig.Respawn
	local run = runOfPlayer[player]
	if run == nil then
		return { Delay = respawn.Hub, Message = "Respawning" }
	end
	run.Deaths += 1
	if run.Status == "Wiped" then
		return { Delay = nil, Message = "Fireteam wiped. The encounter restarts." }
	elseif run.Status ~= "Active" then
		return { Delay = respawn.Activity, Message = "Respawning" }
	end
	if run.Activity.Type == "Raid" then
		if #run.Players <= 1 then
			return { Delay = respawn.RaidSolo, Message = "Solo Keeper down. Respawning at the checkpoint" }
		end
		if #alivePlayers(run) == 0 then
			task.defer(wipe, run, "Fireteam wiped")
			return { Delay = nil, Message = "Fireteam wiped. The encounter restarts." }
		end
		makeGhost(run, player, position)
		return { Delay = nil, Message = "Waiting for a revive: a Keeper can hold E at your ghost" }
	end
	return { Delay = respawn.Activity, Message = "Respawning at the last checkpoint" }
end

local function spawnPoint(player: Player): CFrame
	local run = runOfPlayer[player]
	if run then
		return markerCFrame(run, run.Checkpoint)
	end
	return WorldService.GetHubSpawn()
end

-- Launching -------------------------------------------------------------------------

local function freeSlot(): number?
	for slot = 1, GameConfig.Activities.MaxInstances do
		if not slotsInUse[slot] then
			return slot
		end
	end
	return nil
end

local function createRun(activity: ActivityDef, difficulty: DifficultyDef?): (Run?, string?)
	local template = WorldService.GetMapTemplate(activity.Map or "")
	if template == nil then
		return nil, `Map {activity.Map} is missing from ServerStorage.Activities`
	end
	local slot = freeSlot()
	if slot == nil then
		return nil, "All activity instances are busy; try again in a moment"
	end
	slotsInUse[slot] = true
	nextRunId += 1
	local id = `R{nextRunId}`
	local origin = WorldService.InstanceOrigin(slot)

	local map = template:Clone()
	map.Name = `{activity.Map}_{id}`
	map:PivotTo(CFrame.new(origin))
	map.Parent = WorldService.Folder("Instances")

	local markers: { [string]: BasePart } = {}
	local markerFolder = map:FindFirstChild("Markers")
	if markerFolder then
		for _, child in markerFolder:GetChildren() do
			if child:IsA("BasePart") then
				markers[child.Name] = child
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = id
	folder.Parent = liveFolder

	local modifiers = ActivityRules.ModifiersFor(activity, os.time())
	local run: Run = {
		Id = id,
		Slot = slot,
		Activity = activity,
		Difficulty = difficulty,
		Power = ActivityRules.RecommendedPower(activity, if difficulty then difficulty.Id else nil),
		Modifiers = modifiers,
		Effects = ActivityRules.CombineModifiers(modifiers),
		Map = map,
		Origin = origin,
		Markers = markers,
		Folder = folder,
		Players = {},
		Objectives = ActivityRules.ObjectiveList(activity),
		Index = 1,
		Status = "Active",
		Checkpoint = "PlayerStart",
		StartedAt = now(),
		Score = 0,
		Deaths = 0,
		Token = 0,
		Kills = {},
		Boss = nil,
		DamageBuff = 1,
		Ghosts = {},
		Cleared = {},
	}
	runs[id] = run
	setAttr(run, "Status", "Active")
	setAttr(run, "StartedAt", run.StartedAt)
	setAttr(run, "Score", 0)
	setAttr(run, "ObjectiveCount", #run.Objectives)
	setAttr(run, "BossActive", false)
	setPhase(run, nil, nil)
	return run, nil
end

-- Reserved-server path (GameConfig.Activities.USE_RESERVED_SERVERS). Returns
-- true when the teleport was started.
local function launchReserved(player: Player, activity: ActivityDef, difficultyId: string?): boolean
	local placeId = AssetIds.Places[activity.Place] or 0
	if placeId == 0 then
		warn(`[ActivityService] USE_RESERVED_SERVERS is on but AssetIds.Places.{activity.Place} is 0`)
		return false
	end
	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(placeId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ ActivityId = activity.Id, DifficultyId = difficultyId })
		TeleportService:TeleportAsync(placeId, { player }, options)
	end)
	if not ok then
		warn(`[ActivityService] Reserved server teleport failed: {err}`)
	end
	return ok
end

-- Launches an activity for `player`. Returns (ok, message).
function ActivityService.Launch(
	player: Player,
	activityId: string,
	difficultyId: string?,
	force: boolean?
): (boolean, string?)
	local activity = ActivityConfig.ById[activityId]
	local data = DataService.GetData(player)
	if activity == nil or data == nil then
		return false, "Unknown activity"
	end
	if not activity.Playable then
		return false, "That activity isn't playable yet"
	end
	if not force then
		local unlocked, reason = ActivityRules.CheckUnlock(data, activity)
		if not unlocked then
			return false, reason
		end
	end
	local minPlayers = ActivityRules.MinPlayers(activity)
	if minPlayers > 1 and not force then
		return false, `Needs a fireteam of {minPlayers}. Launch it and have others Join from the Director.`
	end
	local difficulty = ActivityRules.GetDifficulty(activity, difficultyId)

	if
		GameConfig.Activities.USE_RESERVED_SERVERS
		and launchReserved(player, activity, if difficulty then difficulty.Id else nil)
	then
		return true, "Teleporting..."
	end

	local run, err = createRun(activity, difficulty)
	if run == nil then
		return false, err
	end
	addPlayer(run, player)
	startRunner(run)
	return true, nil
end

function ActivityService.Join(player: Player, runId: string): (boolean, string?)
	local run = runs[runId]
	local data = DataService.GetData(player)
	if run == nil or run.Status ~= "Active" or data == nil then
		return false, "That fireteam is no longer active"
	end
	if runOfPlayer[player] == run then
		return false, "You're already there"
	end
	if #run.Players >= run.Activity.MaxPlayers then
		return false, "That fireteam is full"
	end
	local unlocked, reason = ActivityRules.CheckUnlock(data, run.Activity)
	if not unlocked then
		return false, reason
	end
	addPlayer(run, player)
	for _, other in run.Players do
		if other ~= player then
			NetService.Notify(other, `{player.DisplayName} joined the fireteam`, "Info")
		end
	end
	return true, nil
end

function ActivityService.Leave(player: Player)
	removePlayer(player, true)
end

function ActivityService.GetRun(player: Player): Run?
	return runOfPlayer[player]
end

-- Dev tools: skip to the next objective.
function ActivityService.SkipObjective(player: Player): boolean
	local run = runOfPlayer[player]
	if run == nil or run.Status ~= "Active" then
		return false
	end
	EnemyService.DespawnInstance(run.Id)
	run.Boss = nil
	syncBoss(run)
	run.Index += 1
	startRunner(run)
	return true
end

-- Combat context and enemy bookkeeping ----------------------------------------------------

local function contextFor(player: Player): CombatContext.Context
	local data = DataService.GetData(player)
	local power = if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
	local artifact = if data then data.Artifact.Level else 0
	local run = runOfPlayer[player]
	if run == nil then
		-- Hub (shooting range): no power gap, so damage numbers show raw weapon damage.
		return {
			CharacterPower = power,
			ArtifactLevel = 0,
			ActivityPower = power,
			PowerEnabled = true,
			DeltaCap = nil,
			Effects = nil,
			InstanceId = nil,
			DamageBuff = 1,
		}
	end
	return {
		CharacterPower = power,
		ArtifactLevel = artifact,
		ActivityPower = run.Power,
		PowerEnabled = run.Activity.PowerEnabled,
		DeltaCap = run.Activity.PowerDeltaCap,
		Effects = run.Effects,
		InstanceId = run.Id,
		DamageBuff = run.DamageBuff,
	}
end

local function onEnemyKilled(enemy: Enemy, _killer: Player?)
	local run = if enemy.InstanceId then runs[enemy.InstanceId] else nil
	if run == nil then
		return
	end
	if enemy.Tag then
		run.Kills[enemy.Tag] = (run.Kills[enemy.Tag] or 0) + 1
	end
	if run.Activity.Scored then
		local score = CombatConfig.Score
		local points = if enemy.Def.Tier == "Boss"
			then score.Boss
			elseif enemy.Def.Tier == "Minor" then score.Minor
			else score.Major
		run.Score += points
		setAttr(run, "Score", run.Score)
	end
	for _, player in run.Players do
		local data = DataService.GetData(player)
		if data then
			DataService.Set(player, { "Lifetime", "Kills" }, data.Lifetime.Kills + 1)
		end
	end
end

local function lootResolver(instanceId: string): (string?, number, { Player })
	local run = runs[instanceId]
	if run == nil then
		return nil, 1, {}
	end
	return run.Activity.LootSource, run.Effects.AmmoDrops, run.Players
end

local function spawnRangeDummies()
	local index = 1
	while true do
		local marker = WorldService.GetHubMarker(`Dummy_{index}`)
		if marker == nil then
			break
		end
		local defId = if index == 3 then "RANGE_DUMMY_SHIELDED" else "RANGE_DUMMY"
		EnemyService.Spawn(defId, marker.CFrame, { InstanceId = nil, Tag = "range" })
		index += 1
	end
end

-- Lifecycle --------------------------------------------------------------------------

function ActivityService.Init()
	liveFolder = Instance.new("Folder")
	liveFolder.Name = "LiveRuns"
	liveFolder.Parent = ReplicatedStorage

	CombatContext.SetResolver(contextFor)
	CharacterService.SetResolvers(onDeath, spawnPoint)
	LootService.SetInstanceResolver(lootResolver)

	NetService.OnInvoke("DirectorQuery", {}, function(player: Player)
		local list = {}
		for _, run in runs do
			if run.Status == "Active" then
				local names = {}
				for _, member in run.Players do
					table.insert(names, member.DisplayName)
				end
				table.insert(list, {
					RunId = run.Id,
					ActivityId = run.Activity.Id,
					Difficulty = if run.Difficulty then run.Difficulty.Id else nil,
					Players = names,
					MaxPlayers = run.Activity.MaxPlayers,
				})
			end
		end
		local current = runOfPlayer[player]
		return { Runs = list, Current = if current then current.Id else nil, Power = playerPower(player) }
	end)
	NetService.OnInvoke(
		"DirectorLaunch",
		{ Guard.String(64, 1), Guard.Optional(Guard.String(32)) },
		function(player: Player, activityId: string, difficultyId: string?)
			return ActivityService.Launch(player, activityId, difficultyId)
		end
	)
	NetService.OnInvoke("DirectorJoin", { Guard.String(16, 1) }, function(player: Player, runId: string)
		return ActivityService.Join(player, runId)
	end)
	NetService.OnEvent("LeaveActivity", {}, function(player: Player)
		ActivityService.Leave(player)
	end)
end

function ActivityService.Start()
	EnemyService.EnemyKilled:Connect(onEnemyKilled)
	EnemyService.EnemyDamaged:Connect(function(enemy: Enemy)
		local run = if enemy.InstanceId then runs[enemy.InstanceId] else nil
		if run and run.Boss == enemy then
			syncBoss(run)
		end
	end)

	DataService.PlayerLoaded:Connect(function(player: Player)
		sendState(player)
		-- Reserved-server mode: arriving players start the activity they launched.
		local joinData = player:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if GameConfig.Activities.USE_RESERVED_SERVERS and type(teleportData) == "table" then
			local activityId = (teleportData :: any).ActivityId
			if type(activityId) == "string" then
				for _, run in runs do
					if run.Activity.Id == activityId and run.Status == "Active" then
						ActivityService.Join(player, run.Id)
						return
					end
				end
				ActivityService.Launch(player, activityId, (teleportData :: any).DifficultyId, true)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		removePlayer(player, false)
	end)

	spawnRangeDummies()
end

return ActivityService
