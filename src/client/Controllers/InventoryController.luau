--!strict
--[[
	InventoryController
	The full inventory (Tab or I; the Vault terminal, Postmaster and
	Gunsmith in the hub open it on their tab).

	  Top      power (live), highest possible power, class, currencies, tabs
	  Left     the three weapon slots: equipped item + up to 9 spares each
	  Center   your character (ViewportFrame) and the detail panel
	  Right    the five armor slots: equipped item + spares
	  Bottom   loadouts (apply / save), rarity filters, type filter, sort
	  Tabs     Character, Vault (200 slots, move items both ways),
	           Postmaster (overflow drops; collect in the hub)

	Mouse: hover an item for details (compared with what you're wearing),
	click to equip (or move, on the Vault/Postmaster tabs), right-click to
	lock. Hold the Dismantle button for one second to dismantle.
	Gamepad: D-pad moves, A equips/moves, X locks, hold Y dismantles,
	LB/RB switch tabs, B closes. Touch: tap to select, then use the buttons.
	The server validates everything (InventoryService).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ArmorConfig = require(Config:WaitForChild("ArmorConfig"))
local ClassConfig = require(Config:WaitForChild("ClassConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local ElementConfig = require(Config:WaitForChild("ElementConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))
local InputConfig = require(Config:WaitForChild("InputConfig"))
local PerkConfig = require(Config:WaitForChild("PerkConfig"))
local PowerConfig = require(Config:WaitForChild("PowerConfig"))
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local WeaponTypeConfig = require(Config:WaitForChild("WeaponTypeConfig"))
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

local InventoryController = {}

local MENU = "Inventory"
local player = Players.LocalPlayer

local GLYPHS: { [string]: string } = {
	AutoRifle = "AR",
	PulseRifle = "PR",
	ScoutRifle = "SR",
	HandCannon = "HC",
	SMG = "SMG",
	Sidearm = "SA",
	Shotgun = "SG",
	SniperRifle = "SN",
	FusionRifle = "FR",
	GrenadeLauncher = "GL",
	RocketLauncher = "RL",
	Sword = "SW",
	MachineGun = "MG",
	Helmet = "HLM",
	Arms = "ARM",
	Chest = "CHS",
	Legs = "LEG",
	ClassItem = "CLS",
}
local RARITY_RANK: { [string]: number } = { Rare = 1, Epic = 2, Legendary = 3, Exotic = 4 }
local SORTS = { "Power", "Rarity", "Newest" }
local TABS = { "Character", "Vault", "Postmaster" }

type State = {
	Tab: string,
	Infuse: boolean,
	Selected: string?,
	Sort: string,
	Rarities: { [string]: boolean },
	TypeFilter: string,
	LastInput: string,
}

local state: State = {
	Tab = "Character",
	Infuse = false,
	Selected = nil,
	Sort = "Power",
	Rarities = { Rare = true, Epic = true, Legendary = true, Exotic = true },
	TypeFilter = "All",
	LastInput = "Mouse",
}

type Refs = {
	Gui: ScreenGui,
	Power: TextLabel,
	Header: TextLabel,
	Currencies: TextLabel,
	TabButtons: { [string]: TextButton },
	Weapons: Frame,
	Armor: Frame,
	Center: Frame,
	Storage: Frame,
	Viewport: ViewportFrame,
	Detail: Frame,
	Status: TextLabel,
	Bottom: Frame,
	SortButton: TextButton,
	TypeButton: TextButton,
	RarityButtons: { [string]: TextButton },
}

local refs: Refs
local built = false
local refreshQueued = false
local busy = false
local tiles: { [string]: TextButton } = {}
local avatar: Model? = nil
local avatarAngle = 0

-- Item info ----------------------------------------------------------------------------------

type Info = {
	Name: string,
	Kind: string,
	Type: string,
	Flavor: string,
	Element: string?,
	ElementColor: Color3?,
	RarityColor: Color3,
	Glyph: string,
}

local function infoOf(item: ItemInstance): Info
	local entry = ItemCatalog.Get(item.DefId)
	local rarity = RarityConfig.Tiers[item.Rarity]
	local color = if rarity then rarity.Color else Theme.Colors.Text
	if entry and entry.Weapon then
		local weapon = entry.Weapon
		local element = ElementConfig.Elements[weapon.Element]
		local typeDef = (WeaponTypeConfig.Types :: any)[weapon.Type]
		return {
			Name = weapon.Name,
			Kind = "Weapon",
			Type = if typeDef and typeDef.DisplayName then typeDef.DisplayName else weapon.Type,
			Flavor = weapon.Flavor,
			Element = if element then element.DisplayName else weapon.Element,
			ElementColor = if element then element.Color else nil,
			RarityColor = color,
			Glyph = GLYPHS[weapon.Type] or "?",
		}
	elseif entry and entry.Armor then
		local armor = entry.Armor
		return {
			Name = armor.Name,
			Kind = "Armor",
			Type = if armor.Slot == "ClassItem" then "Class Item" else armor.Slot,
			Flavor = armor.Flavor,
			Element = nil,
			ElementColor = nil,
			RarityColor = color,
			Glyph = GLYPHS[armor.Slot] or "?",
		}
	end
	return {
		Name = item.DefId,
		Kind = item.Kind,
		Type = item.Slot,
		Flavor = "",
		Element = nil,
		ElementColor = nil,
		RarityColor = color,
		Glyph = "?",
	}
end

local function weaponType(item: ItemInstance): string
	local entry = ItemCatalog.Get(item.DefId)
	return if entry and entry.Weapon then entry.Weapon.Type else item.Slot
end

local function passesFilters(item: ItemInstance): boolean
	if not state.Rarities[item.Rarity] then
		return false
	end
	if state.TypeFilter ~= "All" and weaponType(item) ~= state.TypeFilter then
		return false
	end
	return true
end

local function sortItems(items: { ItemInstance })
	table.sort(items, function(a: ItemInstance, b: ItemInstance): boolean
		if state.Sort == "Rarity" then
			local ra, rb = RARITY_RANK[a.Rarity] or 0, RARITY_RANK[b.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
		elseif state.Sort == "Newest" then
			if a.AcquiredAt ~= b.AcquiredAt then
				return a.AcquiredAt > b.AcquiredAt
			end
		end
		if a.Power ~= b.Power then
			return a.Power > b.Power
		end
		return a.Uid < b.Uid
	end)
end

local function equippedIn(data: Types.ProfileData, slot: string): ItemInstance?
	local uid = data.Equipped[slot]
	return if uid then data.Items[uid] else nil
end

-- Actions --------------------------------------------------------------------------------------

local function setStatus(text: string, good: boolean?)
	if built then
		refs.Status.Text = text
		refs.Status.TextColor3 = if good == false
			then Theme.Colors.Error
			elseif good == true then Theme.Colors.Success
			else Theme.Colors.TextDim
	end
end

local function call(remote: string, ...: any)
	if busy then
		return
	end
	busy = true
	local ok, message = ClientNet.Invoke(remote, ...)
	busy = false
	if message then
		setStatus(tostring(message), ok == true)
	elseif not ok then
		setStatus("That didn't work", false)
	end
	return ok
end

local function equip(uid: string)
	call("EquipItem", uid)
end

local function toggleLock(uid: string)
	call("ToggleLock", uid)
end

local function dismantle(uid: string)
	if call("DismantleItem", uid) and state.Selected == uid then
		state.Selected = nil
	end
end

local function transfer(uid: string, destination: string)
	call("TransferItem", uid, destination)
end

-- The best infusion fuel for `item`: the highest-power unlocked, unequipped item of the same slot.
local function bestFuel(data: Types.ProfileData, item: ItemInstance): ItemInstance?
	local best: ItemInstance? = nil
	for uid, other in data.Items do
		if
			uid ~= item.Uid
			and other.Slot == item.Slot
			and other.Kind == item.Kind
			and other.Power > item.Power
			and not other.Locked
		then
			local equipped = false
			for _, equippedUid in data.Equipped do
				if equippedUid == uid then
					equipped = true
				end
			end
			if not equipped and (best == nil or other.Power > best.Power) then
				best = other
			end
		end
	end
	return best
end

local function markSeen(item: ItemInstance)
	if item.Seen == false then
		item.Seen = true -- hide the dot right away; the server confirms
		ClientNet.Fire("MarkSeen", item.Uid)
	end
end

-- Detail panel ----------------------------------------------------------------------------------

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function statBar(parent: Instance, order: number, name: string, value: number, compare: number?, maxValue: number)
	local row = UI.Make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
	}, parent)
	UI.Label({ Size = UDim2.fromOffset(90, 16), Text = name, TextSize = 12, TextColor3 = Theme.Colors.TextDim }, row)
	local back = UI.Make("Frame", {
		Position = UDim2.fromOffset(96, 4),
		Size = UDim2.new(1, -140, 0, 8),
		BackgroundColor3 = Color3.fromRGB(40, 46, 58),
		BorderSizePixel = 0,
	}, row)
	local base = math.clamp(math.min(value, compare or value) / maxValue, 0, 1)
	UI.Make("Frame", {
		Size = UDim2.fromScale(base, 1),
		BackgroundColor3 = Color3.fromRGB(230, 234, 240),
		BorderSizePixel = 0,
	}, back)
	if compare and compare ~= value then
		local low, high = math.min(value, compare) / maxValue, math.max(value, compare) / maxValue
		UI.Make("Frame", {
			Position = UDim2.fromScale(math.clamp(low, 0, 1), 0),
			Size = UDim2.fromScale(math.clamp(high - low, 0, 1), 1),
			BackgroundColor3 = if value > compare then Theme.Colors.Success else Theme.Colors.Error,
			BorderSizePixel = 0,
		}, back)
	end
	local delta = if compare and compare ~= value then value - compare else nil
	UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(40, 16),
		Text = tostring(math.floor(value + 0.5)) .. (if delta then (if delta > 0 then " ▲" else " ▼") else ""),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if delta == nil
			then Theme.Colors.Text
			elseif delta > 0 then Theme.Colors.Success
			else Theme.Colors.Error,
	}, row)
end

local holdToken = 0

-- A button that must be held for `seconds` (dismantle).
local function holdButton(parent: Instance, order: number, text: string, seconds: number, onDone: () -> ()): TextButton
	local button = UI.Button({
		LayoutOrder = order,
		Size = UDim2.fromOffset(120, 30),
		Text = text,
		TextSize = 13,
		BackgroundColor3 = Color3.fromRGB(90, 35, 35),
		ClipsDescendants = true,
	}, parent)
	local fill = UI.Make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Colors.Error,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, button) :: Frame
	local function start()
		holdToken += 1
		local token = holdToken
		fill.Size = UDim2.fromScale(0, 1)
		TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
			:Play()
		task.delay(seconds, function()
			if holdToken == token then
				holdToken += 1
				fill.Size = UDim2.fromScale(0, 1)
				onDone()
			end
		end)
	end
	local function stop()
		holdToken += 1
		fill.Size = UDim2.fromScale(0, 1)
	end
	button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			start()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			stop()
		end
	end)
	button.MouseLeave:Connect(stop)
	return button
end

local function showDetail(uid: string?)
	if not built then
		return
	end
	local detail = refs.Detail
	clear(detail)
	local data = DataController.GetData()
	local item = if data and uid then data.Items[uid] else nil
	if data == nil or item == nil then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 40),
			Text = "Hover or select an item to see its details.",
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, detail)
		return
	end
	markSeen(item)
	local info = infoOf(item)
	local current = equippedIn(data, item.Slot)
	local comparing = current ~= nil and current.Uid ~= item.Uid

	local header = UI.Make("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = info.RarityColor:Lerp(Color3.new(0, 0, 0), 0.35),
		BorderSizePixel = 0,
	}, detail)
	UI.Padding(header, 8)
	UI.Label(
		{ Size = UDim2.new(1, -80, 0, 20), Text = string.upper(info.Name), Font = Theme.Fonts.Title, TextSize = 17 },
		header
	)
	UI.Label({
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, -80, 0, 16),
		Text = `{item.Rarity}  ·  {info.Type}` .. (if info.Element then `  ·  {info.Element}` else ""),
		TextSize = 12,
		TextColor3 = Color3.fromRGB(230, 230, 235),
	}, header)
	local powerDelta = if comparing and current then item.Power - current.Power else 0
	UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(80, 34),
		Text = `✦ {item.Power}`,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Theme.Colors.Power,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, header)
	if powerDelta ~= 0 then
		UI.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 30),
			Size = UDim2.fromOffset(80, 14),
			Text = if powerDelta > 0 then `+{powerDelta}` else tostring(powerDelta),
			TextSize = 12,
			TextColor3 = if powerDelta > 0 then Theme.Colors.Success else Theme.Colors.Error,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, header)
	end

	local body = UI.Make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -94),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, detail)
	UI.Padding(body, 6)
	UI.Make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, body)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	if info.Flavor ~= "" then
		UI.Label({
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = `"{info.Flavor}"`,
			TextWrapped = true,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
		}, body)
	end

	if item.Kind == "Weapon" then
		local final = WeaponStats.FinalStats(item)
		local compareFinal = if comparing and current then WeaponStats.FinalStats(current) else nil
		for _, stat in WeaponTypeConfig.RolledStats do
			statBar(body, nextOrder(), stat, final[stat] or 0, if compareFinal then compareFinal[stat] else nil, 100)
		end
		local stats = WeaponStats.Compute(item)
		local compareStats = if comparing and current then WeaponStats.Compute(current) else nil
		if stats then
			local function number(label: string, value: number, other: number?)
				local delta = if other and other ~= value then value - other else nil
				UI.Label({
					LayoutOrder = nextOrder(),
					Size = UDim2.new(1, 0, 0, 16),
					RichText = true,
					Text = `{label}  <b>{math.floor(value + 0.5)}</b>` .. (if delta
						then UI.Colored(
							`  ({if delta > 0 then "+" else ""}{math.floor(delta + 0.5)})`,
							if delta > 0 then Theme.Colors.Success else Theme.Colors.Error
						)
						else ""),
					TextSize = 12,
				}, body)
			end
			number("Rounds per minute", stats.Rpm, if compareStats then compareStats.Rpm else nil)
			number("Magazine", stats.Magazine, if compareStats then compareStats.Magazine else nil)
			number("Damage per shot", stats.Damage, if compareStats then compareStats.Damage else nil)
		end
	else
		for _, stat in ArmorConfig.StatOrder do
			local def = ArmorConfig.Stats[stat]
			statBar(
				body,
				nextOrder(),
				if def then def.DisplayName else stat,
				item.Stats[stat] or 0,
				if comparing and current then current.Stats[stat] or 0 else nil,
				30
			)
		end
	end

	for _, perkId in item.Perks do
		local perk = PerkConfig.ById[perkId]
		if perk then
			UI.Label({
				LayoutOrder = nextOrder(),
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				RichText = true,
				TextWrapped = true,
				Text = `{UI.Colored(
					perk.Name,
					if perk.Column == "Exotic" then RarityConfig.Tiers.Exotic.Color else Theme.Colors.Accent
				)}  {perk.Description}`,
				TextSize = 12,
			}, body)
		end
	end
	if item.Masterwork then
		UI.Label({
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 16),
			Text = `Masterwork: {item.Masterwork}`,
			TextSize = 12,
			TextColor3 = Theme.Colors.Power,
		}, body)
	end

	-- Actions.
	local actions = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	}, detail)
	UI.Make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, actions)
	local isEquipped = current ~= nil and current.Uid == item.Uid
	local function action(orderIndex: number, text: string, color: Color3?, onClick: () -> ())
		local button = UI.Button({
			LayoutOrder = orderIndex,
			Size = UDim2.fromOffset(96, 30),
			Text = text,
			TextSize = 13,
			BackgroundColor3 = color or Theme.Colors.PanelRaised,
		}, actions)
		button.Activated:Connect(function()
			onClick()
		end)
	end
	if not isEquipped then
		action(1, "Equip", Color3.fromRGB(40, 110, 80), function()
			equip(item.Uid)
		end)
	end
	action(2, if item.Locked then "Unlock" else "Lock", nil, function()
		toggleLock(item.Uid)
	end)
	if item.Location == "Vault" then
		action(3, "To character", nil, function()
			transfer(item.Uid, "Inventory")
		end)
	elseif item.Location == "Postmaster" then
		action(3, "Collect", nil, function()
			transfer(item.Uid, "Inventory")
		end)
	elseif not isEquipped then
		action(3, "To vault", nil, function()
			transfer(item.Uid, "Vault")
		end)
	end
	if not isEquipped and not item.Locked then
		holdButton(actions, 4, "Hold: Dismantle", 1, function()
			dismantle(item.Uid)
		end)
	end
	if state.Infuse then
		local fuel = bestFuel(data, item)
		if fuel then
			local cost: { [string]: number } = EconomyConfig.Infusion[item.Rarity] or {}
			local parts: { string } = {}
			for currency, amount in cost do
				table.insert(parts, `{amount} {currency}`)
			end
			table.sort(parts)
			action(5, `Infuse → {fuel.Power}`, Theme.Colors.Power:Lerp(Color3.new(0, 0, 0), 0.4), function()
				call("InfuseItem", item.Uid, fuel.Uid)
			end)
			setStatus(`Infuse uses {infoOf(fuel).Name} (✦{fuel.Power}) and costs {table.concat(parts, ", ")}`)
		end
	end
end

-- Tiles ----------------------------------------------------------------------------------------

local function select(uid: string?)
	state.Selected = uid
	showDetail(uid)
end

local function primaryAction(item: ItemInstance)
	if state.Tab == "Character" then
		equip(item.Uid)
	elseif state.Tab == "Vault" then
		transfer(item.Uid, if item.Location == "Vault" then "Inventory" else "Vault")
	else
		transfer(item.Uid, "Inventory")
	end
end

local function tile(item: ItemInstance, size: number, parent: Instance, order: number, equipped: boolean): TextButton
	local info = infoOf(item)
	local button = UI.Make("TextButton", {
		Name = item.Uid,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = info.RarityColor:Lerp(Color3.fromRGB(12, 14, 20), 0.62),
		AutoButtonColor = true,
		Text = "",
		Selectable = true,
	}, parent) :: TextButton
	UI.Corner(button, 4)
	UI.Stroke(button, if equipped then Color3.new(1, 1, 1) else info.RarityColor, if equipped then 3 else 2)
	UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.9, 0.4),
		Text = info.Glyph,
		Font = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(235, 238, 245),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, button)
	UI.Label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -3, 1, -1),
		Size = UDim2.new(1, 0, 0, math.max(11, size * 0.22)),
		Text = tostring(item.Power),
		Font = Theme.Fonts.Title,
		TextScaled = true,
		TextColor3 = Theme.Colors.Power,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, button)
	if info.ElementColor and info.Element ~= "Kinetic" then
		local dot = UI.Make("Frame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = info.ElementColor,
			BorderSizePixel = 0,
		}, button)
		UI.Corner(dot, 4)
	end
	if item.Rarity == "Exotic" then
		UI.Label({
			Position = UDim2.fromOffset(3, size - 16),
			Size = UDim2.fromOffset(14, 14),
			Text = "★",
			TextColor3 = RarityConfig.Tiers.Exotic.Color,
			TextSize = 12,
		}, button)
	end
	if item.Seen == false then
		local new = UI.Make("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = Theme.Colors.Warning,
			BorderSizePixel = 0,
		}, button)
		UI.Corner(new, 5)
	end
	if item.Locked then
		UI.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, if item.Seen == false then 14 else 2),
			Size = UDim2.fromOffset(14, 14),
			Text = "🔒",
			TextSize = 10,
		}, button)
	end

	button.MouseEnter:Connect(function()
		if state.LastInput == "Mouse" then
			showDetail(item.Uid)
		end
	end)
	button.MouseLeave:Connect(function()
		if state.LastInput == "Mouse" then
			showDetail(state.Selected)
		end
	end)
	button.SelectionGained:Connect(function()
		state.Selected = item.Uid
		showDetail(item.Uid)
	end)
	button.Activated:Connect(function()
		if state.LastInput == "Touch" then
			select(item.Uid)
		else
			state.Selected = item.Uid
			primaryAction(item)
		end
	end)
	button.MouseButton2Click:Connect(function()
		toggleLock(item.Uid)
	end)
	tiles[item.Uid] = button
	return button
end

-- Panels ----------------------------------------------------------------------------------------

local function slotLabel(slot: string): string
	return string.upper(if slot == "ClassItem" then "Class Item" else slot)
end

local function spares(data: Types.ProfileData, slot: string): { ItemInstance }
	local list: { ItemInstance } = {}
	local equippedUid = data.Equipped[slot]
	for uid, item in data.Items do
		if item.Slot == slot and item.Location == "Inventory" and uid ~= equippedUid and passesFilters(item) then
			table.insert(list, item)
		end
	end
	sortItems(list)
	return list
end

local function slotRow(
	parent: Instance,
	data: Types.ProfileData,
	slot: string,
	order: number,
	big: number,
	small: number,
	columns: number
)
	local rows = math.ceil(GameConfig.Inventory.SlotCapacity / columns)
	local height = math.max(big, rows * (small + 6)) + 22
	local row = UI.Make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
	}, parent)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 18),
		Text = slotLabel(slot),
		Font = Theme.Fonts.Title,
		TextSize = 13,
		TextColor3 = Theme.Colors.Accent,
	}, row)
	local equipped = equippedIn(data, slot)
	if equipped then
		local holder = UI.Make("Frame", {
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.fromOffset(big, big),
			BackgroundTransparency = 1,
		}, row)
		tile(equipped, big, holder, 0, true)
	else
		UI.Label({
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.fromOffset(big, big),
			Text = "empty",
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0.6,
			BackgroundColor3 = Theme.Colors.PanelRaised,
		}, row)
	end
	local grid = UI.Make("Frame", {
		Position = UDim2.fromOffset(big + 12, 22),
		Size = UDim2.new(1, -(big + 12), 0, height - 22),
		BackgroundTransparency = 1,
	}, row)
	UI.Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(small, small),
		CellPadding = UDim2.fromOffset(6, 6),
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	for index, item in spares(data, slot) do
		tile(item, small, grid, index, false)
	end
end

local function storageGrid(parent: Instance, title: string, items: { ItemInstance }, capacity: number, size: number)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = `{title}  ({#items}/{capacity})`,
		Font = Theme.Fonts.Title,
		TextSize = 15,
		TextColor3 = Theme.Colors.Accent,
	}, parent)
	local scroll = UI.Make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
	UI.Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(size, size),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	for index, item in items do
		tile(item, size, scroll, index, false)
	end
	if #items == 0 then
		UI.Label(
			{ Size = UDim2.fromOffset(300, 30), Text = "Nothing here.", TextColor3 = Theme.Colors.TextDim },
			scroll
		)
	end
end

local function located(data: Types.ProfileData, location: string, onlyUnequipped: boolean): { ItemInstance }
	local list: { ItemInstance } = {}
	for uid, item in data.Items do
		if item.Location == location and passesFilters(item) then
			local equipped = false
			if onlyUnequipped then
				for _, equippedUid in data.Equipped do
					if equippedUid == uid then
						equipped = true
					end
				end
			end
			if not equipped then
				table.insert(list, item)
			end
		end
	end
	sortItems(list)
	return list
end

-- Avatar -----------------------------------------------------------------------------------------

local function refreshAvatar()
	local viewport = refs.Viewport
	local world = viewport:FindFirstChildOfClass("WorldModel")
	if world == nil then
		local created = Instance.new("WorldModel")
		created.Parent = viewport
		world = created
	end
	clear(world :: WorldModel)
	for _, child in (world :: WorldModel):GetChildren() do
		child:Destroy()
	end
	avatar = nil
	local character = player.Character
	if character == nil then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or clone == nil then
		return
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = world
	avatar = clone
	local camera = viewport.CurrentCamera or Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, -11), Vector3.new(0, 0.6, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Render ----------------------------------------------------------------------------------------

function InventoryController.Refresh()
	refreshQueued = false
	if not built or not refs.Gui.Enabled then
		return
	end
	local data = DataController.GetData()
	if data == nil then
		return
	end
	table.clear(tiles)

	local power = PowerMath.CharacterPower(data.Items, data.Equipped)
	local highest = PowerMath.HighestPossible(data.Items)
	refs.Power.Text = `✦ {power}`
	local class = ClassConfig.ById[data.Class]
	refs.Header.Text =
		`{if class then string.upper(class.Name) else data.Class}   ·   highest possible {highest}   ·   {PowerMath.Stage(
			power
		)} stage`
	local money: { string } = {}
	for _, currency in EconomyConfig.Order do
		table.insert(money, `{currency} {data.Currencies[currency] or 0}`)
	end
	refs.Currencies.Text = table.concat(money, "    ")
	for tab, button in refs.TabButtons do
		button.BackgroundColor3 = if tab == state.Tab then Theme.Colors.Accent else Theme.Colors.PanelRaised
		button.TextColor3 = if tab == state.Tab then Theme.Colors.Backdrop else Theme.Colors.Text
	end
	refs.SortButton.Text = `Sort: {state.Sort}`
	refs.TypeButton.Text = if state.TypeFilter == "All"
		then "Type: All"
		else `Type: {GLYPHS[state.TypeFilter] or state.TypeFilter}`
	for rarity, button in refs.RarityButtons do
		local tier = RarityConfig.Tiers[rarity]
		button.BackgroundColor3 = if state.Rarities[rarity] and tier
			then tier.Color:Lerp(Color3.new(0, 0, 0), 0.3)
			else Theme.Colors.PanelRaised
	end

	clear(refs.Weapons)
	clear(refs.Armor)
	clear(refs.Storage)
	local characterTab = state.Tab == "Character"
	refs.Weapons.Visible = characterTab
	refs.Armor.Visible = characterTab
	refs.Storage.Visible = not characterTab
	if characterTab then
		UI.Make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, refs.Weapons)
		UI.Make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, refs.Armor)
		for index, slot in PowerConfig.WeaponSlots do
			slotRow(refs.Weapons, data, slot, index, 92, 58, 3)
		end
		for index, slot in PowerConfig.ArmorSlots do
			slotRow(refs.Armor, data, slot, index, 60, 48, 9)
		end
	elseif state.Tab == "Vault" then
		local left = UI.Make("Frame", { Size = UDim2.new(0.5, -8, 1, 0), BackgroundTransparency = 1 }, refs.Storage)
		local right = UI.Make("Frame", {
			Position = UDim2.new(0.5, 8, 0, 0),
			Size = UDim2.new(0.5, -8, 1, 0),
			BackgroundTransparency = 1,
		}, refs.Storage)
		storageGrid(
			left,
			"ON CHARACTER (click to store)",
			located(data, "Inventory", true),
			GameConfig.Inventory.SlotCapacity * #PowerMath.AllSlots,
			58
		)
		storageGrid(
			right,
			"VAULT (click to take)",
			located(data, "Vault", false),
			GameConfig.Inventory.VaultCapacity,
			58
		)
	else
		storageGrid(
			refs.Storage,
			"POSTMASTER (click to collect, in the hub)",
			located(data, "Postmaster", false),
			GameConfig.Inventory.PostmasterCapacity,
			64
		)
	end
	showDetail(state.Selected)
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(InventoryController.Refresh)
end

local function setTab(tab: string)
	state.Tab = tab
	state.Selected = nil
	queueRefresh()
end

-- Build ------------------------------------------------------------------------------------------

local function build()
	local gui = UI.Screen("Inventory", 25)
	gui.Enabled = false
	local backdrop = UI.Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, gui) :: Frame
	UI.Make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(18, 26, 40), Color3.fromRGB(6, 8, 12)),
		Rotation = 90,
	}, backdrop)

	local root = UI.Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1760, 980),
		BackgroundTransparency = 1,
	}, gui) :: Frame
	local scale = UI.Make("UIScale", { Scale = 1 }, root) :: UIScale
	local function fit()
		local viewport = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, viewport.X / 1800, viewport.Y / 1010)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- Top bar.
	local power = UI.Label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(260, 56),
		Font = Theme.Fonts.Title,
		TextSize = 50,
		TextColor3 = Theme.Colors.Power,
	}, root)
	local header = UI.Label({
		Position = UDim2.fromOffset(262, 8),
		Size = UDim2.fromOffset(760, 22),
		TextSize = 16,
		TextColor3 = Theme.Colors.Text,
	}, root)
	local currencies = UI.Label({
		Position = UDim2.fromOffset(262, 32),
		Size = UDim2.fromOffset(760, 20),
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
	}, root)
	local tabButtons: { [string]: TextButton } = {}
	for index, tab in TABS do
		local button = UI.Button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(3 - index) * 150 - 60, 0, 8),
			Size = UDim2.fromOffset(140, 36),
			Text = string.upper(tab),
			TextSize = 14,
		}, root)
		button.Activated:Connect(function()
			setTab(tab)
		end)
		tabButtons[tab] = button
	end
	local close = UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.fromOffset(44, 36),
		Text = "X",
	}, root)
	close.Activated:Connect(function()
		UIState.CloseMenu(MENU)
	end)

	-- Body columns.
	local weapons = UI.Make("Frame", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.fromOffset(520, 800),
		BackgroundTransparency = 1,
	}, root) :: Frame
	local center = UI.Make("Frame", {
		Position = UDim2.fromOffset(540, 70),
		Size = UDim2.fromOffset(560, 800),
		BackgroundTransparency = 1,
	}, root) :: Frame
	local armor = UI.Make("Frame", {
		Position = UDim2.fromOffset(1120, 70),
		Size = UDim2.fromOffset(640, 800),
		BackgroundTransparency = 1,
	}, root) :: Frame
	local storage = UI.Make("Frame", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.fromOffset(1100, 800),
		BackgroundTransparency = 1,
		Visible = false,
	}, root) :: Frame

	local viewport = UI.Make("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundColor3 = Color3.fromRGB(14, 20, 30),
		BackgroundTransparency = 0.2,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1, -1),
	}, center) :: ViewportFrame
	UI.Corner(viewport, 8)
	local detail = UI.Panel({
		Position = UDim2.fromOffset(0, 340),
		Size = UDim2.new(1, 0, 0, 450),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
	}, center)
	UI.Stroke(detail, Theme.Colors.Stroke, 1, 0.3)
	UI.Padding(detail, 8)

	-- Bottom bar: loadouts, filters, sort, status.
	local bottom = UI.Make("Frame", {
		Position = UDim2.fromOffset(0, 880),
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 1,
	}, root) :: Frame
	UI.Label({
		Size = UDim2.fromOffset(200, 18),
		Text = "LOADOUTS",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
	}, bottom)
	for index = 1, 3 do
		local applyButton = UI.Button({
			Position = UDim2.fromOffset((index - 1) * 150, 22),
			Size = UDim2.fromOffset(96, 34),
			Text = `Loadout {index}`,
			TextSize = 13,
		}, bottom)
		applyButton.Activated:Connect(function()
			call("ApplyLoadout", index)
		end)
		local saveButton = UI.Button({
			Position = UDim2.fromOffset((index - 1) * 150 + 100, 22),
			Size = UDim2.fromOffset(40, 34),
			Text = "Save",
			TextSize = 11,
			BackgroundColor3 = Color3.fromRGB(40, 70, 60),
		}, bottom)
		saveButton.Activated:Connect(function()
			call("SaveLoadout", index)
		end)
	end
	UI.Label({
		Position = UDim2.fromOffset(470, 0),
		Size = UDim2.fromOffset(200, 18),
		Text = "SHOW",
		Font = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
	}, bottom)
	local rarityButtons: { [string]: TextButton } = {}
	for index, rarity in RarityConfig.Order do
		local button = UI.Button({
			Position = UDim2.fromOffset(470 + (index - 1) * 94, 22),
			Size = UDim2.fromOffset(88, 34),
			Text = rarity,
			TextSize = 12,
		}, bottom)
		button.Activated:Connect(function()
			state.Rarities[rarity] = not state.Rarities[rarity]
			queueRefresh()
		end)
		rarityButtons[rarity] = button
	end
	local typeButton = UI.Button({
		Position = UDim2.fromOffset(860, 22),
		Size = UDim2.fromOffset(120, 34),
		Text = "Type: All",
		TextSize = 12,
	}, bottom)
	typeButton.Activated:Connect(function()
		local types = { "All" }
		for _, weaponTypeId in WeaponTypeConfig.Order do
			table.insert(types, weaponTypeId)
		end
		local index = table.find(types, state.TypeFilter) or 1
		state.TypeFilter = types[index % #types + 1]
		queueRefresh()
	end)
	local sortButton = UI.Button({
		Position = UDim2.fromOffset(990, 22),
		Size = UDim2.fromOffset(130, 34),
		Text = "Sort: Power",
		TextSize = 12,
	}, bottom)
	sortButton.Activated:Connect(function()
		local index = table.find(SORTS, state.Sort) or 1
		state.Sort = SORTS[index % #SORTS + 1]
		queueRefresh()
	end)
	local status = UI.Label({
		Position = UDim2.fromOffset(1140, 22),
		Size = UDim2.fromOffset(620, 34),
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = Theme.Colors.TextDim,
	}, bottom)
	UI.Label({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "Hover: details  ·  Click: equip / move  ·  Right-click: lock  ·  Gamepad: A equip, X lock, LB/RB tabs, B close  ·  [Tab/I] close",
		TextSize = 11,
		TextColor3 = Theme.Colors.TextDim,
	}, bottom)

	refs = {
		Gui = gui,
		Power = power,
		Header = header,
		Currencies = currencies,
		TabButtons = tabButtons,
		Weapons = weapons,
		Armor = armor,
		Center = center,
		Storage = storage,
		Viewport = viewport,
		Detail = detail,
		Status = status,
		Bottom = bottom,
		SortButton = sortButton,
		TypeButton = typeButton,
		RarityButtons = rarityButtons,
	}
	built = true
end

-- Open / close ----------------------------------------------------------------------------------

local function onOpened()
	setStatus(if state.Infuse then "Gunsmith: pick an item to infuse. The best fuel is chosen for you." else "")
	refreshAvatar()
	InventoryController.Refresh()
	if state.LastInput == "Gamepad" then
		local data = DataController.GetData()
		local first = if data then data.Equipped.Kinetic else nil
		local button = if first then tiles[first] else nil
		if button then
			GuiService.SelectedObject = button
		end
	end
end

function InventoryController.Open(tab: string?)
	state.Infuse = tab == "Infuse"
	state.Tab = if tab == "Vault" or tab == "Postmaster" then tab else "Character"
	state.Selected = nil
	if UIState.GetOpenMenu() == MENU then
		onOpened()
	else
		UIState.OpenMenu(MENU)
	end
end

function InventoryController.Init()
	ClientNet.On("OpenMenu", function(menu: any, tab: any)
		if menu == "Inventory" and not UIState.IsDead() then
			InventoryController.Open(if type(tab) == "string" then tab else nil)
		end
	end)
end

function InventoryController.Start()
	build()
	UIState.MenuChanged:Connect(function(name: string?)
		local open = name == MENU
		refs.Gui.Enabled = open
		if open then
			onOpened()
		else
			state.Infuse = false
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(refs.Gui) then
				GuiService.SelectedObject = nil
			end
		end
	end)
	DataController.Changed:Connect(queueRefresh)

	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if inputType == Enum.UserInputType.Touch then
			state.LastInput = "Touch"
		elseif string.find(inputType.Name, "Gamepad") then
			state.LastInput = "Gamepad"
		elseif
			inputType == Enum.UserInputType.MouseMovement
			or inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.Keyboard
		then
			state.LastInput = "Mouse"
		end
	end)

	local keys = {
		InputConfig.Keyboard.CharacterScreen,
		InputConfig.Keyboard.CharacterScreenAlt,
		InputConfig.Gamepad.CharacterScreen,
	}
	local yHeldToken = 0
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		local open = UIState.GetOpenMenu() == MENU
		if table.find(keys, input.KeyCode.Name) and not gameProcessed and not UIState.IsDead() then
			if open then
				UIState.CloseMenu(MENU)
			else
				InventoryController.Open(nil)
			end
			return
		end
		if not open then
			return
		end
		local selected = state.Selected
		if input.KeyCode == Enum.KeyCode.ButtonB then
			UIState.CloseMenu(MENU)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
			local index = table.find(TABS, state.Tab) or 1
			local step = if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1
			setTab(TABS[(index - 1 + step) % #TABS + 1])
		elseif input.KeyCode == Enum.KeyCode.ButtonX and selected then
			toggleLock(selected)
		elseif input.KeyCode == Enum.KeyCode.ButtonY and selected then
			yHeldToken += 1
			local token = yHeldToken
			setStatus("Keep holding Y to dismantle...")
			task.delay(1, function()
				if yHeldToken == token and state.Selected == selected then
					dismantle(selected)
				end
			end)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.ButtonY then
			yHeldToken += 1
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local model = avatar
		if model and refs.Gui.Enabled then
			avatarAngle = (avatarAngle + dt * 0.4) % (math.pi * 2)
			model:PivotTo(CFrame.Angles(0, math.pi + math.sin(avatarAngle) * 0.6, 0))
		end
	end)
	player.CharacterAdded:Connect(function()
		if UIState.GetOpenMenu() == MENU then
			task.wait(1)
			refreshAvatar()
		end
	end)
end

return InventoryController
