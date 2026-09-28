--!strict
--[[
	PresentationConfig
	Tuning for the client-side presentation: loading screen tips, the mission
	intro fly-over, music, the kill feed and waypoints. Nothing here affects
	gameplay; the server never reads it.
]]

local PresentationConfig = {}

-- Shown one at a time on the loading screen.
PresentationConfig.Tips = {
	"Precision hits on a glowing head or core deal extra damage. Watch for the yellow hit marker.",
	"Match your weapon's element to an enemy's shield to break it fast.",
	"Being above the recommended Power lowers the damage you take, up to a cap.",
	"Heavy ammo appears in every boss arena. Save your rockets for when the shield drops.",
	"A grey boss bar means the boss is immune. Clear the adds or destroy the pylons first.",
	"A red circle on the ground means a slam is coming. Step out before it lands.",
	"When the Echo Sovereign charges its nova, stand inside a lit circle. Nothing outside survives.",
	"In the raid a fallen Keeper leaves a ghost. Hold E on it to bring them back.",
	"Falling in the Descent only sends you back to the start of that jump.",
	"Nightfall medals are for speed: finish under 8:00 for Gold and an extra drop.",
	"Each raid encounter chest pays a Pinnacle reward once per week.",
	"Infuse a stronger item into a favourite at the Gunsmith to raise its Power.",
	"Your Vault holds what your inventory can't. The Postmaster keeps drops that didn't fit.",
	"Snipers paint you with a red laser before they fire. Break line of sight.",
	"A dropship brings reinforcements when a wave is almost down. Keep moving.",
	"The lasers in the Silent Hall blink and sweep on a rhythm. Watch one cycle before you run.",
	"Save up to three loadouts from the character screen and swap your whole kit at once.",
	"The Hollow Dark has no light of its own. Your flashlight follows your aim.",
}

PresentationConfig.Loading = {
	-- The screen stays up at least this long so it never just flickers.
	MinSeconds = 1.6,
	-- Gives up waiting for the activity and hides after this long.
	MaxSeconds = 25,
	FadeSeconds = 0.35,
	-- Coming back to the Spire covers the teleport for this long.
	ReturnSeconds = 1.4,
	-- Colors of the drawn placeholder shown while a map's loading art is 0
	-- in AssetIds.Images.Loading: sky, ground and accent.
	Palettes = {
		Default = { Color3.fromRGB(22, 28, 40), Color3.fromRGB(8, 10, 16), Color3.fromRGB(110, 220, 255) },
		Hub = { Color3.fromRGB(196, 214, 232), Color3.fromRGB(70, 82, 98), Color3.fromRGB(255, 150, 60) },
		FirstLight = { Color3.fromRGB(170, 196, 222), Color3.fromRGB(40, 52, 68), Color3.fromRGB(120, 230, 255) },
		SunkenRelay = { Color3.fromRGB(90, 170, 170), Color3.fromRGB(16, 44, 48), Color3.fromRGB(255, 190, 90) },
		HollowDark = { Color3.fromRGB(46, 30, 70), Color3.fromRGB(6, 4, 12), Color3.fromRGB(190, 120, 255) },
		HollowSpire = { Color3.fromRGB(255, 140, 70), Color3.fromRGB(40, 18, 14), Color3.fromRGB(255, 200, 120) },
		VaultOfEchoes = { Color3.fromRGB(70, 56, 30), Color3.fromRGB(8, 7, 5), Color3.fromRGB(255, 205, 90) },
	} :: { [string]: { Color3 } },
}

PresentationConfig.Intro = {
	-- Camera fly-over length; any key or click skips it.
	Seconds = 5.5,
	-- Height of the opening shot over the start, and of the closing shot
	-- over the first objective.
	StartHeight = 38,
	EndHeight = 62,
	-- The title card fades in after this delay and out before the end.
	TitleDelay = 0.5,
	-- Players joining a run older than this skip the intro.
	MaxRunAge = 30,
}

PresentationConfig.Music = {
	Volume = 0.45,
	-- Seconds for a track to fade fully in or out.
	FadeSeconds = 2.5,
	-- Enemies within this many studs of you raise the combat intensity.
	CombatRadius = 110,
	-- Threat per enemy tier; intensity is total threat / ThreatForFull.
	Threat = { Minor = 1, Major = 2, Boss = 4 } :: { [string]: number },
	ThreatForFull = 8,
	-- Intensity rises almost at once and falls back over about this long.
	CalmSeconds = 8,
	-- Below this intensity the explore track plays alone.
	CombatThreshold = 0.15,
}

PresentationConfig.KillFeed = {
	MaxEntries = 6,
	Lifetime = 5,
	-- Minor kills fill the feed quickly in big waves; majors and bosses always show.
	ShowMinorKills = true,
}

-- Nightfall medal colors (HUD tracker, completion banner, Mission Complete screen).
PresentationConfig.MedalColors = {
	Gold = Color3.fromRGB(255, 205, 70),
	Silver = Color3.fromRGB(210, 220, 230),
	Bronze = Color3.fromRGB(215, 140, 80),
} :: { [string]: Color3 }

-- Mission Complete screen headline per activity type.
PresentationConfig.CompleteTitles = {
	Story = "MISSION COMPLETE",
	Strike = "STRIKE COMPLETE",
	Nightfall = "NIGHTFALL COMPLETE",
	Dungeon = "DUNGEON COMPLETE",
	Raid = "RAID COMPLETE",
} :: { [string]: string }

PresentationConfig.Waypoint = {
	-- Pixels kept between an off-screen waypoint and the screen edge.
	EdgeMargin = 56,
}

return PresentationConfig
