--!strict
--[[
	BossConfig
	How each boss fight plays out (run by server/Missions/BossFight).

	A fight is one Boss step of an activity zone (ActivityConfig). The boss
	spawns at the arena marker BossArena/BossSpawn, its health is its
	EnemyConfig Health (15-30x a captain) scaled by power and fireteam size,
	and the HUD shows the big bar at the top of the screen.

	Immune       health thresholds (0.66, 0.33) where the boss raises a
	             shield bubble and becomes immune until the Break is done:
	               Adds    defeat Waves waves of Enemies (arena spawns)
	               Pylons  destroy Count object enemies spawned at the
	                       arena markers BossArena/Pylon_1..n
	             Collapse (optional) names a part/model in the map whose
	             pieces flash red and fall away when the phase starts.
	Attacks      special attacks on their own cooldowns, on top of the
	             boss's normal fire (Phases limits an attack to fight phases
	             1-3; a phase ends at each immune threshold):
	               Barrage   winds up, then sprays Count bolts at everyone
	               Slam      a warning circle of Radius under a player; after
	                         Windup the boss leaps onto it (Leap) and hits
	                         everyone inside
	               Teleport  vanishes and reappears at BossArena/Teleport_n
	               Nova      only standing inside a safe circle
	                         (BossArena/Safe_n) survives the blast
	Adds         a trickle of enemies every Interval seconds (capped)
	HeavyAmmoEvery  seconds between heavy ammo drops at BossArena/Ammo_n
	Enrage       after After seconds the boss wipes the fireteam (raid)
	Script       a special encounter runner instead of the above:
	               EchoPlates   (raid 1) immune until the lit echo plates are
	                            held; the lit plates change every cycle
	               EchoDeposit  (raid 2) immune until Deposit.Needed echoes
	                            are carried from slain Echo Bearers (one per
	                            room, BossArena Room_n) to the well
	Deposit      the EchoDeposit tuning (bearer enemy, echoes needed, how
	             long a carried echo lasts, the damage window)
	Chest        a loot chest appears where the boss fell (the activity's
	             rewards are claimed from it)
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type ImmuneDef = {
	At: number,
	Break: "Adds" | "Pylons",
	Text: string,
	Enemies: { [string]: number }?,
	Waves: number?,
	Count: number?,
	Enemy: string?,
	Collapse: string?,
}

export type AttackDef = {
	Kind: "Barrage" | "Slam" | "Teleport" | "Nova",
	Cooldown: number,
	FirstAt: number?,
	Windup: number?,
	Radius: number?,
	Damage: number?,
	Count: number?,
	Leap: boolean?,
	Phases: { number }?,
}

export type BossDef = {
	Id: string,
	Enemy: string,
	Immune: { ImmuneDef },
	Attacks: { AttackDef },
	Adds: { Interval: number, Enemies: { [string]: number }, MaxAlive: number }?,
	HeavyAmmoEvery: number,
	Enrage: { After: number, Text: string }?,
	Script: string?,
	Deposit: { Bearer: string, Needed: number, ChargeSeconds: number, DamageSeconds: number }?,
	Chest: boolean?,
}

local List: { BossDef } = {
	{
		Id = "SCRAP_WARDEN",
		Enemy = "RUST_SCRAP_WARDEN",
		Immune = {
			{
				At = 0.66,
				Break = "Adds",
				Text = "The Warden hides behind a scrap ward: defeat its guard",
				Enemies = { RUST_SCRAPPER = 3, RUST_GUNNER = 3 },
				Waves = 2,
			},
			{
				At = 0.33,
				Break = "Adds",
				Text = "The ward is back up: take down the drones and the captain",
				Enemies = { RUST_SKIFF_DRONE = 3, RUST_GUNNER = 2, RUST_BREAKER = 1 },
				Waves = 1,
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 11, FirstAt = 6, Windup = 1.2, Count = 14, Damage = 9 },
			{ Kind = "Slam", Cooldown = 13, FirstAt = 11, Windup = 1.8, Radius = 16, Damage = 60, Leap = true },
		},
		Adds = { Interval = 32, Enemies = { RUST_SCRAPPER = 2, RUST_GUNNER = 1 }, MaxAlive = 6 },
		HeavyAmmoEvery = 40,
		Chest = true,
	},
	{
		Id = "TIDE_MARSHAL",
		Enemy = "CONC_TIDE_MARSHAL",
		Immune = {
			{
				At = 0.66,
				Break = "Pylons",
				Text = "The Marshal draws on the tide pylons: destroy them",
				Count = 3,
				Enemy = "CONC_TIDE_PYLON",
			},
			{
				At = 0.33,
				Break = "Adds",
				Text = "The relay compiles a Warden: break its escort",
				Enemies = { CONC_WARDEN = 1, CONC_SENTRY = 3, CONC_DRONE_PRISM = 2 },
				Waves = 1,
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 10, FirstAt = 6, Windup = 1.2, Count = 16, Damage = 9 },
			{ Kind = "Slam", Cooldown = 14, FirstAt = 11, Windup = 1.8, Radius = 16, Damage = 60, Leap = true },
		},
		Adds = { Interval = 30, Enemies = { CONC_LANCER = 2, CONC_SENTRY = 1 }, MaxAlive = 6 },
		HeavyAmmoEvery = 40,
		Chest = true,
	},
	{
		Id = "HOLLOW_PRIEST",
		Enemy = "VEIL_HOLLOW_PRIEST",
		Immune = {
			{
				At = 0.66,
				Break = "Pylons",
				Text = "The Priest hides in the choir's ward: shatter the ward crystals",
				Count = 3,
				Enemy = "VEIL_WARD_CRYSTAL",
			},
			{
				At = 0.33,
				Break = "Adds",
				Text = "The choir rises to shield its voice",
				Enemies = { VEIL_WRAITHKNIGHT = 1, VEIL_HUSK = 5, VEIL_SHADE_WISP = 2 },
				Waves = 1,
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 11, FirstAt = 5, Windup = 1, Count = 14, Damage = 10 },
			{ Kind = "Teleport", Cooldown = 12, FirstAt = 8 },
			{ Kind = "Slam", Cooldown = 13, FirstAt = 14, Windup = 1.6, Radius = 14, Damage = 55 },
		},
		Adds = { Interval = 28, Enemies = { VEIL_HUSK = 3, VEIL_ACOLYTE = 1 }, MaxAlive = 7 },
		HeavyAmmoEvery = 40,
		Chest = true,
	},
	{
		Id = "SPIRE_OVERSEER",
		Enemy = "RUST_SPIRE_OVERSEER",
		Immune = {
			{
				At = 0.66,
				Break = "Adds",
				Text = "Vekta calls the Spire guard: break them",
				Enemies = { RUST_BREAKER = 1, RUST_GUNNER = 3, RUST_SCRAPPER = 3 },
				Waves = 2,
			},
			{
				At = 0.33,
				Break = "Pylons",
				Text = "The floor gives way! Destroy the ward pylons",
				Count = 3,
				Enemy = "RUST_PYLON",
				Collapse = "CollapseFloor",
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 9, FirstAt = 5, Windup = 1, Count = 18, Damage = 11 },
			{ Kind = "Slam", Cooldown = 12, FirstAt = 10, Windup = 1.6, Radius = 17, Damage = 70, Leap = true },
		},
		Adds = { Interval = 26, Enemies = { RUST_SCRAPPER = 2, RUST_GUNNER = 2 }, MaxAlive = 8 },
		HeavyAmmoEvery = 35,
		Chest = true,
	},
	{
		Id = "KALDREK",
		Enemy = "RUST_KALDREK",
		Immune = {
			{
				At = 0.66,
				Break = "Adds",
				Text = "Kaldrek raises an iron ward: defeat his bodyguard",
				Enemies = { RUST_BREAKER = 1, RUST_GUNNER = 3, RUST_SCRAPPER = 3 },
				Waves = 1,
			},
			{
				At = 0.33,
				Break = "Adds",
				Text = "Kaldrek calls the forge guard: break them",
				Enemies = { RUST_SKIFF_DRONE = 3, RUST_SNIPER = 1, RUST_SCRAPPER = 3 },
				Waves = 1,
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 10, FirstAt = 5, Windup = 1, Count = 18, Damage = 10 },
			{ Kind = "Slam", Cooldown = 12, FirstAt = 9, Windup = 1.6, Radius = 18, Damage = 70, Leap = true },
		},
		Adds = { Interval = 28, Enemies = { RUST_SCRAPPER = 2, RUST_GUNNER = 2 }, MaxAlive = 8 },
		HeavyAmmoEvery = 35,
		Chest = true,
	},
	{
		Id = "HARROWMAW",
		Enemy = "RUST_ECHO_ENGINE",
		Immune = {},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 14, FirstAt = 10, Windup = 1.4, Count = 20, Damage = 12 },
			{ Kind = "Slam", Cooldown = 18, FirstAt = 16, Windup = 1.8, Radius = 14, Damage = 55 },
		},
		Adds = { Interval = 25, Enemies = { RUST_SCRAPPER = 3, RUST_GUNNER = 2 }, MaxAlive = 10 },
		HeavyAmmoEvery = 45,
		Script = "EchoPlates",
		Enrage = { After = 360, Text = "ENRAGE: the Echo Engine overloads!" },
		Chest = true,
	},
	{
		Id = "ECHO_WARDEN",
		Enemy = "CONC_ECHO_WARDEN",
		Immune = {},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 12, FirstAt = 8, Windup = 1.2, Count = 18, Damage = 11 },
			{ Kind = "Slam", Cooldown = 14, FirstAt = 14, Windup = 1.6, Radius = 14, Damage = 55 },
		},
		Adds = { Interval = 22, Enemies = { RUST_SCRAPPER = 2, RUST_GUNNER = 1 }, MaxAlive = 10 },
		HeavyAmmoEvery = 40,
		Script = "EchoDeposit",
		Deposit = { Bearer = "RUST_ECHO_BEARER", Needed = 3, ChargeSeconds = 30, DamageSeconds = 25 },
		Enrage = { After = 480, Text = "ENRAGE: the echoes drown the chamber!" },
		Chest = true,
	},
	{
		Id = "ECHO_SOVEREIGN",
		Enemy = "CONC_ECHO_SOVEREIGN",
		Immune = {
			{
				At = 0.66,
				Break = "Pylons",
				Text = "The Sovereign draws on the echo pillars: destroy them",
				Count = 3,
				Enemy = "CONC_ECHO_PILLAR",
			},
			{
				At = 0.33,
				Break = "Adds",
				Text = "The vault's guardians answer the Sovereign",
				Enemies = { CONC_WARDEN = 1, CONC_VAULT_SENTINEL = 3, RUST_SCRAPPER = 3 },
				Waves = 2,
			},
		},
		Attacks = {
			{ Kind = "Barrage", Cooldown = 10, FirstAt = 6, Windup = 1.2, Count = 20, Damage = 11 },
			{ Kind = "Slam", Cooldown = 13, FirstAt = 12, Windup = 1.6, Radius = 16, Damage = 60 },
			{ Kind = "Nova", Cooldown = 40, FirstAt = 20, Windup = 8, Radius = 10, Phases = { 2 } },
			{ Kind = "Nova", Cooldown = 28, FirstAt = 15, Windup = 7, Radius = 10, Phases = { 3 } },
			{ Kind = "Teleport", Cooldown = 16, FirstAt = 10, Phases = { 3 } },
		},
		Adds = { Interval = 30, Enemies = { RUST_GUNNER = 2, CONC_VAULT_SENTINEL = 1 }, MaxAlive = 8 },
		HeavyAmmoEvery = 35,
		Enrage = { After = 540, Text = "ENRAGE: the Sovereign sings the vault closed!" },
		Chest = true,
	},
}

local ById: { [string]: BossDef } = {}
for _, boss in List do
	ById[boss.Id] = boss
end

return TableUtil.DeepFreeze({
	List = List,
	ById = ById,
	-- Boss health must stay within this many captains (ConfigValidator).
	CaptainMultiple = { Min = 15, Max = 30 },
})
