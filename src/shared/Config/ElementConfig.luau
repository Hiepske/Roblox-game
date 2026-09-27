--!strict
--[[
	ElementConfig
	Damage elements. Kinetic has no element; Flare, Storm and Null are the
	three energy elements. Enemy shields carry an element and take bonus
	damage from a matching weapon or ability, then burst when broken.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

export type ElementDef = {
	DisplayName: string,
	Description: string,
	Color: Color3,
}

local Elements: { [string]: ElementDef } = {
	Kinetic = {
		DisplayName = "Kinetic",
		Description = "Plain ballistic force. Hits harder against unshielded targets.",
		Color = Color3.fromRGB(225, 225, 225),
	},
	Flare = {
		DisplayName = "Flare",
		Description = "Solar fire that scorches and ignites.",
		Color = Color3.fromRGB(255, 130, 40),
	},
	Storm = {
		DisplayName = "Storm",
		Description = "Crackling arc energy that chains between targets.",
		Color = Color3.fromRGB(90, 200, 255),
	},
	Null = {
		DisplayName = "Null",
		Description = "Collapsing dark matter that weakens and devours.",
		Color = Color3.fromRGB(175, 95, 255),
	},
}

return TableUtil.DeepFreeze({
	Order = { "Kinetic", "Flare", "Storm", "Null" },
	Elements = Elements,
	-- Energy elements that can appear on enemy shields and energy/heavy weapons.
	EnergyElements = { "Flare", "Storm", "Null" },
	Shields = {
		MatchMultiplier = 2.0, -- matching element vs shield
		MismatchMultiplier = 1.0, -- different energy element vs shield
		KineticMultiplier = 0.75, -- kinetic vs any shield
		BreakBurst = { Radius = 8, Damage = 45 }, -- matching-element shield break
	},
	-- Kinetic weapons deal this much more damage to unshielded targets.
	KineticUnshieldedBonus = 1.1,
})
