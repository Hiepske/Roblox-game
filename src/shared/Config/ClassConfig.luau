--!strict
--[[
	ClassConfig
	The three Keeper classes, their shared class ability and jump, and their
	elemental subclasses (each with grenade, melee, super and a passive).

	Cooldowns are base seconds before armor stat scaling (ArmorConfig.TierEffects).
	Super.ChargeSeconds is the passive charge time with no kills; kills and
	damage add charge on top (Phase 9 tunes this).
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type AbilityDef = {
	Id: string,
	Name: string,
	Description: string,
	Cooldown: number,
}

export type SuperDef = {
	Id: string,
	Name: string,
	Description: string,
	ChargeSeconds: number,
	Duration: number,
}

export type SubclassDef = {
	Id: string,
	Name: string,
	Element: string,
	Description: string,
	Grenade: AbilityDef,
	Melee: AbilityDef,
	Super: SuperDef,
	Passive: { Name: string, Description: string },
}

export type ClassDef = {
	Id: string,
	Name: string,
	Role: string,
	Description: string,
	Health: number,
	Shield: number,
	WalkSpeed: number,
	ClassAbility: AbilityDef,
	Jump: { Id: string, Name: string, Description: string, Kind: "Lift" | "DoubleJump" | "Glide" },
	Subclasses: { SubclassDef },
}

local Classes: { ClassDef } = {
	{
		Id = "Bulwark",
		Name = "Bulwark",
		Role = "Tank",
		Description = "Frontline defenders who turn their bodies and their barriers into walls.",
		Health = 100,
		Shield = 120,
		WalkSpeed = 16,
		ClassAbility = {
			Id = "AegisWall",
			Name = "Aegis Wall",
			Description = "Raise a waist-high energy wall that blocks fire and speeds reloads behind it.",
			Cooldown = 40,
		},
		Jump = {
			Id = "Lift",
			Name = "Thruster Lift",
			Description = "Ignite boot thrusters for a strong, steady vertical lift.",
			Kind = "Lift",
		},
		Subclasses = {
			{
				Id = "Emberwall",
				Name = "Emberwall",
				Element = "Flare",
				Description = "Forge-hot guardians who burn anything that reaches the wall.",
				Grenade = {
					Id = "SlagGrenade",
					Name = "Slag Grenade",
					Description = "Leaves a pool of molten slag that burns enemies inside.",
					Cooldown = 60,
				},
				Melee = {
					Id = "ForgeFist",
					Name = "Forge Fist",
					Description = "A heavy blazing punch that ignites the target.",
					Cooldown = 50,
				},
				Super = {
					Id = "MoltenBastion",
					Name = "Molten Bastion",
					Description = "Plant a great burning shield dome; allies inside deal more damage and heal.",
					ChargeSeconds = 420,
					Duration = 15,
				},
				Passive = { Name = "Stoked", Description = "Flare kills restore a little class ability energy." },
			},
			{
				Id = "Thunderguard",
				Name = "Thunderguard",
				Element = "Storm",
				Description = "Living lightning rods who charge headlong into the fight.",
				Grenade = {
					Id = "ConductorGrenade",
					Name = "Conductor Grenade",
					Description = "Arcs lightning between every enemy caught in its blast.",
					Cooldown = 55,
				},
				Melee = {
					Id = "Shoulderstorm",
					Name = "Shoulderstorm",
					Description = "A sprinting shoulder charge that detonates in a thunderclap.",
					Cooldown = 45,
				},
				Super = {
					Id = "StormfrontAegis",
					Name = "Stormfront Aegis",
					Description = "Raise a crackling tower shield; bash, block and hurl it at enemies.",
					ChargeSeconds = 420,
					Duration = 18,
				},
				Passive = { Name = "Grounded", Description = "Taking damage while shielded builds melee energy." },
			},
		},
	},
	{
		Id = "Ranger",
		Name = "Ranger",
		Role = "Agile",
		Description = "Precision hunters who strike from angles no one else can reach.",
		Health = 100,
		Shield = 100,
		WalkSpeed = 17,
		ClassAbility = {
			Id = "Dodge",
			Name = "Evasive Roll",
			Description = "A quick roll that reloads your weapon.",
			Cooldown = 25,
		},
		Jump = {
			Id = "DoubleJump",
			Name = "Double Jump",
			Description = "Kick off the air itself for a second jump.",
			Kind = "DoubleJump",
		},
		Subclasses = {
			{
				Id = "Shadewalker",
				Name = "Shadewalker",
				Element = "Null",
				Description = "Silent stalkers who blind, weaken and vanish.",
				Grenade = {
					Id = "SnareMine",
					Name = "Snare Mine",
					Description = "A tripwire mine that tethers and weakens anything that crosses it.",
					Cooldown = 55,
				},
				Melee = {
					Id = "SmokeKnife",
					Name = "Smoke Knife",
					Description = "Throw a knife that bursts into blinding Null smoke.",
					Cooldown = 45,
				},
				Super = {
					Id = "NullVolley",
					Name = "Null Volley",
					Description = "Draw a bow of dark matter and loose three piercing, tethering arrows.",
					ChargeSeconds = 400,
					Duration = 8,
				},
				Passive = { Name = "Fade", Description = "Dodging near enemies turns you briefly invisible." },
			},
			{
				Id = "Galecutter",
				Name = "Galecutter",
				Element = "Storm",
				Description = "Duelists who ride the lightning from target to target.",
				Grenade = {
					Id = "RicochetCharge",
					Name = "Ricochet Charge",
					Description = "A charge that bounces along the ground and splits into seekers.",
					Cooldown = 50,
				},
				Melee = {
					Id = "Knifewind",
					Name = "Knifewind",
					Description = "Throw a storm-charged knife that ricochets once on a precision hit.",
					Cooldown = 40,
				},
				Super = {
					Id = "SixfoldArc",
					Name = "Sixfold Arc",
					Description = "Fire six rapid lightning shots, each chaining to nearby enemies.",
					ChargeSeconds = 400,
					Duration = 10,
				},
				Passive = { Name = "Static Step", Description = "Precision kills make your next dodge refresh sooner." },
			},
		},
	},
	{
		Id = "Mystic",
		Name = "Mystic",
		Role = "Caster",
		Description = "Channelers of raw Light who heal allies and unmake enemies.",
		Health = 100,
		Shield = 100,
		WalkSpeed = 16,
		ClassAbility = {
			Id = "Sanctum",
			Name = "Sanctum Circle",
			Description = "Channel a circle of Light that heals or empowers allies standing in it.",
			Cooldown = 60,
		},
		Jump = {
			Id = "Glide",
			Name = "Glide",
			Description = "Hover and drift through the air.",
			Kind = "Glide",
		},
		Subclasses = {
			{
				Id = "Sunweaver",
				Name = "Sunweaver",
				Element = "Flare",
				Description = "Healers who weave sunlight into restoration and ruin.",
				Grenade = {
					Id = "SunflareGrenade",
					Name = "Sunflare Grenade",
					Description = "A lingering burst of sunlight that heals allies and burns enemies.",
					Cooldown = 60,
				},
				Melee = {
					Id = "Cinderpalm",
					Name = "Cinderpalm",
					Description = "A searing palm strike that ignites and heals you on kill.",
					Cooldown = 45,
				},
				Super = {
					Id = "Solarbeam",
					Name = "Radiant Lance",
					Description = "Channel a continuous beam of solar fire that melts everything in its path.",
					ChargeSeconds = 440,
					Duration = 7,
				},
				Passive = { Name = "Afterglow", Description = "Healing an ally grants both of you bonus damage." },
			},
			{
				Id = "Riftcaller",
				Name = "Riftcaller",
				Element = "Null",
				Description = "Void-touched casters who tear holes in the world.",
				Grenade = {
					Id = "MaelstromOrb",
					Name = "Maelstrom Orb",
					Description = "Opens a swirling singularity that damages enemies over time.",
					Cooldown = 60,
				},
				Melee = {
					Id = "HungerTouch",
					Name = "Hunger Touch",
					Description = "A Null strike that drains health from the target to you.",
					Cooldown = 45,
				},
				Super = {
					Id = "AbyssBeam",
					Name = "Abyssal Ray",
					Description = "Fire a beam of collapsing dark matter that weakens and pulls enemies.",
					ChargeSeconds = 440,
					Duration = 6,
				},
				Passive = {
					Name = "Hollow Feast",
					Description = "Ability kills fully restore health and extend grenade energy.",
				},
			},
		},
	},
}

local ById: { [string]: ClassDef } = {}
local SubclassById: { [string]: SubclassDef } = {}
local SubclassOwner: { [string]: string } = {}
for _, class in Classes do
	ById[class.Id] = class
	for _, subclass in class.Subclasses do
		SubclassById[subclass.Id] = subclass
		SubclassOwner[subclass.Id] = class.Id
	end
end

return TableUtil.DeepFreeze({
	List = Classes,
	ById = ById,
	SubclassById = SubclassById,
	-- Subclass id -> class id that owns it.
	SubclassOwner = SubclassOwner,
	-- Super charge gained per kill, as a fraction of a full bar.
	SuperChargePerKill = { Minor = 0.01, Major = 0.03, Boss = 0.06 },
})
