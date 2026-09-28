--!strict
--[[
	IntroController
	The mission intro: when you arrive in a new run, the camera flies from
	above the start toward the first objective while letterbox bars slide in
	and the activity's name and destination fade up. Any key, click or tap
	skips it. Controls and weapons are off while it plays; the HUD hides.

	The shot comes from the server (ActivityState.Intro: the PlayerStart
	marker and the first step target). Players joining a run that started
	more than PresentationConfig.Intro.MaxRunAge seconds ago skip it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PresentationConfig = require(Shared:WaitForChild("Config"):WaitForChild("PresentationConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local ActivityController = require(script.Parent.ActivityController)
local CameraController = require(script.Parent.CameraController)
local LoadingController = require(script.Parent.LoadingController)

local IntroController = {}

local TUNING = PresentationConfig.Intro
local BAR_HEIGHT = 0.11

local player = Players.LocalPlayer
local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local title: TextLabel
local subtitle: TextLabel
local detail: TextLabel
local lastRunId: string? = nil
local playing = false

local function build()
	gui = UI.Screen("MissionIntro", 60)
	gui.Enabled = false
	topBar = UI.Make("Frame", {
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		Position = UDim2.fromScale(0, -BAR_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, gui) :: Frame
	bottomBar = UI.Make("Frame", {
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, gui) :: Frame
	title = UI.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.new(1, 0, 0, 64),
		Font = Theme.Fonts.Title,
		TextSize = 58,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}, gui)
	subtitle = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = Theme.Colors.Power,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
	}, gui)
	detail = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1 - BAR_HEIGHT / 2),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Press any key to skip",
		TextTransparency = 1,
	}, gui)
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function setControls(enabled: boolean)
	pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 2)
		if module and module:IsA("ModuleScript") then
			local controls = (require :: any)(module):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- A point on the quadratic curve a -> b -> c.
local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	return a:Lerp(b, t):Lerp(b:Lerp(c, t), t)
end

local function play(info: ActivityController.ActivityInfo, shot: ActivityController.IntroShot)
	playing = true
	LoadingController.WaitHidden(PresentationConfig.Loading.MaxSeconds)
	if ActivityController.Get().RunId ~= info.RunId then
		playing = false
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(shot.Target, 3)
	end)

	local start, target = shot.Start, shot.Target
	local up = Vector3.yAxis
	local flat = Vector3.new(target.X - start.X, 0, target.Z - start.Z)
	local forward = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(up)
	local from = start - forward * 30 + up * TUNING.StartHeight + right * 20
	local via = start:Lerp(target, 0.45) + up * (TUNING.EndHeight + 14) + right * 6
	local to = start:Lerp(target, 0.75) + up * TUNING.EndHeight - right * 22
	local lookFrom = start + forward * 40
	local lookTo = target

	title.Text = string.upper(info.Name or "")
	subtitle.Text = string.upper(info.Destination or "")
	local extras: { string } = {}
	if info.Difficulty then
		table.insert(extras, string.upper(info.Difficulty))
	end
	if info.Power then
		table.insert(extras, `RECOMMENDED POWER {info.Power}`)
	end
	if #extras > 0 then
		subtitle.Text ..= `   ·   {table.concat(extras, "   ·   ")}`
	end

	UIState.SetCinematic(true)
	CameraController.SetOverride(true)
	setControls(false)
	gui.Enabled = true
	tween(topBar, 0.6, { Position = UDim2.fromScale(0, 0) })
	tween(bottomBar, 0.6, { Position = UDim2.fromScale(0, 1 - BAR_HEIGHT) })
	tween(detail, 1, { TextTransparency = 0.3 })

	local skipped = false
	local skipConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.Keyboard
			or kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or kind == Enum.UserInputType.Gamepad1
		then
			skipped = true
		end
	end)

	local camera = Workspace.CurrentCamera
	local previousFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 62
	local began = os.clock()
	local titleShown, titleHidden = false, false
	while not skipped do
		local elapsed = os.clock() - began
		local t = math.clamp(elapsed / TUNING.Seconds, 0, 1)
		local eased = smooth(t)
		camera.CFrame = CFrame.lookAt(bezier(from, via, to, eased), lookFrom:Lerp(lookTo, smooth(math.min(1, t * 1.3))))
		if not titleShown and elapsed >= TUNING.TitleDelay then
			titleShown = true
			tween(title, 0.8, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
			tween(subtitle, 1.1, { TextTransparency = 0 })
		end
		if not titleHidden and elapsed >= TUNING.Seconds - 0.8 then
			titleHidden = true
			tween(title, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween(subtitle, 0.6, { TextTransparency = 1 })
		end
		if t >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	skipConnection:Disconnect()

	camera.FieldOfView = previousFov
	CameraController.SetOverride(false)
	UIState.SetCinematic(false)
	setControls(true)
	tween(topBar, 0.4, { Position = UDim2.fromScale(0, -BAR_HEIGHT) })
	tween(bottomBar, 0.4, { Position = UDim2.fromScale(0, 1) })
	for _, label in { title, subtitle, detail } do
		tween(label, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end
	task.delay(0.45, function()
		if not playing then
			gui.Enabled = false
		end
	end)
	playing = false
end

local function onActivityChanged(info: ActivityController.ActivityInfo)
	if not info.InActivity then
		lastRunId = nil
		return
	end
	if info.RunId == lastRunId or playing then
		return
	end
	lastRunId = info.RunId
	local shot = info.Intro
	local age = Workspace:GetServerTimeNow() - (info.StartedAt or 0)
	if shot and age <= TUNING.MaxRunAge then
		task.spawn(play, info, shot)
	end
end

function IntroController.IsPlaying(): boolean
	return playing
end

function IntroController.Init() end

function IntroController.Start()
	build()
	ActivityController.Changed:Connect(onActivityChanged)
end

return IntroController
