-- Integration test for ActivityService: the objective runner, checkpoints,
-- doors, boss mechanics, deaths, revives, wipes and completion, with the
-- other services replaced by fakes and a virtual clock driving time.
local roblox = require("@lune/roblox")
local realTask = require("@lune/task")
local Proxy = VirtualGame.Proxy

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- Virtual time -----------------------------------------------------------------------

local clock = 0
local function vwait(seconds)
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
VirtualGame.Services.Workspace = {
	GetServerTimeNow = function()
		return clock
	end,
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
		Root = { Position = cframe.Position },
	}
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
VirtualGame.Preload(Server.Services.EnemyService, FakeEnemies)

local function kill(enemy)
	enemy.Dead = true
	enemy.Health = 0
	EnemyKilled:Fire(enemy, nil)
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
VirtualGame.Preload(Server.Services.LootService, {
	SetInstanceResolver = function() end,
	ClearInstance = function() end,
	AwardCompletion = function(player, info)
		table.insert(completions, { Player = player, Info = info })
		return {}
	end,
})
VirtualGame.Preload(Server.Services.WeaponService, { ResetAmmo = function() end })
local sent = {}
VirtualGame.Preload(Server.Services.NetService, {
	OnInvoke = function() end,
	OnEvent = function() end,
	FireClient = function(player, name, payload)
		table.insert(sent, { Player = player, Name = name, Payload = payload })
	end,
	Notify = function() end,
})
local templates = {}
for _, name in { "FirstLight", "HollowSpire", "VaultOfEchoes" } do
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
		expect(near(chars[player].Position, run.Markers.PlayerStart.Position, 3)).toBe(true)
		advance(0.5)
		expect(run.Index).toBe(1)
		expect(run.Folder:GetAttribute("ObjectiveText")).toBe("Reach the outpost")
		expect(run.Folder:GetAttribute("HasWaypoint")).toBe(true)
	end)

	it("completes travel when a player reaches the zone and moves the checkpoint", function()
		moveTo(player, run.Markers.Zone_Outpost.Position)
		advance(0.5)
		expect(run.Index).toBe(2)
		expect(run.Checkpoint).toBe("Checkpoint_Outpost")
	end)

	it("needs all twelve courtyard enemies, including the delayed wave", function()
		expect(#alive(run.Id)).toBe(10)
		expect(run.Folder:GetAttribute("ObjectiveCount")).toBe("0/12")
		killAll(run.Id)
		advance(1)
		expect(run.Index).toBe(2) -- the back wave hasn't arrived yet
		expect(run.Folder:GetAttribute("ObjectiveCount")).toBe("10/12")
		advance(8)
		expect(#alive(run.Id)).toBe(2)
		killAll(run.Id)
		advance(0.5)
		expect(run.Index).toBe(3)
		expect(run.Checkpoint).toBe("Checkpoint_Terminal")
		expect(run.Map.Doors.Door_Terminal.CanCollide).toBe(false)
	end)

	it("respawns a dead player at the checkpoint after 5 seconds", function()
		FakeCharacters.Kill(player)
		expect(statuses[player].Delay).toBe(5)
		advance(4)
		expect(FakeCharacters.IsAlive(player)).toBe(false)
		advance(1.5)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
		expect(near(chars[player].Position, run.Markers.Checkpoint_Terminal.Position)).toBe(true)
	end)

	it("hacks the terminal only while someone stands in the zone", function()
		advance(5)
		expect(run.Index).toBe(3) -- not in the zone yet
		expect(#alive(run.Id) > 0).toBe(true) -- waves attack the terminal
		moveTo(player, run.Markers.Zone_Terminal.Position)
		advance(10)
		expect(run.Index).toBe(3)
		advance(11)
		expect(run.Index).toBe(4)
		expect(run.Map.Doors.Door_Boss.CanCollide).toBe(false)
	end)

	it("spawns the boss, calls adds at half health, and completes on the kill", function()
		killAll(run.Id, "obj") -- leftover terminal waves
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_SCRAP_BARON")
		expect(run.Folder:GetAttribute("BossActive")).toBe(true)
		boss.Health = boss.MaxHealth * 0.45
		advance(0.5)
		expect(#alive(run.Id, "bossAdds")).toBe(6)
		kill(boss)
		advance(0.5)
		expect(run.Status).toBe("Complete")
		expect(#completions).toBe(1)
		expect(completions[1].Info.Activity.Id).toBe("STORY_01")
		expect(profiles[player].Progress.StoryCompleted.STORY_01).toBe(true)
		expect(profiles[player].Progress.ActivityClears.STORY_01).toBe(1)
	end)

	it("returns the fireteam to the hub and cleans up", function()
		advance(12.5)
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

	it("makes Kaldrek immune at half health until his bodyguard dies", function()
		for _ = 1, 4 do
			ActivityService.SkipObjective(player)
			advance(0.3)
		end
		local boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_KALDREK")
		boss.Health = boss.MaxHealth * 0.49
		advance(0.5)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("BossImmune")).toBe(true)
		killAll(run.Id, "bossAdds")
		advance(0.5)
		expect(boss.Immune).toBe(false)
		kill(boss)
		advance(0.5)
		expect(run.Status).toBe("Complete")
		expect(completions[#completions].Info.Difficulty.Id).toBe("Legend")
		expect(run.Folder:GetAttribute("Score") > 0).toBe(true)
		advance(13)
	end)
end)

describe("Raid: Vault of Echoes, solo", function()
	local player = join("Solo", 495)
	local run, boss

	it("scales the boss down for one Keeper and starts immune", function()
		expect(ActivityService.Launch(player, "RAID_VAULT_OF_ECHOES", nil, true)).toBe(true)
		run = ActivityService.GetRun(player)
		moveTo(player, run.Markers.Zone_Chamber.Position)
		advance(0.5)
		boss = alive(run.Id, "boss")[1]
		expect(boss.Def.Id).toBe("RUST_ECHO_ENGINE")
		local healthScale = PowerMath.ActivityEnemyScale(495)
		expect(math.abs(boss.MaxHealth - 60000 * healthScale / 6) < 1).toBe(true)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("EnrageAt") > 0).toBe(true)
	end)

	it("opens a damage phase after holding a plate for 5 seconds", function()
		local plate = run.Map:FindFirstChild("Plate_2", true)
		moveTo(player, plate.Position + Vector3.new(0, 3, 0))
		advance(3)
		expect(boss.Immune).toBe(true)
		expect(run.Folder:GetAttribute("Charge") > 0).toBe(true)
		advance(2.5)
		expect(boss.Immune).toBe(false)
		expect(CombatContext.Get(player).DamageBuff).toBe(1.25)
		moveTo(player, run.Markers.Checkpoint_Chamber.Position)
		advance(20.5)
		expect(boss.Immune).toBe(true)
		expect(CombatContext.Get(player).DamageBuff).toBe(1)
	end)

	it("respawns a solo Keeper after 10 seconds", function()
		FakeCharacters.Kill(player)
		expect(statuses[player].Delay).toBe(10)
		advance(10.5)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
	end)

	it("wipes on enrage and restarts the encounter with a fresh boss", function()
		advance(360 - clock + run.StartedAt + 5)
		expect(run.Status == "Wiped" or run.Status == "Active").toBe(true)
		advance(9)
		expect(run.Status).toBe("Active")
		expect(boss.Dead).toBe(true)
		local fresh = alive(run.Id, "boss")[1]
		expect(fresh ~= nil and fresh ~= boss).toBe(true)
		expect(FakeCharacters.IsAlive(player)).toBe(true)
		ActivityService.Leave(player)
		expect(run.Status).toBe("Closed")
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
		moveTo(leader, run.Markers.Zone_Chamber.Position)
		advance(0.5)
		local boss = alive(run.Id, "boss")[1]
		local healthScale = PowerMath.ActivityEnemyScale(495)
		expect(math.abs(boss.MaxHealth - 60000 * healthScale * 2 / 6) < 1).toBe(true)
	end)

	it("needs two plates held at once for two Keepers", function()
		local boss = alive(run.Id, "boss")[1]
		moveTo(leader, run.Map:FindFirstChild("Plate_1", true).Position)
		advance(4)
		expect(boss.Immune).toBe(true)
		moveTo(friend, run.Map:FindFirstChild("Plate_3", true).Position)
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
		expect(#alive(run.Id, "boss")).toBe(1)
	end)
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
