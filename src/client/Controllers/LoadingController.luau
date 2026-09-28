--!strict
--[[
	LoadingController
	A full-screen card that covers loading: the destination's art
	(AssetIds.Images.Loading, a drawn placeholder in the map's colors while
	the id is 0), the activity name and a gameplay tip.

	It shows when a launch or join starts (DirectorController calls Show)
	and hides once the run's state has arrived and the area around the start
	has streamed in. Coming back to the Spire is covered briefly too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AssetIds = require(Config:WaitForChild("AssetIds"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local ActivityController = require(script.Parent.ActivityController)

local LoadingController = {}

local TUNING = PresentationConfig.Loading
local IS_STUDIO = RunService:IsStudio()

-- Fires when the screen has finished fading out.
local hidden: Signal.Signal<> = Signal.new()
LoadingController.Hidden = hidden

type Refs = {
	Gui: ScreenGui,
	Group: CanvasGroup,
	Art: ImageLabel,
	Sky: Frame,
	Ground: Frame,
	Glow: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Accent: Frame,
	Tip: TextLabel,
	Spinner: Frame,
	Credit: TextLabel,
}

local refs: Refs? = nil
local fade: Tween? = nil
local showing = false
local shownAt = 0
local token = 0
local tipIndex = 0
local wasInActivity = false

local function nextTip(): string
	local tips = PresentationConfig.Tips
	if #tips == 0 then
		return ""
	end
	if tipIndex == 0 then
		tipIndex = math.random(1, #tips)
	else
		tipIndex = tipIndex % #tips + 1
	end
	return tips[tipIndex]
end

local function build(): Refs
	local gui = UI.Screen("LoadingScreen", 90)
	gui.Enabled = false
	local group = UI.Make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BorderSizePixel = 0,
	}, gui) :: CanvasGroup

	-- Placeholder art: a sky, a horizon glow and a dark ground in the map's
	-- colors. A real image (when the asset id is set) covers all of it.
	local sky = UI.Make("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, group) :: Frame
	UI.Make("UIGradient", { Rotation = 90 }, sky)
	local glow = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.62, 0.6),
		Size = UDim2.fromScale(1.4, 0.35),
		BorderSizePixel = 0,
		BackgroundTransparency = 0.35,
	}, group) :: Frame
	UI.Make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, glow)
	local ground = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.38),
		BorderSizePixel = 0,
	}, group) :: Frame
	-- A few ridges on the horizon.
	for index, ridge in { { 0.08, 0.16, 0.9 }, { 0.34, 0.24, 1.3 }, { 0.7, 0.2, 1.1 } } do
		UI.Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(ridge[1], 1 - 0.38),
			Size = UDim2.fromScale(ridge[3] * 0.35, ridge[2]),
			Rotation = if index % 2 == 0 then 8 else -6,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		}, ground)
	end
	local art = UI.Make("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		Visible = false,
	}, group) :: ImageLabel

	-- Shade the bottom so the text reads on any art.
	local shade = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.45),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, group) :: Frame
	UI.Make("UIGradient", {
		Transparency = NumberSequence.new(1, 0.15),
		Rotation = 90,
	}, shade)

	local title = UI.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 64, 1, -150),
		Size = UDim2.new(1, -128, 0, 60),
		Font = Theme.Fonts.Title,
		TextSize = 54,
		TextStrokeTransparency = 0.6,
	}, group)
	local accent = UI.Make("Frame", {
		Position = UDim2.new(0, 66, 1, -146),
		Size = UDim2.fromOffset(120, 3),
		BorderSizePixel = 0,
	}, group) :: Frame
	local subtitle = UI.Label({
		Position = UDim2.new(0, 66, 1, -136),
		Size = UDim2.new(1, -128, 0, 24),
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
	}, group)
	local tip = UI.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 66, 1, -48),
		Size = UDim2.new(0.7, -66, 0, 44),
		TextSize = 16,
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, group)
	local spinner = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -72, 1, -70),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
	}, group) :: Frame
	UI.Stroke(spinner, Theme.Colors.Text, 3)
	UI.Label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -100, 1, -70),
		Size = UDim2.fromOffset(160, 20),
		Text = "LOADING",
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, group)
	local credit = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 20),
		Size = UDim2.fromOffset(420, 16),
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, group)

	return {
		Gui = gui,
		Group = group,
		Art = art,
		Sky = sky,
		Ground = ground,
		Glow = glow,
		Title = title,
		Subtitle = subtitle,
		Accent = accent,
		Tip = tip,
		Spinner = spinner,
		Credit = credit,
	}
end

local function dress(ui: Refs, map: string)
	local palettes = TUNING.Palettes
	local palette = palettes[map] or palettes.Default
	local sky, ground, accent = palette[1], palette[2], palette[3]
	ui.Sky.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = ui.Sky:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(sky, sky:Lerp(ground, 0.55))
	end
	ui.Glow.BackgroundColor3 = accent
	ui.Ground.BackgroundColor3 = ground
	ui.Accent.BackgroundColor3 = accent
	local image = AssetIds.Get(AssetIds.Images.Loading[map] or AssetIds.Images.Loading.Default)
	ui.Art.Image = image
	ui.Art.Visible = image ~= ""
	ui.Credit.Text = if IS_STUDIO and image == "" then `placeholder art: AssetIds.Images.Loading.{map}` else ""
end

-- Covers the screen: `title` large, `subtitle` under it, art for `map`.
function LoadingController.Show(title: string, subtitle: string?, map: string?)
	local ui = refs
	if ui == nil then
		return
	end
	token += 1
	dress(ui, map or "Default")
	ui.Title.Text = string.upper(title)
	ui.Subtitle.Text = string.upper(subtitle or "")
	ui.Tip.Text = `{UI.Colored("TIP", Theme.Colors.Power)}   {nextTip()}`
	if fade then
		fade:Cancel()
		fade = nil
	end
	if not showing then
		showing = true
		shownAt = os.clock()
	end
	ui.Group.GroupTransparency = 0
	ui.Gui.Enabled = true
	-- Never strand the player behind the card.
	local mine = token
	task.delay(TUNING.MaxSeconds, function()
		if token == mine then
			LoadingController.Hide()
		end
	end)
end

-- Fades the card out, after it has been up for MinSeconds unless `now`.
function LoadingController.Hide(now: boolean?)
	local ui = refs
	if ui == nil or not showing then
		return
	end
	token += 1
	local mine = token
	task.spawn(function()
		local wait = if now then 0 else TUNING.MinSeconds - (os.clock() - shownAt)
		if wait > 0 then
			task.wait(wait)
		end
		if token ~= mine then
			return
		end
		local tween = TweenService:Create(
			ui.Group,
			TweenInfo.new(TUNING.FadeSeconds, Enum.EasingStyle.Quad),
			{ GroupTransparency = 1 }
		)
		fade = tween
		tween:Play()
		tween.Completed:Wait()
		if token ~= mine then
			return
		end
		fade = nil
		ui.Gui.Enabled = false
		showing = false
		hidden:Fire()
	end)
end

function LoadingController.IsShowing(): boolean
	return showing
end

-- Yields until the card is gone (or `timeout` seconds pass).
function LoadingController.WaitHidden(timeout: number)
	local started = os.clock()
	while showing and os.clock() - started < timeout do
		task.wait(0.1)
	end
end

local function onActivityChanged(info: ActivityController.ActivityInfo)
	local entering = info.InActivity
	local leaving = wasInActivity and not info.InActivity
	wasInActivity = info.InActivity
	if entering and showing then
		-- Let the start area stream in before revealing it.
		local intro = info.Intro
		if intro then
			pcall(function()
				Players.LocalPlayer:RequestStreamAroundAsync(intro.Start, 5)
			end)
		end
		LoadingController.Hide()
	elseif leaving then
		LoadingController.Show("The Spire", "Returning to the hub", "Hub")
		task.delay(TUNING.ReturnSeconds, LoadingController.Hide, false)
	end
end

function LoadingController.Init() end

function LoadingController.Start()
	refs = build()
	ActivityController.Changed:Connect(onActivityChanged)
	RunService.RenderStepped:Connect(function(dt: number)
		local ui = refs
		if ui and showing then
			ui.Spinner.Rotation = (ui.Spinner.Rotation + dt * 240) % 360
		end
	end)
end

return LoadingController
