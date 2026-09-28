--!strict
--[[
	KillFeedController
	The kill feed at the top right (KillFeed remote, sent to everyone in the
	run): fireteam kills with the enemy colored by tier, boss defeats in
	gold, deaths in red with what killed you, and revives. Your own name is
	highlighted. Lines fade after PresentationConfig.KillFeed.Lifetime.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PresentationConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PresentationConfig"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)

local KillFeedController = {}

local TUNING = PresentationConfig.KillFeed
local TIER_COLORS: { [string]: Color3 } = {
	Minor = Color3.fromRGB(205, 212, 222),
	Major = Color3.fromRGB(255, 170, 80),
	Boss = Theme.Colors.Power,
	Object = Theme.Colors.Info,
}
local GOLD = Theme.Colors.Power
local RED = Theme.Colors.Error
local GREEN = Theme.Colors.Success

local gui: ScreenGui? = nil
local list: Frame? = nil
local order = 0

local function build()
	local screen = UI.Screen("KillFeed", 6)
	gui = screen
	local frame = UI.Make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 96),
		Size = UDim2.fromOffset(380, 240),
		BackgroundTransparency = 1,
	}, screen) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, frame)
	list = frame
end

local function name(text: string): string
	local me = Players.LocalPlayer.DisplayName
	local escaped = string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;")
	return if text == me then `<b>{UI.Colored(escaped, Theme.Colors.Accent)}</b>` else `<b>{escaped}</b>`
end

local function lineFor(kind: string, actor: string, target: string, tier: string?): (string?, Color3)
	if kind == "Kill" then
		if tier == "Minor" and not TUNING.ShowMinorKills then
			return nil, Theme.Colors.Text
		end
		local color = TIER_COLORS[tier or ""] or Theme.Colors.Text
		local verb = if tier == "Object" then "destroyed" else "✕"
		return `{name(actor)}  {verb}  {UI.Colored(target, color)}`, color
	elseif kind == "Boss" then
		local by = if actor ~= "" then `{name(actor)} defeated ` else "Defeated "
		return `{by}{UI.Colored(`<b>{string.upper(target)}</b>`, GOLD)}`, GOLD
	elseif kind == "Death" then
		local cause = if actor ~= "" then `  ☠  {UI.Colored(actor, RED)}` else "  ☠"
		return `{name(target)}{cause}`, RED
	elseif kind == "Revive" then
		return `{name(actor)}  {UI.Colored("revived", GREEN)}  {name(target)}`, GREEN
	end
	return nil, Theme.Colors.Text
end

local function push(text: string, color: Color3, big: boolean)
	local parent = list
	if parent == nil then
		return
	end
	order += 1
	local entry = UI.Make("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, if big then 30 else 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, parent) :: Frame
	UI.Corner(entry, 4)
	UI.Make("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, entry)
	local edge = UI.Make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, entry) :: Frame
	local label = UI.Label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		RichText = true,
		Text = text,
		TextSize = if big then 17 else 14,
		Font = if big then Theme.Fonts.Title else Theme.Fonts.Body,
		TextStrokeTransparency = 0.7,
	}, entry)

	-- Oldest lines go first when the feed is full.
	local entries: { Frame } = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a: Frame, b: Frame)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #entries - TUNING.MaxEntries do
		entries[index]:Destroy()
	end

	task.delay(TUNING.Lifetime, function()
		if entry.Parent == nil then
			return
		end
		local info = TweenInfo.new(0.6)
		TweenService:Create(entry, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(edge, info, { BackgroundTransparency = 1 }):Play()
		local fade = TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		entry:Destroy()
	end)
end

function KillFeedController.Init()
	ClientNet.On("KillFeed", function(kind: any, actor: any, target: any, tier: any)
		if type(kind) ~= "string" then
			return
		end
		local text, color = lineFor(
			kind,
			if type(actor) == "string" then actor else "",
			if type(target) == "string" then target else "",
			if type(tier) == "string" then tier else nil
		)
		if text then
			push(text, color, kind == "Boss")
		end
	end)
end

function KillFeedController.Start()
	build()
	-- Out of the way of the intro's letterbox.
	RunService.RenderStepped:Connect(function()
		local screen = gui
		if screen then
			screen.Enabled = not UIState.IsCinematic()
		end
	end)
end

return KillFeedController
