-- Smoke test for the client screens: builds the HUD, Director, character
-- screen and loot screen with Lune's real Roblox Instances (which reject
-- unknown properties and wrong value types), feeds them a starter save,
-- weapon state, an activity run and a loot award, and runs a HUD frame.
local roblox = require("@lune/roblox")

-- Minimal engine stand-ins ----------------------------------------------------------

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end, Connected = true }
		end,
		Wait = function() end,
		_fire = function(...)
			for _, fn in handlers do
				fn(select(2, ...))
			end
		end,
		_handlers = handlers,
	}
end

local Proxy = VirtualGame.Proxy
local proxyOf = Proxy.Wrap
local ProxyInstance = Proxy.Instance

local playerGui = roblox.Instance.new("Folder")
playerGui.Name = "PlayerGui"
local attributes = { DebugAccess = true }
local localPlayer = {
	Name = "Tester",
	DisplayName = "Tester",
	UserId = 1,
	Character = nil,
	CharacterAdded = signal(),
	CharacterRemoving = signal(),
	WaitForChild = function(_, name)
		assert(name == "PlayerGui", name)
		return playerGui
	end,
	GetAttribute = function(_, name)
		return attributes[name]
	end,
	SetAttribute = function(_, name, value)
		attributes[name] = value
	end,
	GetAttributeChangedSignal = function()
		return signal()
	end,
}

local renderStepped = signal()
local bound = {}
local realCamera = roblox.Instance.new("Camera")
local camera = setmetatable({ ViewportSize = roblox.Vector2.new(1920, 1080) }, { __index = proxyOf(realCamera) })
Proxy.Register(camera, realCamera)
local serverNow = 1000

VirtualGame.SetGlobal("Instance", ProxyInstance)
VirtualGame.SetGlobal("ColorSequence", roblox.ColorSequence)
VirtualGame.SetGlobal("ColorSequenceKeypoint", roblox.ColorSequenceKeypoint)
VirtualGame.SetGlobal("NumberSequence", roblox.NumberSequence)
VirtualGame.SetGlobal("TweenInfo", {
	new = function()
		return {}
	end,
})
VirtualGame.SetGlobal("RaycastParams", {
	new = function()
		return {}
	end,
})
VirtualGame.Services.Players = {
	LocalPlayer = localPlayer,
	GetPlayers = function()
		return { localPlayer }
	end,
}
VirtualGame.Services.RunService = {
	RenderStepped = renderStepped,
	Heartbeat = signal(),
	BindToRenderStep = function(_, name, _priority, fn)
		bound[name] = fn
	end,
	IsStudio = function()
		return true
	end,
}
VirtualGame.Services.GuiService = { SelectedObject = nil }
VirtualGame.Services.UserInputService = {
	InputBegan = signal(),
	InputEnded = signal(),
	InputChanged = signal(),
	LastInputTypeChanged = signal(),
	TouchEnabled = false,
	MouseBehavior = nil,
	MouseIconEnabled = true,
	GetMouseDelta = function()
		return roblox.Vector2.zero
	end,
}
VirtualGame.Services.StarterGui = { SetCoreGuiEnabled = function() end }
VirtualGame.Services.TweenService = {
	Create = function()
		return { Play = function() end }
	end,
}
VirtualGame.Services.SoundService = roblox.Instance.new("Folder")
VirtualGame.Services.Lighting = proxyOf(roblox.Instance.new("Lighting"))
VirtualGame.Services.TextChatService = { ChatVersion = roblox.Enum.ChatVersion.TextChatService }
local realWorkspace = roblox.Instance.new("Folder")
local workspaceStub = setmetatable({
	CurrentCamera = camera,
	GetServerTimeNow = function()
		return serverNow
	end,
	Raycast = function()
		return nil
	end,
}, { __index = proxyOf(realWorkspace) })
Proxy.Register(workspaceStub, realWorkspace)
VirtualGame.Services.Workspace = workspaceStub

-- Fake network layer: records listeners, answers invokes.
local listeners = {}
local invokes = {}
local fakeNet = {
	On = function(name, handler)
		listeners[name] = listeners[name] or {}
		table.insert(listeners[name], handler)
		return { Disconnect = function() end }
	end,
	Fire = function() end,
	Invoke = function(name, ...)
		table.insert(invokes, name)
		if name == "DirectorQuery" then
			return { Runs = { { RunId = "R9", ActivityId = "STORY_01", Players = { "Friend" }, MaxPlayers = 3 } } }
		end
		return true, nil
	end,
}
local function emit(name, ...)
	for _, handler in listeners[name] or {} do
		handler(...)
	end
end

-- LiveRuns folder the ActivityController waits for.
local runFolder = roblox.Instance.new("Folder")
runFolder.Name = "R1"
local liveRuns = {
	WaitForChild = function(_, name)
		assert(name == "R1", name)
		return runFolder
	end,
}
rawget(game.ReplicatedStorage, "_children").LiveRuns = liveRuns

local Client = game.StarterPlayer.StarterPlayerScripts
VirtualGame.Preload(Client.Net.ClientNet, fakeNet)

local Shared = game.ReplicatedStorage.Shared
local ProfileTemplate = require(game.ServerScriptService.Data.ProfileTemplate)
local UIState = require(Client.UI.UIState)
local Controllers = Client.Controllers
local DataController = require(Controllers.DataController)
local ActivityController = require(Controllers.ActivityController)
local WeaponController = require(Controllers.WeaponController)
local HudController = require(Controllers.HudController)
local DirectorController = require(Controllers.DirectorController)
local InventoryController = require(Controllers.InventoryController)
local LootController = require(Controllers.LootController)
local ItemRoller = require(Shared.Items.ItemRoller)

local counter = 0
local function uid()
	counter += 1
	return "uid-" .. counter
end
local profile = ProfileTemplate.CreateNew(0, uid, VirtualGame.Random.new(4))
-- A few extra items so the character screen has lists to draw.
for _, defId in { "W_TINDER_NINE", "W_FRONTIER_STANDARD", "A_FRONTIER_HELMET" } do
	local item = ItemRoller.Roll(defId, 353, VirtualGame.Random.new(5), uid(), 0, "Random")
	item.Location = "Inventory"
	profile.Items[item.Uid] = item
end

local function frame()
	for _, fn in renderStepped._handlers do
		fn(1 / 60)
	end
	for _, fn in bound do
		fn(1 / 60)
	end
end

local function guiNamed(name)
	for _, child in playerGui:GetChildren() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

describe("Client screens", function()
	it("initialize and start", function()
		for _, controller in
			{
				DataController,
				ActivityController,
				WeaponController,
				HudController,
				DirectorController,
				InventoryController,
				LootController,
			}
		do
			controller.Init()
		end
		for _, controller in
			{
				ActivityController,
				WeaponController,
				HudController,
				DirectorController,
				InventoryController,
				LootController,
			}
		do
			controller.Start()
		end
		emit("DataSnapshot", profile)
		expect(DataController.GetData()).toBe(profile)
		for _, name in { "HUD", "Director", "Inventory", "LootScreen" } do
			expect(guiNamed(name) ~= nil).toBe(true)
		end
	end)

	it("shows weapons, ammo and vitals on the HUD", function()
		emit("WeaponState", {
			Active = "Kinetic",
			Slots = {
				Kinetic = { Uid = profile.Equipped.Kinetic, Mag = 36 },
				Energy = { Uid = profile.Equipped.Energy, Mag = 12 },
				Heavy = { Uid = profile.Equipped.Heavy, Mag = 1, Reserve = 2 },
			},
		})
		expect(WeaponController.GetStats("Kinetic").Rpm).toBe(600)
		emit("CombatFeedback", roblox.Vector3.zero, 25, true, nil)
		emit("Notify", "Hello", "Success")
		frame()
		local hud = guiNamed("HUD")
		local found = false
		for _, descendant in hud:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant.Text == "36" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("draws an activity run with a boss, phase and waypoint", function()
		emit("ActivityState", {
			InActivity = true,
			RunId = "R1",
			ActivityId = "RAID_VAULT_OF_ECHOES",
			Name = "Vault of Echoes",
			Type = "Raid",
			Power = 495,
			Map = "Hub",
			Modifiers = { { Name = "Ironhide", Description = "Enemies have 30% more health." } },
			Scored = true,
		})
		expect(ActivityController.GetFolder()).toBe(runFolder)
		for name, value in
			{
				Status = "Active",
				StartedAt = 900,
				Score = 120,
				ObjectiveText = "Defeat Harrowmaw",
				ObjectiveCount = "3/12",
				ObjectiveProgress = 0.25,
				BossActive = true,
				BossName = "Harrowmaw",
				BossTitle = "Warden",
				BossHealth = 500,
				BossMaxHealth = 1000,
				BossShield = 0,
				BossMaxShield = 0,
				BossImmune = true,
				Phase = "Hold an echo plate (0/1)",
				PhaseEndsAt = 1010,
				Charge = 0.5,
				EnrageAt = 1300,
				HasWaypoint = true,
				Waypoint = roblox.Vector3.new(10, 0, 10),
			}
		do
			runFolder:SetAttribute(name, value)
		end
		frame()
		runFolder:SetAttribute("Status", "Complete")
		runFolder:SetAttribute("ReturnAt", 1012)
		frame()
		emit("PlayerStatus", { Alive = false, RespawnAt = 1005, Message = "Respawning" })
		frame()
		expect(UIState.IsDead()).toBe(true)
		emit("PlayerStatus", { Alive = true })
		frame()
	end)

	it("opens the Director with every playable activity", function()
		UIState.OpenMenu("Director")
		task.wait(0.05)
		local director = guiNamed("Director")
		expect(director.Enabled).toBe(true)
		local launch = 0
		for _, descendant in director:GetDescendants() do
			if descendant:IsA("TextButton") and (descendant.Text == "LAUNCH" or descendant.Text:find("LOCKED")) then
				launch += 1
			end
		end
		expect(launch).toBe(3)
		UIState.CloseMenu("Director")
	end)

	it("opens the inventory with all eight slots, details, vault and postmaster", function()
		UIState.OpenMenu("Inventory")
		local screen = guiNamed("Inventory")
		expect(screen.Enabled).toBe(true)
		local headers = 0
		for _, descendant in screen:GetDescendants() do
			if descendant:IsA("TextLabel") and (descendant.Text == "KINETIC" or descendant.Text == "CLASS ITEM") then
				headers += 1
			end
		end
		expect(headers).toBe(2)
		-- A new drop shows its NEW dot; the detail panel renders stat bars.
		local spare
		for uid, item in profile.Items do
			if item.DefId == "W_TINDER_NINE" then
				spare = item
			end
		end
		spare.Seen = false
		InventoryController.Refresh()
		for _, tab in { "Vault", "Postmaster", "Infuse", "Character" } do
			InventoryController.Open(tab)
			InventoryController.Refresh()
		end
		UIState.CloseMenu("Inventory")
	end)

	it("shows the loot screen and toasts", function()
		local item = ItemRoller.Roll("W_LAST_EMBER", 354, VirtualGame.Random.new(8), uid(), 0, "Random")
		emit("LootAwarded", {
			Title = "First Light",
			Screen = true,
			Awards = { { Item = item, Location = "Inventory", Reason = "Pinnacle" } },
			Power = 350,
			HighestPower = 351,
		})
		expect(guiNamed("LootScreen").Enabled).toBe(true)
		UIState.CloseMenu("Loot")
		emit("LootAwarded", { Screen = false, Awards = { { Item = item, Location = "Postmaster", Reason = "Drop" } } })
		frame()
	end)
end)
