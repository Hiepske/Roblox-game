--!strict
--[[
	DirectorController
	The Director: a full-screen star map for launching activities.
	Open with M (gamepad D-pad up) or by using the terminal in the hub.

	One card per playable activity (story, Nightfall, raid) showing the
	recommended power (your power in red when below it), difficulty picker,
	this week's modifiers, rewards and whether weekly rewards are still
	available, a lock reason, a Launch button and fireteams you can join.
	Unlocks are checked here with the shared ActivityRules for display; the
	server checks them again on launch.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ActivityConfig = require(Config:WaitForChild("ActivityConfig"))
local ActivityRules = require(Shared:WaitForChild("Activities"):WaitForChild("ActivityRules"))
local InputConfig = require(Config:WaitForChild("InputConfig"))
local MilestoneConfig = require(Config:WaitForChild("MilestoneConfig"))
local PowerMath = require(Shared:WaitForChild("Power"):WaitForChild("PowerMath"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local ActivityController = require(script.Parent.ActivityController)
local DataController = require(script.Parent.DataController)
local LoadingController = require(script.Parent.LoadingController)

type ActivityDef = ActivityConfig.ActivityDef

local DirectorController = {}

local MENU = "Director"
local TYPE_COLORS: { [string]: Color3 } = {
	Story = Color3.fromRGB(110, 220, 255),
	Nightfall = Color3.fromRGB(255, 150, 70),
	Raid = Color3.fromRGB(190, 130, 255),
}
local TYPE_LABELS: { [string]: string } = { Story = "STORY MISSION", Nightfall = "NIGHTFALL", Raid = "RAID" }

local player = Players.LocalPlayer
local gui: ScreenGui
local built = false
local cardsFrame: Frame
local leaveButton: TextButton
local statusLabel: TextLabel
local selectedDifficulty: { [string]: string } = {}
local busy = false

type RunInfo = { RunId: string, ActivityId: string, Difficulty: string?, Players: { string }, MaxPlayers: number }
local lastRuns: { RunInfo } = {}

local function rewardLines(activity: ActivityDef, difficulty: ActivityConfig.DifficultyDef?): { string }
	local data = DataController.GetData()
	local lines: { string } = {}
	local rewards = activity.Rewards
	if rewards then
		if rewards.Drops.Max > 0 then
			local rarities: { string } = {}
			if rewards.Rarities then
				for rarity in rewards.Rarities do
					table.insert(rarities, rarity)
				end
				table.sort(rarities)
			end
			local what = if #rarities > 0 then table.concat(rarities, "/") .. " gear" else "gear"
			local count = if rewards.Drops.Min == rewards.Drops.Max
				then tostring(rewards.Drops.Min)
				else `{rewards.Drops.Min}-{rewards.Drops.Max}`
			local bonus = if difficulty and difficulty.BonusDrops
				then ` (+{difficulty.BonusDrops} at {difficulty.Name})`
				else ""
			table.insert(lines, `• {count} {what}{bonus}, up to +5 power below 450`)
		end
		if rewards.ExclusiveChance then
			table.insert(lines, `• {math.floor(rewards.ExclusiveChance * 100)}% chance of a raid-exclusive Legendary`)
		end
	end
	local milestones: { string } = {}
	if difficulty and difficulty.Milestones then
		for _, id in difficulty.Milestones do
			table.insert(milestones, id)
		end
	end
	for _, encounter in activity.Encounters or {} :: { ActivityConfig.EncounterDef } do
		if encounter.Playable and encounter.Milestone then
			table.insert(milestones, encounter.Milestone)
		end
	end
	for _, id in milestones do
		local milestone = MilestoneConfig.ById[id]
		if milestone then
			local claimed = if data
				then (data.Weekly.ClaimedRewards[id] or 0) >= (milestone.WeeklyLimit or 1)
				else false
			local kind = if milestone.Reward.Kind == "Pinnacle"
				then "Pinnacle (+1/+2)"
				else `Powerful (tier {milestone.Reward.Tier or 1})`
			local state = if claimed
				then UI.Colored("claimed this week", Theme.Colors.TextDim)
				else UI.Colored("available", Theme.Colors.Success)
			table.insert(lines, `• {kind}: {milestone.Name}, {state}`)
		end
	end
	return lines
end

local function launch(activity: ActivityDef)
	if busy then
		return
	end
	busy = true
	statusLabel.Text = `Launching {activity.Name}...`
	LoadingController.Show(activity.Name, ActivityRules.DestinationName(activity), activity.Map)
	local ok, message = ClientNet.Invoke("DirectorLaunch", activity.Id, selectedDifficulty[activity.Id])
	busy = false
	if ok then
		statusLabel.Text = ""
		UIState.CloseMenu(MENU)
	else
		LoadingController.Hide(true)
		statusLabel.Text = tostring(message or "Launch failed")
	end
end

local function join(run: RunInfo)
	if busy then
		return
	end
	busy = true
	local activity = ActivityConfig.ById[run.ActivityId]
	if activity then
		LoadingController.Show(activity.Name, ActivityRules.DestinationName(activity), activity.Map)
	end
	local ok, message = ClientNet.Invoke("DirectorJoin", run.RunId)
	busy = false
	if ok then
		UIState.CloseMenu(MENU)
	else
		LoadingController.Hide(true)
		statusLabel.Text = tostring(message or "Couldn't join")
	end
end

local function buildCard(activity: ActivityDef, order: number)
	local data = DataController.GetData()
	local color = TYPE_COLORS[activity.Type] or Theme.Colors.Accent
	local difficulty = ActivityRules.GetDifficulty(activity, selectedDifficulty[activity.Id])
	local recommended = ActivityRules.RecommendedPower(activity, if difficulty then difficulty.Id else nil)
	local power = if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
	local unlocked: boolean, reason: string? = false, "Loading..."
	if data then
		unlocked, reason = ActivityRules.CheckUnlock(data, activity)
	end

	local card = UI.Panel({
		Name = activity.Id,
		LayoutOrder = order,
		Size = UDim2.fromScale(0.31, 1),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.08,
	}, cardsFrame)
	UI.Stroke(card, color, 2, 0.2)
	UI.Padding(card, 16)
	UI.Make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, card)

	local line = 0
	local function text(props: { [string]: any }): TextLabel
		line += 1
		props.LayoutOrder = line
		props.Size = props.Size or UDim2.fromScale(1, 0)
		props.AutomaticSize = Enum.AutomaticSize.Y
		props.TextWrapped = true
		props.RichText = true
		return UI.Label(props, card)
	end

	text({
		Text = TYPE_LABELS[activity.Type] or string.upper(activity.Type),
		TextColor3 = color,
		Font = Theme.Fonts.Title,
		TextSize = 13,
	})
	text({ Text = activity.Name, Font = Theme.Fonts.Title, TextSize = 26 })
	text({ Text = activity.Description, TextColor3 = Theme.Colors.TextDim, TextSize = 13 })

	local powerColor = if power < recommended then Theme.Colors.Error else Theme.Colors.Success
	text({
		Text = `Recommended power  {UI.Colored(tostring(recommended), Theme.Colors.Power)}     Your power  {UI.Colored(
			tostring(power),
			powerColor
		)}`,
		TextSize = 15,
	})

	-- Difficulty picker.
	local difficulties = activity.Difficulties
	if difficulties and #difficulties > 0 then
		line += 1
		local row = UI.Make("Frame", {
			LayoutOrder = line,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
		}, card)
		UI.Make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
		}, row)
		for _, option in difficulties do
			local selected = difficulty ~= nil and option.Id == difficulty.Id
			local button = UI.Button({
				Size = UDim2.new(1 / #difficulties, -6, 1, 0),
				Text = `{option.Name} {option.RecommendedPower}`,
				TextSize = 13,
				BackgroundColor3 = if selected then color else Theme.Colors.PanelRaised,
				TextColor3 = if selected then Theme.Colors.Backdrop else Theme.Colors.Text,
			}, row)
			button.Activated:Connect(function()
				selectedDifficulty[activity.Id] = option.Id
				DirectorController.Refresh()
			end)
		end
	end

	-- Modifiers.
	local modifiers = ActivityRules.ModifiersFor(activity, os.time())
	if #modifiers > 0 then
		local lines: { string } = { UI.Colored("THIS WEEK'S MODIFIERS", Theme.Colors.Warning) }
		for _, id in modifiers do
			local modifier = ActivityConfig.NightfallModifiers[id]
			if modifier then
				table.insert(lines, `• {modifier.Name}: {modifier.Description}`)
			end
		end
		text({ Text = table.concat(lines, "\n"), TextSize = 13 })
	end
	if activity.Type == "Nightfall" and activity.PowerDeltaCap == 0 then
		text({
			Text = "Contest mode: being over-powered doesn't help here.",
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 12,
		})
	end
	if activity.Type == "Raid" then
		local encounters: { string } = {}
		for _, encounter in activity.Encounters or {} :: { ActivityConfig.EncounterDef } do
			local mark = if encounter.Playable then "▶" else "·"
			local name = if encounter.Playable
				then encounter.Name
				else UI.Colored(`{encounter.Name} (coming later)`, Theme.Colors.TextDim)
			table.insert(encounters, `{mark} {name}`)
		end
		text({ Text = table.concat(encounters, "\n"), TextSize = 13 })
	end

	-- Rewards.
	local rewards = rewardLines(activity, difficulty)
	if #rewards > 0 then
		text({ Text = UI.Colored("REWARDS", Theme.Colors.Accent) .. "\n" .. table.concat(rewards, "\n"), TextSize = 13 })
	end

	-- Launch.
	line += 1
	local launchButton = UI.Button({
		LayoutOrder = line,
		Size = UDim2.new(1, 0, 0, 42),
		Text = if unlocked then "LAUNCH" else `LOCKED: {reason or ""}`,
		TextSize = if unlocked then 18 else 13,
		TextWrapped = true,
		BackgroundColor3 = if unlocked then color else Theme.Colors.PanelRaised,
		TextColor3 = if unlocked then Theme.Colors.Backdrop else Theme.Colors.TextDim,
		AutoButtonColor = unlocked,
	}, card)
	if unlocked then
		launchButton.Activated:Connect(function()
			launch(activity)
		end)
	end

	-- Joinable fireteams.
	local current = ActivityController.Get()
	for _, run in lastRuns do
		if run.ActivityId == activity.Id and run.RunId ~= current.RunId and #run.Players < run.MaxPlayers then
			line += 1
			local joinButton = UI.Button({
				LayoutOrder = line,
				Size = UDim2.new(1, 0, 0, 30),
				Text = `Join {table.concat(run.Players, ", ")}{if run.Difficulty then ` ({run.Difficulty})` else ""}  [{#run.Players}/{run.MaxPlayers}]`,
				TextSize = 13,
				Visible = unlocked,
			}, card)
			joinButton.Activated:Connect(function()
				join(run)
			end)
		end
	end
end

function DirectorController.Refresh()
	if not built then
		return
	end
	for _, child in cardsFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, activity in ActivityRules.Playable() do
		buildCard(activity, index)
	end
	local current = ActivityController.Get()
	leaveButton.Visible = current.InActivity
	leaveButton.Text = if current.InActivity
		then `LEAVE {string.upper(current.Name or "ACTIVITY")} AND RETURN TO THE SPIRE`
		else ""
end

local function query()
	local ok, result = pcall(ClientNet.Invoke, "DirectorQuery")
	if ok and type(result) == "table" and type(result.Runs) == "table" then
		local runs: { RunInfo } = {}
		for _, run in result.Runs do
			if type(run) == "table" and type(run.RunId) == "string" and type(run.Players) == "table" then
				table.insert(runs, {
					RunId = run.RunId,
					ActivityId = tostring(run.ActivityId),
					Difficulty = if type(run.Difficulty) == "string" then run.Difficulty else nil,
					Players = run.Players,
					MaxPlayers = tonumber(run.MaxPlayers) or 1,
				})
			end
		end
		lastRuns = runs
	end
end

local function build()
	gui = UI.Screen("Director", 30)
	gui.Enabled = false

	local backdrop = UI.Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
	}, gui) :: Frame
	UI.Make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(26, 20, 48), Color3.fromRGB(6, 10, 18)),
		Rotation = 60,
	}, backdrop)
	-- Stars.
	local stars = Random.new(7)
	for _ = 1, 140 do
		local size = if stars:NextNumber() < 0.1 then 3 else 2
		UI.Make("Frame", {
			Position = UDim2.fromScale(stars:NextNumber(), stars:NextNumber()),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(200, 220, 255),
			BackgroundTransparency = stars:NextNumber(0.1, 0.7),
			BorderSizePixel = 0,
		}, backdrop)
	end

	UI.Label({
		Position = UDim2.fromOffset(40, 26),
		Size = UDim2.new(1, -80, 0, 36),
		Text = "THE DIRECTOR",
		Font = Theme.Fonts.Title,
		TextSize = 32,
		TextColor3 = Theme.Colors.Accent,
	}, gui)
	UI.Label({
		Position = UDim2.fromOffset(40, 62),
		Size = UDim2.new(1, -80, 0, 20),
		Text = "Choose a destination, Keeper.  [M] or [Esc] to close",
		TextColor3 = Theme.Colors.TextDim,
	}, gui)
	local close = UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, 26),
		Size = UDim2.fromOffset(44, 44),
		Text = "X",
		TextSize = 20,
	}, gui)
	close.Activated:Connect(function()
		UIState.CloseMenu(MENU)
	end)

	leaveButton = UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -90, 0, 26),
		Size = UDim2.fromOffset(420, 44),
		TextSize = 14,
		BackgroundColor3 = Color3.fromRGB(120, 40, 40),
		Visible = false,
	}, gui)
	leaveButton.Activated:Connect(function()
		ClientNet.Fire("LeaveActivity")
		UIState.CloseMenu(MENU)
	end)

	cardsFrame = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -80, 1, -150),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.02, 0),
	}, cardsFrame)

	statusLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -80, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Theme.Colors.Warning,
		TextSize = 16,
	}, gui)
	built = true
end

function DirectorController.Open()
	UIState.OpenMenu(MENU)
end

function DirectorController.Init()
	ClientNet.On("OpenDirector", function()
		DirectorController.Open()
	end)
end

function DirectorController.Start()
	build()
	UIState.MenuChanged:Connect(function(name: string?)
		local open = name == MENU
		gui.Enabled = open
		if open then
			statusLabel.Text = ""
			DirectorController.Refresh()
			task.spawn(function()
				query()
				if UIState.GetOpenMenu() == MENU then
					DirectorController.Refresh()
				end
			end)
		end
	end)
	DataController.Changed:Connect(function()
		if UIState.GetOpenMenu() == MENU then
			DirectorController.Refresh()
		end
	end)
	ActivityController.Changed:Connect(function()
		if UIState.GetOpenMenu() == MENU then
			DirectorController.Refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local key = input.KeyCode.Name
		if key == InputConfig.Keyboard.StarChart or key == InputConfig.Gamepad.StarChart then
			if UIState.GetOpenMenu() == MENU then
				UIState.CloseMenu(MENU)
			elseif not UIState.IsDead() then
				UIState.OpenMenu(MENU)
			end
		elseif input.KeyCode == Enum.KeyCode.Escape and UIState.GetOpenMenu() == MENU then
			UIState.CloseMenu(MENU)
		end
	end)
	player.CharacterAdded:Connect(function()
		if UIState.GetOpenMenu() == MENU then
			DirectorController.Refresh()
		end
	end)
end

return DirectorController
