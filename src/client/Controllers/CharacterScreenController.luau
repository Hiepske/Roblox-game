--!strict
--[[
	CharacterScreenController
	Tab or I opens the character screen: live character power, the three
	weapon slots and five armor slots. Each slot shows the equipped item and
	everything else you own for that slot (inventory and postmaster).
	Click an item to equip it; the small x dismantles it for materials.
	Green power numbers mark items that would raise your power.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ClassConfig = require(Config:WaitForChild("ClassConfig"))
local ElementConfig = require(Config:WaitForChild("ElementConfig"))
local InputConfig = require(Config:WaitForChild("InputConfig"))
local PerkConfig = require(Config:WaitForChild("PerkConfig"))
local PowerConfig = require(Config:WaitForChild("PowerConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local ItemCatalog = require(Shared:WaitForChild("Items"):WaitForChild("ItemCatalog"))
local PowerMath = require(Shared:WaitForChild("Power"):WaitForChild("PowerMath"))
local Types = require(Shared:WaitForChild("Types"))
local WeaponStats = require(Shared:WaitForChild("Weapons"):WaitForChild("WeaponStats"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Theme = require(script.Parent.Parent.UI.Theme)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local DataController = require(script.Parent.DataController)

type ItemInstance = Types.ItemInstance

local CharacterScreenController = {}

local MENU = "Character"
local player = Players.LocalPlayer
local gui: ScreenGui
local built = false
local header: TextLabel
local weaponRow: Frame
local armorRow: Frame
local statusLabel: TextLabel
local refreshQueued = false
local busy = false

local function itemName(item: ItemInstance): string
	local entry = ItemCatalog.Get(item.DefId)
	if entry and entry.Weapon then
		return entry.Weapon.Name
	elseif entry and entry.Armor then
		return entry.Armor.Name
	end
	return item.DefId
end

local function itemDetail(item: ItemInstance): string
	local entry = ItemCatalog.Get(item.DefId)
	if item.Kind == "Weapon" then
		local stats = WeaponStats.Compute(item)
		local weapon = if entry then entry.Weapon else nil
		local element = if weapon then ElementConfig.Elements[weapon.Element] else nil
		local perks: { string } = {}
		for _, perkId in item.Perks do
			local perk = PerkConfig.ById[perkId]
			table.insert(perks, if perk then perk.Name else perkId)
		end
		local elementText = if element and weapon then UI.Colored(element.DisplayName, element.Color) else ""
		if stats then
			return `{elementText} {stats.Type}  ·  {math.floor(stats.Damage + 0.5)} dmg  ·  {stats.Rpm} rpm  ·  mag {stats.Magazine}\n{UI.Colored(
				table.concat(perks, ", "),
				Theme.Colors.TextDim
			)}`
		end
		return elementText
	end
	local parts: { string } = {}
	for stat, value in item.Stats do
		table.insert(parts, `{string.sub(stat, 1, 3)} {value}`)
	end
	table.sort(parts)
	return UI.Colored(table.concat(parts, "  "), Theme.Colors.TextDim)
end

local function equip(uid: string)
	if busy then
		return
	end
	busy = true
	local ok, message = ClientNet.Invoke("EquipItem", uid)
	busy = false
	statusLabel.Text = if ok then "" else tostring(message or "Couldn't equip")
	statusLabel.TextColor3 = Theme.Colors.Error
end

local function dismantle(uid: string)
	if busy then
		return
	end
	busy = true
	local ok, message = ClientNet.Invoke("DismantleItem", uid)
	busy = false
	statusLabel.Text = tostring(message or (if ok then "Dismantled" else "Couldn't dismantle"))
	statusLabel.TextColor3 = if ok then Theme.Colors.Success else Theme.Colors.Error
end

local function itemCard(parent: Instance, item: ItemInstance, equipped: boolean, equippedPower: number, order: number)
	local rarity = RarityConfig.Tiers[item.Rarity]
	local color = if rarity then rarity.Color else Theme.Colors.Text
	local card = UI.Make("TextButton", {
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, if equipped then 74 else 50),
		BackgroundColor3 = if equipped then Theme.Colors.PanelRaised else Theme.Colors.Panel,
		BackgroundTransparency = if equipped then 0 else 0.15,
		AutoButtonColor = not equipped,
		Text = "",
	}, parent) :: TextButton
	UI.Corner(card, 4)
	UI.Stroke(card, color, if equipped then 2 else 1, if equipped then 0 else 0.4)
	UI.Make("Frame", {
		Size = UDim2.new(0, 5, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, card)

	local powerColor = if equipped
		then Theme.Colors.Power
		elseif item.Power > equippedPower then Theme.Colors.Success
		else Theme.Colors.TextDim
	local arrow = if not equipped and item.Power > equippedPower then "▲ " else ""
	UI.Label({
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -80, 0, 18),
		Text = itemName(item) .. (if item.Location == "Postmaster" then "  (postmaster)" else ""),
		TextColor3 = color,
		Font = Theme.Fonts.Title,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)
	UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 4),
		Size = UDim2.fromOffset(70, 18),
		Text = `{arrow}{item.Power}`,
		TextColor3 = powerColor,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, card)
	UI.Label({
		Position = UDim2.fromOffset(12, 23),
		Size = UDim2.new(1, -18, 1, -26),
		Text = if equipped then itemDetail(item) else `{item.Rarity}  ·  {(itemDetail(item):split("\n"))[1]}`,
		TextSize = 12,
		RichText = true,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Theme.Colors.Text,
	}, card)

	if not equipped then
		card.Activated:Connect(function()
			equip(item.Uid)
		end)
		local scrap = UI.Button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(20, 20),
			Text = "x",
			TextSize = 13,
			BackgroundColor3 = Color3.fromRGB(90, 35, 35),
		}, card)
		scrap.Activated:Connect(function()
			dismantle(item.Uid)
		end)
	end
end

local function slotColumn(parent: Frame, slot: string, data: Types.ProfileData, order: number, width: number)
	local column = UI.Make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(width, -8, 1, 0),
		BackgroundTransparency = 1,
	}, parent) :: Frame
	UI.Label({
		Size = UDim2.new(1, 0, 0, 18),
		Text = string.upper(if slot == "ClassItem" then "Class Item" else slot),
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = Theme.Colors.Accent,
	}, column)

	local list = UI.Make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 1, -22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, column) :: ScrollingFrame
	UI.Make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, list)

	local equippedUid = data.Equipped[slot]
	local equippedItem = if equippedUid then data.Items[equippedUid] else nil
	local equippedPower = if equippedItem then equippedItem.Power else 0
	if equippedItem then
		itemCard(list, equippedItem, true, equippedPower, 0)
	end
	local others: { ItemInstance } = {}
	for uid, item in data.Items do
		if item.Slot == slot and uid ~= equippedUid and item.Location ~= "Vault" then
			table.insert(others, item)
		end
	end
	table.sort(others, function(a: ItemInstance, b: ItemInstance): boolean
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return a.Uid < b.Uid
	end)
	for index, item in others do
		itemCard(list, item, false, equippedPower, index)
	end
	if #others == 0 then
		UI.Label({
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Text = "Nothing else for this slot yet",
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
		}, list)
	end
end

function CharacterScreenController.Refresh()
	refreshQueued = false
	if not built or not gui.Enabled then
		return
	end
	local data = DataController.GetData()
	if data == nil then
		return
	end
	for _, row in { weaponRow, armorRow } do
		for _, child in row:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	local power = PowerMath.CharacterPower(data.Items, data.Equipped)
	local highest = PowerMath.HighestPossible(data.Items)
	local class = ClassConfig.ById[data.Class]
	local stage = PowerMath.Stage(power)
	local stageText = if stage == "SoftCap"
		then `Any drop can raise you until {PowerConfig.SoftCap}`
		elseif stage == "Powerful" then `Powerful rewards raise you until {PowerConfig.PowerfulCap}`
		elseif stage == "Pinnacle" then `Only Pinnacle rewards raise you until {PowerConfig.PinnacleCap}`
		else "Maximum power"
	header.Text = `{UI.Colored("✦ " .. power, Theme.Colors.Power)}   <font size="16">{if class
		then class.Name
		else data.Class}  ·  highest possible {highest}  ·  {stageText}</font>`

	for index, slot in PowerConfig.WeaponSlots do
		slotColumn(weaponRow, slot, data, index, 1 / #PowerConfig.WeaponSlots)
	end
	for index, slot in PowerConfig.ArmorSlots do
		slotColumn(armorRow, slot, data, index, 1 / #PowerConfig.ArmorSlots)
	end
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(CharacterScreenController.Refresh)
end

local function build()
	gui = UI.Screen("CharacterScreen", 25)
	gui.Enabled = false
	local backdrop = UI.Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, gui) :: Frame
	UI.Padding(backdrop, 28)

	UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = `CHARACTER  ·  [Tab/I] close  ·  click an item to equip, x to dismantle`,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 13,
	}, backdrop)
	header = UI.Label({
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.Fonts.Title,
		TextSize = 34,
		RichText = true,
	}, backdrop)

	weaponRow = UI.Make("Frame", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0.52, -60),
		BackgroundTransparency = 1,
	}, backdrop) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, weaponRow)

	armorRow = UI.Make("Frame", {
		Position = UDim2.new(0, 0, 0.52, 20),
		Size = UDim2.new(1, 0, 0.48, -50),
		BackgroundTransparency = 1,
	}, backdrop) :: Frame
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, armorRow)

	statusLabel = UI.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 14,
		RichText = true,
	}, backdrop)
	built = true
end

function CharacterScreenController.Init() end

function CharacterScreenController.Start()
	build()
	UIState.MenuChanged:Connect(function(name: string?)
		gui.Enabled = name == MENU
		if gui.Enabled then
			statusLabel.Text = ""
			CharacterScreenController.Refresh()
		end
	end)
	DataController.Changed:Connect(queueRefresh)

	local keys = {
		InputConfig.Keyboard.CharacterScreen,
		InputConfig.Keyboard.CharacterScreenAlt,
		InputConfig.Gamepad.CharacterScreen,
	}
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UIState.IsDead() then
			return
		end
		if table.find(keys, input.KeyCode.Name) then
			UIState.ToggleMenu(MENU)
		end
	end)
	player.CharacterRemoving:Connect(function()
		if UIState.GetOpenMenu() == MENU then
			UIState.CloseMenu(MENU)
		end
	end)
end

return CharacterScreenController
