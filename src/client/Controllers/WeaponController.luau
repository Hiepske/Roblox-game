--!strict
--[[
	WeaponController
	Client side of shooting.

	  Left click     fire (hold for automatic weapons)
	  Right click    aim down sights
	  R              reload
	  1 / 2 / 3      kinetic / energy / heavy weapon
	  (gamepad: R2 fire, L2 aim, X reload, Y cycle; touch: on-screen buttons)

	The client predicts ammo and fire rate for responsiveness and draws its
	own tracer, muzzle flash and recoil immediately. The aim point comes from
	a ray through the screen center (with spread). The server re-checks
	everything (WeaponService) and sends WeaponState back to correct ammo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AssetIds = require(Config:WaitForChild("AssetIds"))
local ElementConfig = require(Config:WaitForChild("ElementConfig"))
local InputConfig = require(Config:WaitForChild("InputConfig"))
local WeaponStats = require(Shared:WaitForChild("Weapons"):WaitForChild("WeaponStats"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UI = require(script.Parent.Parent.UI.UI)
local UIState = require(script.Parent.Parent.UI.UIState)
local CameraController = require(script.Parent.CameraController)
local DataController = require(script.Parent.DataController)
local EffectsController = require(script.Parent.EffectsController)

export type SlotInfo = {
	Uid: string,
	Mag: number,
	Reserve: number?,
	Reloading: boolean?,
}

local WeaponController = {}

local SLOTS = { "Kinetic", "Energy", "Heavy" }
local player = Players.LocalPlayer

local active = "Kinetic"
local slots: { [string]: SlotInfo } = {}
local statsCache: { [string]: WeaponStats.WeaponStats } = {}
local fireHeld = false
local semiReady = true
local aiming = false
local nextFireAt = 0
local reloadingUntil = 0
local reloadDuration = 0
local swapReadyAt = 0
local bloom = 0
local shotId = 0
local baseWalkSpeed: number? = nil
local holdTrack: AnimationTrack? = nil
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

-- Placeholder-safe weapon sound id (0 when the type has no such sound).
local function weaponSound(weaponType: string, key: string): number
	local set = (AssetIds.Sounds.Weapons :: any)[weaponType]
	return if set and type(set[key]) == "number" then set[key] else 0
end

-- Input mapping ------------------------------------------------------------------

local function matches(input: InputObject, name: string?): boolean
	if name == nil then
		return false
	end
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and keyCode and input.KeyCode == keyCode then
		return true
	end
	local okType, inputType = pcall(function()
		return (Enum.UserInputType :: any)[name]
	end)
	return okType and inputType ~= nil and input.UserInputType == inputType
end

local function isAction(input: InputObject, action: string): boolean
	local data = DataController.GetData()
	local override = if data then data.Settings.Keybinds[action] else nil
	return matches(input, override or InputConfig.Keyboard[action]) or matches(input, InputConfig.Gamepad[action])
end

-- Stats ------------------------------------------------------------------------------

function WeaponController.GetStats(slot: string): WeaponStats.WeaponStats?
	local info = slots[slot]
	if info == nil then
		return nil
	end
	local cached = statsCache[info.Uid]
	if cached then
		return cached
	end
	local data = DataController.GetData()
	local item = if data then data.Items[info.Uid] else nil
	local stats = if item then WeaponStats.Compute(item) else nil
	if stats then
		statsCache[info.Uid] = stats
	end
	return stats
end

function WeaponController.GetActiveSlot(): string
	return active
end

function WeaponController.GetSlots(): { [string]: SlotInfo }
	return slots
end

-- Current spread cone in degrees (for the crosshair).
function WeaponController.GetSpread(): number
	local stats = WeaponController.GetStats(active)
	if stats == nil then
		return 1
	end
	return (if aiming then stats.SpreadAds else stats.SpreadHip) + bloom
end

-- 0..1 while reloading, nil otherwise.
function WeaponController.GetReloadProgress(): number?
	local now = os.clock()
	if reloadingUntil <= now or reloadDuration <= 0 then
		return nil
	end
	return 1 - (reloadingUntil - now) / reloadDuration
end

function WeaponController.IsAiming(): boolean
	return aiming
end

-- Actions -------------------------------------------------------------------------

local function setAiming(isAiming: boolean)
	if isAiming and not WeaponController.IsDrawn() then
		return
	end
	if aiming == isAiming then
		return
	end
	aiming = isAiming
	local stats = WeaponController.GetStats(active)
	CameraController.SetAiming(isAiming, if stats then stats.AdsFov else nil)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		if isAiming then
			baseWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = humanoid.WalkSpeed * (if stats then stats.AdsMoveScale else 0.85)
		elseif baseWalkSpeed then
			humanoid.WalkSpeed = baseWalkSpeed
			baseWalkSpeed = nil
		end
	end
end

local function reload()
	local info = slots[active]
	local stats = WeaponController.GetStats(active)
	local now = os.clock()
	if info == nil or stats == nil or reloadingUntil > now then
		return
	end
	if info.Mag >= stats.Magazine or (info.Reserve ~= nil and info.Reserve <= 0) then
		return
	end
	reloadingUntil = now + stats.ReloadTime
	reloadDuration = stats.ReloadTime
	local slot = active
	local finishAt = reloadingUntil
	ClientNet.Fire("WeaponReload", slot)
	EffectsController.PlaySound(weaponSound(stats.Type, "Reload"))
	task.delay(stats.ReloadTime, function()
		-- Predict the result; the server's WeaponState confirms it.
		if reloadingUntil == finishAt and active == slot and slots[slot] == info then
			reloadingUntil = 0
			if info.Reserve == nil then
				info.Mag = stats.Magazine
			else
				local taken = math.min(stats.Magazine - info.Mag, info.Reserve :: number)
				info.Mag += taken
				info.Reserve = (info.Reserve :: number) - taken
			end
		end
	end)
end

local function switchTo(slot: string)
	if slots[slot] == nil or slot == active then
		return
	end
	active = slot
	reloadingUntil = 0
	bloom = 0
	local stats = WeaponController.GetStats(slot)
	swapReadyAt = os.clock() + (if stats then stats.SwapTime else 0.4)
	ClientNet.Fire("WeaponSwitch", slot)
	if aiming then
		CameraController.SetAiming(true, if stats then stats.AdsFov else nil)
	end
end

local function cycle(direction: number)
	local index = table.find(SLOTS, active) or 1
	for step = 1, #SLOTS do
		local candidate = SLOTS[(index - 1 + step * direction) % #SLOTS + 1]
		if slots[candidate] then
			switchTo(candidate)
			return
		end
	end
end

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Weapons are holstered in the hub outside the firing range (server attribute).
function WeaponController.IsDrawn(): boolean
	return player:GetAttribute("WeaponsDrawn") == true
end

local function fire()
	local info = slots[active]
	local stats = WeaponController.GetStats(active)
	local character = player.Character
	if info == nil or stats == nil or character == nil or not WeaponController.IsDrawn() then
		return
	end
	local now = os.clock()
	if now < swapReadyAt or now < reloadingUntil or now < nextFireAt then
		return
	end
	if stats.FireMode ~= "Auto" and not semiReady then
		return
	end
	if info.Mag <= 0 then
		semiReady = false
		reload()
		return
	end

	semiReady = false
	nextFireAt = now + stats.FireInterval
	info.Mag -= 1

	local origin, look = CameraController.GetAimRay()
	local direction = spreadDirection(look, WeaponController.GetSpread())
	aimParams.FilterDescendantsInstances = { character, Workspace:FindFirstChild("ClientEffects") :: Instance }
	local result = Workspace:Raycast(origin, direction * stats.MaxRange, aimParams)
	local aimPoint = if result then result.Position else origin + direction * stats.MaxRange

	shotId += 1
	ClientNet.Fire("WeaponFire", active, aimPoint, shotId)

	bloom = math.min(stats.SpreadMax, bloom + stats.SpreadPerShot)
	local side = (math.random() * 2 - 1) * stats.RecoilHorizontal
	CameraController.Kick(stats.RecoilVertical, side, stats.RecoilRecovery)

	local element = ElementConfig.Elements[stats.Element]
	local color = if element then element.Color else Color3.new(1, 1, 1)
	local muzzle = EffectsController.MuzzleOf(character) or origin
	EffectsController.MuzzleFlash(muzzle, color)
	if stats.Projectile == nil then
		EffectsController.Tracer(muzzle, aimPoint, color)
		if result then
			EffectsController.Impact(aimPoint)
		end
	end
	EffectsController.PlaySound(weaponSound(stats.Type, "Fire"), muzzle, 0.5)

	if info.Mag <= 0 then
		task.delay(0.15, reload)
	end
end

-- Hold pose: plays Roblox's default "tool held" arm animation so guns point forward.
local function playHoldAnimation(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10)
	if animator == nil or not animator:IsA("Animator") then
		return
	end
	local set = if humanoid.RigType == Enum.HumanoidRigType.R15 then AssetIds.Animations.R15 else AssetIds.Animations.R6
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{set.HoldWeapon}`
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
		holdTrack = track
	end
end

local function buildTouchButtons()
	local gui = UI.Screen("TouchWeapons", 20)
	local function button(text: string, position: UDim2, size: number): TextButton
		local b = UI.Button({
			Text = text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 0.35,
		}, gui)
		UI.Corner(b, size // 2)
		return b
	end
	local fireButton = button("FIRE", UDim2.new(1, -90, 1, -190), 96)
	fireButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			fireHeld = true
			semiReady = true
		end
	end)
	fireButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			fireHeld = false
		end
	end)
	button("AIM", UDim2.new(1, -190, 1, -250), 64).Activated:Connect(function()
		setAiming(not aiming)
	end)
	button("R", UDim2.new(1, -200, 1, -150), 56).Activated:Connect(reload)
	button("SWAP", UDim2.new(1, -90, 1, -300), 64).Activated:Connect(function()
		cycle(1)
	end)
end

-- Lifecycle -------------------------------------------------------------------------

function WeaponController.Init()
	ClientNet.On("WeaponState", function(state: any)
		if type(state) ~= "table" or type(state.Slots) ~= "table" then
			return
		end
		local incoming: { [string]: SlotInfo } = {}
		for slot, info in state.Slots do
			if type(slot) == "string" and type(info) == "table" and type(info.Uid) == "string" then
				incoming[slot] = {
					Uid = tostring(info.Uid),
					Mag = tonumber(info.Mag) or 0,
					Reserve = tonumber(info.Reserve),
					Reloading = info.Reloading == true,
				}
			end
		end
		slots = incoming
		if type(state.Active) == "string" and incoming[state.Active] then
			active = state.Active
		end
		local current = incoming[active]
		if current and not current.Reloading then
			reloadingUntil = 0
		end
	end)

	-- Item rolls can change (infusion, /setpower): recompute cached stats.
	DataController.Observe({ "Items" }, function()
		table.clear(statsCache)
	end)
end

function WeaponController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UIState.InputBlocked() then
			return
		end
		if isAction(input, "Fire") then
			fireHeld = true
			semiReady = true
			fire()
		elseif isAction(input, "Aim") then
			setAiming(true)
		elseif isAction(input, "Reload") then
			reload()
		elseif isAction(input, "WeaponKinetic") then
			switchTo("Kinetic")
		elseif isAction(input, "WeaponEnergy") then
			switchTo("Energy")
		elseif isAction(input, "WeaponHeavy") then
			switchTo("Heavy")
		elseif isAction(input, "CycleWeapon") then
			cycle(1)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if isAction(input, "Fire") then
			fireHeld = false
		elseif isAction(input, "Aim") then
			setAiming(false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if
			not gameProcessed
			and input.UserInputType == Enum.UserInputType.MouseWheel
			and not UIState.InputBlocked()
		then
			cycle(if input.Position.Z > 0 then -1 else 1)
		end
	end)

	UIState.MenuChanged:Connect(function()
		fireHeld = false
		setAiming(false)
	end)

	player:GetAttributeChangedSignal("WeaponsDrawn"):Connect(function()
		if not WeaponController.IsDrawn() then
			fireHeld = false
			setAiming(false)
		end
	end)

	player.CharacterAdded:Connect(function(character: Model)
		fireHeld = false
		aiming = false
		baseWalkSpeed = nil
		CameraController.SetAiming(false)
		bloom = 0
		reloadingUntil = 0
		if holdTrack then
			holdTrack:Stop()
			holdTrack = nil
		end
		playHoldAnimation(character)
	end)
	if player.Character then
		task.spawn(playHoldAnimation, player.Character)
	end

	if UserInputService.TouchEnabled then
		buildTouchButtons()
	end

	RunService:BindToRenderStep("LastLightWeapons", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local stats = WeaponController.GetStats(active)
		if stats then
			bloom = math.max(0, bloom - dt * stats.SpreadMax * 2.5)
		end
		if fireHeld and not UIState.InputBlocked() then
			fire()
		end
	end)
end

return WeaponController
