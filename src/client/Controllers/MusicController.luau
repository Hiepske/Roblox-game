--!strict
--[[
	MusicController
	Background music that follows the action, crossfading between looping
	tracks (AssetIds.Sounds.Music):
	  Hub      in the Spire
	  Explore  in an activity when nothing is near
	  Combat   fades in as enemies close in: its volume follows the threat
	           around you (tiers weighted by PresentationConfig.Music.Threat)
	           and falls back over a few seconds once it's quiet
	  Boss     while a boss bar is up
	  Victory  plays once when an activity completes

	With placeholder ids (0) nothing is audible, but the state still runs; in
	Studio the zone debug panel shows it (the LL_Music folder's State
	attribute).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AssetIds = require(Config:WaitForChild("AssetIds"))
local PresentationConfig = require(Config:WaitForChild("PresentationConfig"))

local ActivityController = require(script.Parent.ActivityController)

local MusicController = {}

local TUNING = PresentationConfig.Music
local LOOPS = { "Hub", "Explore", "Combat", "Boss" }

type Track = { Sound: Sound, Level: number, Target: number }

local player = Players.LocalPlayer
local folder: Folder
local tracks: { [string]: Track } = {}
local victory: Sound
local intensity = 0
local threatClock = 0
local lastStatus: any = nil

local function makeSound(name: string, id: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = AssetIds.Get(id)
	sound.Looped = looped
	sound.Volume = 0
	sound.Parent = folder
	return sound
end

-- Threat around the player, 0..1.
local function measureThreat(): number
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local enemies = Workspace:FindFirstChild("Enemies")
	if root == nil or not root:IsA("BasePart") or enemies == nil then
		return 0
	end
	local total = 0
	for _, model in enemies:GetChildren() do
		local weight = TUNING.Threat[tostring(model:GetAttribute("Tier"))]
		if weight and model:IsA("Model") then
			local pivot = model.PrimaryPart
			if pivot and (pivot.Position - root.Position).Magnitude <= TUNING.CombatRadius then
				total += weight
			end
		end
	end
	return math.clamp(total / TUNING.ThreatForFull, 0, 1)
end

local function setTargets(targets: { [string]: number })
	for name, track in tracks do
		track.Target = targets[name] or 0
	end
end

local function update(dt: number)
	local info = ActivityController.Get()
	local live = ActivityController.GetFolder()
	local state: string
	if not info.InActivity or live == nil then
		intensity = 0
		setTargets({ Hub = 1 })
		state = "Hub"
		lastStatus = nil
	else
		local status = live:GetAttribute("Status")
		if status == "Complete" and lastStatus ~= "Complete" and victory.SoundId ~= "" then
			victory.Volume = TUNING.Volume
			victory.TimePosition = 0
			victory.Playing = true
		end
		lastStatus = status

		threatClock += dt
		if threatClock >= 0.25 then
			threatClock = 0
			local threat = measureThreat()
			if threat > intensity then
				intensity += (threat - intensity) * 0.6
			end
		end
		intensity = math.max(0, intensity - dt / TUNING.CalmSeconds)

		if status == "Complete" then
			setTargets({ Explore = 0.5 })
			state = "Victory"
		elseif live:GetAttribute("BossActive") == true then
			setTargets({ Boss = 1 })
			state = "Boss"
		elseif intensity >= TUNING.CombatThreshold then
			setTargets({ Explore = 1 - intensity * 0.8, Combat = 0.35 + intensity * 0.65 })
			state = `Combat {string.format("%.2f", intensity)}`
		else
			setTargets({ Explore = 1 })
			state = "Explore"
		end
	end

	local step = dt / TUNING.FadeSeconds
	for _, track in tracks do
		if track.Level < track.Target then
			track.Level = math.min(track.Target, track.Level + step)
		elseif track.Level > track.Target then
			track.Level = math.max(track.Target, track.Level - step)
		end
		local sound = track.Sound
		sound.Volume = track.Level * TUNING.Volume
		if track.Level > 0 and not sound.Playing and sound.SoundId ~= "" then
			sound.Playing = true
		elseif track.Level <= 0 and sound.Playing then
			sound.Playing = false
		end
	end
	folder:SetAttribute("State", state)
end

-- "Hub", "Explore", "Combat 0.62", "Boss" or "Victory".
function MusicController.GetState(): string
	return tostring(folder and folder:GetAttribute("State") or "")
end

function MusicController.Init()
	folder = Instance.new("Folder")
	folder.Name = "LL_Music"
	folder.Parent = SoundService
	local ids = AssetIds.Sounds.Music
	for _, name in LOOPS do
		tracks[name] = { Sound = makeSound(name, (ids :: any)[name] or 0, true), Level = 0, Target = 0 }
	end
	victory = makeSound("Victory", ids.Victory, false)
end

function MusicController.Start()
	RunService.Heartbeat:Connect(update)
end

return MusicController
