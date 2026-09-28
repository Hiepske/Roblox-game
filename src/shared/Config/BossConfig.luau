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
	Script       a special encounter runner instead of the above
	             ("EchoPlates": the raid's plate mechanic)
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
		},
		Adds = { Interval = 25, Enemies = { RUST_SCRAPPER = 3, RUST_GUNNER = 2 }, MaxAlive = 10 },
		HeavyAmmoEvery = 45,
		Script = "EchoPlates",
		Enrage = { After = 360, Text = "ENRAGE: the Echo Engine overloads!" },
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
