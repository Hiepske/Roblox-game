--!strict
--[[
	RunTypes
	The state of one running activity instance, shared by ActivityService
	(instances, players, deaths, rewards) and the mission modules (zones,
	steps, waves, bosses).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local ActivityRules = require(Shared.Activities.ActivityRules)
local MissionRules = require(Shared.Activities.MissionRules)

local EnemyService = require(script.Parent.Parent.Services.EnemyService)
local MapMarkers = require(script.Parent.MapMarkers)

export type RunStatus = "Active" | "Wiped" | "Complete" | "Closed"

export type Ghost = { Part: BasePart, Position: Vector3 }

export type PlayerStats = { Kills: number, Deaths: number }

-- A laser trap (a part tagged LL_Laser), with the timing clients animate it by.
export type Hazard = {
	Part: BasePart,
	Base: CFrame,
	Offset: Vector3,
	Period: number,
	Dwell: number,
	Phase: number,
	BlinkPeriod: number,
	BlinkOn: number,
	BlinkPhase: number,
	Damage: number,
}

export type Run = {
	Id: string,
	Slot: number,
	Activity: ActivityConfig.ActivityDef,
	Difficulty: ActivityConfig.DifficultyDef?,
	Power: number,
	Modifiers: { string },
	Effects: ActivityRules.ModifierEffects,
	Map: Model,
	Origin: Vector3,
	Markers: MapMarkers.Index,
	-- Live state for clients (ReplicatedStorage.LiveRuns.<Id> attributes).
	Folder: Folder,
	Players: { Player },
	Zones: { MissionRules.ZoneEntry },
	ZoneIndex: number,
	StepIndex: number,
	ZoneStartedAt: number,
	-- "Zone=seconds;..." for the Studio debug HUD.
	ZoneLog: string,
	Status: RunStatus,
	-- Name of the marker players respawn at.
	Checkpoint: string,
	StartedAt: number,
	Score: number,
	Deaths: number,
	-- Bumped whenever the runner must stop (wipe restart, completion, close).
	Token: number,
	-- Kills and enemies still arriving (spawn effects), per spawn tag.
	Kills: { [string]: number },
	Pending: { [string]: number },
	Boss: EnemyService.Enemy?,
	-- The current boss fight's marker folder (Arena) and spawn point.
	Arena: string?,
	BossSpawn: CFrame?,
	DamageBuff: number,
	Ghosts: { [Player]: Ghost },
	Cleared: { ActivityConfig.EncounterDef },
	Stats: { [Player]: PlayerStats },
	-- Where the loot chest appears (where the last boss fell).
	ChestAt: CFrame?,
	-- Players who already claimed their rewards.
	Rewarded: { [Player]: boolean },
	-- Medal earned by the finish time ("Gold" | "Silver" | "Bronze").
	Medal: string?,
	-- Seconds from start to finish, once complete.
	Elapsed: number?,
	-- Kills everyone and restarts the encounter (set by ActivityService).
	Wipe: (reason: string) -> (),
	-- A raid encounter was cleared (set by ActivityService: its chest).
	OnEncounterCleared: (encounter: ActivityConfig.EncounterDef) -> (),
	-- Laser traps in the map (found on first use) and when each player can be hit again.
	Hazards: { Hazard }?,
	HazardCooldown: { [Player]: number },
	-- Raid encounters: who was there when each was cleared, and who opened its chest.
	EncounterEligible: { [string]: { [Player]: boolean } },
	EncounterClaims: { [string]: { [Player]: boolean } },
}

return {}
