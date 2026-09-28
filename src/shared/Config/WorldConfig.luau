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
	-- Terrain clouds (nil = none).
	Clouds: { Cover: number, Density: number, Color: Color3 }?,
	-- Key into AssetIds.Images for skybox faces (placeholder ids keep the default sky).
	Sky: string?,
	-- Players carry a flashlight (dark caves).
	Flashlight: boolean?,
}

local Lighting: { [string]: LightingPreset } = {
	-- Sunny afternoon on top of the Spire: light haze, soft bloom, warm grade.
	Hub = {
		ClockTime = 15,
		Brightness = 3,
		Ambient = Color3.fromRGB(120, 122, 130),
		OutdoorAmbient = Color3.fromRGB(165, 165, 170),
		ExposureCompensation = 0,
		Atmosphere = {
			Density = 0.3,
			Offset = 0.08,
			Color = Color3.fromRGB(205, 220, 235),
			Decay = Color3.fromRGB(150, 170, 200),
			Glare = 0.25,
			Haze = 1.4,
		},
		Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.6 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.06,
			Saturation = 0.08,
			TintColor = Color3.fromRGB(255, 248, 236),
		},
		SunRays = { Intensity = 0.1, Spread = 0.5 },
		StarCount = 0,
		Clouds = { Cover = 0.55, Density = 0.45, Color = Color3.fromRGB(255, 255, 255) },
		Sky = "HubSky",
	},
	-- Dusty afternoon on Veyra.
	-- Frostreach: a bright, overcast snowy valley.
	FirstLight = {
		ClockTime = 13.5,
		Brightness = 2.4,
		Ambient = Color3.fromRGB(120, 130, 150),
		OutdoorAmbient = Color3.fromRGB(170, 180, 200),
		ExposureCompensation = 0.1,
		Atmosphere = {
			Density = 0.42,
			Offset = 0.1,
			Color = Color3.fromRGB(210, 222, 238),
			Decay = Color3.fromRGB(150, 165, 190),
			Glare = 0.1,
			Haze = 2.4,
		},
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.5 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.08,
			Saturation = -0.08,
			TintColor = Color3.fromRGB(235, 242, 255),
		},
		SunRays = { Intensity = 0.05, Spread = 0.4 },
		StarCount = 0,
		Clouds = { Cover = 0.8, Density = 0.6, Color = Color3.fromRGB(225, 230, 240) },
	},
	-- Meridian Coast: golden late afternoon, humid haze over the water.
	SunkenRelay = {
		ClockTime = 17.3,
		Brightness = 2.8,
		Ambient = Color3.fromRGB(110, 110, 100),
		OutdoorAmbient = Color3.fromRGB(170, 160, 130),
		ExposureCompensation = 0.05,
		Atmosphere = {
			Density = 0.36,
			Offset = 0.12,
			Color = Color3.fromRGB(235, 210, 170),
			Decay = Color3.fromRGB(160, 150, 120),
			Glare = 0.4,
			Haze = 1.8,
		},
		Bloom = { Intensity = 0.55, Size = 26, Threshold = 1.3 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.08,
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 244, 225),
		},
		SunRays = { Intensity = 0.14, Spread = 0.7 },
		StarCount = 0,
		Clouds = { Cover = 0.5, Density = 0.4, Color = Color3.fromRGB(255, 236, 214) },
	},
	-- Hollowmere: a foggy night; the caves are dark (flashlights on).
	HollowDark = {
		ClockTime = 0.3,
		Brightness = 0.6,
		Ambient = Color3.fromRGB(38, 40, 52),
		OutdoorAmbient = Color3.fromRGB(90, 100, 110),
		ExposureCompensation = 0.25,
		Atmosphere = {
			Density = 0.52,
			Offset = 0.1,
			Color = Color3.fromRGB(150, 170, 160),
			Decay = Color3.fromRGB(50, 60, 70),
			Glare = 0,
			Haze = 3,
		},
		Bloom = { Intensity = 1, Size = 28, Threshold = 1 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.14,
			Saturation = -0.15,
			TintColor = Color3.fromRGB(225, 240, 235),
		},
		SunRays = { Intensity = 0, Spread = 0.5 },
		StarCount = 3000,
		Flashlight = true,
	},
	-- Veyra at dusk: an orange sky over the cliff fortress.
	HollowSpire = {
		ClockTime = 17.9,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(90, 60, 55),
		OutdoorAmbient = Color3.fromRGB(170, 110, 90),
		ExposureCompensation = 0.1,
		Atmosphere = {
			Density = 0.4,
			Offset = 0.15,
			Color = Color3.fromRGB(255, 150, 90),
			Decay = Color3.fromRGB(150, 60, 40),
			Glare = 0.6,
			Haze = 2,
		},
		Bloom = { Intensity = 0.7, Size = 28, Threshold = 1.2 },
		ColorCorrection = {
			Brightness = 0.01,
			Contrast = 0.12,
			Saturation = 0.1,
			TintColor = Color3.fromRGB(255, 225, 200),
		},
		SunRays = { Intensity = 0.2, Spread = 0.9 },
		StarCount = 400,
		Clouds = { Cover = 0.45, Density = 0.5, Color = Color3.fromRGB(255, 170, 120) },
	},
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

export type ChestDef = {
	-- "Daily" or "Weekly": how often it can be opened.
	Reset: "Daily" | "Weekly",
	Currencies: { [string]: number },
	-- Chance of a gear drop (World power rules).
	DropChance: number,
	Message: string,
}

-- Hidden caches in the hub (Props.Chest with a ChestId).
local Chests: { [string]: ChestDef } = {
	HUB_ROOFTOP = {
		Reset = "Daily",
		Currencies = { Quanta = 300, Alloy = 2 },
		DropChance = 0.25,
		Message = "Rooftop cache: someone stashed supplies up here.",
	},
	HUB_SECRET = {
		Reset = "Weekly",
		Currencies = { Quanta = 800, Alloy = 5, Fluxite = 1 },
		DropChance = 1,
		Message = "A hidden archive. The terminal flickers: KEEP THE LIGHT.",
	},
}

return TableUtil.DeepFreeze({
	Chests = Chests,
	-- Map builders that exist in src/server/Maps (ActivityConfig.Map must be one).
	Maps = { "FirstLight", "SunkenRelay", "HollowDark", "HollowSpire", "VaultOfEchoes" },
	Lighting = Lighting,
	-- Where players stand when they return to the hub.
	HubSpawnHeight = 4,
})
