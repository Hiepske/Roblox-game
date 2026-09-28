--!strict
--[[
	CombatConfig
	Tuning for moment-to-moment combat: player shields and regeneration,
	respawn rules, weapon stat formulas, enemy AI accuracy, ammo drops,
	party scaling, activity scoring and the raid mechanic.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local CombatConfig = {
	Player = {
		-- Shields absorb damage first. After ShieldRegenDelay seconds without
		-- taking damage, shields refill, then health.
		ShieldRegenDelay = 4,
		ShieldRegenPerSecond = 55,
		HealthRegenPerSecond = 30,
		-- Seconds of invulnerability after (re)spawning.
		SpawnProtection = 2,
	},

	Respawn = {
		Hub = 5,
		-- Story missions and the hardened strike: back at the last checkpoint.
		Activity = 5,
		-- Raid with one player: respawn instead of waiting for a revive.
		RaidSolo = 10,
		-- Raid team wipe: everyone respawns and the encounter restarts.
		RaidWipe = 6,
		-- Holding the interact key on a teammate's ghost marker.
		ReviveHoldSeconds = 3,
	},

	-- Converting 0-100 weapon stats into gameplay numbers (see WeaponStats).
	WeaponStats = {
		ImpactDamageMin = 0.8, -- damage multiplier at Impact 0
		ImpactDamageMax = 1.2, -- ... and at Impact 100
		RangeScaleMin = 0.75, -- falloff distance multiplier at Range 0
		RangeScaleMax = 1.25,
		ReloadScaleSlow = 1.3, -- reload time multiplier at Reload 0
		ReloadScaleFast = 0.7, -- ... and at Reload 100
		HandlingScaleSlow = 1.25, -- swap time multiplier at Handling 0
		HandlingScaleFast = 0.75,
		StabilityRecoilMax = 1.3, -- recoil multiplier at Stability 0
		StabilityRecoilMin = 0.7,
	},

	Weapons = {
		-- The server accepts a shot if at least this fraction of the fire
		-- interval has passed (absorbs network jitter).
		FireRateTolerance = 0.8,
		-- Extra studs allowed between the server's ray end and the client's aim point.
		AimPointSlack = 60,
		-- Rockets in reserve when a character spawns or enters an activity.
		HeavyStartingReserve = 2,
		-- Special ammo (shotguns, snipers, fusion rifles) starts at this many magazines.
		SpecialStartingMagazines = 2,
		-- Melee weapons hit enemies within this cone (degrees either side).
		MeleeArc = 60,
		-- Weapons never damage their owner; explosions fall off to this at the edge.
		SplashEdgeMultiplier = 0.5,
	},

	Enemies = {
		-- Seconds between AI updates (per enemy).
		TickInterval = 0.15,
		-- Aim error cone, in degrees, by tier.
		AimSpreadDegrees = { Minor = 4, Major = 3, Boss = 2.5 } :: { [string]: number },
		-- Rushers wind up before a melee hit lands, so it can be dodged.
		MeleeWindup = 0.4,
		-- Bosses fire this many projectiles per attack, spread this far apart.
		BossVolley = { Count = 3, SpreadDegrees = 7 },
		-- Phase-two bosses attack this much faster.
		EnragedCooldownScale = 0.7,
		-- Seconds a shot-at dummy waits before healing back to full.
		DummyRegenDelay = 3,
		-- Snipers: the red laser tracks you this long, then locks in place for
		-- SniperLock seconds before the shot (step out of it!).
		SniperWindup = 1.8,
		SniperLock = 0.35,
		-- Drones hover this high above the ground near their target.
		DroneHover = 12,
		-- Turrets fire bursts of this many bolts.
		TurretBurst = 5,
	},

	Ammo = {
		BoxLifetime = 30,
		PickupRadius = 7,
	},

	-- Every activity scales with fireteam size: each player beyond the first
	-- adds these fractions (so 3 players = 1 + 2 x value).
	PartyScaling = {
		-- Wave sizes.
		CountPerExtraPlayer = 0.35,
		-- Health of regular enemies.
		HealthPerExtraPlayer = 0.25,
		-- Health of bosses.
		BossHealthPerExtraPlayer = 0.6,
	},

	-- Zone flow (MissionService).
	Missions = {
		-- The next wave arrives when this fraction of the current one is down...
		Advance = 0.8,
		-- ...or after this many seconds, whichever comes first.
		WaveTimer = 45,
		-- Waves wait while this many enemies are already alive in the run.
		MaxAlive = 16,
		-- Seconds between a rift opening and the enemy stepping out of it.
		PortalDelay = 1.1,
		-- Seconds for a dropship to arrive overhead and drop its wave.
		DropshipDelay = 3,
		-- Spawn points closer than this to a player are used only as a last resort.
		SpawnMinDistance = 24,
		-- Defend/Survive/Destroy/Interact steps: seconds between waves.
		WaveInterval = 12,
	},

	-- Boss fights (BossConfig, BossFight).
	Boss = {
		-- Heavy ammo boxes dropped in the arena last this long.
		ArenaAmmoLifetime = 40,
		-- Slam and Nova only hit players within this height of the circle.
		HitHeight = 10,
		-- Seconds the collapsing floor flashes before it falls.
		CollapseWarning = 3,
		-- Enemies alive in the arena before periodic adds stop.
		MaxAlive = 10,
	},

	-- Nightfall score: points per kill by tier, plus a time bonus on completion.
	Score = {
		Minor = 10,
		Major = 50,
		Boss = 500,
		ParSeconds = 900,
		PointsPerSecondUnderPar = 5,
	},

	-- Vault of Echoes, encounter 1.
	Raid = {
		PlateChargeSeconds = 3, -- all three plates held at once
		SoloPlateHoldSeconds = 5, -- fewer than 3 players: any one plate
		DamagePhaseSeconds = 20,
		DamageBuff = 1.25, -- "Echo Resonance": damage bonus during the phase
		EnrageSeconds = 360,
		AddsInterval = 25,
	},
}

return TableUtil.DeepFreeze(CombatConfig)
