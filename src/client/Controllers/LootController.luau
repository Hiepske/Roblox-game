--!strict
--[[
	LootController
	Shows gear the server awarded (LootAwarded):
	  * end of an activity: the Mission Complete screen. How the run went
	    (time, your kills and deaths, the fireteam's, medal and score) over
	    one card per item, colored by rarity, with its power, why it dropped
	    (Powerful, Pinnacle, raid exclusive) and whether it's an upgrade.
	    "Equip upgrades" equips every reward that beats what you're wearing.
	    Raid encounter chests use the same screen without the run summary.
	  * mid-activity drops: a toast per item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local ItemCatalog = require(Shared:WaitForChild("Items"):WaitForChild("ItemCatalog"))
local PowerMath = require(Shared:WaitForChild("Power"):WaitForChild("PowerMath"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local DataController = require(script.Parent.DataController)
local HudController = require(script.Parent.HudController)

local LootController = {}

local MENU = "Loot"
local REASONS: { [string]: string } = {
	Drop = "",
	Powerful = "POWERFUL",
	Pinnacle = "PINNACLE",
	Exclusive = "RAID EXCLUSIVE",
	NewWeapon = "NEW WEAPON",
}

type AwardView = {
	Uid: string,
	DefId: string,
	Rarity: string,
	Power: number,
	Slot: string,
	Kind: string,
	Reason: string,
	Location: string,
}

local gui: ScreenGui
local title: TextLabel
local subtitle: TextLabel
local statsRow: Frame
local cards: Frame
local current: { AwardView } = {}

local function fmtTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function nameOf(defId: string): (string, string)
	local entry = ItemCatalog.Get(defId)
	if entry and entry.Weapon then
		return entry.Weapon.Name, entry.Weapon.Type
	elseif entry and entry.Armor then
		return entry.Armor.Name, entry.Armor.Slot
	end
	return defId, ""
end

local function parseAwards(payload: any): { AwardView }
	local list: { AwardView } = {}
	if type(payload.Awards) ~= "table" then
		return list
	end
	for _, award in payload.Awards do
		local item = if type(award) == "table" then award.Item else nil
		if type(item) == "table" and type(item.Uid) == "string" and type(item.DefId) == "string" then
			table.insert(list, {
				Uid = item.Uid,
				DefId = item.DefId,
				Rarity = tostring(item.Rarity),
				Power = tonumber(item.Power) or 0,
				Slot = tostring(item.Slot),
				Kind = tostring(item.Kind),
				Reason = tostring(award.Reason),
				Location = tostring(award.Location),
			})
		end
	end
	return list
end

-- Power of what's equipped in `slot` right now.
local function equippedPower(slot: string): number
	local data = DataController.GetData()
	local uid = if data then data.Equipped[slot] else nil
	local item = if data and uid then data.Items[uid] else nil
	return if item then item.Power else 0
end

local function stat(order: number, label: string, value: string, color: Color3?)
	local block = UI.Panel({
		LayoutOrder = order,
		Size = UDim2.fromOffset(118, 64),
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BackgroundTransparency = 0.2,
	}, statsRow)
	UI.Label({
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 30),
		Text = value,
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = color or Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, block)
	UI.Label({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		Text = label,
		Font = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, block)
end

-- The run summary strip; false when the payload has none.
local function showSummary(summary: any): boolean
	for _, child in statsRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if type(summary) ~= "table" then
		statsRow.Visible = false
		return false
	end
	local kills = tonumber(summary.Kills) or 0
	local teamKills = tonumber(summary.FireteamKills) or kills
	stat(1, "TIME", fmtTime(tonumber(summary.Elapsed) or 0))
	stat(2, "KILLS", tostring(kills), Theme.Colors.Accent)
	stat(3, "DEATHS", tostring(tonumber(summary.Deaths) or 0), Theme.Colors.Error)
	if teamKills ~= kills then
		stat(4, "FIRETEAM KILLS", tostring(teamKills))
		stat(5, "FIRETEAM DEATHS", tostring(tonumber(summary.FireteamDeaths) or 0))
	end
	local medal = summary.Medal
	if type(medal) == "string" and medal ~= "" then
		stat(6, "MEDAL", string.upper(medal), PresentationConfig.MedalColors[medal])
	end
	local score = tonumber(summary.Score)
	if score then
		stat(7, "SCORE", tostring(score), Theme.Colors.Power)
	end
	statsRow.Visible = true
	return true
end

local function showScreen(payload: any, awards: { AwardView })
	current = awards
	for _, child in cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rewardsTitle = tostring(payload.Title or "Rewards")
	local power = tonumber(payload.Power) or 0
	local highest = tonumber(payload.HighestPower) or power
	local powerLine = if highest > power
		then `Power {power}  ·  equip your upgrades to reach {highest}`
		else `Power {power}`
	if showSummary(payload.Summary) then
		local kind = tostring(payload.Summary.Kind)
		title.Text = PresentationConfig.CompleteTitles[kind] or "ACTIVITY COMPLETE"
		subtitle.Text = `{string.upper(rewardsTitle)}   ·   {powerLine}`
	else
		title.Text = string.upper(rewardsTitle)
		subtitle.Text = powerLine
	end

	if #awards == 0 then
		UI.Label({
			Size = UDim2.fromOffset(400, 40),
			Text = "No gear this time. Weekly rewards already claimed.",
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, cards)
	end
	for index, award in awards do
		local rarity = RarityConfig.Tiers[award.Rarity]
		local color = if rarity then rarity.Color else Theme.Colors.Text
		local name, subtype = nameOf(award.DefId)
		local card = UI.Panel({
			LayoutOrder = index,
			Size = UDim2.fromOffset(220, 150),
			BackgroundColor3 = Theme.Colors.Panel,
		}, cards)
		UI.Stroke(card, color, 2)
		UI.Make("UIGradient", {
			Color = ColorSequence.new(color:Lerp(Theme.Colors.Panel, 0.55), Theme.Colors.Panel),
			Rotation = 90,
		}, card)
		UI.Padding(card, 10)
		local upgrade = award.Power > equippedPower(award.Slot)
		local reason = REASONS[award.Reason] or ""
		UI.Label({
			Size = UDim2.new(1, 0, 0, 14),
			Text = `{string.upper(award.Rarity)}{if reason ~= "" then "  ·  " .. reason else ""}`,
			TextColor3 = color,
			Font = Theme.Fonts.Title,
			TextSize = 11,
		}, card)
		UI.Label({
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 44),
			Text = name,
			Font = Theme.Fonts.Title,
			TextSize = 18,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, card)
		UI.Label({
			Position = UDim2.fromOffset(0, 62),
			Size = UDim2.new(1, 0, 0, 16),
			Text = `{award.Slot}  ·  {subtype}`,
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 12,
		}, card)
		UI.Label({
			Position = UDim2.fromOffset(0, 84),
			Size = UDim2.new(1, 0, 0, 30),
			Text = `✦ {award.Power}{if upgrade then "  ▲" else ""}`,
			TextColor3 = if upgrade then Theme.Colors.Success else Theme.Colors.Power,
			Font = Theme.Fonts.Title,
			TextSize = 26,
		}, card)
		UI.Label({
			Position = UDim2.fromOffset(0, 116),
			Size = UDim2.new(1, 0, 0, 14),
			Text = if award.Location == "Postmaster" then "Inventory full: sent to the postmaster" else "",
			TextColor3 = Theme.Colors.Warning,
			TextSize = 11,
		}, card)
	end
	UIState.OpenMenu(MENU)
end

local function equipUpgrades()
	local best: { [string]: AwardView } = {}
	for _, award in current do
		local existing = best[award.Slot]
		if award.Power > equippedPower(award.Slot) and (existing == nil or award.Power > existing.Power) then
			best[award.Slot] = award
		end
	end
	local equipped = 0
	for _, award in best do
		local ok = ClientNet.Invoke("EquipItem", award.Uid)
		if ok then
			equipped += 1
		end
	end
	local data = DataController.GetData()
	local power = if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
	HudController.Toast(
		if equipped > 0 then `Equipped {equipped} upgrade(s). Power {power}` else "Nothing to upgrade",
		"Success"
	)
	UIState.CloseMenu(MENU)
end

local function build()
	gui = UI.Screen("LootScreen", 28)
	gui.Enabled = false
	local backdrop = UI.Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, gui) :: Frame
	-- Title, subtitle, run summary, loot cards and buttons, stacked and
	-- centered (the summary row collapses when there is none).
	local content = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.new(1, -80, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, backdrop) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, content)
	title = UI.Label({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextColor3 = Theme.Colors.Power,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, content)
	subtitle = UI.Label({
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, content)
	statsRow = UI.Make("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		Visible = false,
	}, content) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}, statsRow)
	cards = UI.Make("Frame", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 160),
		BackgroundTransparency = 1,
	}, content) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
	}, cards)

	local buttons = UI.Make("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	}, content) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 16),
	}, buttons)
	local equipButton = UI.Button({
		LayoutOrder = 1,
		Size = UDim2.fromOffset(200, 40),
		Text = "EQUIP UPGRADES",
		BackgroundColor3 = Theme.Colors.Success,
		TextColor3 = Theme.Colors.Backdrop,
	}, buttons)
	equipButton.Activated:Connect(equipUpgrades)
	local closeButton = UI.Button({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(200, 40),
		Text = "CONTINUE  [Space]",
	}, buttons)
	closeButton.Activated:Connect(function()
		UIState.CloseMenu(MENU)
	end)
end

function LootController.Init()
	ClientNet.On("LootAwarded", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local awards = parseAwards(payload)
		if payload.Screen == true then
			if gui then
				showScreen(payload, awards)
			end
			return
		end
		for _, award in awards do
			local rarity = RarityConfig.Tiers[award.Rarity]
			local name = nameOf(award.DefId)
			local upgrade = if award.Power > equippedPower(award.Slot) then "  ▲ upgrade" else ""
			HudController.Toast(
				`◆ {award.Rarity} {name}  ✦{award.Power}{upgrade}`,
				nil,
				if rarity then rarity.Color else nil
			)
		end
	end)
end

function LootController.Start()
	build()
	UIState.MenuChanged:Connect(function(name: string?)
		gui.Enabled = name == MENU
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if gui.Enabled and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonB) then
			UIState.CloseMenu(MENU)
		end
	end)
end

return LootController
