--!strict
--[[
	ActivityService
	Runs story missions, the hardened strike (Nightfall) and the raid: the
	instance, its players, deaths and rewards. The content itself (zones,
	waves, gates, bosses) is walked by MissionService.

	Instances ("runs"): with GameConfig.Activities.USE_RESERVED_SERVERS off
	(the default, so everything works in Studio), each launch clones the
	activity's map Model from ServerStorage.Activities into Workspace.Instances
	at X = InstanceSpacing * slot, fills in the map's terrain there, moves the
	fireteam in, and deletes it all afterwards. With the flag on (and place
	ids in AssetIds.Places) launches teleport to a reserved server instead;
	that server reads the teleport data and runs the activity the same way
	(see launchReserved / Start).

	Deaths (CharacterService resolver):
	  hub                respawn after CombatConfig.Respawn.Hub seconds
	  story / Nightfall  respawn at the last checkpoint
	  raid, solo         respawn after Respawn.RaidSolo seconds
	  raid, fireteam     wait for a revive (hold E at the ghost); everyone
	                     dead = wipe, the encounter restarts

	Completion: a loot chest appears where the last boss fell; opening it
	claims your rewards (anything unclaimed is sent when the fireteam
	returns to the hub, GameConfig.Activities.ReturnToHubDelay later).

	Live state for the HUD is kept as attributes on a Folder per run in
	ReplicatedStorage.LiveRuns (objective text/progress, zone, boss health,
	phase, timer, score, per-player kills/deaths). ActivityState tells a
	client which run folder is theirs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local AssetIds = require(Shared.Config.AssetIds)
local CombatConfig = require(Shared.Config.CombatConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Guard = require(Shared.Net.Guard)
local MissionRules = require(Shared.Activities.MissionRules)
local PowerMath = require(Shared.Power.PowerMath)

local CharacterService = require(script.Parent.CharacterService)
local CombatContext = require(script.Parent.Parent.Combat.CombatContext)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local LootService = require(script.Parent.LootService)
local MissionService = require(script.Parent.MissionService)
local NetService = require(script.Parent.NetService)
local WeaponService = require(script.Parent.WeaponService)
local WorldService = require(script.Parent.WorldService)

local Missions = script.Parent.Parent.Missions
local MapMarkers = require(Missions.MapMarkers)
local MissionKit = require(Missions.MissionKit)
local RunTypes = require(Missions.RunTypes)
local MapKit = require(script.Parent.Parent.MapBuilders.MapKit)

type ActivityDef = ActivityConfig.ActivityDef
type DifficultyDef = ActivityConfig.DifficultyDef
type Enemy = EnemyService.Enemy

export type RunStatus = RunTypes.RunStatus
export type Run = RunTypes.Run

local ActivityService = {}

local runs: { [string]: Run } = {}
local runOfPlayer: { [Player]: Run } = {}
local slotsInUse: { [number]: boolean } = {}
local nextRunId = 0
local liveFolder: Folder

-- Helpers ---------------------------------------------------------------------------

local now = MissionKit.Now
local setAttr = MissionKit.SetAttr
local setPhase = MissionKit.SetPhase
local syncBoss = MissionKit.SyncBoss
local alivePlayers = MissionKit.AlivePlayers

local function isActive(run: Run, token: number): boolean
	return run.Status == "Active" and run.Token == token
end

local function playerPower(player: Player): number
	local data = DataService.GetData(player)
	return if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
end

local function markerCFrame(run: Run, name: string?): CFrame
	return MissionKit.MarkerCFrame(run, name)
end

local function statsOf(run: Run, player: Player): RunTypes.PlayerStats
	local stats = run.Stats[player]
	if stats == nil then
		stats = { Kills = 0, Deaths = 0 }
		run.Stats[player] = stats
	end
	return stats
end

local function syncStats(run: Run, player: Player)
	local stats = statsOf(run, player)
	setAttr(run, `Kills_{player.UserId}`, stats.Kills)
	setAttr(run, `Deaths_{player.UserId}`, stats.Deaths)
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

-- Runner ----------------------------------------------------------------------------

local complete: (run: Run) -> ()
-- Kills everyone and restarts the current encounter (raid).
local wipe: (run: Run, reason: string) -> ()

local function runZones(run: Run, token: number)
	if MissionService.Run(run, token) and isActive(run, token) then
		complete(run)
	end
end

local function startRunner(run: Run)
	run.Token += 1
	task.spawn(runZones, run, run.Token)
end

-- Gives `player` their end-of-activity rewards (once).
local function claimRewards(run: Run, player: Player)
	if run.Rewarded[player] or DataService.GetData(player) == nil then
		return
	end
	run.Rewarded[player] = true
	local title = run.Activity.Name
	if run.Difficulty then
		title ..= ` ({run.Difficulty.Name})`
	end
	local ok, err = pcall(LootService.AwardCompletion, player, {
		Activity = run.Activity,
		Difficulty = run.Difficulty,
		Encounters = run.Cleared,
		Title = title,
	})
	if not ok then
		warn(`[ActivityService] Rewards failed for {player.Name}: {err}`)
	end
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
	run.Folder:Destroy()
	runs[run.Id] = nil
	-- The slot is free once its terrain is gone (clearing yields).
	local map = run.Map
	task.spawn(function()
		MapKit.ClearTerrain(map)
		map:Destroy()
		slotsInUse[run.Slot] = nil
	end)
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
	if run.Status == "Complete" then
		-- Leaving before opening the chest still pays out.
		claimRewards(run, player)
	end
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
		run.Wipe("Fireteam wiped")
	end
end

local function addPlayer(run: Run, player: Player)
	removePlayer(player, false)
	table.insert(run.Players, player)
	runOfPlayer[player] = run
	player:SetAttribute("InstanceId", run.Id)
	sendState(player)
	syncStats(run, player)
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
	if run.Activity.Scored then
		local score = CombatConfig.Score
		local bonus = math.max(0, score.ParSeconds - elapsed) * score.PointsPerSecondUnderPar
		run.Score += math.floor(bonus)
		setAttr(run, "Score", run.Score)
	end
	local delay = GameConfig.Activities.ReturnToHubDelay
	setAttr(run, "Status", "Complete")
	setAttr(run, "ReturnAt", now() + delay)
	setAttr(run, "Elapsed", elapsed)
	setAttr(run, "TotalDeaths", run.Deaths)
	setPhase(run, nil, nil)
	EnemyService.DespawnInstance(run.Id)

	local activity = run.Activity
	for _, player in run.Players do
		syncStats(run, player)
		local data = DataService.GetData(player)
		if data then
			if activity.Type == "Story" then
				DataService.Set(player, { "Progress", "StoryCompleted", activity.Id }, true)
			end
			DataService.Set(
				player,
				{ "Progress", "ActivityClears", activity.Id },
				(data.Progress.ActivityClears[activity.Id] or 0) + 1
			)
			DataService.Set(player, { "Lifetime", "ActivitiesCompleted" }, data.Lifetime.ActivitiesCompleted + 1)
		end
	end

	local chest = MissionService.SpawnChest(run, function(player: Player)
		claimRewards(run, player)
	end)
	local chestAt = if chest.PrimaryPart then chest.PrimaryPart.Position else nil
	MissionKit.SetObjective(run, "Open the chest to claim your rewards", nil, nil, chestAt)

	task.delay(delay, function()
		for _, player in table.clone(run.Players) do
			claimRewards(run, player)
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
		MissionService.Rewind(run)
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
	statsOf(run, player).Deaths += 1
	syncStats(run, player)
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
	local shift = origin - map:GetPivot().Position
	map:PivotTo(CFrame.new(origin))
	MapKit.ShiftMotion(map, shift)
	map.Parent = WorldService.Folder("Instances")
	MapKit.ApplyTerrain(map)

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
		Markers = MapMarkers.Index(map),
		Folder = folder,
		Players = {},
		Zones = MissionRules.ZoneList(activity),
		ZoneIndex = 1,
		StepIndex = 1,
		ZoneStartedAt = now(),
		ZoneLog = "",
		Status = "Active",
		Checkpoint = "PlayerStart",
		StartedAt = now(),
		Score = 0,
		Deaths = 0,
		Token = 0,
		Kills = {},
		Pending = {},
		Boss = nil,
		DamageBuff = 1,
		Ghosts = {},
		Cleared = {},
		Stats = {},
		ChestAt = nil,
		Rewarded = {},
		Wipe = function(_reason: string) end,
	}
	run.Wipe = function(reason: string)
		wipe(run, reason)
	end
	runs[id] = run
	setAttr(run, "Status", "Active")
	setAttr(run, "StartedAt", run.StartedAt)
	setAttr(run, "Score", 0)
	setAttr(run, "ZoneCount", #run.Zones)
	setAttr(run, "BossActive", false)
	setPhase(run, nil, nil)

	-- Falling off the map puts players back at the checkpoint.
	task.spawn(function()
		while run.Status ~= "Closed" do
			MissionService.CheckFalls(run)
			task.wait(0.25)
		end
	end)
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
	run.Token += 1
	EnemyService.DespawnInstance(run.Id)
	run.Boss = nil
	run.DamageBuff = 1
	syncBoss(run)
	setPhase(run, nil, nil)
	MissionService.SkipStep(run)
	startRunner(run)
	return true
end

-- Dev tools: jump to zone `index` of the current activity.
function ActivityService.JumpToZone(player: Player, index: number): boolean
	local run = runOfPlayer[player]
	if run == nil or run.Status ~= "Active" then
		return false
	end
	run.Token += 1
	EnemyService.DespawnInstance(run.Id)
	run.Boss = nil
	run.DamageBuff = 1
	syncBoss(run)
	setPhase(run, nil, nil)
	local checkpoint = MissionService.JumpTo(run, index)
	for _, member in run.Players do
		if CharacterService.IsAlive(member) then
			CharacterService.Teleport(member, markerCFrame(run, checkpoint))
		end
	end
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

local function onEnemyKilled(enemy: Enemy, killer: Player?)
	local run = if enemy.InstanceId then runs[enemy.InstanceId] else nil
	if run == nil then
		return
	end
	if enemy.Tag then
		run.Kills[enemy.Tag] = (run.Kills[enemy.Tag] or 0) + 1
	end
	if killer and runOfPlayer[killer] == run then
		statsOf(run, killer).Kills += 1
		syncStats(run, killer)
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
