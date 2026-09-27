--!strict
--[[
	LootController
	Shows gear the server awarded (LootAwarded):
	  * end of an activity: a loot screen with one card per item, colored by
	    rarity, with its power, why it dropped (Powerful, Pinnacle, raid
	    exclusive) and whether it's an upgrade. "Equip upgrades" equips every
	    reward that beats what you're wearing.
	  * mid-activity drops: a toast per item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
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
local cards: Frame
local current: { AwardView } = {}

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

local function showScreen(payload: any, awards: { AwardView })
	current = awards
	for _, child in cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	title.Text = string.upper(tostring(payload.Title or "Rewards"))
	local power = tonumber(payload.Power) or 0
	local highest = tonumber(payload.HighestPower) or power
	subtitle.Text = if highest > power
		then `Power {power}  ·  equip your upgrades to reach {highest}`
		else `Power {power}`

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
	title = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		TextColor3 = Theme.Colors.Power,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, backdrop)
	subtitle = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.18, 44),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, backdrop)
	cards = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.new(1, -80, 0, 160),
		BackgroundTransparency = 1,
	}, backdrop) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 14),
	}, cards)

	local equipButton = UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -8, 0.34, 190),
		Size = UDim2.fromOffset(200, 40),
		Text = "EQUIP UPGRADES",
		BackgroundColor3 = Theme.Colors.Success,
		TextColor3 = Theme.Colors.Backdrop,
	}, backdrop)
	equipButton.Activated:Connect(equipUpgrades)
	local closeButton = UI.Button({
		Position = UDim2.new(0.5, 8, 0.34, 190),
		Size = UDim2.fromOffset(200, 40),
		Text = "CONTINUE  [Space]",
	}, backdrop)
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
