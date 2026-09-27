--!strict
--[[
	LightingPresets
	Applies a WorldConfig.Lighting preset to Lighting: sky time, ambient
	colors, Atmosphere, Bloom, ColorCorrection, SunRays and stars.

	The server applies "Hub" at startup. Each client re-applies the preset
	for wherever it is (hub or an activity map); client-side Lighting changes
	are local, so players in different instances see different moods.
]]

local Lighting = game:GetService("Lighting")

local WorldConfig = require(script.Parent.Parent.Config.WorldConfig)

local LightingPresets = {}

local PREFIX = "LL_"

local function atmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		return existing
	end
	local created = Instance.new("Atmosphere")
	created.Name = PREFIX .. "Atmosphere"
	created.Parent = Lighting
	return created
end

local function bloom(): BloomEffect
	local existing = Lighting:FindFirstChild(PREFIX .. "Bloom")
	if existing and existing:IsA("BloomEffect") then
		return existing
	end
	local created = Instance.new("BloomEffect")
	created.Name = PREFIX .. "Bloom"
	created.Parent = Lighting
	return created
end

local function colorCorrection(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild(PREFIX .. "ColorCorrection")
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing
	end
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = PREFIX .. "ColorCorrection"
	created.Parent = Lighting
	return created
end

local function sunRays(): SunRaysEffect
	local existing = Lighting:FindFirstChild(PREFIX .. "SunRays")
	if existing and existing:IsA("SunRaysEffect") then
		return existing
	end
	local created = Instance.new("SunRaysEffect")
	created.Name = PREFIX .. "SunRays"
	created.Parent = Lighting
	return created
end

local function sky(): Sky
	local existing = Lighting:FindFirstChildOfClass("Sky")
	if existing then
		return existing
	end
	local created = Instance.new("Sky")
	created.Name = PREFIX .. "Sky"
	created.Parent = Lighting
	return created
end

function LightingPresets.Apply(name: string)
	local preset = WorldConfig.Lighting[name] or WorldConfig.Lighting.Hub

	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.ExposureCompensation = preset.ExposureCompensation
	Lighting.GlobalShadows = true

	local air = atmosphere()
	air.Density = preset.Atmosphere.Density
	air.Offset = preset.Atmosphere.Offset
	air.Color = preset.Atmosphere.Color
	air.Decay = preset.Atmosphere.Decay
	air.Glare = preset.Atmosphere.Glare
	air.Haze = preset.Atmosphere.Haze

	local glow = bloom()
	glow.Intensity = preset.Bloom.Intensity
	glow.Size = preset.Bloom.Size
	glow.Threshold = preset.Bloom.Threshold

	local grade = colorCorrection()
	grade.Brightness = preset.ColorCorrection.Brightness
	grade.Contrast = preset.ColorCorrection.Contrast
	grade.Saturation = preset.ColorCorrection.Saturation
	grade.TintColor = preset.ColorCorrection.TintColor

	local rays = sunRays()
	rays.Intensity = preset.SunRays.Intensity
	rays.Spread = preset.SunRays.Spread

	local skybox = sky()
	skybox.StarCount = preset.StarCount
	skybox.CelestialBodiesShown = true
end

return LightingPresets
