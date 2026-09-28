--!strict
--[[
	CameraController
	Over-the-shoulder shooter camera.

	  * Mouse locked to the screen center; moving it turns the camera, and
	    the character always faces where the camera looks.
	  * Aiming down sights pulls the camera in over the shoulder and zooms
	    the field of view to the weapon's ADS FOV.
	  * Recoil kicks the view up; most of it recovers on its own.
	  * The camera is pulled in when a wall is behind the player.
	  * Menus and the death screen release the mouse.
	  * Gamepad right stick and touch-drag (right half of the screen) also look around.
	  * SetOverride hands the camera to a cutscene (the mission intro).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DataController = require(script.Parent.DataController)
local UIState = require(script.Parent.Parent.UI.UIState)

local CameraController = {}

local HIP_OFFSET = Vector3.new(2.3, 0.7, 8.5)
local AIM_OFFSET = Vector3.new(1.7, 0.45, 4.2)
local PIVOT_HEIGHT = 1.8
local MAX_PITCH = math.rad(80)
local RADIANS_PER_PIXEL = 0.0035 -- at sensitivity 0.5
local GAMEPAD_SPEED = 3.2 -- radians per second at full tilt
local TOUCH_RADIANS_PER_PIXEL = 0.006

local player = Players.LocalPlayer
local yaw, pitch = 0, 0
local recoilDebt = 0
local recoilRecovery = 8
local aiming = false
local aimFov = 55
local currentOffset = HIP_OFFSET
local trackedCharacter: Model? = nil
local gamepadLook = Vector2.zero
local touchLook: InputObject? = nil
local overridden = false
local collisionParams = RaycastParams.new()
collisionParams.FilterType = Enum.RaycastFilterType.Exclude

local function settings(): (number, boolean, number)
	local data = DataController.GetData()
	if data == nil then
		return 0.5, false, 70
	end
	return data.Settings.MouseSensitivity, data.Settings.InvertY, data.Settings.FieldOfView
end

function CameraController.SetAiming(isAiming: boolean, fov: number?)
	aiming = isAiming
	if fov then
		aimFov = fov
	end
end

-- While overridden the camera is left alone; afterwards it snaps back
-- behind the character, facing where the character faces.
function CameraController.SetOverride(active: boolean)
	overridden = active
	if not active then
		trackedCharacter = nil
	end
end

function CameraController.IsAiming(): boolean
	return aiming
end

-- Recoil: degrees up (and sideways), recovering at `recovery` degrees/second.
function CameraController.Kick(verticalDegrees: number, horizontalDegrees: number, recovery: number?)
	local up = math.rad(verticalDegrees)
	pitch = math.clamp(pitch + up, -MAX_PITCH, MAX_PITCH)
	yaw += math.rad(horizontalDegrees)
	recoilDebt += up * 0.7
	recoilRecovery = recovery or recoilRecovery
end

-- Where shots come from: the camera position pushed forward past the
-- shoulder offset (so nothing behind the character blocks the aim ray).
function CameraController.GetAimRay(): (Vector3, Vector3)
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	return camera.CFrame.Position + look * currentOffset.Z, look
end

local function update(dt: number)
	if overridden then
		return
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	if character ~= trackedCharacter then
		trackedCharacter = character
		local look = root.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = 0
		recoilDebt = 0
		collisionParams.FilterDescendantsInstances = { character }
	end

	camera.CameraType = Enum.CameraType.Scriptable
	local blocked = UIState.InputBlocked()
	local sensitivity, invertY, baseFov = settings()
	if blocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
		local scale = RADIANS_PER_PIXEL * (sensitivity / 0.5) * (if aiming then 0.7 else 1)
		yaw -= delta.X * scale
		pitch -= delta.Y * scale * (if invertY then -1 else 1)
		if gamepadLook.Magnitude > 0 then
			yaw -= gamepadLook.X * GAMEPAD_SPEED * dt * (if aiming then 0.6 else 1)
			pitch += gamepadLook.Y * GAMEPAD_SPEED * dt * (if aiming then 0.6 else 1) * (if invertY then -1 else 1)
		end
	end

	if recoilDebt > 0 then
		local recover = math.min(recoilDebt, math.rad(recoilRecovery) * dt)
		pitch -= recover
		recoilDebt -= recover
	end
	pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)

	local targetOffset = if aiming then AIM_OFFSET else HIP_OFFSET
	currentOffset = currentOffset:Lerp(targetOffset, math.min(1, dt * 14))

	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local pivot = root.Position + Vector3.new(0, PIVOT_HEIGHT, 0)
	local desired = (CFrame.new(pivot) * rotation * CFrame.new(currentOffset)).Position
	local toCamera = desired - pivot
	local hit = Workspace:Raycast(pivot, toCamera, collisionParams)
	local position = if hit then hit.Position - toCamera.Unit * 0.5 else desired
	camera.CFrame = CFrame.new(position) * rotation

	local targetFov = if aiming then aimFov else baseFov
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 12)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.AutoRotate = false
		if not blocked then
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
		end
	end
end

function CameraController.Init() end

function CameraController.Start()
	RunService:BindToRenderStep("LastLightCamera", Enum.RenderPriority.Camera.Value + 1, update)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local value = Vector2.new(input.Position.X, input.Position.Y)
			gamepadLook = if value.Magnitude > 0.15 then value else Vector2.zero
		elseif input == touchLook and not UIState.InputBlocked() then
			yaw -= input.Delta.X * TOUCH_RADIANS_PER_PIXEL
			pitch -= input.Delta.Y * TOUCH_RADIANS_PER_PIXEL
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and not gameProcessed then
			local viewport = Workspace.CurrentCamera.ViewportSize
			if input.Position.X > viewport.X * 0.45 then
				touchLook = input
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == touchLook then
			touchLook = nil
		end
	end)
end

return CameraController
