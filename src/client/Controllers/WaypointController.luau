--!strict
--[[
	WaypointController
	The objective waypoint: a diamond on screen over the run's Waypoint
	attribute with the distance in meters under it. Off screen (or behind
	you) it slides to the nearest screen edge and points the way with an
	arrow. It fades while you look straight at it so it never hides a
	target, and hides during the mission intro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PresentationConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local ActivityController = require(script.Parent.ActivityController)

local WaypointController = {}

local LIFT = Vector3.new(0, 4, 0)
local MARGIN = PresentationConfig.Waypoint.EdgeMargin

local player = Players.LocalPlayer
local holder: Frame
local diamond: Frame
local inner: Frame
local stroke: UIStroke
local distanceLabel: TextLabel
local arrow: TextLabel

local function build()
	local gui = UI.Screen("Waypoint", 4)
	holder = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(80, 64),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui) :: Frame
	diamond = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(18, 18),
		Rotation = 45,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, holder) :: Frame
	stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Accent
	stroke.Thickness = 2
	stroke.Parent = diamond
	inner = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
	}, diamond) :: Frame
	distanceLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(80, 16),
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = Theme.Colors.Accent,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, holder)
	arrow = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(20, 20),
		Font = Theme.Fonts.Title,
		Text = "▲",
		TextSize = 14,
		TextColor3 = Theme.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, holder)
end

local function hide()
	holder.Visible = false
end

local function setOpacity(alpha: number)
	local transparency = 1 - alpha
	stroke.Transparency = transparency
	inner.BackgroundTransparency = transparency
	diamond.BackgroundTransparency = 0.55 + 0.45 * transparency
	distanceLabel.TextTransparency = transparency
	distanceLabel.TextStrokeTransparency = 0.5 + 0.5 * transparency
	arrow.TextTransparency = transparency
end

local function update()
	local folder = ActivityController.GetFolder()
	if not ActivityController.Get().InActivity or folder == nil or UIState.IsCinematic() then
		hide()
		return
	end
	local waypoint = folder:GetAttribute("Waypoint")
	if folder:GetAttribute("HasWaypoint") ~= true or typeof(waypoint) ~= "Vector3" then
		hide()
		return
	end
	local status = folder:GetAttribute("Status")
	if status ~= "Active" and status ~= "Complete" then
		hide()
		return
	end

	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local distance = if root and root:IsA("BasePart") then (root.Position - waypoint).Magnitude else 0
	distanceLabel.Text = `{math.floor(distance)}m`

	local point, visible = camera:WorldToViewportPoint(waypoint + LIFT)
	local screen = Vector2.new(point.X, point.Y)
	local center = viewport / 2
	local inside = visible
		and point.Z > 0
		and screen.X >= MARGIN
		and screen.X <= viewport.X - MARGIN
		and screen.Y >= MARGIN
		and screen.Y <= viewport.Y - MARGIN

	if inside then
		arrow.Visible = false
		diamond.Visible = true
		-- Fade while it sits under the crosshair, and when you're on top of it.
		local fromCenter = (screen - center).Magnitude
		local alpha = math.clamp(fromCenter / 90, 0.25, 1)
		if distance < 8 then
			alpha *= math.clamp((distance - 3) / 5, 0, 1)
		end
		setOpacity(alpha)
	else
		-- Push it to the edge, in the direction of the waypoint.
		local direction = screen - center
		if point.Z < 0 then
			direction = -direction
		end
		if direction.Magnitude < 1 then
			direction = Vector2.new(0, 1)
		end
		local half = center - Vector2.new(MARGIN, MARGIN)
		local scale =
			math.min(half.X / math.max(1e-3, math.abs(direction.X)), half.Y / math.max(1e-3, math.abs(direction.Y)))
		screen = center + direction * scale
		arrow.Visible = true
		arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
		diamond.Visible = false
		setOpacity(1)
	end
	holder.Position = UDim2.fromOffset(screen.X, screen.Y - 14)
	holder.Visible = true
end

function WaypointController.Init() end

function WaypointController.Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return WaypointController
