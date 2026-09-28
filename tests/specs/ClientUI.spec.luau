-- Smoke test for the client screens: builds the HUD, Director, character
-- screen, loot screen, loading screen, mission intro, waypoint, kill feed
-- and music with Lune's real Roblox Instances (which reject unknown
-- properties and wrong value types), feeds them a starter save, weapon
-- state, an activity run and a loot award, and runs HUD frames.
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
-- Code that waits a frame (the intro's camera loop) yields for real.
renderStepped.Wait = function()
	task.wait()
end
local heartbeat = signal()
local bound = {}
local realCamera = roblox.Instance.new("Camera")
local projected = { roblox.Vector3.new(960, 540, 10), true }
local camera = setmetatable({
	ViewportSize = roblox.Vector2.new(1920, 1080),
	WorldToViewportPoint = function()
		return projected[1], projected[2]
	end,
}, { __index = proxyOf(realCamera) })
Proxy.Register(camera, realCamera)
local serverNow = 1000

VirtualGame.SetGlobal("Instance", ProxyInstance)
VirtualGame.SetGlobal("ColorSequence", roblox.ColorSequence)
VirtualGame.SetGlobal("ColorSequenceKeypoint", roblox.ColorSequenceKeypoint)
VirtualGame.SetGlobal("NumberSequence", roblox.NumberSequence)
VirtualGame.SetGlobal("NumberSequenceKeypoint", roblox.NumberSequenceKeypoint)
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
	Heartbeat = heartbeat,
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
		return {
			Play = function() end,
			Cancel = function() end,
			Completed = { Wait = function() end, Connect = function() end },
		}
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
	WaitForChild = function()
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
local CueController = require(Controllers.CueController)
local CameraController = require(Controllers.CameraController)
local LoadingController = require(Controllers.LoadingController)
local IntroController = require(Controllers.IntroController)
local MusicController = require(Controllers.MusicController)
local WaypointController = require(Controllers.WaypointController)
local KillFeedController = require(Controllers.KillFeedController)
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

-- The first TextLabel under `root` whose text contains `text`.
local function findText(root, text)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") and string.find(descendant.Text, text, 1, true) then
			return descendant
		end
	end
	return nil
end

local function waitFor(condition, seconds)
	local started = os.clock()
	while not condition() and os.clock() - started < seconds do
		task.wait()
	end
	return condition()
end

describe("Client screens", function()
	it("initialize and start", function()
		for _, controller in
			{
				DataController,
				ActivityController,
				LoadingController,
				CameraController,
				IntroController,
				WeaponController,
				MusicController,
				HudController,
				WaypointController,
				KillFeedController,
				DirectorController,
				InventoryController,
				LootController,
				CueController,
			}
		do
			controller.Init()
		end
		for _, controller in
			{
				ActivityController,
				LoadingController,
				CameraController,
				IntroController,
				WeaponController,
				MusicController,
				HudController,
				WaypointController,
				KillFeedController,
				DirectorController,
				InventoryController,
				LootController,
				CueController,
			}
		do
			controller.Start()
		end
		emit("DataSnapshot", profile)
		expect(DataController.GetData()).toBe(profile)
		for _, name in
			{ "HUD", "Director", "Inventory", "LootScreen", "LoadingScreen", "MissionIntro", "Waypoint", "KillFeed" }
		do
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
		runFolder:SetAttribute("BossThresholds", "0.66,0.33")
		runFolder:SetAttribute("ZoneLog", "The Approach=42;Outpost Courtyard=131")
		runFolder:SetAttribute("ZoneName", "Relay Terminal")
		runFolder:SetAttribute("ZoneStartedAt", 990)
		runFolder:SetAttribute("ZoneIndex", 3)
		runFolder:SetAttribute("ZoneCount", 4)
		frame()
		local debug = guiNamed("HUD"):FindFirstChild("ZoneDebug", true)
		expect(debug.Visible).toBe(true)
		expect(string.find(debug.Text, "Outpost Courtyard  2:11", 1, true) ~= nil).toBe(true)
		expect(string.find(debug.Text, "Relay Terminal  0:10", 1, true) ~= nil).toBe(true)
		expect(string.find(debug.Text, "Music:", 1, true) ~= nil).toBe(true)

		-- The waypoint: a diamond on screen, an arrow at the edge off screen.
		local waypoint = guiNamed("Waypoint"):FindFirstChildOfClass("Frame")
		expect(waypoint.Visible).toBe(true)
		expect(findText(waypoint, "0m") ~= nil).toBe(true)
		expect(findText(waypoint, "▲").Visible).toBe(false)
		projected[1], projected[2] = roblox.Vector3.new(-400, 300, -5), false
		frame()
		expect(findText(waypoint, "▲").Visible).toBe(true)
		local x, y = waypoint.Position.X.Offset, waypoint.Position.Y.Offset
		expect(x >= 0 and x <= 1920 and y >= 0 and y <= 1080).toBe(true)
		projected[1], projected[2] = roblox.Vector3.new(960, 540, 10), true

		-- Music follows the boss bar, then drops back to exploring.
		heartbeat:_fire(0.1)
		expect(MusicController.GetState()).toBe("Boss")
		runFolder:SetAttribute("BossActive", false)
		heartbeat:_fire(0.1)
		expect(MusicController.GetState()).toBe("Explore")
		runFolder:SetAttribute("BossActive", true)
		runFolder:SetAttribute("Status", "Complete")
		runFolder:SetAttribute("ReturnAt", 1012)
		frame()
		emit("PlayerStatus", { Alive = false, RespawnAt = 1005, Message = "Respawning" })
		frame()
		expect(UIState.IsDead()).toBe(true)
		emit("PlayerStatus", { Alive = true })
		frame()
	end)

	it("draws every mission cue without errors", function()
		local at = roblox.Vector3.new(5, 0, 5)
		for _, cue in
			{
				{ "Portal", at, 1 },
				{ "Dropship", at, 3 },
				{ "Telegraph", at, 14, 1.5 },
				{ "Shockwave", at, 14 },
				{ "SafeZone", at, 10, 6 },
				{ "Nova", at },
				{ "Charge", at, 1 },
				{ "Blink", at },
				{ "ShieldUp", at },
				{ "ShieldBreak", at },
				{ "GateOpen", at, "Door" },
				{ "Collapse", at, 3 },
				{ "BossIntro", at, "Orrek", "Warden" },
				{ "BossDeath", at, "Orrek" },
				{ "ChestDrop", at },
				{ "AmmoDrop", at },
			}
		do
			emit("WorldCue", table.unpack(cue))
		end
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
		expect(launch).toBe(5)
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

	it("turns the loot screen into the Mission Complete screen with the run summary", function()
		local item = ItemRoller.Roll("W_LAST_EMBER", 354, VirtualGame.Random.new(9), uid(), 0, "Random")
		emit("LootAwarded", {
			Title = "The Hollow Spire (Legend)",
			Screen = true,
			Awards = { { Item = item, Location = "Inventory", Reason = "Drop" } },
			Power = 470,
			HighestPower = 470,
			Summary = {
				Activity = "The Hollow Spire",
				Kind = "Nightfall",
				Elapsed = 452,
				Kills = 41,
				Deaths = 2,
				FireteamKills = 77,
				FireteamDeaths = 3,
				Medal = "Gold",
				Score = 51230,
			},
		})
		local screen = guiNamed("LootScreen")
		expect(screen.Enabled).toBe(true)
		expect(findText(screen, "NIGHTFALL COMPLETE") ~= nil).toBe(true)
		expect(findText(screen, "7:32") ~= nil).toBe(true)
		expect(findText(screen, "FIRETEAM KILLS") ~= nil).toBe(true)
		expect(findText(screen, "GOLD") ~= nil).toBe(true)
		expect(findText(screen, "51230") ~= nil).toBe(true)
		UIState.CloseMenu("Loot")
		-- A raid encounter chest has no summary.
		emit("LootAwarded", {
			Title = "Vault of Echoes: The Gate",
			Screen = true,
			Awards = {},
			Power = 470,
			HighestPower = 470,
		})
		expect(findText(screen, "VAULT OF ECHOES: THE GATE") ~= nil).toBe(true)
		expect(findText(screen, "FIRETEAM KILLS")).toBeNil()
		UIState.CloseMenu("Loot")
	end)

	it("lists kills, boss defeats, deaths and revives in the kill feed, newest last", function()
		emit("KillFeed", "Kill", "Tester", "Rustborn Scavenger", "Minor")
		emit("KillFeed", "Boss", "Friend", "Scrap Warden", "Boss")
		emit("KillFeed", "Death", "Laser", "Tester")
		emit("KillFeed", "Revive", "Friend", "Tester")
		emit("KillFeed", "Nonsense", 5, nil)
		local feed = guiNamed("KillFeed")
		local list = feed:FindFirstChildOfClass("Frame")
		local function lines()
			local count = 0
			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					count += 1
				end
			end
			return count
		end
		expect(lines()).toBe(4)
		expect(findText(feed, "SCRAP WARDEN") ~= nil).toBe(true)
		expect(findText(feed, "revived") ~= nil).toBe(true)
		for _ = 1, 5 do
			emit("KillFeed", "Kill", "Friend", "Concord Sentinel", "Major")
		end
		expect(lines()).toBe(6)
	end)

	it("covers a launch with the loading screen, then flies the intro camera", function()
		LoadingController.Show("First Light", "Frostreach", "FirstLight")
		local loading = guiNamed("LoadingScreen")
		expect(loading.Enabled).toBe(true)
		expect(findText(loading, "FIRST LIGHT") ~= nil).toBe(true)
		expect(findText(loading, "TIP") ~= nil).toBe(true)
		expect(findText(loading, "AssetIds.Images.Loading.FirstLight") ~= nil).toBe(true)

		runFolder:SetAttribute("Status", "Active")
		emit("ActivityState", {
			InActivity = true,
			RunId = "R2",
			ActivityId = "STORY_01",
			Name = "First Light",
			Type = "Story",
			Difficulty = nil,
			Power = 350,
			Map = "FirstLight",
			Modifiers = {},
			Scored = false,
			Destination = "Frostreach",
			StartedAt = serverNow,
			Intro = { Start = roblox.Vector3.new(0, 5, 0), Target = roblox.Vector3.new(0, 5, -140) },
		})
		expect(waitFor(function()
			return not LoadingController.IsShowing()
		end, 4)).toBe(true)
		expect(loading.Enabled).toBe(false)
		expect(waitFor(UIState.IsCinematic, 2)).toBe(true)
		frame()
		expect(guiNamed("HUD").Enabled).toBe(false)
		expect(guiNamed("MissionIntro").Enabled).toBe(true)
		expect(findText(guiNamed("MissionIntro"), "FROSTREACH") ~= nil).toBe(true)
		expect(UIState.InputBlocked()).toBe(true)
		-- Any key skips it and hands the camera and HUD back.
		game:GetService("UserInputService").InputBegan:_fire({
			UserInputType = Enum.UserInputType.Keyboard,
			KeyCode = Enum.KeyCode.Unknown,
		}, false)
		expect(waitFor(function()
			return not IntroController.IsPlaying()
		end, 2)).toBe(true)
		expect(UIState.IsCinematic()).toBe(false)
		frame()
		expect(guiNamed("HUD").Enabled).toBe(true)

		-- Leaving covers the trip back to the Spire.
		emit("ActivityState", { InActivity = false, Map = "Hub" })
		expect(LoadingController.IsShowing()).toBe(true)
		expect(findText(loading, "THE SPIRE") ~= nil).toBe(true)
	end)
end)
