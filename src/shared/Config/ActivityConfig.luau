--!strict
--[[
	ActivityConfig
	Destinations and every launchable activity shown in the Director.

	Unlock rules: an activity is launchable when every listed requirement is
	met (Story = mission id completed, Power = minimum character power).
	Only activities marked Playable have a map and appear in the Director.

	Playable activities are a series of Zones (MissionService). A zone is a
	stretch of the map with its own name (shown when you get there), a
	checkpoint (the respawn point from the moment the zone starts), a gate
	that opens when it is cleared and an ordered list of Steps:
	  Travel    reach the marker box Target
	  Waves     fight Waves from the EnemySpawns/<Spawns> markers: the next
	            wave comes when Advance (0.8) of the current one is down or
	            after Timer seconds; done when every wave is dead
	  Defend    keep someone inside Target for Duration seconds while waves
	            arrive every WaveInterval seconds
	  Survive   stay alive for Duration seconds of waves
	  Destroy   destroy Count objects (Enemy, default Shield Generator)
	            spawned at the markers <Target>_1..n while waves attack
	  Interact  use the console at Target (a hold-E prompt)
	  Patrol    send Waves out to walk the EnemySpawns/<Spawns> points in a
	            loop (they only notice you up close); finishes at once
	  Boss      the boss fight Boss (BossConfig); Arena names the marker
	            folder holding that fight's BossSpawn, Ammo_n, Pylon_n...
	            (needed when a map has more than one boss)
	Wave enemy counts are for one player and grow with the fireteam
	(CombatConfig.PartyScaling). Enemies arrive through rifts ("Portal"),
	from a dropship ("Dropship") or silently ("Ambush"), preferring spawn
	points out of the players' sight.

	Markers are looked up by name anywhere under the map's Markers folder
	(see MapKit): Spawns/PlayerStart, Checkpoints/<zone>, Objectives/...,
	EnemySpawns/<folder>/..., BossArena/...; gates are Gates/Gate_<zone>.

	Objectives (older format) describe activities that aren't built yet.

	Place is a key into AssetIds.Places (the reserved-server place to teleport to).
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Types = require(script.Parent.Parent.Types)

export type SpawnDef = {
	Group: string,
	Enemies: { { Id: string, Count: number } },
	Delay: number?,
}

export type ObjectiveDef = {
	Kind: "Travel" | "Defeat" | "Defend" | "Carry" | "Interact" | "Survive" | "Boss",
	Text: string,
	Target: string?,
	Count: number?,
	Duration: number?,
	Enemy: string?,
	Faction: string?,
	Item: string?,
	Spawns: { SpawnDef }?,
	WaveInterval: number?,
	MaxAlive: number?,
	Mechanic: string?,
	AddsGroup: string?,
	Checkpoint: string?,
	Door: string?,
}

export type WaveDef = {
	-- Enemy id -> count for a solo player.
	Enemies: { [string]: number },
	-- "Portal" (default), "Dropship" or "Ambush".
	Arrival: string?,
	-- EnemySpawns folder for this wave (default: the step's Spawns).
	Spawns: string?,
}

export type StepDef = {
	Kind: "Travel" | "Waves" | "Defend" | "Survive" | "Destroy" | "Interact" | "Patrol" | "Boss",
	Text: string,
	Target: string?,
	-- EnemySpawns folder (default: the zone's Id).
	Spawns: string?,
	Waves: { WaveDef }?,
	Advance: number?,
	Timer: number?,
	Duration: number?,
	WaveInterval: number?,
	Count: number?,
	Enemy: string?,
	Boss: string?,
	Arena: string?,
}

export type ZoneDef = {
	Id: string,
	Name: string,
	Steps: { StepDef },
	-- Respawn marker once the zone starts (default Checkpoints/<Id> if the map has it).
	Checkpoint: string?,
	-- Opened when the zone is cleared (default Gate_<Id> if the map has it).
	Gate: string?,
}

export type EncounterDef = {
	Id: string,
	Name: string,
	RecommendedPower: number,
	Description: string,
	Objectives: { ObjectiveDef },
	Zones: { ZoneDef }?,
	-- Weekly reward source id (MilestoneConfig) granted on first clear each week.
	Milestone: string?,
	-- Encounters without a built map yet are listed but skipped.
	Playable: boolean?,
}

export type DifficultyDef = {
	Id: string,
	Name: string,
	RecommendedPower: number,
	ModifierCount: number,
	-- Weekly reward sources claimed on completion at this difficulty.
	Milestones: { string }?,
	-- Extra end-of-activity drops at this difficulty.
	BonusDrops: number?,
}

export type RewardDef = {
	-- End-of-activity drops rolled from the activity's LootSource.
	Drops: { Min: number, Max: number },
	-- Overrides the LootSource rarity weights (e.g. story: Rare/Epic only).
	Rarities: { [string]: number }?,
	-- Chance of an extra drop from the LootSource's exclusive pool (raid gear).
	ExclusiveChance: number?,
	-- Extra drops given when every weekly milestone was already claimed.
	FallbackDrops: number?,
	-- Guarantee a weapon from the pool the player doesn't own yet.
	NewWeapon: boolean?,
}

export type ModifierDef = {
	Name: string,
	Description: string,
	EnemyHealth: number?,
	EnemyDamage: number?,
	AmmoDrops: number?,
	Surge: string?,
	SurgeBonus: number?,
	ExtraShields: number?,
	MatchGame: boolean?,
}

export type ActivityDef = {
	Id: string,
	Name: string,
	Type: Types.ActivityType,
	Destination: string,
	Description: string,
	RecommendedPower: number,
	MinPlayers: number,
	MaxPlayers: number,
	-- false = power is ignored in combat (PvP).
	PowerEnabled: boolean,
	-- Largest power advantage (delta) that still counts. nil = uncapped.
	PowerDeltaCap: number?,
	-- LootConfig source used for end-of-activity rewards.
	LootSource: string,
	Unlock: { Story: string?, Power: number? }?,
	Factions: { string },
	Place: string,
	Order: number,
	Objectives: { ObjectiveDef }?,
	Zones: { ZoneDef }?,
	Encounters: { EncounterDef }?,
	Difficulties: { DifficultyDef }?,
	PublicEvents: { { Id: string, Name: string, Description: string } }?,
	-- Strikes the Nightfall rotates through.
	Rotation: { string }?,
	-- Map model name (WorldConfig.Maps); activities without one aren't playable yet.
	Map: string?,
	Playable: boolean?,
	Rewards: RewardDef?,
	-- Show a run timer and score on the HUD (hardened strike).
	Scored: boolean?,
	-- Finish under these many seconds for a Gold/Silver/Bronze medal.
	Medals: { Gold: number, Silver: number, Bronze: number }?,
}

export type DestinationDef = {
	Name: string,
	Description: string,
	Kind: "Hub" | "Destination",
	Faction: string?,
}

local Destinations: { [string]: DestinationDef } = {
	Frostreach = {
		Name = "Frostreach",
		Description = "A frozen mountain range where the first colony ships went down. The Rustborn got there first.",
		Kind = "Destination",
		Faction = "Rustborn",
	},
	Meridian = {
		Name = "Meridian Coast",
		Description = "A drowned coastal city swallowed by jungle, where a Concord relay still hums above the waves.",
		Kind = "Destination",
		Faction = "Concord",
	},
	HavenSpire = {
		Name = "Haven Spire",
		Description = "The last city's last tower. Vendors, vault and your fireteam live here.",
		Kind = "Hub",
		Faction = nil,
	},
	Veyra = {
		Name = "Veyra",
		Description = "A rust-red desert world picked clean by Rustborn scavenger fleets.",
		Kind = "Destination",
		Faction = "Rustborn",
	},
	Hollowmere = {
		Name = "Hollowmere",
		Description = "A pale moon wrapped in whispering fog, where the Veiled keep their rites.",
		Kind = "Destination",
		Faction = "Veiled",
	},
	KesslerDrift = {
		Name = "Kessler Drift",
		Description = "A halo of shattered stations still humming with Concord machine thought.",
		Kind = "Destination",
		Faction = "Concord",
	},
	SolaceDeep = {
		Name = "Solace Deep",
		Description = "An ocean world sealed under kilometres of ice, and something drowned beneath it.",
		Kind = "Destination",
		Faction = nil,
	},
}

-- One wave: enemy id -> count (for a solo player), how it arrives
-- ("Portal", "Dropship", "Ambush") and an optional EnemySpawns folder.
local function Wave(enemies: { [string]: number }, arrival: string?, spawns: string?): WaveDef
	return { Enemies = enemies, Arrival = arrival, Spawns = spawns }
end

local List: { ActivityDef } = {
	-- Story campaign -----------------------------------------------------------------
	{
		Id = "STORY_01",
		Name = "First Light",
		Type = "Story",
		Destination = "Frostreach",
		Description = "Your ship is down in a snowbound valley. Follow the beacon through Frostfall village, hack the Rustborn outpost's uplink, shut down its reactor and end the Scrap Warden.",
		RecommendedPower = 350,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "FirstLight",
		Factions = { "Rustborn" },
		Place = "Mission",
		Order = 1,
		Map = "FirstLight",
		Playable = true,
		Rewards = { Drops = { Min = 2, Max = 3 }, Rarities = { Rare = 60, Epic = 40 }, NewWeapon = true },
		Zones = {
			{
				Id = "CrashSite",
				Name = "The Crash Site",
				Steps = {
					{ Kind = "Travel", Text = "Search the wreckage", Target = "Wreck" },
					{
						Kind = "Waves",
						Text = "Fight off the scavengers",
						Waves = {
							Wave({ RUST_GUNNER = 3, RUST_SCRAPPER = 3 }),
							Wave({ RUST_SKIFF_DRONE = 2, RUST_SCRAPPER = 2 }, "Dropship"),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Village",
				Name = "Frostfall Village",
				Steps = {
					{ Kind = "Travel", Text = "Push into Frostfall", Target = "VillageGate" },
					{
						Kind = "Waves",
						Text = "Clear the village",
						Waves = {
							Wave({ RUST_GUNNER = 4, RUST_SCRAPPER = 3 }),
							Wave({ RUST_SNIPER = 2, RUST_GUNNER = 1 }, "Ambush", "VillageRoofs"),
							Wave({ RUST_SKIFF_DRONE = 3, RUST_SCRAPPER = 2 }, "Dropship"),
							Wave({ RUST_BREAKER = 1, RUST_GUNNER = 3 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Outpost",
				Name = "Kessrin Outpost",
				Steps = {
					{
						Kind = "Waves",
						Text = "Take the courtyard",
						Waves = {
							Wave({ RUST_TURRET = 2, RUST_GUNNER = 1 }, "Ambush", "OutpostTurrets"),
							Wave({ RUST_GUNNER = 3, RUST_SCRAPPER = 3 }),
						},
					},
					{
						Kind = "Defend",
						Text = "Hack the outpost uplink",
						Target = "Uplink",
						Duration = 60,
						WaveInterval = 15,
						Waves = {
							Wave({ RUST_SCRAPPER = 3, RUST_GUNNER = 1 }),
							Wave({ RUST_SKIFF_DRONE = 2, RUST_GUNNER = 2 }, "Dropship"),
							Wave({ RUST_SNIPER = 1, RUST_SCRAPPER = 3 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Reactor",
				Name = "The Reactor",
				Steps = {
					{
						Kind = "Waves",
						Text = "Clear the reactor hall",
						Waves = {
							Wave({ RUST_GUNNER = 3, RUST_SCRAPPER = 3 }),
							Wave({ RUST_BREAKER = 1, RUST_SKIFF_DRONE = 2 }),
						},
					},
					{
						Kind = "Destroy",
						Text = "Destroy the coolant regulators",
						Target = "Regulator",
						Count = 3,
						WaveInterval = 18,
						Waves = { Wave({ RUST_SCRAPPER = 2, RUST_GUNNER = 1 }) },
					},
				} :: { StepDef },
			},
			{
				Id = "ScrapPit",
				Name = "The Scrap Pit",
				Steps = { { Kind = "Boss", Text = "Defeat Orrek, the Scrap Warden", Boss = "SCRAP_WARDEN" } } :: { StepDef },
			},
		} :: { ZoneDef },
	},
	{
		Id = "STORY_02",
		Name = "Sunken Relay",
		Type = "Story",
		Destination = "Meridian",
		Description = "The beacon's echo comes from a drowned city. Land on the beach, cross the flooded market and climb the Concord relay tower to silence the Tide Marshal on its crown.",
		RecommendedPower = 380,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "SunkenRelay",
		Unlock = { Story = "STORY_01" },
		Factions = { "Concord" },
		Place = "Mission",
		Order = 2,
		Map = "SunkenRelay",
		Playable = true,
		Rewards = { Drops = { Min = 2, Max = 3 }, Rarities = { Rare = 55, Epic = 45 }, NewWeapon = true },
		Zones = {
			{
				Id = "Beach",
				Name = "Glasswater Beach",
				Steps = {
					{ Kind = "Travel", Text = "Get off the beach", Target = "Dunes" },
					{
						Kind = "Waves",
						Text = "Break the Concord landing guard",
						Waves = {
							Wave({ CONC_SENTRY = 3, CONC_LANCER = 3 }),
							Wave({ CONC_DRONE_PRISM = 3, CONC_SENTRY = 1 }, "Dropship"),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Market",
				Name = "The Drowned Market",
				Steps = {
					{
						Kind = "Waves",
						Text = "Fight through the flooded market",
						Waves = {
							Wave({ CONC_SENTRY = 3, CONC_LANCER = 3 }),
							Wave({ CONC_MARKSMAN = 2, CONC_SENTRY = 1 }, "Ambush", "MarketBalconies"),
							Wave({ CONC_DRONE_PRISM = 3, CONC_LANCER = 2 }, "Dropship"),
							Wave({ CONC_WARDEN = 1, CONC_SENTRY = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "LowerDeck",
				Name = "Relay Tower: Lower Deck",
				Steps = {
					{
						Kind = "Waves",
						Text = "Clear the relay floor",
						Waves = {
							Wave({ CONC_ARC_TURRET = 2, CONC_SENTRY = 2 }, "Ambush"),
							Wave({ CONC_LANCER = 4, CONC_SENTRY = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "SignalDeck",
				Name = "Relay Tower: Signal Deck",
				Steps = {
					{
						Kind = "Destroy",
						Text = "Destroy the signal jammers",
						Target = "Jammer",
						Count = 3,
						Enemy = "CONC_JAMMER",
						WaveInterval = 16,
						Waves = {
							Wave({ CONC_SENTRY = 2, CONC_LANCER = 2 }),
							Wave({ CONC_MARKSMAN = 1, CONC_DRONE_PRISM = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Crown",
				Name = "The Relay Crown",
				Steps = { { Kind = "Boss", Text = "Defeat the Tide Marshal", Boss = "TIDE_MARSHAL" } } :: { StepDef },
			},
		} :: { ZoneDef },
	},
	{
		Id = "STORY_03",
		Name = "The Hollow Dark",
		Type = "Story",
		Destination = "Hollowmere",
		Description = "Something answered the beacon from under Hollowmere. Follow the Veiled song into the caves, through their barracks, and stop the Hollow Priest's ritual. Bring a light.",
		RecommendedPower = 410,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "HollowDark",
		Unlock = { Story = "STORY_02" },
		Factions = { "Veiled" },
		Place = "Mission",
		Order = 3,
		Map = "HollowDark",
		Playable = true,
		Rewards = { Drops = { Min = 2, Max = 3 }, Rarities = { Rare = 50, Epic = 50 }, NewWeapon = true },
		Zones = {
			{
				Id = "Mouth",
				Name = "The Pale Woods",
				Steps = {
					{ Kind = "Travel", Text = "Follow the song to the caves", Target = "CaveMouth" },
					{
						Kind = "Waves",
						Text = "Silence the watchers at the mouth",
						Waves = {
							Wave({ VEIL_HUSK = 5, VEIL_ACOLYTE = 2 }),
							Wave({ VEIL_SHADE_WISP = 3, VEIL_ACOLYTE = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Caverns",
				Name = "The Glimmering Deep",
				Steps = {
					{ Kind = "Travel", Text = "Descend into the caverns", Target = "CavernHeart" },
					{
						Kind = "Waves",
						Text = "Clear the crystal caverns",
						Waves = {
							Wave({ VEIL_HUSK = 6, VEIL_ACOLYTE = 2 }, "Ambush"),
							Wave({ VEIL_SEER = 2, VEIL_ACOLYTE = 1 }, "Ambush", "CavernLedges"),
							Wave({ VEIL_SHADE_WISP = 3, VEIL_HUSK = 4 }),
							Wave({ VEIL_WRAITHKNIGHT = 1, VEIL_ACOLYTE = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Barracks",
				Name = "The Veiled Barracks",
				Steps = {
					{
						Kind = "Waves",
						Text = "Clear the barracks",
						Waves = {
							Wave({ VEIL_ACOLYTE = 3, VEIL_HUSK = 4 }),
							Wave({ VEIL_CANTOR = 1, VEIL_HUSK = 4 }),
						},
					},
					{
						Kind = "Interact",
						Text = "Shatter the ward seal",
						Target = "WardSeal",
						Duration = 2,
						WaveInterval = 14,
						Waves = { Wave({ VEIL_HUSK = 4, VEIL_SHADE_WISP = 1 }) },
					},
				} :: { StepDef },
			},
			{
				Id = "Ritual",
				Name = "The Hollow Choir",
				Steps = {
					{
						Kind = "Destroy",
						Text = "Shatter the ritual crystals",
						Target = "RitualCrystal",
						Count = 3,
						Enemy = "VEIL_RITUAL_CRYSTAL",
						WaveInterval = 15,
						Waves = {
							Wave({ VEIL_HUSK = 4, VEIL_ACOLYTE = 1 }),
							Wave({ VEIL_SHADE_WISP = 2, VEIL_SEER = 1 }),
						},
					},
					{ Kind = "Boss", Text = "Defeat the Hollow Priest", Boss = "HOLLOW_PRIEST" },
				} :: { StepDef },
			},
		} :: { ZoneDef },
	},
	{
		Id = "STORY_04",
		Name = "Into the Fog",
		Type = "Story",
		Destination = "Hollowmere",
		Description = "The beacon's signal came from Hollowmere. Something answered it.",
		RecommendedPower = 420,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_03" },
		Factions = { "Veiled" },
		Place = "Mission",
		Order = 4,
		Objectives = {
			{ Kind = "Travel", Text = "Follow the signal into the fog", Target = "FogEdge" },
			{ Kind = "Defeat", Text = "Silence the Veiled acolytes", Count = 20, Faction = "Veiled" },
			{ Kind = "Interact", Text = "Read the altar inscription", Target = "Altar" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_05",
		Name = "Choir Below",
		Type = "Story",
		Destination = "Hollowmere",
		Description = "Descend beneath the altar and stop the rite before it completes.",
		RecommendedPower = 425,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_04" },
		Factions = { "Veiled" },
		Place = "Mission",
		Order = 5,
		Objectives = {
			{ Kind = "Travel", Text = "Descend into the crypt", Target = "CryptDoor" },
			{ Kind = "Survive", Text = "Survive the rite", Duration = 75 },
			{ Kind = "Boss", Text = "Defeat Wraithknight Sorrow", Enemy = "VEIL_WRAITHKNIGHT_SORROW" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_06",
		Name = "Dead Signal",
		Type = "Story",
		Destination = "KesslerDrift",
		Description = "Recover the Concord data core that heard the rite's song.",
		RecommendedPower = 430,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_05" },
		Factions = { "Concord" },
		Place = "Mission",
		Order = 6,
		Objectives = {
			{ Kind = "Travel", Text = "Board the derelict station", Target = "Airlock" },
			{ Kind = "Carry", Text = "Extract the data core", Item = "DataCore", Target = "Extraction" },
			{ Kind = "Defend", Text = "Hold until the dropship arrives", Target = "Extraction", Duration = 60 },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_07",
		Name = "The Arbiter's Gaze",
		Type = "Story",
		Destination = "KesslerDrift",
		Description = "The Concord have noticed you. Shut down the Overseer before it calculates your end.",
		RecommendedPower = 435,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_06" },
		Factions = { "Concord" },
		Place = "Mission",
		Order = 7,
		Objectives = {
			{ Kind = "Travel", Text = "Reach the Overseer's core", Target = "CoreChamber" },
			{ Kind = "Defeat", Text = "Destroy the Warden Frames", Count = 3, Enemy = "CONC_WARDEN" },
			{ Kind = "Boss", Text = "Defeat the Overseer", Enemy = "CONC_OVERSEER" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_08",
		Name = "Last Light",
		Type = "Story",
		Destination = "SolaceDeep",
		Description = "Beneath the ice of Solace Deep, the source of the song waits. End it.",
		RecommendedPower = 440,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_07" },
		Factions = { "Veiled", "Concord" },
		Place = "Mission",
		Order = 8,
		Objectives = {
			{ Kind = "Travel", Text = "Break through the ice shelf", Target = "IceShelf" },
			{ Kind = "Defend", Text = "Protect the drill", Target = "DrillSite", Duration = 120 },
			{ Kind = "Boss", Text = "Defeat the Drowned Herald", Enemy = "VEIL_DROWNED_HERALD" },
		} :: { ObjectiveDef },
	},

	-- Patrol zones --------------------------------------------------------------------
	{
		Id = "PATROL_VEYRA",
		Name = "Veyra: The Rust Flats",
		Type = "Patrol",
		Destination = "Veyra",
		Description = "Open desert, salvage fields and Rustborn camps.",
		RecommendedPower = 380,
		MinPlayers = 1,
		MaxPlayers = 12,
		PowerEnabled = true,
		LootSource = "Patrol",
		Unlock = { Story = "STORY_01" },
		Factions = { "Rustborn" },
		Place = "PatrolVeyra",
		Order = 10,
		PublicEvents = {
			{
				Id = "EVT_SUPPLY_DROP",
				Name = "Supply Drop",
				Description = "Defend a falling supply cache from scavengers.",
			},
			{ Id = "EVT_WARLORD_AMBUSH", Name = "Warlord Ambush", Description = "A Rustborn warlord makes a stand." },
		},
	},
	{
		Id = "PATROL_HOLLOWMERE",
		Name = "Hollowmere: The Pale Woods",
		Type = "Patrol",
		Destination = "Hollowmere",
		Description = "Fog-drowned forest and crumbling shrines.",
		RecommendedPower = 410,
		MinPlayers = 1,
		MaxPlayers = 12,
		PowerEnabled = true,
		LootSource = "Patrol",
		Unlock = { Story = "STORY_04" },
		Factions = { "Veiled" },
		Place = "PatrolHollowmere",
		Order = 11,
		PublicEvents = {
			{ Id = "EVT_FOG_RITE", Name = "Fog Rite", Description = "Disrupt a Veiled ritual before it completes." },
			{ Id = "EVT_LOST_KEEPER", Name = "Lost Keeper", Description = "Escort a lost scout back to safety." },
		},
	},
	{
		Id = "PATROL_KESSLER",
		Name = "Kessler Drift: The Graveyard Ring",
		Type = "Patrol",
		Destination = "KesslerDrift",
		Description = "Zero-g wreckage and humming Concord relays.",
		RecommendedPower = 430,
		MinPlayers = 1,
		MaxPlayers = 12,
		PowerEnabled = true,
		LootSource = "Patrol",
		Unlock = { Story = "STORY_06" },
		Factions = { "Concord" },
		Place = "PatrolKessler",
		Order = 12,
		PublicEvents = {
			{ Id = "EVT_RELAY_SURGE", Name = "Relay Surge", Description = "Overload three Concord relays at once." },
			{ Id = "EVT_SALVAGE_RUN", Name = "Salvage Run", Description = "Recover data shards before they burn up." },
		},
	},
	{
		Id = "PATROL_SOLACE",
		Name = "Solace Deep: The Ice Shelf",
		Type = "Patrol",
		Destination = "SolaceDeep",
		Description = "Frozen canyons over a black ocean. Every faction wants what lies below.",
		RecommendedPower = 450,
		MinPlayers = 1,
		MaxPlayers = 12,
		PowerEnabled = true,
		LootSource = "Patrol",
		Unlock = { Story = "STORY_08" },
		Factions = { "Rustborn", "Veiled", "Concord" },
		Place = "PatrolSolace",
		Order = 13,
		PublicEvents = {
			{ Id = "EVT_THAW", Name = "The Thaw", Description = "Hold a drill site while the ice cracks around you." },
			{
				Id = "EVT_THREE_WAY",
				Name = "Three-Way Brawl",
				Description = "Two factions clash; clean up the winner.",
			},
		},
	},

	-- Strikes ------------------------------------------------------------------------
	{
		Id = "STRIKE_RUST_TYRANT",
		Name = "The Rust Tyrant",
		Type = "Strike",
		Destination = "Veyra",
		Description = "Kaldrek has united the scavenger clans. Break his fortress-crawler.",
		RecommendedPower = 450,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Strike",
		Unlock = { Story = "STORY_08" },
		Factions = { "Rustborn" },
		Place = "Strike",
		Order = 20,
		Objectives = {
			{ Kind = "Travel", Text = "Board the fortress-crawler", Target = "CrawlerRamp" },
			{ Kind = "Defeat", Text = "Clear the engine deck", Count = 30, Faction = "Rustborn" },
			{ Kind = "Carry", Text = "Plant the charge on the engine", Item = "BreachCharge", Target = "Engine" },
			{ Kind = "Boss", Text = "Defeat Kaldrek, the Rust Tyrant", Enemy = "RUST_KALDREK" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STRIKE_HOLLOW_CHOIR",
		Name = "The Hollow Choir",
		Type = "Strike",
		Destination = "Hollowmere",
		Description = "The Veiled sing their queen awake. Silence the choir.",
		RecommendedPower = 460,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Strike",
		Unlock = { Story = "STORY_08" },
		Factions = { "Veiled" },
		Place = "Strike",
		Order = 21,
		Objectives = {
			{ Kind = "Travel", Text = "Enter the cathedral", Target = "CathedralDoor" },
			{ Kind = "Defend", Text = "Hold the nave against the choir", Target = "Nave", Duration = 90 },
			{ Kind = "Boss", Text = "Defeat Mother Sorrow", Enemy = "VEIL_MOTHER_SORROW" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STRIKE_ARBITER",
		Name = "Arbiter Protocol",
		Type = "Strike",
		Destination = "KesslerDrift",
		Description = "A Concord mind is rewriting the station's physics. Delete it.",
		RecommendedPower = 470,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Strike",
		Unlock = { Story = "STORY_08" },
		Factions = { "Concord" },
		Place = "Strike",
		Order = 22,
		Objectives = {
			{ Kind = "Travel", Text = "Reach the logic core", Target = "LogicCore" },
			{ Kind = "Interact", Text = "Disable the three firewalls", Target = "Firewall" },
			{ Kind = "Boss", Text = "Defeat Prime Arbiter Kethis", Enemy = "CONC_PRIME_ARBITER" },
		} :: { ObjectiveDef },
	},

	-- Nightfall ------------------------------------------------------------------------
	{
		Id = "NIGHTFALL",
		Name = "Hollow Spire",
		Type = "Nightfall",
		Destination = "Veyra",
		Description = "A hardened strike up a cliff fortress at dusk: fight up Redrock Canyon, break the Iron Gate's generators, hold the inner halls and bring down Vekta on the Spire Crown. Two weekly modifiers; beat the clock for a medal.",
		RecommendedPower = 450,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		PowerDeltaCap = 0,
		LootSource = "Nightfall",
		Unlock = { Story = "STORY_01" },
		Factions = { "Rustborn" },
		Place = "Strike",
		Order = 30,
		Map = "HollowSpire",
		Playable = true,
		Scored = true,
		Rewards = { Drops = { Min = 1, Max = 2 } },
		Difficulties = {
			{
				Id = "Adept",
				Name = "Adept",
				RecommendedPower = 450,
				ModifierCount = 2,
				Milestones = { "NIGHTFALL_WEEKLY" },
			},
			{
				Id = "Hero",
				Name = "Hero",
				RecommendedPower = 470,
				ModifierCount = 2,
				Milestones = { "NIGHTFALL_WEEKLY" },
				BonusDrops = 1,
			},
			{
				Id = "Legend",
				Name = "Legend",
				RecommendedPower = 490,
				ModifierCount = 2,
				Milestones = { "NIGHTFALL_WEEKLY", "NIGHTFALL_LEGEND" },
				BonusDrops = 2,
			},
		} :: { DifficultyDef },
		Medals = { Gold = 480, Silver = 660, Bronze = 900 },
		Zones = {
			{
				Id = "Canyon",
				Name = "Redrock Canyon",
				Steps = {
					{ Kind = "Travel", Text = "Advance up the canyon", Target = "CanyonBend" },
					{
						Kind = "Waves",
						Text = "Break through the canyon",
						Waves = {
							Wave({ RUST_TURRET = 2, RUST_GUNNER = 3 }, "Ambush", "CanyonLedges"),
							Wave({ RUST_SCRAPPER = 4, RUST_GUNNER = 2 }),
							Wave({ RUST_SKIFF_DRONE = 3, RUST_SCRAPPER = 2 }, "Dropship"),
							Wave({ RUST_BREAKER = 1, RUST_GUNNER = 3, RUST_SNIPER = 1 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Gate",
				Name = "The Iron Gate",
				Steps = {
					{
						Kind = "Destroy",
						Text = "Break the three shield generators",
						Target = "Generator",
						Count = 3,
						WaveInterval = 14,
						Waves = {
							Wave({ RUST_SCRAPPER = 3, RUST_GUNNER = 2 }),
							Wave({ RUST_SNIPER = 2 }, "Ambush", "GateWall"),
							Wave({ RUST_SKIFF_DRONE = 2, RUST_GUNNER = 2 }, "Dropship"),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Halls",
				Name = "The Inner Halls",
				Steps = {
					{
						Kind = "Waves",
						Text = "Clear the inner halls",
						Waves = {
							Wave({ RUST_GUNNER = 4, RUST_SCRAPPER = 4 }),
							Wave({ RUST_TURRET = 2, RUST_GUNNER = 2 }, "Ambush", "HallTurrets"),
							Wave({ RUST_BREAKER = 1, RUST_SCRAPPER = 3 }),
						},
					},
					{
						Kind = "Defend",
						Text = "Hold the lift controls",
						Target = "LiftControls",
						Duration = 35,
						WaveInterval = 11,
						Waves = {
							Wave({ RUST_SCRAPPER = 3, RUST_GUNNER = 2 }),
							Wave({ RUST_SKIFF_DRONE = 2, RUST_SCRAPPER = 2 }),
						},
					},
				} :: { StepDef },
			},
			{
				Id = "Summit",
				Name = "The Spire Crown",
				Steps = {
					{ Kind = "Boss", Text = "Defeat Vekta, the Spire Overseer", Boss = "SPIRE_OVERSEER" },
				} :: { StepDef },
			},
		} :: { ZoneDef },
	},

	-- Dungeon --------------------------------------------------------------------------
	{
		Id = "DUNGEON_SUNKEN_RELIQUARY",
		Name = "Sunken Reliquary",
		Type = "Dungeon",
		Destination = "SolaceDeep",
		Description = "A flooded vault where the Veiled keep relics of the drowned star.",
		RecommendedPower = 490,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		PowerDeltaCap = 0,
		LootSource = "Dungeon",
		Unlock = { Story = "STORY_08", Power = 470 },
		Factions = { "Veiled" },
		Place = "Dungeon",
		Order = 40,
		Encounters = {
			{
				Id = "FLOODED_NAVE",
				Name = "The Flooded Nave",
				RecommendedPower = 490,
				Description = "Carry relics to pressure plates to drain the nave before the water rises.",
				Objectives = {
					{ Kind = "Carry", Text = "Place relics on the plates", Item = "Relic", Target = "PressurePlate" },
					{ Kind = "Survive", Text = "Hold while the nave drains", Duration = 60 },
				},
			},
			{
				Id = "RELIQUARY_WARDEN",
				Name = "The Reliquary Warden",
				RecommendedPower = 490,
				Description = "Ysolde guards the final relic behind an immune shield.",
				Objectives = {
					{ Kind = "Boss", Text = "Defeat Ysolde, Reliquary Warden", Enemy = "VEIL_YSOLDE" },
				},
				Milestone = "DUNGEON_WEEKLY",
			},
		} :: { EncounterDef },
	},

	-- Raid -------------------------------------------------------------------------------
	{
		Id = "RAID_VAULT_OF_ECHOES",
		Name = "Vault of Echoes",
		Type = "Raid",
		Destination = "SolaceDeep",
		Description = "Six Keepers descend into a gold-and-black vault where every sound becomes a weapon. Break the Gate, cross the Descent, carry echoes through the Echo Chamber, slip through the Silent Hall and silence the Echo Sovereign. Each encounter's chest holds a weekly Pinnacle.",
		RecommendedPower = 495,
		MinPlayers = 1,
		MaxPlayers = 6,
		PowerEnabled = true,
		PowerDeltaCap = 0,
		LootSource = "Raid",
		Unlock = { Power = 480 },
		Factions = { "Rustborn", "Concord" },
		Place = "Raid",
		Order = 50,
		Map = "VaultOfEchoes",
		Playable = true,
		Rewards = { Drops = { Min = 0, Max = 0 }, ExclusiveChance = 0.2, FallbackDrops = 1 },
		Encounters = {
			{
				Id = "THE_GATE",
				Name = "The Gate",
				RecommendedPower = 495,
				Description = "Harrowmaw guards the vault gate, immune while its echo plates are silent. Hold the lit plates (they change every cycle) to charge Echo Resonance, then burn it. Don't let the enrage timer run out.",
				Playable = true,
				Milestone = "RAID_ENCOUNTER_1",
				Objectives = {},
				Zones = {
					{
						Id = "Gate",
						Name = "The Gate",
						Steps = {
							{ Kind = "Travel", Text = "Approach the vault gate", Target = "GateEntry" },
							{
								Kind = "Boss",
								Text = "Defeat Harrowmaw, the Echo Engine",
								Boss = "HARROWMAW",
								Arena = "GateArena",
							},
						} :: { StepDef },
					},
				},
			},
			{
				Id = "THE_DESCENT",
				Name = "The Descent",
				RecommendedPower = 495,
				Description = "A jumping puzzle over the vault's heart: moving platforms, long drops. Fall and you're back at the top.",
				Playable = true,
				Objectives = {},
				Zones = {
					{
						Id = "Descent",
						Name = "The Descent",
						Steps = { { Kind = "Travel", Text = "Cross the Descent", Target = "DescentEnd" } } :: { StepDef },
					},
				},
			},
			{
				Id = "THE_ECHO_CHAMBER",
				Name = "The Echo Chamber",
				RecommendedPower = 498,
				Description = "Oriane is sealed behind three echoes. Kill the marked Echo Bearer in each room and carry its echo to the well before it fades. Adds never stop coming.",
				Playable = true,
				Milestone = "RAID_ENCOUNTER_2",
				Objectives = {},
				Zones = {
					{
						Id = "Chamber",
						Name = "The Echo Chamber",
						Steps = {
							{ Kind = "Travel", Text = "Enter the Echo Chamber", Target = "ChamberEntry" },
							{
								Kind = "Boss",
								Text = "Defeat Oriane, the Echo Warden",
								Boss = "ECHO_WARDEN",
								Arena = "ChamberArena",
							},
						} :: { StepDef },
					},
				},
			},
			{
				Id = "THE_SILENT_HALL",
				Name = "The Silent Hall",
				RecommendedPower = 498,
				Description = "Sweeping lasers and sentinel patrols. Time your runs.",
				Playable = true,
				Objectives = {},
				Zones = {
					{
						Id = "SilentHall",
						Name = "The Silent Hall",
						Steps = {
							{
								Kind = "Patrol",
								Text = "Slip past the sentinels",
								Spawns = "HallPatrol",
								Waves = { Wave({ CONC_VAULT_SENTINEL = 4 }) },
							},
							{ Kind = "Travel", Text = "Reach the Sovereign's door", Target = "HallEnd" },
						} :: { StepDef },
					},
				},
			},
			{
				Id = "ECHO_SOVEREIGN",
				Name = "The Echo Sovereign",
				RecommendedPower = 500,
				Description = "The heart of the vault. Three phases: pillars, guardians, and a final song. When it winds up its nova, get inside a lit circle. It enrages after nine minutes.",
				Playable = true,
				Milestone = "RAID_ENCOUNTER_3",
				Objectives = {},
				Zones = {
					{
						Id = "Throne",
						Name = "The Sovereign's Throne",
						Steps = {
							{ Kind = "Travel", Text = "Face the Sovereign", Target = "ThroneEntry" },
							{
								Kind = "Boss",
								Text = "Silence the Echo Sovereign",
								Boss = "ECHO_SOVEREIGN",
								Arena = "ThroneArena",
							},
						} :: { StepDef },
					},
				},
			},
		} :: { EncounterDef },
	},

	-- PvP --------------------------------------------------------------------------------
	{
		Id = "PVP_PROVING_GROUNDS",
		Name = "Proving Grounds",
		Type = "PvP",
		Destination = "HavenSpire",
		Description = "6v6 skirmish in the Spire's training halls. Power is disabled.",
		RecommendedPower = 350,
		MinPlayers = 2,
		MaxPlayers = 12,
		PowerEnabled = false,
		LootSource = "PvP",
		Unlock = { Story = "STORY_03" },
		Factions = {},
		Place = "PvP",
		Order = 60,
	},
}

-- Hardened strike modifiers. Two are active each week (ActivityRules.WeeklyModifiers).
local NightfallModifiers: { [string]: ModifierDef } = {
	EXTRA_SHIELDS = {
		Name = "Overcharged Shields",
		Description = "Unshielded enemies gain a Flare shield and existing shields are stronger.",
		ExtraShields = 0.5,
	},
	MATCH_GAME = {
		Name = "Match Game",
		Description = "Shields only break to weapons of the matching element.",
		MatchGame = true,
	},
	IRONHIDE = { Name = "Ironhide", Description = "Enemies have 30% more health.", EnemyHealth = 1.3 },
	BLOODLUST = { Name = "Bloodlust", Description = "Enemies deal 30% more damage.", EnemyDamage = 1.3 },
	FLARE_SURGE = {
		Name = "Flare Surge",
		Description = "Your Flare weapons deal 25% more damage.",
		Surge = "Flare",
		SurgeBonus = 0.25,
	},
	SCARCITY = { Name = "Scarcity", Description = "Heavy ammo drops half as often.", AmmoDrops = 0.5 },
}

local ById: { [string]: ActivityDef } = {}
for _, activity in List do
	ById[activity.Id] = activity
end

return TableUtil.DeepFreeze({
	Destinations = Destinations,
	List = List,
	ById = ById,
	NightfallModifiers = NightfallModifiers,
})
