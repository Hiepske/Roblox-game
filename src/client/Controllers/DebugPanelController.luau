--!strict
--[[
	DebugPanelController
	A developer panel for Phase 1 testing: shows the replicated save (class,
	power, currencies, inventory, equipped gear, reset timers, storage
	backend) and has buttons for the server's debug commands so you can
	change data, rejoin, and confirm it persisted.

	Only shown to players the server marks with the DebugAccess attribute
	(everyone in Studio). Toggle with F2 or the DEV button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local Inventory = require(Shared:WaitForChild("Items"):WaitForChild("Inventory"))
local ItemCatalog = require(Shared:WaitForChild("Items"):WaitForChild("ItemCatalog"))
local PowerMath = require(Shared:WaitForChild("Power"):WaitForChild("PowerMath"))
local TimeUtil = require(Shared:WaitForChild("Util"):WaitForChild("TimeUtil"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UIState = require(script.Parent.Parent.UI.UIState)
local DataController = require(script.Parent.DataController)

local DebugPanelController = {}

local TOGGLE_KEY = Enum.KeyCode.F2
local MAX_LOG_LINES = 8

local player = Players.LocalPlayer

local panel: Frame? = nil
local infoLabel: TextLabel? = nil
local logLabel: TextLabel? = nil
local logLines: { string } = {}
local refreshQueued = false

local function make(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance)
	make("UICorner", { CornerRadius = Theme.CornerRadius }, parent)
end

local function colorText(text: string, color: Color3): string
	return `<font color="#{color:ToHex()}">{text}</font>`
end

local function formatInfo(): string
	local data = DataController.GetData()
	if data == nil then
		return "Waiting for data..."
	end
	local now = os.time()
	local lines: { string } = {}
	local function line(text: string)
		table.insert(lines, text)
	end

	local backend = player:GetAttribute("DataBackend")
	line(
		`<b>Storage</b>  {if backend == "Mock"
			then colorText("MOCK (in-memory, not saved)", Theme.Colors.Warning)
			else colorText(tostring(backend or "?"), Theme.Colors.Success)}`
	)
	line(`<b>Class</b>  {data.Class} / {data.Subclasses[data.Class] or "?"}`)

	local power = PowerMath.CharacterPower(data.Items, data.Equipped)
	local highest = PowerMath.HighestPossible(data.Items)
	line(
		`<b>Power</b>  {colorText(tostring(power), Theme.Colors.Power)}  (highest possible {highest}, stage {PowerMath.Stage(
			highest
		)})`
	)

	local currencies: { string } = {}
	for _, currency in EconomyConfig.Order do
		table.insert(currencies, `{currency} {data.Currencies[currency] or 0}`)
	end
	line(`<b>Currencies</b>  {table.concat(currencies, " · ")}`)

	local itemCount = 0
	for _ in data.Items do
		itemCount += 1
	end
	line(
		`<b>Items</b>  {itemCount} total · vault {Inventory.Count(data, "Vault")}/{GameConfig.Inventory.VaultCapacity} · postmaster {Inventory.Count(
			data,
			"Postmaster"
		)}/{GameConfig.Inventory.PostmasterCapacity}`
	)

	line("<b>Equipped</b>")
	for _, slot in PowerMath.AllSlots do
		local uid = data.Equipped[slot]
		local item = if uid then data.Items[uid] else nil
		if item then
			local entry = ItemCatalog.Get(item.DefId)
			local tier = RarityConfig.Tiers[item.Rarity]
			local name = if entry then entry.Name else item.DefId
			local spare = Inventory.Count(data, "Inventory", slot)
			line(
				`  {slot}: {colorText(name, if tier then tier.Color else Theme.Colors.Text)} {item.Power}  <font color="#{Theme.Colors.TextDim:ToHex()}">(+{spare} spare)</font>`
			)
		else
			line(`  {slot}: {colorText("empty", Theme.Colors.Error)}`)
		end
	end

	local resets = GameConfig.Resets
	local weekly = TimeUtil.GetNextWeeklyReset(now, resets.WeeklyWeekday, resets.HourUtc) - now
	local daily = TimeUtil.GetNextDailyReset(now, resets.HourUtc) - now
	local claimed = 0
	for _, count in data.Weekly.ClaimedRewards do
		claimed += count
	end
	line(
		`<b>Resets</b>  weekly in {TimeUtil.FormatDuration(weekly)} · daily in {TimeUtil.FormatDuration(daily)} · {claimed} weekly claims`
	)
	line(
		`<b>Lifetime</b>  logins {data.LoginCount} · playtime {TimeUtil.FormatDuration(data.Lifetime.PlaytimeSeconds)} · best power {data.Lifetime.HighestPower}`
	)
	return table.concat(lines, "\n")
end

local function refresh()
	if infoLabel then
		infoLabel.Text = formatInfo()
	end
	if logLabel then
		logLabel.Text = table.concat(logLines, "\n")
	end
end

-- Coalesces bursts of data changes into one refresh.
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refresh()
	end)
end

local function log(message: string, kind: string?)
	local color = Theme.Colors.Info
	if kind == "Success" then
		color = Theme.Colors.Success
	elseif kind == "Warning" then
		color = Theme.Colors.Warning
	elseif kind == "Error" then
		color = Theme.Colors.Error
	end
	local stamp = DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
	table.insert(logLines, 1, colorText(`{stamp}  {message}`, color))
	while #logLines > MAX_LOG_LINES do
		table.remove(logLines)
	end
	queueRefresh()
end

local function build(screen: ScreenGui)
	screen.Enabled = true

	local toggle = make("TextButton", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(56, 28),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		TextColor3 = Theme.Colors.Accent,
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Small,
		Text = "DEV",
		AutoButtonColor = true,
	}, screen) :: TextButton
	corner(toggle)

	local frame = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 44),
		Size = UDim2.fromScale(0.9, 0.8),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
	}, screen) :: Frame
	corner(frame)
	make("UISizeConstraint", { MaxSize = Vector2.new(380, 640) }, frame)
	make("UIStroke", { Color = Theme.Colors.Stroke, Thickness = 1 }, frame)
	make("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Padding),
		PaddingBottom = UDim.new(0, Theme.Padding),
		PaddingLeft = UDim.new(0, Theme.Padding),
		PaddingRight = UDim.new(0, Theme.Padding),
	}, frame)
	panel = frame

	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	make("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, -6, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{GameConfig.Title} · DEV PANEL`,
	}, scroll)

	infoLabel = make("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Text = "Waiting for data...",
	}, scroll) :: TextLabel

	local grid = make("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, scroll)
	make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 30),
		CellPadding = UDim2.fromOffset(8, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	local buttonCount = 0
	local function button(label: string, onClick: (TextButton) -> ())
		buttonCount += 1
		local b = make("TextButton", {
			LayoutOrder = buttonCount,
			BackgroundColor3 = Theme.Colors.PanelRaised,
			TextColor3 = Theme.Colors.Text,
			Font = Theme.Fonts.Body,
			TextSize = Theme.TextSize.Small,
			Text = label,
			AutoButtonColor = true,
		}, grid) :: TextButton
		corner(b)
		b.Activated:Connect(function()
			onClick(b)
		end)
	end

	local function command(label: string, name: string, text: string?, number: number?)
		button(label, function()
			ClientNet.Fire("DebugCommand", name, text, number)
		end)
	end

	command("+1000 Quanta", "AddCurrency", "Quanta", 1000)
	command("+10 Alloy", "AddCurrency", "Alloy", 10)
	command("+5 Fluxite", "AddCurrency", "Fluxite", 5)
	command("+1 Starglass", "AddCurrency", "Starglass", 1)
	command("Grant Rare", "GrantItem", "Rare")
	command("Grant Epic", "GrantItem", "Epic")
	command("Grant Legendary", "GrantItem", "Legendary")
	command("Grant Exotic", "GrantItem", "Exotic")
	command("Pinnacle Drop", "GrantPinnacle")
	command("Cycle Class", "CycleClass")
	command("Save Now", "SaveNow")
	command("Apply Resets", "ExpireResets")
	-- Phase 2 shortcuts (same as the chat commands /setpower, /launch, /god...).
	command("Power 450", "SetPower", nil, 450)
	command("Power 490", "SetPower", nil, 490)
	command("Launch Story", "Launch", "story")
	command("Launch Nightfall", "Launch", "nightfall:adept")
	command("Launch Raid", "Launch", "raid")
	command("Skip Objective", "Skip")
	command("God Mode", "God")
	command("Heavy Ammo", "Heavy")
	command("Leave Activity", "Leave")

	local confirmUntil = 0
	button("Reset Profile", function(b: TextButton)
		if os.clock() < confirmUntil then
			confirmUntil = 0
			b.Text = "Reset Profile"
			ClientNet.Fire("DebugCommand", "ResetProfile")
		else
			confirmUntil = os.clock() + 3
			b.Text = "Click again!"
			task.delay(3, function()
				if b.Text == "Click again!" then
					b.Text = "Reset Profile"
				end
			end)
		end
	end)

	make("TextLabel", {
		LayoutOrder = 4,
		Size = UDim2.new(1, -6, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SERVER MESSAGES",
	}, scroll)

	logLabel = make("TextLabel", {
		LayoutOrder = 5,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Mono,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Text = "",
	}, scroll) :: TextLabel

	local function setVisible(visible: boolean)
		frame.Visible = visible
		-- Frees the mouse from the shooter camera while the panel is open.
		if visible then
			UIState.OpenMenu("DevPanel")
			refresh()
		else
			UIState.CloseMenu("DevPanel")
		end
	end
	UIState.MenuChanged:Connect(function(name: string?)
		if name ~= "DevPanel" and frame.Visible then
			frame.Visible = false
		end
	end)

	toggle.Activated:Connect(function()
		setVisible(not frame.Visible)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			setVisible(not frame.Visible)
		end
	end)

	setVisible(false)
end

function DebugPanelController.Init()
	ClientNet.On("Notify", function(message: any, kind: any)
		local text = tostring(message)
		print(`[Notify] {text}`)
		log(text, if type(kind) == "string" then kind else nil)
	end)
end

function DebugPanelController.Start()
	if not player:GetAttribute("DebugAccess") then
		player:GetAttributeChangedSignal("DebugAccess"):Wait()
	end
	if not player:GetAttribute("DebugAccess") then
		return
	end

	local screen = player:WaitForChild("PlayerGui"):WaitForChild("DebugPanel") :: ScreenGui
	build(screen)

	DataController.Changed:Connect(queueRefresh)
	player:GetAttributeChangedSignal("DataBackend"):Connect(queueRefresh)

	-- Keep reset countdowns ticking while the panel is open.
	while true do
		task.wait(1)
		local frame = panel
		if frame and frame.Visible then
			refresh()
		end
	end
end

return DebugPanelController
