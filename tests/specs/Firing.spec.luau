-- WeaponService firing modes and exotic hooks against a fake world.
local roblox = require("@lune/roblox")
local realTask = require("@lune/task")
local Proxy = VirtualGame.Proxy
VirtualGame.SetGlobal("Instance", Proxy.Instance)
VirtualGame.SetGlobal("RaycastParams", {
	new = function()
		return {}
	end,
})

local Shared = game.ReplicatedStorage.Shared
local Server = game.ServerScriptService
local ItemRoller = require(Shared.Items.ItemRoller)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local Vector3 = roblox.Vector3

local counter = 0
local function uid()
	counter += 1
	return "uid-" .. counter
end

local data = ProfileTemplate.CreateNew(0, uid, VirtualGame.Random.new(5))
local attributes = { WeaponsDrawn = true }
local player = {
	Name = "Shooter",
	UserId = 1,
	GetAttribute = function(_, key)
		return attributes[key]
	end,
	GetAttributeChangedSignal = function()
		return Proxy.Signal()
	end,
}

local function fakePart(name, position)
	return {
		Name = name,
		Position = position,
		CFrame = roblox.CFrame.new(position),
		IsA = function(_, className)
			return className == "BasePart"
		end,
	}
end
local head = fakePart("Head", Vector3.new(0, 5, 0))
local root = fakePart("HumanoidRootPart", Vector3.new(0, 3, 0))
local character = {
	FindFirstChild = function(_, name)
		return if name == "Head" then head elseif name == "HumanoidRootPart" then root else nil
	end,
}

VirtualGame.Services.Players = {
	GetPlayers = function()
		return { player }
	end,
	PlayerAdded = Proxy.Signal(),
	PlayerRemoving = Proxy.Signal(),
}
VirtualGame.Services.ServerStorage = { FindFirstChild = function() end }
local enemyPart = fakePart("Torso", Vector3.new(0, 5, -30))
local raycasts = 0
VirtualGame.Services.Workspace = {
	Raycast = function(_, origin, direction)
		raycasts += 1
		return { Instance = enemyPart, Position = origin + direction.Unit * 30 }
	end,
}

local handlers = {}
VirtualGame.Preload(Server.Services.NetService, {
	OnEvent = function(name, _checks, handler)
		handlers[name] = handler
	end,
	FireClient = function() end,
	Flag = function() end,
})
VirtualGame.Preload(Server.Services.DataService, {
	GetData = function()
		return data
	end,
})
VirtualGame.Preload(Server.Services.CharacterService, {
	CharacterSpawned = Proxy.Signal(),
	GetCharacter = function()
		return character
	end,
})
local enemy = { Root = fakePart("Root", enemyPart.Position), Dead = false }
local log = { Hits = 0, Explosions = 0, Melee = 0, Projectiles = 0 }
VirtualGame.Preload(Server.Services.CombatService, {
	HitscanHit = function()
		log.Hits += 1
		return enemy, { Killed = false }
	end,
	ExplodeAt = function()
		log.Explosions += 1
	end,
	Explode = function() end,
	Melee = function()
		log.Melee += 1
		return 1
	end,
	Chain = function() end,
	Singularity = function() end,
	Effect = function() end,
	Nearby = function()
		return {}
	end,
})
VirtualGame.Preload(Server.Services.EnemyService, {
	IsPrecisionPart = function()
		return false
	end,
})
VirtualGame.Preload(Server.Services.ProjectileService, {
	Spawn = function(spec)
		log.Projectiles += 1
		log.LastGravity = spec.Gravity
	end,
})
VirtualGame.Preload(Server.Services.WorldService, {
	PlayerCharacters = function()
		return {}
	end,
	Folder = function()
		return Proxy.Instance.new("Folder")
	end,
})

local WeaponService = require(Server.Services.WeaponService)
WeaponService.Init()

local function equip(slot, defId)
	local item = ItemRoller.Roll(defId, 360, VirtualGame.Random.new(counter + 3), uid(), 0, "Base")
	item.Location = "Inventory"
	data.Items[item.Uid] = item
	data.Equipped[slot] = item.Uid
	WeaponService.RefreshLoadout(player)
	handlers.WeaponSwitch(player, slot)
	realTask.wait(1) -- swap time
	return item
end

local function fire(slot)
	handlers.WeaponFire(player, slot, Vector3.new(0, 5, -30), 1)
end

local function reset()
	log.Hits, log.Explosions, log.Melee, log.Projectiles = 0, 0, 0, 0
end

describe("Firing modes", function()
	it("fires a cone of pellets from a shotgun", function()
		equip("Energy", "W_DOORKICKER")
		reset()
		fire("Energy")
		expect(log.Hits).toBe(12)
	end)

	it("fires three rounds per pulse rifle burst", function()
		equip("Kinetic", "W_CADENCE_OF_IRON")
		reset()
		local before = WeaponService.GetActiveStats(player).Magazine
		fire("Kinetic")
		expect(log.Hits).toBe(3)
		local _ = before
	end)

	it("lofts grenades with gravity and flies rockets straight", function()
		equip("Heavy", "W_MOTH_AND_EMBER")
		reset()
		fire("Heavy")
		expect(log.Projectiles).toBe(1)
		expect(log.LastGravity > 0).toBe(true)
	end)

	it("swings swords instead of shooting", function()
		equip("Heavy", "W_GROUNDSKEEPER")
		reset()
		fire("Heavy")
		expect(log.Melee).toBe(1)
		expect(log.Hits).toBe(0)
	end)

	it("won't fire while weapons are holstered in the hub", function()
		equip("Energy", "W_DOORKICKER")
		attributes.WeaponsDrawn = false
		reset()
		fire("Energy")
		expect(log.Hits).toBe(0)
		attributes.WeaponsDrawn = true
	end)

	it("Widow's Tally detonates on every sixth consecutive hit", function()
		equip("Kinetic", "W_WIDOWS_TALLY")
		reset()
		local interval = WeaponService.GetActiveStats(player).FireInterval
		for _ = 1, 6 do
			fire("Kinetic")
			realTask.wait(interval + 0.02)
		end
		expect(log.Hits).toBe(6)
		expect(log.Explosions).toBe(1)
	end)
end)
