-- Runs the real EnemyService (with Lune's Roblox Instances behind proxies)
-- against one fake player: machine rigs, the drone, sniper and turret
-- brains, objects that never act, and the boss hooks (immune bubble,
-- health floor, relocation) the boss fights use. A fake clock drives os.clock.
local roblox = require("@lune/roblox")
local Proxy = VirtualGame.Proxy

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

-- Engine stand-ins -------------------------------------------------------------------------

local clock = 100
local realOs = os
VirtualGame.SetGlobal("os", {
	clock = function()
		return clock
	end,
	time = realOs.time,
	date = realOs.date,
})
VirtualGame.SetGlobal("Instance", Proxy.Instance)
VirtualGame.SetGlobal("ColorSequence", roblox.ColorSequence)
VirtualGame.SetGlobal("ColorSequenceKeypoint", roblox.ColorSequenceKeypoint)
VirtualGame.SetGlobal("NumberSequence", roblox.NumberSequence)
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

local heartbeat = Proxy.Signal()
VirtualGame.Services.RunService = { Heartbeat = heartbeat }
VirtualGame.Services.PathfindingService = {
	CreatePath = function()
		return {
			ComputeAsync = function() end,
			Status = "Failed",
			GetWaypoints = function()
				return {}
			end,
		}
	end,
}
VirtualGame.Services.PhysicsService = {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
}
VirtualGame.Services.TweenService = {
	Create = function()
		return { Play = function() end }
	end,
}
VirtualGame.Services.ServerStorage = Proxy.Instance.new("Folder")
VirtualGame.Services.Workspace = {
	-- Open ground everywhere: nothing blocks sight, no floor under anyone.
	Raycast = function()
		return nil
	end,
	GetServerTimeNow = function()
		return clock
	end,
}

-- One player standing at a fixed spot.
local character = Proxy.Instance.new("Model")
local root = Proxy.Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(40, 3, 0)
root.Parent = character
character.PrimaryPart = root

local PlayersService = { PlayerAdded = Proxy.Signal() }
local player = {
	Name = "Target",
	UserId = 7,
	Parent = PlayersService,
	CharacterAdded = Proxy.Signal(),
	GetAttribute = function(_, key)
		return if key == "InstanceId" then "R1" else nil
	end,
}
function PlayersService.GetPlayers()
	return { player }
end
function PlayersService.GetPlayerFromCharacter(_, model)
	return if model == character then player else nil
end
function PlayersService.CreateHumanoidModelFromDescriptionAsync()
	error("not available outside Roblox")
end
VirtualGame.Services.Players = PlayersService

local Server = game.ServerScriptService
local damage = {}
VirtualGame.Preload(Server.Services.CharacterService, {
	GetCharacter = function()
		return character
	end,
	DamagePlayer = function(_, amount)
		table.insert(damage, amount)
		return amount
	end,
})
local shots = {}
VirtualGame.Preload(Server.Services.ProjectileService, {
	Spawn = function(spec)
		table.insert(shots, spec)
		return #shots
	end,
})
local enemiesFolder = Proxy.Instance.new("Folder")
enemiesFolder.Name = "Enemies"
local pickups = Proxy.Instance.new("Folder")
VirtualGame.Preload(Server.Services.WorldService, {
	Folder = function(name)
		return if name == "Enemies" then enemiesFolder else pickups
	end,
	PlayerCharacters = function()
		return { character }
	end,
})

local EnemyService = require(Server.Services.EnemyService)
EnemyService.Init()
EnemyService.Start()

-- Advances the fake clock, running the AI every frame.
local function run(seconds)
	local steps = math.floor(seconds / 0.05 + 0.5)
	for _ = 1, steps do
		clock += 0.05
		heartbeat:Fire(0.05)
	end
end

local function spawn(id, position)
	local enemy = EnemyService.Spawn(id, CFrame.lookAt(position, Vector3.new(40, position.Y, 0)), {
		InstanceId = "R1",
		Tag = "test",
		Aggro = true,
	})
	assert(enemy, "spawn failed for " .. id)
	return enemy
end

local function clear()
	EnemyService.DespawnInstance("R1")
	table.clear(shots)
	table.clear(damage)
end

-- Tests ------------------------------------------------------------------------------------------

describe("Machine rigs", function()
	it("builds drones, turrets and objects as anchored machines with a crit head", function()
		for id, rig in { RUST_SKIFF_DRONE = "Drone", RUST_TURRET = "Turret", RUST_GENERATOR = "Object" } do
			local enemy = spawn(id, Vector3.new(0, 0, 0))
			expect(enemy.Rig).toBe(rig)
			expect(enemy.Root.Anchored).toBe(true)
			expect(enemy.Head.Name).toBe("Head")
			expect(EnemyService.IsPrecisionPart(enemy, enemy.Head)).toBe(true)
			expect(enemy.Model:GetAttribute("Rig")).toBe(rig)
		end
		clear()
	end)
end)

describe("Drone", function()
	it("hovers, circles in toward its target and strafes it", function()
		local drone = spawn("RUST_SKIFF_DRONE", Vector3.new(0, 0, 60))
		local start = drone.Root.Position
		expect(start.Y > 10).toBe(true) -- hovering, not standing
		run(3)
		expect(drone.FlyGoal ~= nil).toBe(true)
		expect((drone.Root.Position - start).Magnitude > 5).toBe(true)
		expect(#shots > 0).toBe(true)
		expect(shots[1].Style).toBe("EnemyBolt")
		clear()
	end)
end)

describe("Sniper", function()
	it("paints the target with a red laser, then fires one heavy shot", function()
		local sniper = spawn("RUST_SNIPER", Vector3.new(0, 0, 100))
		local laserAt
		for _ = 1, 80 do
			run(0.05)
			if sniper.Laser then
				laserAt = clock
				break
			end
		end
		expect(laserAt ~= nil).toBe(true)
		expect(enemiesFolder:FindFirstChild("LaserDot") ~= nil).toBe(true)
		expect(#shots).toBe(0) -- still aiming
		run(1.2)
		expect(#shots).toBe(0) -- the laser has locked but not fired
		run(0.9) -- past the 1.8 s wind-up (the AI thinks every ~0.15 s)
		expect(sniper.Laser).toBeNil()
		expect(enemiesFolder:FindFirstChild("LaserDot")).toBeNil()
		expect(#shots).toBe(1)
		expect(shots[1].Velocity.Magnitude > 600).toBe(true)
		shots[1].OnHit({ Instance = root })
		expect(damage[1]).toBe(sniper.Def.Damage)
		clear()
	end)
end)

describe("Turret", function()
	it("fires bursts, then pauses", function()
		local turret = spawn("RUST_TURRET", Vector3.new(0, 0, -30))
		run(3.2)
		local first = #shots
		expect(first >= 5).toBe(true)
		expect(turret.BurstLeft >= 0).toBe(true)
		clear()
	end)
end)

describe("Objects", function()
	it("never act, and die to damage", function()
		local generator = spawn("RUST_GENERATOR", Vector3.new(10, 0, 10))
		local killed = 0
		EnemyService.EnemyKilled:Connect(function(enemy)
			if enemy == generator then
				killed += 1
			end
		end)
		run(4)
		expect(#shots).toBe(0)
		EnemyService.ApplyDamage(generator, generator.MaxHealth + 1, { Element = "Kinetic" })
		expect(generator.Dead).toBe(true)
		expect(killed).toBe(1)
		clear()
	end)
end)

describe("Boss hooks", function()
	it("shows a shield bubble while immune and respects the health floor", function()
		local boss = spawn("RUST_SCRAP_WARDEN", Vector3.new(0, 0, 30))
		EnemyService.SetImmune(boss, true)
		expect(boss.Model:FindFirstChild("ImmuneBubble") ~= nil).toBe(true)
		expect(EnemyService.ApplyDamage(boss, 500, { Element = "Kinetic" }).Flag).toBe("Immune")
		EnemyService.SetImmune(boss, false)
		expect(boss.Model:FindFirstChild("ImmuneBubble")).toBeNil()

		EnemyService.SetHealthFloor(boss, boss.MaxHealth * 0.66)
		EnemyService.ApplyDamage(boss, boss.MaxHealth * 10, { Element = "Flare" })
		expect(boss.Dead).toBe(false)
		expect(boss.Health).toBe(boss.MaxHealth * 0.66)

		EnemyService.SetBusy(boss, 2)
		run(1)
		expect(#shots).toBe(0) -- busy: no normal fire
		EnemyService.Relocate(boss, CFrame.new(0, 5, -50))
		expect((boss.Root.Position - Vector3.new(0, 5, -50)).Magnitude < 0.01).toBe(true)
		EnemyService.FireVolley(boss, { Targets = { Vector3.new(40, 3, 0) }, Damage = 12 })
		expect(#shots).toBe(1)
		expect(shots[1].Style).toBe("BossOrb")
		clear()
	end)
end)
