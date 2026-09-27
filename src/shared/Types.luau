--!strict
--[[
	Types
	Shared type definitions used by server, client and config modules.

	This module has no runtime logic, so anything can require it without
	creating dependency cycles. Config modules describe their data with the
	*Def types below; saved player data is described by ProfileData.
]]

-- Enumerations ---------------------------------------------------------------

export type Rarity = "Rare" | "Epic" | "Legendary" | "Exotic"
export type ItemKind = "Weapon" | "Armor"
export type WeaponSlot = "Kinetic" | "Energy" | "Heavy"
export type ArmorSlot = "Helmet" | "Arms" | "Chest" | "Legs" | "ClassItem"
export type GearSlot = WeaponSlot | ArmorSlot
export type Element = "Kinetic" | "Flare" | "Storm" | "Null"
export type AmmoType = "Primary" | "Special" | "Heavy"
export type ItemLocation = "Inventory" | "Vault" | "Postmaster"
export type ClassId = "Bulwark" | "Ranger" | "Mystic"
export type WeaponTypeId =
	"AutoRifle"
	| "PulseRifle"
	| "ScoutRifle"
	| "HandCannon"
	| "SMG"
	| "Sidearm"
	| "Shotgun"
	| "SniperRifle"
	| "FusionRifle"
	| "GrenadeLauncher"
	| "RocketLauncher"
	| "Sword"
	| "MachineGun"
export type WeaponStat = "Impact" | "Range" | "Stability" | "Handling" | "Reload"
export type ArmorStat = "Agility" | "Fortitude" | "Vitality" | "Ordnance" | "Focus" | "Might"
export type PerkColumn = "Barrel" | "Magazine" | "Trait1" | "Trait2" | "Exotic" | "ExoticArmor"
export type RewardKind = "World" | "Powerful" | "Pinnacle"
export type FireMode = "Auto" | "Burst" | "Semi" | "Charge" | "Projectile" | "Melee"
export type EnemyTier = "Minor" | "Major" | "Boss"
export type ActivityType = "Story" | "Patrol" | "Strike" | "Nightfall" | "Dungeon" | "Raid" | "PvP"

-- Config definitions ---------------------------------------------------------

export type StatModifiers = { [string]: number }

export type WeaponTypeDef = {
	DisplayName: string,
	AmmoType: AmmoType,
	AllowedSlots: { WeaponSlot },
	FireMode: FireMode,
	BaseStats: { [string]: number },
	Rpm: number,
	Magazine: number,
	-- Reserve capacity for Special/Heavy ammo (Primary reserves are infinite).
	Reserves: number?,
	BurstCount: number?,
	ChargeTime: number?,
	Pellets: number?,
	BaseDamage: number,
	PrecisionMultiplier: number,
	Falloff: { Start: number, End: number, MinMultiplier: number },
	Ads: { Fov: number, MoveSpeedScale: number },
	Spread: { Hip: number, Ads: number, PerShot: number, Max: number },
	Recoil: { Vertical: number, Horizontal: number, Recovery: number },
	Projectile: { Speed: number, BlastRadius: number }?,
}

export type PerkEffect = {
	-- What makes the perk activate: "Passive", "Kill", "PrecisionKill", "PrecisionHit",
	-- "Hit", "Reload", "Moving", "LowHealth", "Sprint", "Aim", "Sustained", ...
	Trigger: string,
	-- What the perk does; combat code in later phases switches on this.
	Kind: string,
	Value: number?,
	Duration: number?,
	MaxStacks: number?,
	Radius: number?,
	Every: number?,
}

export type PerkDef = {
	Id: string,
	Name: string,
	Column: PerkColumn,
	Description: string,
	-- Weapon types (or "Armor") the perk can roll on. Exotic perks list their owner.
	AppliesTo: { string },
	StatModifiers: StatModifiers?,
	MagazineScale: number?,
	Effect: PerkEffect?,
}

export type WeaponDef = {
	Id: string,
	Name: string,
	Flavor: string,
	Rarity: Rarity,
	Type: WeaponTypeId,
	Slot: WeaponSlot,
	Element: Element,
	-- Where the weapon can drop: "World", "Story", "Patrol", "Strike", "Nightfall",
	-- "Dungeon", "Raid", "PvP", "Vendor", "Quest", "Starter".
	Sources: { string },
	-- Per-weapon stat personality applied on top of the archetype base stats.
	StatBias: StatModifiers?,
	Rpm: number?,
	Magazine: number?,
	-- Exotics (and curated weapons) list their perks here instead of rolling.
	FixedPerks: { string }?,
	-- Model name under ReplicatedStorage.Assets.Weapons (see AssetIds).
	Model: string,
}

export type ArmorDef = {
	Id: string,
	Name: string,
	Flavor: string,
	Rarity: Rarity,
	Slot: ArmorSlot,
	SetId: string?,
	ClassRestriction: ClassId?,
	Sources: { string },
	FixedPerks: { string }?,
	-- Optional stat personality: points shifted toward these stats when rolling.
	StatFocus: { string }?,
	Model: string,
}

-- Saved data -------------------------------------------------------------------

-- One owned weapon or armor piece. Everything needed to rebuild the item lives
-- here, so an item keeps its roll even if its config def is later rebalanced.
export type ItemInstance = {
	Uid: string,
	DefId: string,
	Kind: ItemKind,
	Slot: GearSlot,
	Rarity: Rarity,
	Power: number,
	-- Rolled base stats (weapon stats 0-100, or armor stats 2-30).
	Stats: { [string]: number },
	-- Perk ids ordered by column.
	Perks: { string },
	-- Weapon stat boosted by the masterwork, if any.
	Masterwork: string?,
	Location: ItemLocation,
	Locked: boolean,
	AcquiredAt: number,
}

export type BountyState = {
	Id: string,
	Progress: number,
	AcquiredAt: number,
	ExpiresAt: number,
}

export type PlayerSettings = {
	MouseSensitivity: number,
	AimSensitivityScale: number,
	ControllerSensitivity: number,
	FieldOfView: number,
	InvertY: boolean,
	ShowDamageNumbers: boolean,
	-- Action name -> KeyCode name overrides; defaults live in InputConfig.
	Keybinds: { [string]: string },
}

export type ProfileData = {
	SchemaVersion: number,
	CreatedAt: number,
	LastLoginAt: number,
	LoginCount: number,

	Class: string,
	-- Selected subclass per class, e.g. { Bulwark = "Emberwall" }.
	Subclasses: { [string]: string },

	-- Every owned item keyed by Uid, wherever it is stored.
	Items: { [string]: ItemInstance },
	-- Gear slot -> Uid of the equipped item.
	Equipped: { [string]: string },

	Currencies: { [string]: number },

	Progress: {
		StoryCompleted: { [string]: boolean },
		ActivityClears: { [string]: number },
		Unlocks: { [string]: boolean },
	},

	Weekly: {
		-- Timestamp of the weekly reset this block belongs to.
		ResetAt: number,
		-- Reward source id -> times claimed this week (Powerful/Pinnacle limits).
		ClaimedRewards: { [string]: number },
		MilestoneProgress: { [string]: number },
	},

	Daily: {
		ResetAt: number,
		ClaimedRewards: { [string]: number },
	},

	Bounties: {
		Active: { BountyState },
	},

	Artifact: {
		Level: number,
		Xp: number,
	},

	Lifetime: {
		HighestPower: number,
		Kills: number,
		PrecisionKills: number,
		ActivitiesCompleted: number,
		PlaytimeSeconds: number,
	},

	Settings: PlayerSettings,
	Flags: { [string]: boolean },
}

-- Modules must return exactly one value; the types above are what matter.
return table.freeze({})
