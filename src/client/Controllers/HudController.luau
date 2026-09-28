--!strict
--[[
	HudController
	The in-game HUD:
	  * crosshair that widens with spread, and hit markers (white hit,
	    yellow precision, red kill)
	  * weapon panel: name in rarity color, element, ammo (infinite primary,
	    counted heavy), the three slots and a reload bar
	  * shield (blue) and health bars, character power
	  * objective tracker, run timer and score, active modifiers
	  * boss health bar, raid phase banner and enrage timer
	  * waypoint marker for travel/defend objectives
	  * death screen (grey) with the respawn countdown or revive message
	  * toast notifications and a key hint line
	Roblox's backpack and health bar are hidden (no Tools are used).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ElementConfig = require(Config:WaitForChild("ElementConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local PowerMath = require(Shared:WaitForChild("Power"):WaitForChild("PowerMath"))
local MissionRules = require(Shared:WaitForChild("Activities"):WaitForChild("MissionRules"))
local ActivityConfig = require(Config:WaitForChild("ActivityConfig"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local ActivityController = require(script.Parent.ActivityController)
local DataController = require(script.Parent.DataController)
local WeaponController = require(script.Parent.WeaponController)

local HudController = {}

local player = Players.LocalPlayer
local SLOT_KEYS = { Kinetic = "1", Energy = "2", Heavy = "3" }
local SLOTS = { "Kinetic", "Energy", "Heavy" }
local SHIELD_COLOR = Color3.fromRGB(110, 200, 255)
local HEALTH_COLOR = Color3.fromRGB(235, 240, 245)
local LOW_HEALTH_COLOR = Color3.fromRGB(255, 90, 80)
local BOSS_COLOR = Color3.fromRGB(245, 200, 60)
local MEDAL_COLORS: { [string]: Color3 } = {
	Gold = Color3.fromRGB(255, 205, 70),
	Silver = Color3.fromRGB(210, 220, 230),
	Bronze = Color3.fromRGB(215, 140, 80),
}

type Refs = {
	Gui: ScreenGui,
	Crosshair: Frame,
	Lines: { Frame },
	WeaponPanel: Frame,
	Scope: Frame,
	Charge: Frame,
	HitMarker: Frame,
	WeaponName: TextLabel,
	WeaponElement: TextLabel,
	Ammo: TextLabel,
	Reserve: TextLabel,
	ReloadBar: Frame,
	ReloadFill: Frame,
	SlotLabels: { [string]: TextLabel },
	ShieldFill: Frame,
	HealthFill: Frame,
	PowerLabel: TextLabel,
	Tracker: Frame,
	TrackerTitle: TextLabel,
	TrackerObjective: TextLabel,
	TrackerProgress: Frame,
	TrackerProgressFill: Frame,
	TrackerExtra: TextLabel,
	BossFrame: Frame,
	BossName: TextLabel,
	BossHealthFill: Frame,
	BossShieldFill: Frame,
	BossTag: TextLabel,
	BossTicks: Frame,
	Phase: TextLabel,
	ZoneDebug: TextLabel,
	ChargeBar: Frame,
	ChargeFill: Frame,
	Banner: TextLabel,
	Death: Frame,
	DeathTitle: TextLabel,
	DeathMessage: TextLabel,
	Toasts: Frame,
}

local refs: Refs
local hitMarkerUntil = 0
local deathStatus: { Alive: boolean, RespawnAt: number?, Message: string } = { Alive = true, Message = "" }
local grey: ColorCorrectionEffect? = nil
local waypointPart: Part? = nil
local waypointLabel: TextLabel? = nil
local shownThresholds = ""
local IS_STUDIO = RunService:IsStudio()

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function bar(parent: Instance, props: { [string]: any }, fillColor: Color3): (Frame, Frame)
	local back = UI.Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 14, 20),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, parent) :: Frame
	for key, value in props do
		(back :: any)[key] = value
	end
	UI.Corner(back, 3)
	local fill = UI.Make("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, back) :: Frame
	UI.Corner(fill, 3)
	return back, fill
end

-- Building ------------------------------------------------------------------------------

local function build()
	local gui = UI.Screen("HUD", 5)

	-- Crosshair: four lines around the center plus a dot.
	local crosshair = UI.Make("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, crosshair)
	local lines: { Frame } = {}
	for index = 1, 4 do
		local vertical = index <= 2
		local line = UI.Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if vertical then UDim2.fromOffset(2, 9) else UDim2.fromOffset(9, 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, crosshair) :: Frame
		UI.Stroke(line, Color3.new(0, 0, 0), 1, 0.6)
		table.insert(lines, line)
	end

	-- Hit marker: an X of four short diagonal lines.
	local hitMarker = UI.Make("Frame", {
		Name = "HitMarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	for index = 0, 3 do
		local angle = 45 + index * 90
		local offset = Vector2.new(math.cos(math.rad(angle)), math.sin(math.rad(angle))) * 9
		UI.Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, offset.X, 0.5, offset.Y),
			Size = UDim2.fromOffset(8, 2),
			Rotation = angle,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, hitMarker)
	end

	-- Sniper scope: a clear circle in a black vignette (a huge stroke on a
	-- round frame), with fine cross lines.
	local scope = UI.Make("Frame", {
		Name = "Scope",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	UI.Make("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, scope)
	UI.Corner(scope, 2000)
	UI.Make("UIStroke", { Thickness = 2500, Color = Color3.new(0, 0, 0), Transparency = 0.05 }, scope)
	for _, vertical in { true, false } do
		UI.Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, scope)
	end
	local charge = UI.Make("Frame", {
		Name = "Charge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 26),
		Size = UDim2.fromOffset(70, 5),
		BackgroundColor3 = Color3.fromRGB(20, 24, 32),
		BorderSizePixel = 0,
		Visible = false,
	}, gui) :: Frame
	UI.Make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
	}, charge)

	-- Weapon panel (bottom right).
	local weapon = UI.Make("Frame", {
		Name = "Weapon",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local weaponName = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 0),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
	}, weapon)
	local weaponElement = UI.Label({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 22),
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.6,
	}, weapon)
	local ammo = UI.Label({
		Size = UDim2.new(0.6, 0, 0, 44),
		Position = UDim2.new(0.4, 0, 0, 38),
		Font = Theme.Fonts.Title,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
	}, weapon)
	local reserve = UI.Label({
		Size = UDim2.new(0.4, -10, 0, 20),
		Position = UDim2.fromOffset(0, 58),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.6,
	}, weapon)
	local reloadBar, reloadFill = bar(weapon, {
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.fromOffset(0, 86),
		Visible = false,
	}, Theme.Colors.Accent)
	local slotLabels: { [string]: TextLabel } = {}
	for index, slot in SLOTS do
		slotLabels[slot] = UI.Label({
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 92 + (index - 1) * 19),
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Right,
			RichText = true,
			TextStrokeTransparency = 0.6,
		}, weapon)
	end

	-- Shield/health (bottom center) and power.
	local vitals = UI.Make("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(340, 40),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local _, shieldFill =
		bar(vitals, { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 12) }, SHIELD_COLOR)
	local _, healthFill =
		bar(vitals, { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, 23) }, HEALTH_COLOR)
	local powerLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, -2),
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Power,
		TextStrokeTransparency = 0.6,
	}, vitals)

	-- Objective tracker (left).
	local tracker = UI.Make("Frame", {
		Name = "Tracker",
		Position = UDim2.new(0, 24, 0.3, 0),
		Size = UDim2.fromOffset(320, 150),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	local trackerTitle = UI.Label({
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = Theme.Colors.Accent,
		TextStrokeTransparency = 0.5,
	}, tracker)
	local trackerObjective = UI.Label({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 20),
		TextSize = 16,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 0.5,
	}, tracker)
	local trackerProgress, trackerProgressFill = bar(tracker, {
		Size = UDim2.new(0.8, 0, 0, 5),
		Position = UDim2.fromOffset(0, 58),
	}, Theme.Colors.Accent)
	local trackerExtra = UI.Label({
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 68),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 0.6,
	}, tracker)

	-- Studio only: how long each zone took (tune missions to 5-10 minutes).
	local zoneDebug = UI.Label({
		Name = "ZoneDebug",
		Position = UDim2.new(0, 24, 0.3, 170),
		Size = UDim2.fromOffset(300, 150),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Color3.fromRGB(150, 255, 170),
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextStrokeTransparency = 0.5,
		Visible = false,
	}, gui)

	-- Boss bar (top center).
	local bossFrame = UI.Make("Frame", {
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.new(0.62, 0, 0, 66),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	local bossName = UI.Label({
		Size = UDim2.new(1, 0, 0, 28),
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		RichText = true,
	}, bossFrame)
	local bossBack, bossHealthFill = bar(bossFrame, {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 32),
	}, BOSS_COLOR)
	-- Tick marks at the boss's immune thresholds (BossThresholds attribute).
	local bossTicks = UI.Make("Frame", {
		Name = "Ticks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, bossBack) :: Frame
	local bossShieldFill = UI.Make("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 140, 60),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 4),
		Position = UDim2.new(0, 0, 1, 2),
	}, bossBack) :: Frame
	local bossTag = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Warning,
		TextStrokeTransparency = 0.4,
	}, bossFrame)

	-- Raid phase banner and plate charge.
	local phase = UI.Label({
		Name = "Phase",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.new(0.6, 0, 0, 24),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(140, 235, 255),
		TextStrokeTransparency = 0.3,
		Visible = false,
	}, gui)
	local chargeBar, chargeFill = bar(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.fromOffset(260, 6),
		Visible = false,
	}, Color3.fromRGB(140, 235, 255))

	-- Big center banner (activity complete, wipes).
	local banner = UI.Label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.8, 0, 0, 60),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		TextWrapped = true,
		RichText = true,
		Visible = false,
	}, gui)

	-- Death screen.
	local death = UI.Make("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BackgroundTransparency = 0.55,
		Visible = false,
		ZIndex = 20,
	}, gui) :: Frame
	local deathTitle = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0, 50),
		Font = Theme.Fonts.Title,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "YOU DIED",
		TextColor3 = LOW_HEALTH_COLOR,
		ZIndex = 21,
	}, death)
	local deathMessage = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21,
	}, death)

	-- Toasts (top center, newest at the bottom).
	local toasts = UI.Make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(440, 200),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	UI.Make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, toasts)

	-- Key hints (bottom left).
	UI.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(420, 16),
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.7,
		Text = "[M] Director   [Tab/I] Inventory   [1/2/3] Weapons   [R] Reload   [RMB] Aim",
	}, gui)

	refs = {
		Gui = gui,
		Crosshair = crosshair,
		Lines = lines,
		WeaponPanel = weapon,
		Scope = scope,
		Charge = charge,
		HitMarker = hitMarker,
		WeaponName = weaponName,
		WeaponElement = weaponElement,
		Ammo = ammo,
		Reserve = reserve,
		ReloadBar = reloadBar,
		ReloadFill = reloadFill,
		SlotLabels = slotLabels,
		ShieldFill = shieldFill,
		HealthFill = healthFill,
		PowerLabel = powerLabel,
		Tracker = tracker,
		TrackerTitle = trackerTitle,
		TrackerObjective = trackerObjective,
		TrackerProgress = trackerProgress,
		TrackerProgressFill = trackerProgressFill,
		TrackerExtra = trackerExtra,
		BossFrame = bossFrame,
		BossName = bossName,
		BossHealthFill = bossHealthFill,
		BossShieldFill = bossShieldFill,
		BossTag = bossTag,
		BossTicks = bossTicks,
		Phase = phase,
		ZoneDebug = zoneDebug,
		ChargeBar = chargeBar,
		ChargeFill = chargeFill,
		Banner = banner,
		Death = death,
		DeathTitle = deathTitle,
		DeathMessage = deathMessage,
		Toasts = toasts,
	}
end

-- Location name ---------------------------------------------------------------------------

local locationToken = 0

-- Big area name on entry ("THE BAZAAR"), fading out after a few seconds.
function HudController.ShowLocation(title: string, subtitle: string?)
	if refs == nil then
		return
	end
	locationToken += 1
	local token = locationToken
	local gui = refs.Gui
	local existing = gui:FindFirstChild("Location")
	if existing then
		existing:Destroy()
	end
	local frame = UI.Make("Frame", {
		Name = "Location",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 36, 0.14, 0),
		Size = UDim2.fromOffset(520, 70),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local titleLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		Text = string.upper(title),
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
	}, frame)
	local line = UI.Make("Frame", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
	}, frame) :: Frame
	local subtitleLabel = UI.Label({
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		Text = subtitle or "",
		TextStrokeTransparency = 0.7,
		TextTransparency = 1,
	}, frame)
	local fadeIn = TweenInfo.new(0.6)
	TweenService:Create(titleLabel, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLabel, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(line, TweenInfo.new(0.8), { Size = UDim2.fromOffset(260, 2) }):Play()
	task.delay(3.5, function()
		if token ~= locationToken or frame.Parent == nil then
			return
		end
		local fadeOut = TweenInfo.new(1)
		TweenService:Create(titleLabel, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subtitleLabel, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(line, fadeOut, { BackgroundTransparency = 1 }):Play()
		task.wait(1.1)
		frame:Destroy()
	end)
end

-- Toasts ----------------------------------------------------------------------------------

local toastOrder = 0
local TOAST_COLORS: { [string]: Color3 } = {
	Info = Theme.Colors.Info,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Error = Theme.Colors.Error,
}

function HudController.Toast(text: string, kind: string?, color: Color3?)
	if refs == nil then
		return
	end
	toastOrder += 1
	local label = UI.Label({
		Size = UDim2.fromOffset(440, 26),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.25,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 15,
		RichText = true,
		Text = text,
		TextColor3 = color or TOAST_COLORS[kind or "Info"] or Theme.Colors.Text,
		LayoutOrder = toastOrder,
	}, refs.Toasts)
	UI.Corner(label, 4)
	local children = refs.Toasts:GetChildren()
	local labels = 0
	for _, child in children do
		if child:IsA("TextLabel") then
			labels += 1
		end
	end
	if labels > 6 then
		for _, child in children do
			if child:IsA("TextLabel") and child ~= label then
				child:Destroy()
				break
			end
		end
	end
	task.delay(4, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.5)
			label:Destroy()
		end
	end)
end

-- Per-frame updates -----------------------------------------------------------------------

local function updateCrosshair()
	local camera = Workspace.CurrentCamera
	local spread = WeaponController.GetSpread()
	local half = camera.ViewportSize.Y / 2
	local pixels = math.tan(math.rad(spread)) / math.tan(math.rad(camera.FieldOfView / 2)) * half
	local gap = math.clamp(pixels, 4, 80) + 4
	local offsets = { Vector2.new(0, -gap), Vector2.new(0, gap), Vector2.new(-gap, 0), Vector2.new(gap, 0) }
	for index, line in refs.Lines do
		line.Position = UDim2.fromOffset(offsets[index].X, offsets[index].Y)
	end
	refs.Crosshair.Visible = not UIState.InputBlocked() and WeaponController.IsDrawn()
	local activeStats = WeaponController.GetStats(WeaponController.GetActiveSlot())
	refs.Scope.Visible = refs.Crosshair.Visible
		and WeaponController.IsAiming()
		and activeStats ~= nil
		and activeStats.Type == "SniperRifle"
	local chargeLevel = WeaponController.GetCharge()
	refs.Charge.Visible = chargeLevel ~= nil
	if chargeLevel then
		(refs.Charge:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(chargeLevel, 1)
	end
	refs.HitMarker.Visible = os.clock() < hitMarkerUntil
end

local function updateWeapon()
	refs.WeaponPanel.Visible = WeaponController.IsDrawn()
	local slot = WeaponController.GetActiveSlot()
	local slots = WeaponController.GetSlots()
	local info = slots[slot]
	local stats = WeaponController.GetStats(slot)
	if info and stats then
		local rarity = RarityConfig.Tiers[stats.Rarity]
		local element = ElementConfig.Elements[stats.Element]
		refs.WeaponName.Text = stats.Name
		refs.WeaponName.TextColor3 = if rarity then rarity.Color else Theme.Colors.Text
		refs.WeaponElement.Text = `{if element then element.DisplayName else stats.Element}  ·  {stats.Type}`
		refs.WeaponElement.TextColor3 = if element then element.Color else Theme.Colors.TextDim
		refs.Ammo.Text = tostring(info.Mag)
		refs.Ammo.TextColor3 = if info.Mag <= math.max(1, stats.Magazine // 5)
			then LOW_HEALTH_COLOR
			else Theme.Colors.Text
		refs.Reserve.Text = if info.Reserve == nil then "∞" else tostring(info.Reserve)
	else
		refs.WeaponName.Text = ""
		refs.WeaponElement.Text = ""
		refs.Ammo.Text = ""
		refs.Reserve.Text = ""
	end
	local reload = WeaponController.GetReloadProgress()
	refs.ReloadBar.Visible = reload ~= nil
	if reload then
		refs.ReloadFill.Size = UDim2.fromScale(reload, 1)
	end
	for _, key in SLOTS do
		local label = refs.SlotLabels[key]
		local slotStats = WeaponController.GetStats(key)
		local slotInfo = slots[key]
		if slotStats and slotInfo then
			local rarity = RarityConfig.Tiers[slotStats.Rarity]
			local name = UI.Colored(slotStats.Name, if rarity then rarity.Color else Theme.Colors.Text)
			local ammoText = if slotInfo.Reserve ~= nil then `  {slotInfo.Mag}/{slotInfo.Reserve}` else ""
			label.Text = `{name}{ammoText}  [{SLOT_KEYS[key]}]`
			label.TextTransparency = if key == slot then 0 else 0.45
		else
			label.Text = ""
		end
	end
end

local function updateVitals()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if character and humanoid then
		local shield = tonumber(character:GetAttribute("Shield")) or 0
		local maxShield = tonumber(character:GetAttribute("MaxShield")) or 1
		refs.ShieldFill.Size = UDim2.fromScale(math.clamp(shield / math.max(1, maxShield), 0, 1), 1)
		local fraction = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		refs.HealthFill.Size = UDim2.fromScale(fraction, 1)
		refs.HealthFill.BackgroundColor3 = if fraction < 0.35 then LOW_HEALTH_COLOR else HEALTH_COLOR
	end
	local data = DataController.GetData()
	if data then
		local power = PowerMath.CharacterPower(data.Items, data.Equipped)
		local activity = ActivityController.Get()
		local text = `✦ {power}`
		if activity.InActivity and activity.Power then
			local color = if power < activity.Power then Theme.Colors.Error else Theme.Colors.Success
			text ..= `   <font color="{UI.Hex(color)}">(recommended {activity.Power})</font>`
		end
		refs.PowerLabel.RichText = true
		refs.PowerLabel.Text = text
	end
end

local function updateActivity()
	local info = ActivityController.Get()
	local folder = ActivityController.GetFolder()
	if not info.InActivity or folder == nil then
		refs.Tracker.Visible = false
		refs.BossFrame.Visible = false
		refs.ZoneDebug.Visible = false
		refs.Phase.Visible = false
		refs.ChargeBar.Visible = false
		refs.Banner.Visible = false
		if waypointPart then
			waypointPart.Parent = nil
		end
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	local attr = function(name: string): any
		return folder:GetAttribute(name)
	end

	-- Tracker.
	refs.Tracker.Visible = true
	local title = string.upper(info.Name or "")
	if info.Difficulty then
		title ..= `  ·  {string.upper(info.Difficulty)}`
	end
	refs.TrackerTitle.Text = title
	local count = attr("ObjectiveCount")
	local objectiveText = tostring(attr("ObjectiveText") or "")
	if type(count) == "string" and count ~= "" then
		objectiveText ..= `  ({count})`
	end
	refs.TrackerObjective.Text = objectiveText
	local progress = tonumber(attr("ObjectiveProgress")) or -1
	refs.TrackerProgress.Visible = progress >= 0
	refs.TrackerProgressFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)

	local extra: { string } = {}
	local status = attr("Status")
	local startedAt = tonumber(attr("StartedAt")) or serverNow
	if info.Scored then
		local elapsed = if status == "Complete" then tonumber(attr("Elapsed")) or 0 else serverNow - startedAt
		local line = `Time {fmtTime(elapsed)}    Score {attr("Score") or 0}`
		local activity = if info.ActivityId then ActivityConfig.ById[info.ActivityId] else nil
		if activity and status ~= "Complete" then
			local medal, limit = MissionRules.NextMedal(activity, elapsed)
			if medal and limit then
				line ..= `    {UI.Colored(`{medal} under {fmtTime(limit)}`, MEDAL_COLORS[medal] or Theme.Colors.Text)}`
			end
		end
		table.insert(extra, line)
	end
	local enrageAt = tonumber(attr("EnrageAt")) or 0
	if enrageAt > 0 then
		local left = enrageAt - serverNow
		table.insert(
			extra,
			UI.Colored(`Enrage in {fmtTime(left)}`, if left < 60 then Theme.Colors.Error else Theme.Colors.Warning)
		)
	end
	for _, modifier in info.Modifiers do
		table.insert(extra, `{UI.Colored(modifier.Name, Theme.Colors.Warning)}: {modifier.Description}`)
	end
	refs.TrackerExtra.Text = table.concat(extra, "\n")

	-- Boss.
	local bossActive = attr("BossActive") == true
	refs.BossFrame.Visible = bossActive
	if bossActive then
		local health = tonumber(attr("BossHealth")) or 0
		local maxHealth = math.max(1, tonumber(attr("BossMaxHealth")) or 1)
		local shield = tonumber(attr("BossShield")) or 0
		local maxShield = tonumber(attr("BossMaxShield")) or 0
		local bossTitle = tostring(attr("BossTitle") or "")
		refs.BossName.Text = `{string.upper(tostring(attr("BossName") or ""))}`
			.. (if bossTitle ~= "" then `  <font size="13" color="#C8C8C8">{bossTitle}</font>` else "")
		refs.BossHealthFill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		local immune = attr("BossImmune") == true
		refs.BossHealthFill.BackgroundColor3 = if immune then Color3.fromRGB(150, 150, 160) else BOSS_COLOR
		refs.BossShieldFill.Size = UDim2.new(if maxShield > 0 then math.clamp(shield / maxShield, 0, 1) else 0, 0, 0, 4)
		refs.BossTag.Text = if immune then "IMMUNE" else ""
		local thresholds = tostring(attr("BossThresholds") or "")
		if thresholds ~= shownThresholds then
			shownThresholds = thresholds
			refs.BossTicks:ClearAllChildren()
			for _, value in string.split(thresholds, ",") do
				local at = tonumber(value)
				if at then
					UI.Make("Frame", {
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.fromScale(at, 0),
						Size = UDim2.new(0, 3, 1, 0),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
					}, refs.BossTicks)
				end
			end
		end
	end

	-- Studio: zone timing.
	refs.ZoneDebug.Visible = IS_STUDIO
	if IS_STUDIO then
		local lines = { "<b>ZONE TIMES (Studio)</b>" }
		local total = 0
		for _, entry in MissionRules.ParseZoneLog(tostring(attr("ZoneLog") or "")) do
			total += entry.Seconds
			table.insert(lines, `{entry.Name}  {MissionRules.FormatTime(entry.Seconds)}`)
		end
		local zoneName = attr("ZoneName")
		local zoneStart = tonumber(attr("ZoneStartedAt"))
		if status == "Active" and type(zoneName) == "string" and zoneStart then
			local current = serverNow - zoneStart
			table.insert(lines, `▶ {zoneName}  {MissionRules.FormatTime(current)}`)
			total += current
		end
		table.insert(
			lines,
			`Total {MissionRules.FormatTime(total)}  ·  zone {attr("ZoneIndex") or "?"}/{attr("ZoneCount") or "?"}`
		)
		refs.ZoneDebug.Text = table.concat(lines, "\n")
	end

	-- Phase banner.
	local phaseText = tostring(attr("Phase") or "")
	local phaseEndsAt = tonumber(attr("PhaseEndsAt")) or 0
	local countdown = if phaseEndsAt > serverNow then `  {math.ceil(phaseEndsAt - serverNow)}s` else ""
	refs.Phase.Visible = phaseText ~= ""
	refs.Phase.Text = phaseText .. countdown
	local charge = tonumber(attr("Charge")) or 0
	refs.ChargeBar.Visible = charge > 0
	refs.ChargeFill.Size = UDim2.fromScale(math.clamp(charge, 0, 1), 1)

	-- Completion banner.
	if status == "Complete" then
		local returnAt = tonumber(attr("ReturnAt")) or serverNow
		refs.Banner.Visible = true
		refs.Banner.TextColor3 = Theme.Colors.Power
		local medal = tostring(attr("Medal") or "")
		local medalLine = if medal ~= ""
			then `\n{UI.Colored(
				`{string.upper(medal)} MEDAL  ·  {fmtTime(tonumber(attr("Elapsed")) or 0)}`,
				MEDAL_COLORS[medal] or Theme.Colors.Text
			)}`
			else ""
		refs.Banner.Text =
			`{string.upper(info.Name or "Activity")} COMPLETE{medalLine}\n<font size="18">Returning to the Spire in {math.ceil(
				math.max(0, returnAt - serverNow)
			)}s</font>`
	elseif status == "Wiped" then
		refs.Banner.Visible = true
		refs.Banner.TextColor3 = Theme.Colors.Error
		refs.Banner.Text = "FIRETEAM WIPED"
	else
		refs.Banner.Visible = false
	end

	-- Waypoint.
	local hasWaypoint = attr("HasWaypoint") == true and status == "Active"
	local waypoint = attr("Waypoint")
	if hasWaypoint and typeof(waypoint) == "Vector3" then
		if waypointPart == nil then
			local part = Instance.new("Part")
			part.Name = "Waypoint"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(1, 1, 1)
			local billboard = Instance.new("BillboardGui")
			billboard.AlwaysOnTop = true
			billboard.Size = UDim2.fromOffset(120, 40)
			billboard.LightInfluence = 0
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Theme.Fonts.Title
			label.TextSize = 14
			label.TextColor3 = Theme.Colors.Accent
			label.TextStrokeTransparency = 0.4
			label.Parent = billboard
			billboard.Parent = part
			waypointPart = part
			waypointLabel = label
		end
		local part = waypointPart :: Part
		part.Position = waypoint + Vector3.new(0, 6, 0)
		part.Parent = Workspace
		local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
		local distance = if root and root:IsA("BasePart") then (root.Position - waypoint).Magnitude else 0
		if waypointLabel then
			waypointLabel.Text = `◆\n{math.floor(distance)}m`
		end
	elseif waypointPart then
		waypointPart.Parent = nil
	end
end

local function updateDeath()
	local dead = not deathStatus.Alive
	refs.Death.Visible = dead
	if grey then
		grey.Enabled = dead
	end
	if dead then
		local respawnAt = deathStatus.RespawnAt
		local message = deathStatus.Message
		if respawnAt then
			local left = math.max(0, math.ceil(respawnAt - Workspace:GetServerTimeNow()))
			message ..= `  {left}s`
		end
		refs.DeathMessage.Text = message
	end
end

-- Lifecycle ---------------------------------------------------------------------------------

local function hideCoreGui()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

function HudController.Init()
	ClientNet.On("Notify", function(message: any, kind: any)
		HudController.Toast(tostring(message), if type(kind) == "string" then kind else nil)
	end)
	ClientNet.On("CombatFeedback", function(_position: any, amount: any, precision: any, rawFlag: any)
		local flag: string = if type(rawFlag) == "string" then rawFlag else ""
		if refs == nil or flag == "Immune" then
			return
		end
		local killed = flag == "Kill"
		local resisted = flag == "Resisted"
		if (tonumber(amount) or 0) <= 0 and not resisted then
			return
		end
		local color = if killed
			then Color3.fromRGB(255, 80, 70)
			elseif precision == true then Color3.fromRGB(255, 220, 70)
			else Color3.new(1, 1, 1)
		for _, child in refs.HitMarker:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundColor3 = color
			end
		end
		hitMarkerUntil = os.clock() + (if killed then 0.3 else 0.12)
	end)
	ClientNet.On("PlayerStatus", function(status: any)
		if type(status) ~= "table" then
			return
		end
		deathStatus = {
			Alive = status.Alive == true,
			RespawnAt = if type(status.RespawnAt) == "number" then status.RespawnAt else nil,
			Message = if type(status.Message) == "string" then status.Message else "",
		}
		UIState.SetDead(not deathStatus.Alive)
	end)
end

function HudController.Start()
	task.spawn(hideCoreGui)
	build()

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "LL_DeathGrey"
	correction.Saturation = -1
	correction.Contrast = -0.1
	correction.Enabled = false
	correction.Parent = Workspace.CurrentCamera
	grey = correction

	RunService.RenderStepped:Connect(function()
		updateCrosshair()
		updateWeapon()
		updateVitals()
		updateActivity()
		updateDeath()
	end)
end

return HudController
