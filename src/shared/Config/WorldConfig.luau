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
	Maps = { "FirstLight", "HollowSpire", "VaultOfEchoes" },
	Lighting = Lighting,
	-- Where players stand when they return to the hub.
	HubSpawnHeight = 4,
})
