--!strict
--[[
	ActivityConfig
	Destinations and every launchable activity shown in the Director.

	Unlock rules: an activity is launchable when every listed requirement is
	met (Story = mission id completed, Power = minimum character power).
	Only activities marked Playable have a map and appear in the Director.

	Objectives are an ordered script ActivityService walks through. Kinds:
	  Travel    reach the zone marker named Target
	  Defeat    defeat every enemy spawned from Spawns
	  Defend    keep a player inside zone Target for Duration seconds while
	            waves from Spawns arrive every WaveInterval seconds
	  Carry     bring Item from its spawn to Target            (not built yet)
	  Interact  use the object named Target                    (not built yet)
	  Survive   stay alive for Duration seconds of waves       (not built yet)
	  Boss      defeat Enemy, spawned at marker Target, running the named
	            Mechanic ("Standard", "ImmuneAdds", "EchoPlates"); adds spawn
	            at the AddsGroup markers

	Spawns: each entry spawns its Enemies at the map markers named
	Spawn_<Group>_<n>, optionally Delay seconds after the objective starts.
	When an objective completes, the respawn checkpoint moves to marker
	Checkpoint and the part named Door opens.

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

export type EncounterDef = {
	Id: string,
	Name: string,
	RecommendedPower: number,
	Description: string,
	Objectives: { ObjectiveDef },
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
}

export type DestinationDef = {
	Name: string,
	Description: string,
	Kind: "Hub" | "Destination",
	Faction: string?,
}

local Destinations: { [string]: DestinationDef } = {
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

local List: { ActivityDef } = {
	-- Story campaign -----------------------------------------------------------------
	{
		Id = "STORY_01",
		Name = "First Light",
		Type = "Story",
		Destination = "Veyra",
		Description = "A distress beacon flickers on Veyra. Fight through a ruined outpost, hack its terminal and bring down the Rustborn captain who holds it.",
		RecommendedPower = 350,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Factions = { "Rustborn" },
		Place = "Mission",
		Order = 1,
		Map = "FirstLight",
		Playable = true,
		Rewards = { Drops = { Min = 2, Max = 3 }, Rarities = { Rare = 60, Epic = 40 } },
		Objectives = {
			{ Kind = "Travel", Text = "Reach the outpost", Target = "Zone_Outpost", Checkpoint = "Checkpoint_Outpost" },
			{
				Kind = "Defeat",
				Text = "Clear the courtyard",
				Spawns = {
					{
						Group = "Courtyard",
						Enemies = { { Id = "RUST_GUNNER", Count = 6 }, { Id = "RUST_SCRAPPER", Count = 4 } },
					},
					{
						Group = "CourtyardBack",
						Delay = 8,
						Enemies = { { Id = "RUST_BREAKER", Count = 1 }, { Id = "RUST_GUNNER", Count = 1 } },
					},
				},
				Checkpoint = "Checkpoint_Terminal",
				Door = "Door_Terminal",
			},
			{
				Kind = "Defend",
				Text = "Hack the terminal",
				Target = "Zone_Terminal",
				Duration = 20,
				WaveInterval = 7,
				MaxAlive = 8,
				Spawns = {
					{
						Group = "Terminal",
						Enemies = { { Id = "RUST_SCRAPPER", Count = 2 }, { Id = "RUST_GUNNER", Count = 2 } },
					},
				},
				Checkpoint = "Checkpoint_Boss",
				Door = "Door_Boss",
			},
			{
				Kind = "Boss",
				Text = "Defeat the Captain: Vulk, the Scrap Baron",
				Enemy = "RUST_SCRAP_BARON",
				Target = "BossSpawn",
				Mechanic = "Standard",
				AddsGroup = "BossAdds",
			},
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_02",
		Name = "Dust and Iron",
		Type = "Story",
		Destination = "Veyra",
		Description = "Hold an old uplink long enough to hear who sent the beacon.",
		RecommendedPower = 365,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_01" },
		Factions = { "Rustborn" },
		Place = "Mission",
		Order = 2,
		Objectives = {
			{ Kind = "Travel", Text = "Find the uplink tower", Target = "Uplink" },
			{ Kind = "Defend", Text = "Defend the uplink", Target = "UplinkZone", Duration = 90 },
			{ Kind = "Defeat", Text = "Defeat the Rustbreaker", Count = 1, Enemy = "RUST_BREAKER" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_03",
		Name = "The Scrapyard King",
		Type = "Story",
		Destination = "Veyra",
		Description = "Steal a power cell from the Rustborn quartermaster and bring it home.",
		RecommendedPower = 380,
		MinPlayers = 1,
		MaxPlayers = 3,
		PowerEnabled = true,
		LootSource = "Story",
		Unlock = { Story = "STORY_02" },
		Factions = { "Rustborn" },
		Place = "Mission",
		Order = 3,
		Objectives = {
			{ Kind = "Travel", Text = "Infiltrate the scrapyard", Target = "ScrapyardGate" },
			{ Kind = "Carry", Text = "Carry the power cell to the skiff", Item = "PowerCell", Target = "Skiff" },
			{ Kind = "Boss", Text = "Defeat Harrow, the Quartermaster", Enemy = "RUST_QUARTERMASTER" },
		} :: { ObjectiveDef },
	},
	{
		Id = "STORY_04",
		Name = "Into the Fog",
		Type = "Story",
		Destination = "Hollowmere",
		Description = "The beacon's signal came from Hollowmere. Something answered it.",
		RecommendedPower = 395,
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
		RecommendedPower = 405,
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
		RecommendedPower = 415,
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
		RecommendedPower = 430,
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
		Description = "A hardened strike into Kaldrek's fortress. Three arenas, a tyrant at the top, and two weekly modifiers stacked against you. Beat the clock for a higher score.",
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
		Objectives = {
			{ Kind = "Travel", Text = "Enter the Hollow Spire", Target = "Zone_Gate", Checkpoint = "Checkpoint_Gate" },
			{
				Kind = "Defeat",
				Text = "Clear the Gate Hall",
				Spawns = {
					{
						Group = "Arena1",
						Enemies = { { Id = "RUST_GUNNER", Count = 5 }, { Id = "RUST_SCRAPPER", Count = 4 } },
					},
					{
						Group = "Arena1",
						Delay = 10,
						Enemies = { { Id = "RUST_BREAKER", Count = 1 }, { Id = "RUST_GUNNER", Count = 2 } },
					},
				},
				Checkpoint = "Checkpoint_Arena2",
				Door = "Door_1",
			},
			{
				Kind = "Defeat",
				Text = "Break the Forge Line",
				Spawns = {
					{
						Group = "Arena2",
						Enemies = {
							{ Id = "RUST_GUNNER", Count = 6 },
							{ Id = "RUST_SCRAPPER", Count = 3 },
							{ Id = "RUST_BREAKER", Count = 1 },
						},
					},
					{
						Group = "Arena2",
						Delay = 12,
						Enemies = { { Id = "RUST_BREAKER", Count = 1 }, { Id = "RUST_SCRAPPER", Count = 4 } },
					},
				},
				Checkpoint = "Checkpoint_Arena3",
				Door = "Door_2",
			},
			{
				Kind = "Defend",
				Text = "Hold the lift",
				Target = "Zone_Lift",
				Duration = 30,
				WaveInterval = 8,
				MaxAlive = 10,
				Spawns = {
					{
						Group = "Arena3",
						Enemies = { { Id = "RUST_SCRAPPER", Count = 3 }, { Id = "RUST_GUNNER", Count = 2 } },
					},
				},
				Checkpoint = "Checkpoint_Boss",
				Door = "Door_3",
			},
			{
				Kind = "Boss",
				Text = "Defeat Kaldrek, the Rust Tyrant",
				Enemy = "RUST_KALDREK",
				Target = "BossSpawn",
				Mechanic = "ImmuneAdds",
				AddsGroup = "BossAdds",
			},
		} :: { ObjectiveDef },
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
		Description = "Six Keepers descend into a vault where every sound becomes a weapon. Encounter 1: silence the Echo Engine.",
		RecommendedPower = 495,
		MinPlayers = 1,
		MaxPlayers = 6,
		PowerEnabled = true,
		PowerDeltaCap = 0,
		LootSource = "Raid",
		Unlock = { Power = 480 },
		Factions = { "Rustborn" },
		Place = "Raid",
		Order = 50,
		Map = "VaultOfEchoes",
		Playable = true,
		Rewards = { Drops = { Min = 0, Max = 0 }, ExclusiveChance = 0.15, FallbackDrops = 1 },
		Encounters = {
			{
				Id = "THE_ECHO_CHAMBER",
				Name = "The Echo Chamber",
				RecommendedPower = 495,
				Description = "Harrowmaw is immune until three Keepers stand on the echo plates at once. Then: twenty seconds to hurt it. Don't let the enrage timer run out.",
				Playable = true,
				Milestone = "RAID_ENCOUNTER_1",
				Objectives = {
					{
						Kind = "Travel",
						Text = "Enter the Echo Chamber",
						Target = "Zone_Chamber",
						Checkpoint = "Checkpoint_Chamber",
					},
					{
						Kind = "Boss",
						Text = "Defeat Harrowmaw, the Echo Engine",
						Enemy = "RUST_ECHO_ENGINE",
						Target = "BossSpawn",
						Mechanic = "EchoPlates",
						AddsGroup = "Adds",
					},
				},
			},
			{
				Id = "HALL_OF_MIRRORS",
				Name = "Hall of Mirrors",
				RecommendedPower = 498,
				Description = "Coming later: split the team and match reflected symbols.",
				Milestone = "RAID_ENCOUNTER_2",
				Objectives = {},
			},
			{
				Id = "THE_SILENT_CORE",
				Name = "The Silent Core",
				RecommendedPower = 500,
				Description = "Coming later: the heart of the vault.",
				Milestone = "RAID_ENCOUNTER_3",
				Objectives = {},
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
