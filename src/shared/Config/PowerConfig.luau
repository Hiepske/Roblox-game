--!strict
--[[
	PowerConfig
	All numbers behind power progression. PowerMath reads these; nothing
	else should hard-code a power value. See DESIGN.md "Power math".

	Stage            | Range     | What raises power
	-----------------|-----------|-----------------------------------------
	Starting         | 350       | new character
	Soft cap         | 350 - 450 | any drop (world, enemies, chests)
	Powerful cap     | 450 - 490 | only Powerful rewards (weekly)
	Pinnacle cap     | 490 - 500 | only Pinnacle rewards (weekly)
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local PowerConfig = {
	StartingPower = 350,
	SoftCap = 450,
	PowerfulCap = 490,
	PinnacleCap = 500,

	-- Gear slots that make up character power (average of all eight).
	WeaponSlots = { "Kinetic", "Energy", "Heavy" },
	ArmorSlots = { "Helmet", "Arms", "Chest", "Legs", "ClassItem" },

	-- Ordinary drops (enemies, chests, story, patrol, vendors).
	World = {
		-- Below the soft cap: highest possible power + [MinBonus, MaxBonus].
		MinBonus = 0,
		MaxBonus = 5,
		-- At/above the soft cap ordinary drops can no longer raise power.
		-- "AtCurrent": drop at your highest power (never junk, never an upgrade).
		-- "AtSoftCap": drop at exactly the soft cap (strict reading of the cap).
		AboveSoftCap = "AtCurrent",
	},

	-- Powerful rewards: weekly milestones, weekly bounties, playlist completions.
	Powerful = {
		-- Tier -> bonus over highest possible power (until the powerful cap).
		TierBonus = { 3, 4, 5 },
		-- Once at/above the powerful cap they drop at highest possible power.
	},

	-- Pinnacle rewards: raid encounters, dungeon boss, top-tier Nightfall...
	Pinnacle = {
		MinBonus = 1,
		MaxBonus = 2,
		-- Below the powerful cap a pinnacle is at least as good as this
		-- Powerful tier (clamped to the powerful cap), so it is never wasted.
		BelowPowerfulCapTier = 3,
	},

	-- Combat scaling by the gap between player power and activity power.
	-- delta = (character power + artifact bonus) - activity recommended power.
	-- Points are linearly interpolated and clamped at both ends.
	-- Outgoing multiplies damage the player deals; Incoming multiplies damage
	-- the player takes.
	PowerDelta = {
		Points = {
			{ Delta = -50, Outgoing = 0.30, Incoming = 3.00 },
			{ Delta = -30, Outgoing = 0.50, Incoming = 2.00 },
			{ Delta = -20, Outgoing = 0.65, Incoming = 1.60 },
			{ Delta = -10, Outgoing = 0.82, Incoming = 1.25 },
			{ Delta = -5, Outgoing = 0.91, Incoming = 1.10 },
			{ Delta = 0, Outgoing = 1.00, Incoming = 1.00 },
			{ Delta = 10, Outgoing = 1.06, Incoming = 0.92 },
			{ Delta = 20, Outgoing = 1.10, Incoming = 0.88 },
		},
	},

	-- Enemies in higher-power activities are sturdier on top of the delta
	-- curve, so a 500 raid feels harder than a 350 mission even at delta 0.
	ActivityScaling = {
		ReferencePower = 350,
		HealthPerPower = 0.004, -- +0.4% enemy health per power over reference
		DamagePerPower = 0.003, -- +0.3% enemy damage per power over reference
	},

	-- Seasonal artifact: +PowerPerLevel combat power per level. Not gear power,
	-- not limited by the pinnacle cap, and only used for combat math.
	Artifact = {
		Enabled = true,
		PowerPerLevel = 1,
		MaxLevel = 100,
		-- XP needed for level n = BaseXp + (n - 1) * XpGrowth.
		BaseXp = 5000,
		XpGrowth = 500,
	},
}

return TableUtil.DeepFreeze(PowerConfig)
