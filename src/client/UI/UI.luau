--!strict
--[[
	UI
	Tiny helpers for building interfaces in code with the shared Theme.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local UI = {}

-- Creates an instance, applies properties, and parents it.
function UI.Make(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

-- A full-screen ScreenGui in the player's PlayerGui.
function UI.Screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UI.Corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius then UDim.new(0, radius) else Theme.CornerRadius
	corner.Parent = parent
end

function UI.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Stroke
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

function UI.Padding(parent: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
end

function UI.Panel(props: { [string]: any }, parent: Instance?): Frame
	local frame = UI.Make("Frame", {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, parent) :: Frame
	for key, value in props do
		(frame :: any)[key] = value
	end
	UI.Corner(frame)
	return frame
end

function UI.Label(props: { [string]: any }, parent: Instance?): TextLabel
	local label = UI.Make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

function UI.Button(props: { [string]: any }, parent: Instance?): TextButton
	local button = UI.Make("TextButton", {
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.Text,
		AutoButtonColor = true,
	}, parent) :: TextButton
	for key, value in props do
		(button :: any)[key] = value
	end
	UI.Corner(button)
	return button
end

function UI.Hex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Rich-text colored span.
function UI.Colored(text: string, color: Color3): string
	return `<font color="{UI.Hex(color)}">{text}</font>`
end

return UI
