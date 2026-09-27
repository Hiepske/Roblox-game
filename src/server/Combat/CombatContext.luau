--!strict
--[[
	CombatContext
	Answers "what power situation is this player fighting in?" so damage in
	both directions uses the power-gap curve (PowerMath.CombatMultipliers).

	ActivityService installs a resolver at startup. Without one (or in the
	hub), the activity power equals the player's own power: delta 0, which
	is exactly what the shooting range should show.

	Kept dependency-free so any service can require it without cycles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityRules = require(ReplicatedStorage.Shared.Activities.ActivityRules)

export type Context = {
	CharacterPower: number,
	ArtifactLevel: number,
	ActivityPower: number,
	PowerEnabled: boolean,
	DeltaCap: number?,
	-- Active modifier effects (hardened strike), if any.
	Effects: ActivityRules.ModifierEffects?,
	-- Id of the activity instance the player is in (nil in the hub).
	InstanceId: string?,
	-- Extra outgoing damage multiplier (e.g. the raid's Echo Resonance).
	DamageBuff: number,
}

local CombatContext = {}

local resolver: ((Player) -> Context)? = nil

function CombatContext.SetResolver(fn: (Player) -> Context)
	resolver = fn
end

function CombatContext.Get(player: Player): Context
	if resolver then
		return resolver(player)
	end
	return {
		CharacterPower = 0,
		ArtifactLevel = 0,
		ActivityPower = 0,
		PowerEnabled = false,
		DeltaCap = nil,
		Effects = nil,
		InstanceId = nil,
		DamageBuff = 1,
	}
end

return CombatContext
