-- Integration test for ActivityService + MissionService: the zone flow
-- (waves, checkpoints, gates), boss fights (immune phases, attacks, the
-- raid's plates), deaths, revives, wipes and the loot chest, with the other
-- services replaced by fakes and a virtual clock driving time.
local roblox = require("@lune/roblox")
local realTask = require("@lune/task")
local Proxy = VirtualGame.Proxy

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- Virtual time -----------------------------------------------------------------------

local clock = 0
local function vwait(seconds)
	if seconds == nil then
		-- task.wait() with no time: just yield a frame (terrain batches).
		realTask.wait()
		return 0
	end
	local start = clock
	local target = clock + (seconds or 0.03)
	repeat
		realTask.wait()
	until clock >= target
	return clock - start
end
local fakeTask = {
	wait = vwait,
	spawn = realTask.spawn,
	defer = realTask.defer,
	cancel = realTask.cancel,
	delay = function(seconds, fn, ...)
		local args = table.pack(...)
		return realTask.spawn(function()
			vwait(seconds)
			fn(table.unpack(args, 1, args.n))
		end)
	end,
}
-- Moves virtual time forward, letting waiting threads run as it goes.
local function advance(seconds)
	local target = clock + seconds
	while clock < target do
		clock = math.min(target, clock + 0.1)
		realTask.wait()
		realTask.wait()
	end
end

VirtualGame.SetGlobal("task", fakeTask)
VirtualGame.SetGlobal("Instance", Proxy.Instance)
for _, name in { "NumberRange", "NumberSequence", "ColorSequence", "ColorSequenceKeypoint" } do
	VirtualGame.SetGlobal(name, (roblox :: any)[name])
end
VirtualGame.SetGlobal("RaycastParams", {
	new = function()
		return {}
	end,
})
VirtualGame.SetGlobal("TweenInfo", {
	new = function()
		return {}
	end,
})
VirtualGame.Services.TweenService = {
	Create = function()
		return { Play = function() end }
	end,
}

-- Fakes --------------------------------------------------------------------------------

local Shared = game.ReplicatedStorage.Shared
local Server = game.ServerScriptService
local EnemyConfig = require(Shared.Config.EnemyConfig)
local PowerMath = require(Shared.Power.PowerMath)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local TableUtil = require(Shared.Util.TableUtil)

local PlayersService = { PlayerRemoving = Proxy.Signal() }
VirtualGame.Services.Players = PlayersService
VirtualGame.Services.TeleportService = {}
local function noop() end
VirtualGame.Services.Workspace = {
	GetServerTimeNow = function()
		return clock
	end,
	Raycast = function()
		return nil
	end,
	Terrain = { FillBlock = noop, FillBall = noop, FillCylinder = noop, FillWedge = noop },
}

local function makePlayer(name)
	local attributes = {}
	return {
		Name = name,
		DisplayName = name,
		UserId = #name,
		Parent = PlayersService,
		SetAttribute = function(_, key, value)
			attributes[key] = value
		end,
		GetAttribute = function(_, key)
			return attributes[key]
		end,
		GetJoinData = function()
			return {}
		end,
	}
end

-- Data
local profiles = {}
local counter = 0
local function uid()
	counter += 1
	return "uid-" .. counter
end
VirtualGame.Preload(Server.Services.DataService, {
	PlayerLoaded = Proxy.Signal(),
	GetData = function(player)
		return profiles[player]
	end,
	Set = function(player, path, value)
		TableUtil.SetPath(profiles[player], path, value)
	end,
})

-- Characters
local chars = {}
local statuses = {}
local deathResolver, spawnResolver
local FakeCharacters = {}
function FakeCharacters.SetResolvers(onDeath, spawnAt)
	deathResolver, spawnResolver = onDeath, spawnAt
end
function FakeCharacters.IsAlive(player)
	return chars[player] ~= nil and chars[player].Alive
end
function FakeCharacters.GetCharacter(player)
	local state = chars[player]
	if state == nil or not state.Alive then
		return nil
	end
	return {
		FindFirstChild = function(_, name)
			if name == "HumanoidRootPart" then
				return {
					Position = state.Position,
					CFrame = CFrame.new(state.Position),
					IsA = function(_, className)
						return className == "BasePart"
					end,
				}
			end
			return nil
		end,
	}
end
function FakeCharacters.Spawn(player, at)
	local target = at or spawnResolver(player)
	chars[player] = { Alive = true, Position = target.Position }
end
function FakeCharacters.Teleport(player, cframe)
	chars[player].Position = cframe.Position
end
function FakeCharacters.HealFull() end
local damageTaken = {}
function FakeCharacters.DamagePlayer(player, amount)
	damageTaken[player] = (damageTaken[player] or 0) + amount
	return amount
end
function FakeCharacters.LastDamageSource()
	return "Scrap Warden"
end
function FakeCharacters.SendStatus(player, status)
	statuses[player] = status
end
function FakeCharacters.Kill(player)
	local state = chars[player]
	if state == nil or not state.Alive then
		return
	end
	state.Alive = false
	local policy = deathResolver(player, state.Position)
	statuses[player] = policy
	if policy.Delay then
		fakeTask.delay(policy.Delay, function()
			if not chars[player].Alive then
				FakeCharacters.Spawn(player)
			end
		end)
	end
end
VirtualGame.Preload(Server.Services.CharacterService, FakeCharacters)

-- Enemies
local enemies = {}
local EnemyKilled = Proxy.Signal()
local FakeEnemies = { EnemyKilled = EnemyKilled, EnemyDamaged = Proxy.Signal() }
function FakeEnemies.Spawn(defId, cframe, options)
	local def = EnemyConfig.ById[defId]
	local scale = options.HealthScale or 1
	local enemy = {
		Def = def,
		Health = def.Health * scale,
		MaxHealth = def.Health * scale,
		Shield = 0,
		MaxShield = 0,
		Immune = false,
		Enraged = false,
		Dead = false,
		InstanceId = options.InstanceId,
		Tag = options.Tag,
		Options = options,
		HealthFloor = 0,
		DamageScale = options.DamageScale or 1,
		Root = { Position = cframe.Position },
	}
	enemy.Head = enemy.Root
	table.insert(enemies, enemy)
	return enemy
end
function FakeEnemies.GetEnemies(instanceId)
	local list = {}
	for _, enemy in enemies do
		if not enemy.Dead and enemy.InstanceId == instanceId then
			table.insert(list, enemy)
		end
	end
	return list
end
function FakeEnemies.DespawnInstance(instanceId)
	for _, enemy in enemies do
		if enemy.InstanceId == instanceId then
			enemy.Dead = true
		end
	end
end
function FakeEnemies.SetImmune(enemy, immune)
	enemy.Immune = immune
end
function FakeEnemies.SetEnraged(enemy, enraged)
	enemy.Enraged = enraged
end
function FakeEnemies.SetHealthFloor(enemy, floor)
	enemy.HealthFloor = floor
end
function FakeEnemies.SetBusy() end
local volleys = 0
function FakeEnemies.FireVolley()
	volleys += 1
end
function FakeEnemies.Relocate(enemy, cframe)
	enemy.Root.Position = cframe.Position
end
local leaps = 0
function FakeEnemies.Leap(enemy, landing)
	leaps += 1
	enemy.Root.Position = landing
end
function FakeEnemies.Despawn(enemy)
	enemy.Dead = true
end
function FakeEnemies.Kill(enemy)
	enemy.Dead = true
	EnemyKilled:Fire(enemy, nil)
end
VirtualGame.Preload(Server.Services.EnemyService, FakeEnemies)

local function kill(enemy, killer)
	enemy.Dead = true
	enemy.Health = 0
	EnemyKilled:Fire(enemy, killer)
end
local function alive(instanceId, tagPrefix)
	local list = {}
	for _, enemy in FakeEnemies.GetEnemies(instanceId) do
		if tagPrefix == nil or string.sub(enemy.Tag or "", 1, #tagPrefix) == tagPrefix then
			table.insert(list, enemy)
		end
	end
	return list
end
local function killAll(instanceId, tagPrefix)
	for _, enemy in alive(instanceId, tagPrefix) do
		kill(enemy)
	end
end

-- Loot, weapons, network, world
local completions = {}
local ammoDrops = 0
VirtualGame.Preload(Server.Services.LootService, {
	SetInstanceResolver = function() end,
	ClearInstance = function() end,
	AwardCompletion = function(player, info)
		table.insert(completions, { Player = player, Info = info })
		return {}
	end,
	DropAmmo = function()
		ammoDrops += 1
	end,
	AwardEncounter = function(player, activity, encounter, summary)
		table.insert(
			completions,
			{ Player = player, Info = { Activity = activity, Encounter = encounter, Summary = summary } }
		)
		return {}
	end,
})
VirtualGame.Preload(Server.Services.WeaponService, { ResetAmmo = function() end })
local sent = {}
local cues = {}
local cueLog = {}
VirtualGame.Preload(Server.Services.NetService, {
	OnInvoke = function() end,
	OnEvent = function() end,
	FireClient = function(player, name, payload, ...)
		if name == "WorldCue" then
			cues[payload] = (cues[payload] or 0) + 1
			cueLog[payload] = cueLog[payload] or {}
			table.insert(cueLog[payload], { ... })
			return
		end
		table.insert(sent, { Player = player, Name = name, Payload = payload, Args = { ... } })
	end,
	Notify = function() end,
})
-- The last `name` event sent to `player`.
local function lastSent(player, name)
	for index = #sent, 1, -1 do
		local entry = sent[index]
		if entry.Player == player and entry.Name == name then
			return entry
		end
	end
	return nil
end
local templates = {}
for _, name in { "FirstLight", "SunkenRelay", "HollowDark", "HollowSpire", "VaultOfEchoes" } do
	templates[name] = require(Server.MapBuilders[name .. "Builder"]).Build()
end
local instancesFolder = Proxy.Instance.new("Folder")
VirtualGame.Preload(Server.Services.WorldService, {
	GetMapTemplate = function(name)
		return templates[name]
	end,
	Folder = function()
		return instancesFolder
	end,
	InstanceOrigin = function(slot)
		return Vector3.new(5000 * slot, 0, 0)
	end,
	GetHubSpawn = function()
		return CFrame.new(0, 5, 0)
	end,
	GetHubMarker = function()
		return nil
	end,
	PlayerCharacters = function()
		return {}
	end,
})

local ActivityService = require(Server.Services.ActivityService)
local CombatContext = require(Server.Combat.CombatContext)
ActivityService.Init()
ActivityService.Start()

local function join(name, power)
	local player = makePlayer(name)
	profiles[player] = ProfileTemplate.CreateNew(0, uid, VirtualGame.Random.new(#name))
	for _, itemUid in profiles[player].Equipped do
		profiles[player].Items[itemUid].Power = power
	end
	chars[player] = { Alive = true, Position = Vector3.new(0, 5, 0) }
	return player
end

local function moveTo(player, position)
	chars[player].Position = position
end

local function near(a, b, tolerance)
	return (a - b).Magnitude <= (tolerance or 4)
end

local function marker(run, name)
	return run.Markers.ByName[name]
end

-- Lets rifts and dropships deliver their enemies.
local function arrive()
	advance(3.5)
end

-- Tests ---------------------------------------------------------------------------------

describe("Story mission: First Light", function()
	local player = join("Tester", 350)
	local run

	it("launches into its own copy of the map at the start marker", function()
		local ok, err = ActivityService.Launch(player, "STORY_01")
		expect(err).toBeNil()
		expect(ok).toBe(true)
		run = ActivityService.GetRun(player)
		expect(player:GetAttribute("InstanceId")).toBe(run.Id)
		expect(near(chars[player].Position, marker(run, "PlayerStart").Position, 3)).toBe(true)
		local state = lastSent(player, "ActivityState").Payload
		expect(state.Destination).toBe("Frostreach")
		expect(state.StartedAt).toBe(run.StartedAt)
		expect(near(state.Intro.Start, marker(run, "PlayerStart").Position, 1)).toBe(true)
		expect(near(state.Intro.Target, marker(run, "Wreck").Position, 1)).toBe(true)
		advance(0.5)
		expect(run.ZoneIndex).toBe(1)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Crash Site")
		expect(run.Folder:GetAttribute("ObjectiveText")).toBe("Search the wreckage")
		expect(run.Folder:GetAttribute("HasWaypoint")).toBe(true)
		expect(run.Checkpoint).toBe("CP_CrashSite")
	end)

	it("brings the scavengers in through rifts once the wreck is reached", function()
		moveTo(player, marker(run, "Wreck").Position)
		advance(0.5)
		expect(run.StepIndex).toBe(2)
		expect(#alive(run.Id)).toBe(0) -- still stepping out of the rifts
		expect((cues.Portal or 0) > 0).toBe(true)
		arrive()
		expect(#alive(run.Id)).toBe(6)
		expect(run.Folder:GetAttribute("ObjectiveCount")).toBe("0/10")
		expect(run.Folder:GetAttribute("Wave")).toBe("1/2")
	end)

	it("sends the next wave at 80% cleared, by dropship", function()
		local list = alive(run.Id)
		for index = 1, 4 do
			kill(list[index], player)
		end
		local line = lastSent(player, "KillFeed")
		expect(line.Payload).toBe("Kill")
		expect(line.Args[1]).toBe("Tester")
		expect(line.Args[2]).toBe(list[4].Def.Name)
		expect(line.Args[3]).toBe(list[4].Def.Tier)
		advance(0.5)
		expect(run.Folder:GetAttribute("Wave")).toBe("1/2") -- 4 of 6 isn't 80% yet
		kill(list[5])
		advance(0.5)
		expect(run.Folder:GetAttribute("Wave")).toBe("2/2")
		expect(cues.Dropship).toBe(1)
		arrive()
		local kinds = {}
		for _, enemy in alive(run.Id) do
			kinds[enemy.Def.Id] = (kinds[enemy.Def.Id] or 0) + 1
		end
		expect(kinds.RUST_SKIFF_DRONE).toBe(2)
	end)

	it("opens the shield gate into the village when every wave is dead", function()
		killAll(run.Id)
		advance(0.5)
		expect(run.ZoneIndex).toBe(2)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("Frostfall Village")
		expect(run.Checkpoint).toBe("CP_Village")
		expect(run.Map.Gates.Gate_CrashSite.Field.CanCollide).toBe(false)
		expect(cues.GateOpen).toBe(1)
		expect(string.find(run.Folder:GetAttribute("ZoneLog"), "The Crash Site=", 1, true) ~= nil).toBe(true)
	end)

	it("respawns a dead player at the checkpoint after 5 seconds", function()
		FakeCharacters.Kill(player)
		expect(statuses[player].Delay).toBe(5)
		local line = lastSent(player, "KillFeed")
		expect(line.Payload).toBe("Death")
		expect(line.Args[1]).toBe("Scrap Warden")
		expect(line.Args[2]).toBe("Tester")
		advance(4)
		expect(FakeCharacters.IsAlive(player)).toBe(false)
		advance(1.5)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
		expect(near(chars[player].Position, marker(run, "CP_Village").Position)).toBe(true)
		expect(run.Folder:GetAttribute("Deaths_" .. player.UserId)).toBe(1)
	end)

	it("puts snipers on the village roofs", function()
		moveTo(player, marker(run, "VillageGate").Position)
		advance(0.5)
		arrive()
		local list = alive(run.Id)
		for index = 1, #list - 1 do
			kill(list[index])
		end
		advance(0.5)
		arrive()
		local snipers = 0
		for _, enemy in alive(run.Id) do
			if enemy.Def.Id == "RUST_SNIPER" then
				snipers += 1
				expect(enemy.Root.Position.Y > 15).toBe(true)
			end
		end
		expect(snipers).toBe(2)
	end)

	it("takes the outpost courtyard, then hacks the uplink only while someone stands there", function()
		expect(ActivityService.JumpToZone(player, 3)).toBe(true)
		advance(0.5)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("Kessrin Outpost")
		arrive()
		local turrets = 0
		for _, enemy in alive(run.Id) do
			if enemy.Def.Id == "RUST_TURRET" then
				turrets += 1
			end
		end
		expect(turrets).toBe(2)
		killAll(run.Id)
		advance(0.5)
		arrive()
		killAll(run.Id)
		advance(0.5)
		expect(run.StepIndex).toBe(2)
		advance(10)
		expect(#alive(run.Id) > 0).toBe(true) -- waves attack the uplink
		expect(run.StepIndex).toBe(2) -- not in the zone yet
		moveTo(player, marker(run, "Uplink").Position)
		advance(40)
		expect(run.StepIndex).toBe(2)
		advance(21)
		expect(run.ZoneIndex).toBe(4)
		expect(run.Map.Gates.Gate_Outpost.Slab.CanCollide).toBe(false)
	end)

	it("destroys the reactor's regulators, which extends the bridge to the pit", function()
		killAll(run.Id)
		advance(0.5)
		arrive()
		killAll(run.Id)
		advance(0.5)
		arrive()
		killAll(run.Id)
		advance(0.5)
		expect(run.StepIndex).toBe(2)
		local regulators = alive(run.Id, "z4s2")
		local objects = {}
		for _, enemy in regulators do
			if enemy.Def.Id == "RUST_GENERATOR" then
				table.insert(objects, enemy)
			end
		end
		expect(#objects).toBe(3)
		expect(run.Folder:GetAttribute("ObjectiveCount")).toBe("0/3")
		for _, object in objects do
			kill(object)
		end
		advance(0.5)
		expect(run.ZoneIndex).toBe(5)
		expect(run.Map.Gates.Gate_Reactor.Deck.CanCollide).toBe(true)
		expect(run.Checkpoint).toBe("CP_ScrapPit")
	end)

	it("fights the Scrap Warden: 15-30 captains of health, attacks and arena ammo", function()
		killAll(run.Id, "z4") -- leftover reactor waves
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_SCRAP_WARDEN")
		local captains = boss.Def.Health / EnemyConfig.CaptainHealth
		expect(captains >= 15 and captains <= 30).toBe(true)
		expect(run.Folder:GetAttribute("BossActive")).toBe(true)
		expect(boss.HealthFloor).toBe(boss.MaxHealth * 0.66)
		advance(25)
		expect(volleys > 0).toBe(true) -- barrage
		expect(leaps > 0).toBe(true) -- slam
		expect((cues.Telegraph or 0) > 0).toBe(true)
		expect(ammoDrops > 0).toBe(true)
	end)

	it("turns immune at 66% until two waves of its guard are dead", function()
		killAll(run.Id, "bossAdds")
		local boss = alive(run.Id, "boss")[1]
		boss.Health = boss.MaxHealth * 0.66
		advance(0.5)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("BossImmune")).toBe(true)
		expect(boss.HealthFloor).toBe(boss.MaxHealth * 0.33)
		arrive()
		expect(#alive(run.Id, "bossImmune1")).toBe(6)
		killAll(run.Id, "bossImmune1")
		advance(0.5)
		expect(boss.Immune).toBe(true) -- second wave
		arrive()
		killAll(run.Id, "bossImmune1")
		advance(0.5)
		expect(boss.Immune).toBe(false)
	end)

	it("turns immune again at 33%, then dies into a loot chest", function()
		local boss = alive(run.Id, "boss")[1]
		boss.Health = boss.MaxHealth * 0.3
		advance(0.5)
		expect(boss.Immune).toBe(true)
		arrive()
		killAll(run.Id, "bossImmune2")
		advance(0.5)
		expect(boss.Immune).toBe(false)
		expect(boss.HealthFloor).toBe(0)
		kill(boss, player)
		expect(lastSent(player, "KillFeed").Payload).toBe("Boss")
		expect(lastSent(player, "KillFeed").Args[2]).toBe(boss.Def.Name)
		advance(0.5)
		expect(cues.BossDeath).toBe(1)
		expect(run.Status).toBe("Complete")
		expect(profiles[player].Progress.StoryCompleted.STORY_01).toBe(true)
		expect(profiles[player].Progress.ActivityClears.STORY_01).toBe(1)
		expect(#completions).toBe(0) -- waiting in the chest
		local chest = run.Map:FindFirstChild("RewardChest")
		expect(chest ~= nil).toBe(true)
		local prompt = chest:FindFirstChild("ClaimRewards", true)
		prompt.Triggered:Fire(player)
		prompt.Triggered:Fire(player)
		expect(#completions).toBe(1)
		expect(completions[1].Info.Activity.Id).toBe("STORY_01")
		-- The Mission Complete screen's numbers.
		local summary = completions[1].Info.Summary
		expect(summary.Kind).toBe("Story")
		expect(summary.Elapsed).toBe(run.Folder:GetAttribute("Elapsed"))
		expect(summary.Kills).toBe(5)
		expect(summary.Deaths).toBe(1)
		expect(summary.FireteamKills).toBe(5)
		expect(summary.Score).toBeNil()
	end)

	it("returns the fireteam to the hub and cleans up", function()
		advance(30.5)
		expect(#completions).toBe(1) -- no double rewards
		expect(player:GetAttribute("InstanceId")).toBeNil()
		expect(ActivityService.GetRun(player)).toBeNil()
		expect(run.Status).toBe("Closed")
		expect(near(chars[player].Position, Vector3.new(0, 5, 0), 1)).toBe(true)
		local last = sent[#sent]
		expect(last.Name).toBe("ActivityState")
		expect(last.Payload.InActivity).toBe(false)
	end)
end)

describe("Nightfall: Hollow Spire", function()
	local player = join("Striker", 470)
	local run

	it("uses the difficulty's power, the weekly modifiers and contest mode", function()
		local ok = ActivityService.Launch(player, "NIGHTFALL", "Legend", true)
		expect(ok).toBe(true)
		run = ActivityService.GetRun(player)
		expect(run.Power).toBe(490)
		expect(#run.Modifiers).toBe(2)
		local context = CombatContext.Get(player)
		expect(context.ActivityPower).toBe(490)
		expect(context.DeltaCap).toBe(0)
		expect(context.Effects ~= nil).toBe(true)
	end)

	it("jumps to a zone with /zone, opening the gates before it", function()
		expect(ActivityService.JumpToZone(player, 3)).toBe(true)
		advance(0.3)
		expect(run.ZoneIndex).toBe(3)
		expect(run.Map.Gates.Gate_Canyon:GetAttribute("Open")).toBe(true)
		expect(run.Map.Gates.Gate_Gate:GetAttribute("Open")).toBe(true)
		expect(run.Map.Gates.Gate_Halls:GetAttribute("Open")).toBeNil()
		expect(run.Checkpoint).toBe("CP_Halls")
		expect(near(chars[player].Position, marker(run, "CP_Halls").Position)).toBe(true)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Inner Halls")
	end)

	it("skips steps with /skip, opening the zone's gate", function()
		ActivityService.SkipObjective(player)
		advance(0.3)
		ActivityService.SkipObjective(player)
		advance(0.3)
		expect(run.ZoneIndex).toBe(4)
		expect(run.Map.Gates.Gate_Halls.Slab.CanCollide).toBe(false)
		expect(run.Checkpoint).toBe("CP_Summit")
	end)

	it("makes Vekta immune at 66% (guards) and 33% (pylons, and the floor collapses)", function()
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_SPIRE_OVERSEER")
		boss.Health = boss.MaxHealth * 0.6
		advance(0.5)
		expect(boss.Immune).toBe(true)
		for _ = 1, 2 do
			arrive()
			killAll(run.Id, "bossImmune1")
			advance(0.5)
		end
		expect(boss.Immune).toBe(false)
		boss.Health = boss.MaxHealth * 0.3
		advance(0.5)
		expect(boss.Immune).toBe(true)
		expect(cues.Collapse).toBe(1)
		local pylons = alive(run.Id, "bossImmune2")
		expect(#pylons).toBe(3)
		expect(pylons[1].Def.Id).toBe("RUST_PYLON")
		for _, pylon in pylons do
			kill(pylon)
		end
		advance(0.5)
		expect(boss.Immune).toBe(false)
		advance(4)
		local floor = run.Map:FindFirstChild("CollapseFloor", true)
		for _, part in floor:GetDescendants() do
			if part:IsA("BasePart") then
				expect(part.CanCollide).toBe(false)
			end
		end
	end)

	it("scores the run and hands out a medal for the time", function()
		local boss = alive(run.Id, "boss")[1]
		kill(boss)
		advance(0.5)
		expect(run.Status).toBe("Complete")
		expect(run.Folder:GetAttribute("Score") > 0).toBe(true)
		local elapsed = run.Folder:GetAttribute("Elapsed")
		local MissionRules = require(Shared.Activities.MissionRules)
		expect(run.Folder:GetAttribute("Medal")).toBe(MissionRules.Medal(run.Activity, elapsed) or "")
		expect(run.Folder:GetAttribute("Medal")).toBe("Gold") -- /zone skipped most of it
		ActivityService.Leave(player)
		local info = completions[#completions].Info
		expect(info.Difficulty.Id).toBe("Legend")
		expect(info.BonusDrops).toBe(1)
		expect(info.Summary.Kind).toBe("Nightfall")
		expect(info.Summary.Medal).toBe("Gold")
		expect(info.Summary.Score).toBe(run.Score)
	end)
end)

local function litPlates(run)
	local list = {}
	for index = 1, 3 do
		local plate = run.Map:FindFirstChild("Plate_" .. index, true)
		if plate:GetAttribute("Lit") then
			table.insert(list, plate)
		end
	end
	return list
end

describe("Raid: The Gate, solo", function()
	local player = join("Solo", 495)
	local run, boss

	it("brings Harrowmaw out at solo health, immune, behind lit echo plates", function()
		expect(ActivityService.Launch(player, "RAID_VAULT_OF_ECHOES", nil, true)).toBe(true)
		run = ActivityService.GetRun(player)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Gate")
		moveTo(player, marker(run, "GateEntry").Position)
		advance(0.5)
		boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_ECHO_ENGINE")
		local healthScale = PowerMath.ActivityEnemyScale(495)
		expect(math.abs(boss.MaxHealth - boss.Def.Health * healthScale) < 1).toBe(true)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("EnrageAt") > 0).toBe(true)
		expect(#litPlates(run)).toBe(1) -- solo: one lit plate
	end)

	it("opens a damage phase after holding the lit plate, then lights a new one", function()
		local unlit
		for index = 1, 3 do
			local plate = run.Map:FindFirstChild("Plate_" .. index, true)
			if not plate:GetAttribute("Lit") then
				unlit = plate
			end
		end
		moveTo(player, unlit.Position + Vector3.new(0, 3, 0))
		advance(6)
		expect(boss.Immune).toBe(true) -- the wrong plate does nothing
		local lit = litPlates(run)[1]
		moveTo(player, lit.Position + Vector3.new(0, 3, 0))
		advance(3)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("Charge") > 0).toBe(true)
		advance(2.5)
		expect(boss.Immune).toBe(false)
		expect(CombatContext.Get(player).DamageBuff).toBe(1.25)
		moveTo(player, marker(run, "CP_Gate").Position)
		advance(20.5)
		expect(boss.Immune).toBe(true)
		expect(CombatContext.Get(player).DamageBuff).toBe(1)
		expect(#litPlates(run)).toBe(1)
		expect(litPlates(run)[1] ~= lit).toBe(true) -- a different plate this time
	end)

	it("respawns a solo Keeper after 10 seconds", function()
		FakeCharacters.Kill(player)
		expect(statuses[player].Delay).toBe(10)
		advance(10.5)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
	end)

	it("wipes on enrage and restarts the encounter with a fresh boss", function()
		advance(360 - (clock - run.StartedAt) + 5)
		expect(run.Status == "Wiped" or run.Status == "Active").toBe(true)
		advance(9)
		expect(run.Status).toBe("Active")
		expect(boss.Dead).toBe(true)
		expect(run.ZoneIndex).toBe(1)
		moveTo(player, marker(run, "GateEntry").Position)
		advance(0.5)
		local fresh = alive(run.Id, "boss")[1]
		expect(fresh ~= nil and fresh ~= boss).toBe(true)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
		ActivityService.Leave(player)
		expect(run.Status).toBe("Closed")
	end)
end)

describe("Raid: every encounter, solo", function()
	local player = join("Keeper", 500)
	local run

	it("drops a chest with the weekly Pinnacle when the Gate falls", function()
		ActivityService.Launch(player, "RAID_VAULT_OF_ECHOES", nil, true)
		run = ActivityService.GetRun(player)
		moveTo(player, marker(run, "GateEntry").Position)
		advance(0.5)
		kill(alive(run.Id, "boss")[1])
		advance(0.5)
		expect(run.Cleared[1].Id).toBe("THE_GATE")
		expect(run.Map.Gates.Gate_Gate:GetAttribute("Open")).toBe(true)
		local chest = run.Map:FindFirstChild("Chest_THE_GATE")
		expect(chest ~= nil).toBe(true)
		chest:FindFirstChild("ClaimRewards", true).Triggered:Fire(player)
		chest:FindFirstChild("ClaimRewards", true).Triggered:Fire(player)
		local gateClaims = 0
		for _, entry in completions do
			if entry.Player == player and entry.Info.Encounter and entry.Info.Encounter.Id == "THE_GATE" then
				gateClaims += 1
			end
		end
		expect(gateClaims).toBe(1)
	end)

	it("puts fallers back at the top of the Descent", function()
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Descent")
		expect(run.Checkpoint).toBe("CP_Descent")
		moveTo(player, Vector3.new(run.Origin.X, -200, 300))
		advance(0.5)
		expect(near(chars[player].Position, marker(run, "CP_Descent").Position)).toBe(true)
		moveTo(player, marker(run, "DescentEnd").Position)
		advance(0.5)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Echo Chamber")
		expect(run.Map.Gates.Gate_Descent:GetAttribute("Open")).toBe(true)
	end)

	it("lowers Oriane's shield with three echoes carried to the well", function()
		moveTo(player, marker(run, "ChamberEntry").Position)
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("CONC_ECHO_WARDEN")
		expect(boss.Immune).toBe(true)
		arrive()
		local bearers = alive(run.Id, "bearer")
		expect(#bearers).toBe(3)
		local well = marker(run, "EchoWell")
		for index = 1, 3 do
			kill(bearers[index])
			advance(0.5)
			expect((player:GetAttribute("EchoChargeUntil") or 0) > clock).toBe(true)
			moveTo(player, well.Position)
			advance(0.5)
			expect(player:GetAttribute("EchoChargeUntil")).toBeNil()
			moveTo(player, marker(run, "CP_Chamber").Position)
		end
		expect(cues.Deposit).toBe(3)
		expect(boss.Immune).toBe(false)
		expect(CombatContext.Get(player).DamageBuff).toBe(1.25)
	end)

	it("lets a carried echo fade, and a new Bearer takes its place", function()
		local boss = alive(run.Id, "boss")[1]
		advance(26) -- the damage window closes
		expect(boss.Immune).toBe(true)
		arrive()
		local bearer = alive(run.Id, "bearer")[1]
		kill(bearer)
		advance(0.5)
		expect(player:GetAttribute("EchoChargeUntil") ~= nil).toBe(true)
		advance(31)
		expect(player:GetAttribute("EchoChargeUntil")).toBeNil()
		advance(8)
		expect(#alive(run.Id, "bearer")).toBe(3)
		kill(boss)
		advance(0.5)
		expect(run.Cleared[#run.Cleared].Id).toBe("THE_ECHO_CHAMBER")
		expect(run.Map:FindFirstChild("Chest_THE_ECHO_CHAMBER") ~= nil).toBe(true)
	end)

	it("sends sentinels on patrol and burns Keepers who walk into a laser", function()
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Silent Hall")
		advance(0.5)
		local sentinels = alive(run.Id, "z4s1")
		expect(#sentinels).toBe(4)
		expect(sentinels[1].Def.Id).toBe("CONC_VAULT_SENTINEL")
		expect(#sentinels[1].Options.Patrol).toBe(6)
		expect(sentinels[1].Options.Aggro).toBe(false)
		-- Stand inside the last blinking wall long enough to catch it on.
		local before = damageTaken[player] or 0
		local wall
		for _, part in run.Map:GetDescendants() do
			if part.Name == "Laser" and part:GetAttribute("LaserPeriod") == 3 then
				wall = part
			end
		end
		moveTo(player, wall.Position)
		advance(3.5)
		expect((damageTaken[player] or 0) - before >= 45).toBe(true)
		moveTo(player, marker(run, "HallEnd").Position)
		advance(0.5)
		expect(run.Folder:GetAttribute("ZoneName")).toBe("The Sovereign's Throne")
	end)

	it("fights the Sovereign through three phases, with safe circles against its nova", function()
		killAll(run.Id)
		moveTo(player, marker(run, "ThroneEntry").Position)
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("CONC_ECHO_SOVEREIGN")
		expect(run.Folder:GetAttribute("BossPhase")).toBe(1)
		boss.Health = boss.MaxHealth * 0.6
		advance(0.5)
		local pillars = alive(run.Id, "bossImmune1")
		expect(#pillars).toBe(3)
		expect(pillars[1].Def.Id).toBe("CONC_ECHO_PILLAR")
		for _, pillar in pillars do
			kill(pillar)
		end
		advance(0.5)
		expect(run.Folder:GetAttribute("BossPhase")).toBe(2)
		-- Phase 2 brings the nova: stand in a lit circle and survive it.
		local before = #(cueLog.SafeZone or {})
		for _ = 1, 60 do
			advance(1)
			if #(cueLog.SafeZone or {}) > before then
				break
			end
		end
		local circle = cueLog.SafeZone[#cueLog.SafeZone][1]
		moveTo(player, circle)
		local hurt = damageTaken[player] or 0
		advance(9)
		expect((cues.Nova or 0) > 0).toBe(true)
		expect((damageTaken[player] or 0) - hurt < 9999).toBe(true)
		killAll(run.Id, "bossAdds")
		boss.Health = boss.MaxHealth * 0.3
		advance(0.5)
		for _ = 1, 2 do
			arrive()
			killAll(run.Id, "bossImmune2")
			advance(0.5)
		end
		expect(boss.Immune).toBe(false)
		expect(run.Folder:GetAttribute("BossPhase")).toBe(3)
		kill(boss)
		advance(0.5)
		expect(run.Status).toBe("Complete")
	end)

	it("pays every encounter's chest once, including ones left unopened", function()
		ActivityService.Leave(player)
		local claimed = {}
		for _, entry in completions do
			if entry.Player == player and entry.Info.Encounter then
				claimed[entry.Info.Encounter.Id] = (claimed[entry.Info.Encounter.Id] or 0) + 1
			end
		end
		expect(claimed.THE_GATE).toBe(1)
		expect(claimed.THE_ECHO_CHAMBER).toBe(1)
		expect(claimed.ECHO_SOVEREIGN).toBe(1)
		expect(claimed.THE_DESCENT).toBeNil()
		-- Only the last chest carries the Mission Complete summary.
		for _, entry in completions do
			if entry.Player == player and entry.Info.Encounter then
				local last = entry.Info.Encounter.Id == "ECHO_SOVEREIGN"
				expect(entry.Info.Summary ~= nil).toBe(last)
				if last then
					expect(entry.Info.Summary.Kind).toBe("Raid")
				end
			end
		end
	end)
end)

describe("Raid: Vault of Echoes, fireteam", function()
	local leader = join("Leader", 495)
	local friend = join("Friend", 495)
	local run

	it("lets a second Keeper join and scales the boss for two", function()
		ActivityService.Launch(leader, "RAID_VAULT_OF_ECHOES", nil, true)
		run = ActivityService.GetRun(leader)
		local ok, err = ActivityService.Join(friend, run.Id)
		expect(err).toBeNil()
		expect(ok).toBe(true)
		moveTo(leader, marker(run, "GateEntry").Position)
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		local healthScale = PowerMath.ActivityEnemyScale(495)
		expect(math.abs(boss.MaxHealth - boss.Def.Health * healthScale * 1.6) < 1).toBe(true)
	end)

	it("needs both lit plates held at once for two Keepers", function()
		local boss = alive(run.Id, "boss")[1]
		local lit = litPlates(run)
		expect(#lit).toBe(2)
		moveTo(leader, lit[1].Position)
		advance(4)
		expect(boss.Immune).toBe(true)
		moveTo(friend, lit[2].Position)
		advance(3.5)
		expect(boss.Immune).toBe(false)
	end)

	it("leaves a ghost that a teammate revives by holding E", function()
		FakeCharacters.Kill(leader)
		expect(statuses[leader].Delay).toBeNil()
		local ghost = run.Map:FindFirstChild("Ghost_Leader", true)
		expect(ghost ~= nil).toBe(true)
		local prompt = ghost:FindFirstChildOfClass("ProximityPrompt")
		expect(prompt.HoldDuration).toBe(3)
		prompt.Triggered:Fire(friend)
		local line = lastSent(leader, "KillFeed")
		expect(line.Payload).toBe("Revive")
		expect(line.Args[1]).toBe("Friend")
		expect(line.Args[2]).toBe("Leader")
		advance(0.2)
		expect(FakeCharacters.IsAlive(leader)).toBe(true)
		expect(run.Map:FindFirstChild("Ghost_Leader", true)).toBeNil()
	end)

	it("wipes when everyone is down and restarts the encounter", function()
		FakeCharacters.Kill(leader)
		FakeCharacters.Kill(friend)
		advance(0.5)
		expect(run.Status).toBe("Wiped")
		advance(8.5)
		expect(run.Status).toBe("Active")
		expect(FakeCharacters.IsAlive(leader)).toBe(true)
		expect(FakeCharacters.IsAlive(friend)).toBe(true)
		moveTo(leader, marker(run, "GateEntry").Position)
		advance(0.5)
		expect(#alive(run.Id, "boss")).toBe(1)
	end)
end)

-- Plays whatever step the run is on like a (very good) player would.
local function autoplay(player, run, onBoss)
	local seenBoss = false
	for _ = 1, 500 do
		if run.Status ~= "Active" then
			return
		end
		local entry = run.Zones[run.ZoneIndex]
		local step = entry and entry.Zone.Steps[run.StepIndex]
		if step and (step.Kind == "Travel" or step.Kind == "Defend") then
			moveTo(player, marker(run, step.Target).Position)
		end
		if step and step.Kind == "Interact" then
			local prompt = run.Map:FindFirstChild("MissionInteract", true)
			if prompt then
				prompt.Triggered:Fire(player)
			end
		end
		local boss = run.Boss
		if boss and not boss.Dead then
			if not seenBoss then
				seenBoss = true
				if onBoss then
					onBoss(boss)
				end
			end
			if boss.Immune then
				for _, enemy in alive(run.Id) do
					if enemy ~= boss then
						kill(enemy)
					end
				end
			elseif boss.HealthFloor > 0 then
				boss.Health = boss.HealthFloor
			else
				kill(boss)
			end
		else
			for _, enemy in alive(run.Id) do
				kill(enemy)
			end
		end
		advance(1)
	end
end

describe("Every mission plays through to the chest", function()
	for _, spec in
		{
			{ Id = "STORY_02", Boss = "CONC_TIDE_MARSHAL", Power = 380 },
			{ Id = "STORY_03", Boss = "VEIL_HOLLOW_PRIEST", Power = 410 },
			{ Id = "NIGHTFALL", Boss = "RUST_SPIRE_OVERSEER", Power = 450 },
		}
	do
		it(spec.Id, function()
			local player = join("Auto" .. spec.Id, spec.Power)
			expect(ActivityService.Launch(player, spec.Id, nil, true)).toBe(true)
			local run = ActivityService.GetRun(player)
			local bossId
			local blinksBefore = cues.Blink or 0
			autoplay(player, run, function(boss)
				bossId = boss.Def.Id
				-- Let it use its attacks for a while before it goes down.
				advance(20)
			end)
			expect(run.Status).toBe("Complete")
			expect(bossId).toBe(spec.Boss)
			if spec.Id == "STORY_03" then
				expect((cues.Blink or 0) > blinksBefore).toBe(true) -- the Priest teleports
			end
			-- Every zone's gate that exists was opened on the way.
			for _, gate in run.Map.Gates:GetChildren() do
				expect(gate:GetAttribute("Open")).toBe(true)
			end
			local chest = run.Map:FindFirstChild("RewardChest")
			chest:FindFirstChild("ClaimRewards", true).Triggered:Fire(player)
			expect(completions[#completions].Info.Activity.Id).toBe(spec.Id)
			ActivityService.Leave(player)
		end)
	end
end)

describe("Cleanup", function()
	it("closes every run so no simulated threads outlive the spec", function()
		for player in profiles do
			ActivityService.Leave(player)
		end
		clock = math.huge
		for _ = 1, 5 do
			realTask.wait()
		end
		expect(#FakeEnemies.GetEnemies(nil)).toBe(0)
	end)
end)
