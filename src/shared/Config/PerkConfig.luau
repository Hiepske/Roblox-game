--!strict
--[[
	PerkConfig
	Every weapon and armor perk. Columns:
	  Barrel / Magazine  Legendary-only stat options
	  Trait1             utility traits (reload, handling, ammo economy)
	  Trait2             damage traits
	  Exotic             signature perks owned by one exotic weapon
	  ExoticArmor        signature perks owned by one exotic armor piece

	AppliesTo lists weapon types a perk can roll on. Effect is plain data for
	the combat code (Phase 2+) to interpret: Trigger says when, Kind says what.

	Synergies are "god roll" pairs: a Trait1 + Trait2 combo that plays
	especially well together. Loot UI highlights them.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local Types = require(script.Parent.Parent.Types)

type PerkDef = Types.PerkDef

-- Weapon type groups ------------------------------------------------------------

local PRIMARIES = { "AutoRifle", "PulseRifle", "ScoutRifle", "HandCannon", "SMG", "Sidearm" }
local LAUNCHERS = { "GrenadeLauncher", "RocketLauncher" }

local function merge(...: { string }): { string }
	local out = {}
	local seen = {}
	for _, list in { ... } do
		for _, item in list do
			if not seen[item] then
				seen[item] = true
				table.insert(out, item)
			end
		end
	end
	return out
end

-- Weapons that can land precision (head) shots.
local PRECISION = merge(PRIMARIES, { "SniperRifle", "MachineGun" })
-- Everything that fires bullets or pellets (not launchers, not swords).
local BARRELED = merge(PRIMARIES, { "Shotgun", "SniperRifle", "FusionRifle", "MachineGun" })
local ALL_GUNS = merge(BARRELED, LAUNCHERS)
local ALL = merge(ALL_GUNS, { "Sword" })

-- Perk list -------------------------------------------------------------------------

local List: { PerkDef } = {
	-- Barrels ------------------------------------------------------------------------
	{
		Id = "BARREL_STABILIZED",
		Name = "Stabilized Bore",
		Column = "Barrel",
		Description = "A counterweighted bore that tames recoil.",
		AppliesTo = BARRELED,
		StatModifiers = { Stability = 10 },
	},
	{
		Id = "BARREL_LONG_RAIL",
		Name = "Long Rail",
		Column = "Barrel",
		Description = "An extended rail that keeps rounds true over distance at a cost to handling.",
		AppliesTo = BARRELED,
		StatModifiers = { Range = 10, Handling = -5 },
	},
	{
		Id = "BARREL_LIGHT_SHROUD",
		Name = "Lightened Shroud",
		Column = "Barrel",
		Description = "Skeletonized housing for faster draws and aims.",
		AppliesTo = BARRELED,
		StatModifiers = { Handling = 10 },
	},
	{
		Id = "BARREL_CHOKE_COIL",
		Name = "Choke Coil",
		Column = "Barrel",
		Description = "Magnetic coils tighten the spread of pellets and bolts.",
		AppliesTo = { "Shotgun", "FusionRifle" },
		StatModifiers = { Range = 12, Stability = -4 },
	},
	{
		Id = "TUBE_QUICKFIRE",
		Name = "Quickfire Tube",
		Column = "Barrel",
		Description = "A lighter launch tube that is quicker to ready and reload.",
		AppliesTo = LAUNCHERS,
		StatModifiers = { Handling = 10, Reload = 5 },
	},
	{
		Id = "TUBE_REINFORCED",
		Name = "Reinforced Tube",
		Column = "Barrel",
		Description = "A braced tube that steadies aim and lengthens the flight path.",
		AppliesTo = LAUNCHERS,
		StatModifiers = { Stability = 10, Range = 5 },
	},
	{
		Id = "BLADE_HONED",
		Name = "Honed Edge",
		Column = "Barrel",
		Description = "A keen edge that extends your lunge.",
		AppliesTo = { "Sword" },
		StatModifiers = { Range = 10 },
	},
	{
		Id = "BLADE_BALANCED",
		Name = "Balanced Edge",
		Column = "Barrel",
		Description = "A perfectly weighted blade for faster swings.",
		AppliesTo = { "Sword" },
		StatModifiers = { Handling = 10 },
	},

	-- Magazines ---------------------------------------------------------------------
	{
		Id = "MAG_EXTENDED",
		Name = "Extended Cell",
		Column = "Magazine",
		Description = "Holds more rounds but is slower to swap.",
		AppliesTo = BARRELED,
		StatModifiers = { Reload = -5 },
		MagazineScale = 1.25,
	},
	{
		Id = "MAG_QUICKFEED",
		Name = "Quickfeed Cell",
		Column = "Magazine",
		Description = "A spring-assisted feed for faster reloads.",
		AppliesTo = BARRELED,
		StatModifiers = { Reload = 12 },
	},
	{
		Id = "MAG_DENSE",
		Name = "Dense Rounds",
		Column = "Magazine",
		Description = "Heavier rounds that carry farther.",
		AppliesTo = BARRELED,
		StatModifiers = { Range = 8, Stability = 3 },
	},
	{
		Id = "MAG_STEADY",
		Name = "Steady Rounds",
		Column = "Magazine",
		Description = "Low-recoil propellant for a steadier sight picture.",
		AppliesTo = BARRELED,
		StatModifiers = { Stability = 10, Handling = -3 },
	},
	{
		Id = "PAYLOAD_PROXIMITY",
		Name = "Proximity Fuse",
		Column = "Magazine",
		Description = "Projectiles detonate when they pass close to an enemy.",
		AppliesTo = LAUNCHERS,
		Effect = { Trigger = "Passive", Kind = "ProximityDetonation", Radius = 4 },
	},
	{
		Id = "PAYLOAD_IMPACT",
		Name = "Impact Casing",
		Column = "Magazine",
		Description = "Direct hits deal additional damage.",
		AppliesTo = LAUNCHERS,
		Effect = { Trigger = "DirectHit", Kind = "DamageBonus", Value = 0.1 },
	},
	{
		Id = "GUARD_SWIFT",
		Name = "Swift Guard",
		Column = "Magazine",
		Description = "Guard energy recovers faster.",
		AppliesTo = { "Sword" },
		StatModifiers = { Reload = 10 },
	},
	{
		Id = "GUARD_IRON",
		Name = "Iron Guard",
		Column = "Magazine",
		Description = "Blocking absorbs more damage.",
		AppliesTo = { "Sword" },
		StatModifiers = { Stability = 10 },
	},

	-- Trait 1: utility ---------------------------------------------------------------
	{
		Id = "SWIFT_RECHAMBER",
		Name = "Swift Rechamber",
		Column = "Trait1",
		Description = "Precision kills greatly increase reload speed for a short time.",
		AppliesTo = PRECISION,
		Effect = { Trigger = "PrecisionKill", Kind = "ReloadBonus", Value = 50, Duration = 6 },
	},
	{
		Id = "MOMENTUM_LOADER",
		Name = "Momentum Loader",
		Column = "Trait1",
		Description = "Each kill speeds up your next reload. Stacks 3 times.",
		AppliesTo = ALL_GUNS,
		Effect = { Trigger = "Kill", Kind = "ReloadBonus", Value = 15, Duration = 5, MaxStacks = 3 },
	},
	{
		Id = "DEEP_RESERVES",
		Name = "Deep Reserves",
		Column = "Trait1",
		Description = "Precision kills pull a quarter of the magazine back from reserves.",
		AppliesTo = PRECISION,
		Effect = { Trigger = "PrecisionKill", Kind = "RefillMagazine", Value = 0.25 },
	},
	{
		Id = "PRECISION_ECHO",
		Name = "Precision Echo",
		Column = "Trait1",
		Description = "Every third consecutive precision hit returns a round to the magazine.",
		AppliesTo = PRECISION,
		Effect = { Trigger = "PrecisionHit", Kind = "ReturnRound", Value = 1, Every = 3 },
	},
	{
		Id = "AUTO_CYCLE",
		Name = "Auto-Cycle",
		Column = "Trait1",
		Description = "After a few seconds without firing, the magazine quietly refills itself.",
		AppliesTo = ALL_GUNS,
		Effect = { Trigger = "Idle", Kind = "AutoReload", Duration = 2.5 },
	},
	{
		Id = "SPRINT_READY",
		Name = "Sprint Ready",
		Column = "Trait1",
		Description = "Greatly improved handling for a moment after sprinting.",
		AppliesTo = ALL,
		Effect = { Trigger = "Sprint", Kind = "HandlingBonus", Value = 50, Duration = 2 },
	},
	{
		Id = "THREAT_SENSE",
		Name = "Threat Sense",
		Column = "Trait1",
		Description = "Nearby enemies sharpen your focus: bonus stability and handling per enemy close by.",
		AppliesTo = merge(PRIMARIES, { "Shotgun", "FusionRifle", "Sword" }),
		Effect = { Trigger = "Proximity", Kind = "StabilityHandlingBonus", Value = 8, MaxStacks = 3, Radius = 15 },
	},
	{
		Id = "OVERFLOW_CHAMBER",
		Name = "Overflow Chamber",
		Column = "Trait1",
		Description = "Picking up ammo overfills the magazine to 150%.",
		AppliesTo = merge({ "Shotgun", "SniperRifle", "FusionRifle", "MachineGun" }, LAUNCHERS),
		Effect = { Trigger = "AmmoPickup", Kind = "Overfill", Value = 1.5 },
	},
	{
		Id = "STEADY_HANDS",
		Name = "Steady Hands",
		Column = "Trait1",
		Description = "Kills grant a burst of handling and stability.",
		AppliesTo = ALL_GUNS,
		Effect = { Trigger = "Kill", Kind = "StabilityHandlingBonus", Value = 25, Duration = 4 },
	},
	{
		Id = "SCAVENGERS_LUCK",
		Name = "Scavenger's Luck",
		Column = "Trait1",
		Description = "Kills have a chance to leave behind ammo for this weapon.",
		AppliesTo = merge({ "Shotgun", "SniperRifle", "FusionRifle", "MachineGun" }, LAUNCHERS),
		Effect = { Trigger = "Kill", Kind = "AmmoDrop", Value = 0.2 },
	},
	{
		Id = "RIPOSTE_GUARD",
		Name = "Riposte Guard",
		Column = "Trait1",
		Description = "Blocking an attack empowers your next swing.",
		AppliesTo = { "Sword" },
		Effect = { Trigger = "Block", Kind = "DamageBonus", Value = 0.4, Duration = 3 },
	},

	-- Trait 2: damage ----------------------------------------------------------------
	{
		Id = "HOT_STREAK",
		Name = "Hot Streak",
		Column = "Trait2",
		Description = "Rapid precision hits stack bonus damage and stability.",
		AppliesTo = PRECISION,
		Effect = { Trigger = "PrecisionHit", Kind = "DamageBonus", Value = 0.07, Duration = 2, MaxStacks = 3 },
	},
	{
		Id = "PAYLOAD_ROUNDS",
		Name = "Payload Rounds",
		Column = "Trait2",
		Description = "Part of each hit's damage becomes a small explosion.",
		AppliesTo = merge(BARRELED, LAUNCHERS),
		Effect = { Trigger = "Hit", Kind = "SplashConversion", Value = 0.3, Radius = 3 },
	},
	{
		Id = "SURGING_STRIDE",
		Name = "Surging Stride",
		Column = "Trait2",
		Description = "Damage builds while you keep moving and fades when you stand still.",
		AppliesTo = merge(PRIMARIES, { "Shotgun", "Sword" }),
		Effect = { Trigger = "Moving", Kind = "DamageBonus", Value = 0.03, MaxStacks = 5, Duration = 1 },
	},
	{
		Id = "CULL_THE_WEAK",
		Name = "Cull the Weak",
		Column = "Trait2",
		Description = "Bonus damage against enemies below 30% health.",
		AppliesTo = ALL,
		Effect = { Trigger = "TargetLowHealth", Kind = "DamageBonus", Value = 0.25 },
	},
	{
		Id = "CASCADE_BURST",
		Name = "Cascade Burst",
		Column = "Trait2",
		Description = "Kills make the target erupt in a burst of the weapon's element.",
		AppliesTo = ALL,
		Effect = { Trigger = "Kill", Kind = "Explosion", Value = 0.5, Radius = 5 },
	},
	{
		Id = "OPENING_SALVO",
		Name = "Opening Salvo",
		Column = "Trait2",
		Description = "The first shot from a full magazine deals heavy bonus damage.",
		AppliesTo = merge(PRIMARIES, { "Shotgun", "SniperRifle", "FusionRifle" }, LAUNCHERS),
		Effect = { Trigger = "FirstShot", Kind = "DamageBonus", Value = 0.4 },
	},
	{
		Id = "BATTLE_RHYTHM",
		Name = "Battle Rhythm",
		Column = "Trait2",
		Description = "After a while in combat: bonus damage, handling and reload until the fight ends.",
		AppliesTo = ALL,
		Effect = { Trigger = "InCombat", Kind = "AllRounder", Value = 0.15, Duration = 8 },
	},
	{
		Id = "TEMPO_SURGE",
		Name = "Tempo Surge",
		Column = "Trait2",
		Description = "Kills grant stacking bonus damage for a few seconds.",
		AppliesTo = ALL,
		Effect = { Trigger = "Kill", Kind = "DamageBonus", Value = 0.1, Duration = 5, MaxStacks = 3 },
	},
	{
		Id = "LAST_STAND",
		Name = "Last Stand",
		Column = "Trait2",
		Description = "Bonus damage while your health is low.",
		AppliesTo = ALL,
		Effect = { Trigger = "LowHealth", Kind = "DamageBonus", Value = 0.25 },
	},
	{
		Id = "FOCUSED_CHARGE",
		Name = "Focused Charge",
		Column = "Trait2",
		Description = "Aiming without firing charges up bonus damage for your next shot.",
		AppliesTo = merge({ "ScoutRifle", "SniperRifle", "HandCannon", "PulseRifle", "FusionRifle" }, LAUNCHERS),
		Effect = { Trigger = "Aim", Kind = "DamageBonus", Value = 0.25, Duration = 1 },
	},
	{
		Id = "RESONANT_ROUNDS",
		Name = "Resonant Rounds",
		Column = "Trait2",
		Description = "Even more damage against shields that match the weapon's element.",
		AppliesTo = ALL,
		Effect = { Trigger = "ShieldHit", Kind = "ShieldDamageBonus", Value = 0.5 },
	},
	{
		Id = "SUSTAINED_FIRE",
		Name = "Sustained Fire",
		Column = "Trait2",
		Description = "Damage ramps up the longer you hold the trigger.",
		AppliesTo = { "AutoRifle", "SMG", "MachineGun", "PulseRifle" },
		Effect = { Trigger = "Sustained", Kind = "DamageBonus", Value = 0.3, Duration = 3 },
	},
	{
		Id = "SPLINTER_SHOT",
		Name = "Splinter Shot",
		Column = "Trait2",
		Description = "Precision hits fling a shard at a nearby enemy.",
		AppliesTo = PRECISION,
		Effect = { Trigger = "PrecisionHit", Kind = "Ricochet", Value = 0.3, Radius = 12 },
	},

	-- Exotic weapon signatures ---------------------------------------------------------
	{
		Id = "EXO_SIXTH_TOLL",
		Name = "Sixth Toll",
		Column = "Exotic",
		Description = "Every sixth consecutive hit detonates, dealing heavy bonus damage around the target.",
		AppliesTo = { "HandCannon" },
		Effect = { Trigger = "Hit", Kind = "Explosion", Every = 6, Value = 1.5, Radius = 5 },
	},
	{
		Id = "EXO_CHOIR_OF_CINDERS",
		Name = "Choir of Cinders",
		Column = "Exotic",
		Description = "Rockets split into six tracking cinder bomblets on impact.",
		AppliesTo = { "RocketLauncher" },
		Effect = { Trigger = "Impact", Kind = "ClusterBomblets", Value = 6, Radius = 20 },
	},
	{
		Id = "EXO_COLLAPSE_POINT",
		Name = "Collapse Point",
		Column = "Exotic",
		Description = "Kills tear open a Null singularity that drags enemies in and crushes them.",
		AppliesTo = { "SniperRifle" },
		Effect = { Trigger = "Kill", Kind = "Singularity", Value = 60, Duration = 3, Radius = 12 },
	},
	{
		Id = "EXO_PERPETUAL_MOTION",
		Name = "Perpetual Motion",
		Column = "Exotic",
		Description = "Holding the trigger spins the engine up to 50% faster; every twelfth hit arcs lightning to nearby foes.",
		AppliesTo = { "AutoRifle" },
		Effect = { Trigger = "Sustained", Kind = "RpmRampAndChain", Value = 0.5, Every = 12, Radius = 10 },
	},
	{
		Id = "EXO_EMBER_OATH",
		Name = "Ember Oath",
		Column = "Exotic",
		Description = "Heavy attacks send a wave of fire racing forward. Sword kills return ammo.",
		AppliesTo = { "Sword" },
		Effect = { Trigger = "HeavyAttack", Kind = "FireWave", Value = 2, Radius = 25 },
	},
	{
		Id = "EXO_PHANTOM_MARK",
		Name = "Phantom Mark",
		Column = "Exotic",
		Description = "Precision hits mark targets. Killing a marked target releases a seeker drone.",
		AppliesTo = { "PulseRifle" },
		Effect = { Trigger = "PrecisionHit", Kind = "MarkAndSeek", Duration = 5, Radius = 30 },
	},

	-- Exotic armor signatures ----------------------------------------------------------
	{
		Id = "EXA_ANVIL_CROWN",
		Name = "Forge Ward",
		Column = "ExoticArmor",
		Description = "Your barrier recharges faster for each ally standing near it.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "Passive", Kind = "ClassAbilityRecharge", Value = 0.15, MaxStacks = 3, Radius = 15 },
	},
	{
		Id = "EXA_HEARTHGUARD",
		Name = "Hearth Embers",
		Column = "ExoticArmor",
		Description = "Heavy melee kills leave a healing ember for allies.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "MeleeKill", Kind = "HealingPickup", Value = 40 },
	},
	{
		Id = "EXA_QUICKSTEP",
		Name = "Quickstep",
		Column = "ExoticArmor",
		Description = "Dodging reloads your weapon and refunds melee energy.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "ClassAbility", Kind = "ReloadAndMelee", Value = 1 },
	},
	{
		Id = "EXA_UNSEEN_VEIL",
		Name = "Unseen Veil",
		Column = "ExoticArmor",
		Description = "Precision kills turn you briefly invisible.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "PrecisionKill", Kind = "Invisibility", Duration = 3 },
	},
	{
		Id = "EXA_EMBER_CROWN",
		Name = "Kindled Mind",
		Column = "ExoticArmor",
		Description = "Standing in your Sanctum Circle charges your grenade.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "InSanctum", Kind = "GrenadeRecharge", Value = 0.08 },
	},
	{
		Id = "EXA_WEAVERS_GRASP",
		Name = "Weaver's Grasp",
		Column = "ExoticArmor",
		Description = "Energy melee strikes chain to two more enemies.",
		AppliesTo = { "Armor" },
		Effect = { Trigger = "MeleeHit", Kind = "Chain", Value = 2, Radius = 10 },
	},
}

-- Trait1 + Trait2 pairs that make a "god roll".
local Synergies: { { string } } = {
	{ "SWIFT_RECHAMBER", "TEMPO_SURGE" },
	{ "DEEP_RESERVES", "HOT_STREAK" },
	{ "PRECISION_ECHO", "SPLINTER_SHOT" },
	{ "SPRINT_READY", "SURGING_STRIDE" },
	{ "AUTO_CYCLE", "OPENING_SALVO" },
	{ "OVERFLOW_CHAMBER", "BATTLE_RHYTHM" },
	{ "MOMENTUM_LOADER", "CASCADE_BURST" },
	{ "THREAT_SENSE", "CULL_THE_WEAK" },
	{ "STEADY_HANDS", "TEMPO_SURGE" },
	{ "SCAVENGERS_LUCK", "CASCADE_BURST" },
	{ "RIPOSTE_GUARD", "LAST_STAND" },
}

local ById: { [string]: PerkDef } = {}
for _, perk in List do
	ById[perk.Id] = perk
end

local synergyLookup: { [string]: boolean } = {}
for _, pair in Synergies do
	synergyLookup[pair[1] .. "|" .. pair[2]] = true
	synergyLookup[pair[2] .. "|" .. pair[1]] = true
end

local PerkConfig = {
	List = List,
	ById = ById,
	Synergies = Synergies,
	-- Weapon-type groups, exposed for tools and tests.
	Groups = {
		Primaries = PRIMARIES,
		Launchers = LAUNCHERS,
		Precision = PRECISION,
		Barreled = BARRELED,
		AllGuns = ALL_GUNS,
		All = ALL,
	},
}

function PerkConfig.IsSynergy(perkA: string, perkB: string): boolean
	return synergyLookup[perkA .. "|" .. perkB] == true
end

-- Perks of `column` that can roll on `weaponType`, in config order.
function PerkConfig.PoolFor(column: string, weaponType: string): { PerkDef }
	local pool = {}
	for _, perk in List do
		if perk.Column == column and table.find(perk.AppliesTo, weaponType) ~= nil then
			table.insert(pool, perk)
		end
	end
	return pool
end

return TableUtil.DeepFreeze(PerkConfig)
