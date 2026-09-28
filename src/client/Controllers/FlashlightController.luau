--!strict
--[[
	FlashlightController
	Maps whose lighting preset has Flashlight = true (the caves of The Hollow
	Dark) give every player a flashlight: a shadow-casting SpotLight on the
	head pointing where you look, plus a faint glow around you so the floor
	under your feet stays readable. Everyone sees everyone's beam because
	each client lights all characters in the same activity.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LightingPresets =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World"):WaitForChild("LightingPresets"))

local ActivityController = require(script.Parent.ActivityController)

local FlashlightController = {}

local NAME = "LL_Flashlight"
local enabled = false

local function lightFor(character: Model)
	local head = character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") or head:FindFirstChild(NAME) then
		return
	end
	local beam = Instance.new("SpotLight")
	beam.Name = NAME
	beam.Face = Enum.NormalId.Front
	beam.Angle = 50
	beam.Range = 70
	beam.Brightness = 3
	beam.Color = Color3.fromRGB(255, 244, 225)
	beam.Shadows = true
	beam.Parent = head
	local glow = Instance.new("PointLight")
	glow.Name = NAME .. "Glow"
	glow.Range = 12
	glow.Brightness = 0.35
	glow.Color = Color3.fromRGB(200, 215, 255)
	glow.Parent = head
end

local function clear(character: Model)
	for _, name in { NAME, NAME .. "Glow" } do
		local existing = character:FindFirstChild(name, true)
		if existing then
			existing:Destroy()
		end
	end
end

local function refresh()
	local info = ActivityController.Get()
	enabled = info.InActivity and LightingPresets.HasFlashlight(info.Map)
	local runId = info.RunId
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local together = player == Players.LocalPlayer or player:GetAttribute("InstanceId") == runId
			if enabled and together then
				lightFor(character)
			else
				clear(character)
			end
		end
	end
end

function FlashlightController.Init() end

function FlashlightController.Start()
	ActivityController.Changed:Connect(refresh)
	-- Characters respawn and other players come and go: keep it in sync.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			if enabled then
				refresh()
			end
		end
	end)
	refresh()
end

return FlashlightController
