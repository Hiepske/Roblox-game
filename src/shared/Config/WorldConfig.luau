--!strict
--[[
	WorldConfig
	Maps and lighting.

	Maps are built from parts by code (src/server/Maps) when the server
	starts. If a model with the same name already exists (Workspace.Hub, or
	ServerStorage.Activities.<Map>), it is used instead, so a hand-built map
	in Studio always wins over the generated one.

	Lighting presets are applied by the server for the hub and by each
	client when it enters an activity (client-side, so every instance can
	have its own mood even though Lighting is shared).
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type LightingPreset = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ExposureCompensation: number,
	Atmosphere: { Density: number, Offset: number, Color: Color3, Decay: Color3, Glare: number, Haze: number },
	Bloom: { Intensity: number, Size: number, Threshold: number },
	ColorCorrection: { Brightness: number, Contrast: number, Saturation: number, TintColor: Color3 },
	SunRays: { Intensity: number, Spread: number },
	StarCount: number,
}

local Lighting: { [string]: LightingPreset } = {
	-- Sci-fi evening over Haven Spire.
	Hub = {
		ClockTime = 18.3,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(45, 38, 70),
		OutdoorAmbient = Color3.fromRGB(120, 95, 150),
		ExposureCompensation = 0.1,
		Atmosphere = {
			Density = 0.32,
			Offset = 0.12,
			Color = Color3.fromRGB(235, 165, 190),
			Decay = Color3.fromRGB(105, 75, 160),
			Glare = 0.6,
			Haze = 1.6,
		},
		Bloom = { Intensity = 0.9, Size = 28, Threshold = 1.1 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.12,
			Saturation = 0.1,
			TintColor = Color3.fromRGB(255, 242, 255),
		},
		SunRays = { Intensity = 0.08, Spread = 0.6 },
		StarCount = 3000,
	},
	-- Dusty afternoon on Veyra.
	FirstLight = {
		ClockTime = 16.2,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(70, 55, 45),
		OutdoorAmbient = Color3.fromRGB(150, 120, 95),
		ExposureCompensation = 0,
		Atmosphere = {
			Density = 0.38,
			Offset = 0.05,
			Color = Color3.fromRGB(230, 180, 130),
			Decay = Color3.fromRGB(160, 105, 70),
			Glare = 0.3,
			Haze = 2.2,
		},
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.3 },
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.1,
			Saturation = 0.05,
			TintColor = Color3.fromRGB(255, 240, 225),
		},
		SunRays = { Intensity = 0.12, Spread = 0.8 },
		StarCount = 500,
	},
	-- Red-lit night inside the Hollow Spire.
	HollowSpire = {
		ClockTime = 0.5,
		Brightness = 1.2,
		Ambient = Color3.fromRGB(60, 30, 30),
		OutdoorAmbient = Color3.fromRGB(90, 45, 45),
		ExposureCompensation = 0.3,
		Atmosphere = {
			Density = 0.42,
			Offset = 0.2,
			Color = Color3.fromRGB(150, 60, 50),
			Decay = Color3.fromRGB(60, 20, 30),
			Glare = 0,
			Haze = 2.5,
		},
		Bloom = { Intensity = 1.2, Size = 30, Threshold = 0.95 },
		ColorCorrection = {
			Brightness = 0.03,
			Contrast = 0.18,
			Saturation = 0.05,
			TintColor = Color3.fromRGB(255, 225, 220),
		},
		SunRays = { Intensity = 0, Spread = 0.5 },
		StarCount = 1500,
	},
	-- Cold, echoing vault lit by cyan crystals.
	VaultOfEchoes = {
		ClockTime = 22,
		Brightness = 1,
		Ambient = Color3.fromRGB(30, 50, 70),
		OutdoorAmbient = Color3.fromRGB(50, 80, 110),
		ExposureCompensation = 0.4,
		Atmosphere = {
			Density = 0.45,
			Offset = 0.25,
			Color = Color3.fromRGB(90, 170, 210),
			Decay = Color3.fromRGB(20, 40, 70),
			Glare = 0,
			Haze = 2.2,
		},
		Bloom = { Intensity = 1.1, Size = 30, Threshold = 1 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.15,
			Saturation = -0.05,
			TintColor = Color3.fromRGB(225, 245, 255),
		},
		SunRays = { Intensity = 0, Spread = 0.5 },
		StarCount = 2000,
	},
}

return TableUtil.DeepFreeze({
	-- Map builders that exist in src/server/Maps (ActivityConfig.Map must be one).
	Maps = { "FirstLight", "HollowSpire", "VaultOfEchoes" },
	Lighting = Lighting,
	-- Where players stand when they return to the hub.
	HubSpawnHeight = 4,
})
