--!strict
--[[
	MissionRules
	Pure rules for the zone flow (MissionService), shared so tests and the
	HUD agree with the server:
	  * the ordered list of zones an activity runs (raid encounters' zones
	    follow the activity's own)
	  * fireteam scaling of wave sizes and enemy/boss health
	  * wave sizes, the markers a map needs, and time formatting
]]

local Shared = script.Parent.Parent
local ActivityConfig = require(Shared.Config.ActivityConfig)
local BossConfig = require(Shared.Config.BossConfig)
local CombatConfig = require(Shared.Config.CombatConfig)

type ActivityDef = ActivityConfig.ActivityDef
type ZoneDef = ActivityConfig.ZoneDef
type StepDef = ActivityConfig.StepDef
type WaveDef = ActivityConfig.WaveDef

local MissionRules = {}

export type ZoneEntry = {
	Zone: ZoneDef,
	-- Set when the zone belongs to a raid/dungeon encounter.
	Encounter: ActivityConfig.EncounterDef?,
}

-- Every zone the runner walks through, in order.
function MissionRules.ZoneList(activity: ActivityDef): { ZoneEntry }
	local list: { ZoneEntry } = {}
	for _, zone in activity.Zones or {} :: { ZoneDef } do
		table.insert(list, { Zone = zone })
	end
	for _, encounter in activity.Encounters or {} :: { ActivityConfig.EncounterDef } do
		if encounter.Playable then
			for _, zone in encounter.Zones or {} :: { ZoneDef } do
				table.insert(list, { Zone = zone, Encounter = encounter })
			end
		end
	end
	return list
end

-- Index of the first zone of the encounter that zone `index` belongs to
-- (raid wipes restart there). Zones outside encounters restart themselves.
function MissionRules.EncounterStart(list: { ZoneEntry }, index: number): number
	local entry = list[index]
	if entry == nil or entry.Encounter == nil then
		return index
	end
	local first = index
	while first > 1 and list[first - 1].Encounter == entry.Encounter do
		first -= 1
	end
	return first
end

-- Party scaling ---------------------------------------------------------------------

local function extra(players: number): number
	return math.max(0, math.floor(players) - 1)
end

-- Enemies in a wave for a fireteam of `players` (always at least 1 of each kind).
function MissionRules.ScaledCount(count: number, players: number): number
	if count <= 0 then
		return 0
	end
	return math.max(1, math.floor(count * (1 + extra(players) * CombatConfig.PartyScaling.CountPerExtraPlayer) + 0.5))
end

function MissionRules.HealthScale(players: number, boss: boolean): number
	local per = if boss
		then CombatConfig.PartyScaling.BossHealthPerExtraPlayer
		else CombatConfig.PartyScaling.HealthPerExtraPlayer
	return 1 + extra(players) * per
end

-- A wave as a sorted list (deterministic order) of { Id, Count } for `players`.
function MissionRules.WaveList(wave: WaveDef, players: number): { { Id: string, Count: number } }
	local list: { { Id: string, Count: number } } = {}
	for id, count in wave.Enemies do
		local scaled = MissionRules.ScaledCount(count, players)
		if scaled > 0 then
			table.insert(list, { Id = id, Count = scaled })
		end
	end
	table.sort(list, function(a: { Id: string, Count: number }, b: { Id: string, Count: number }): boolean
		return a.Id < b.Id
	end)
	return list
end

function MissionRules.WaveSize(wave: WaveDef, players: number): number
	local total = 0
	for _, entry in MissionRules.WaveList(wave, players) do
		total += entry.Count
	end
	return total
end

-- Total enemies across a step's waves.
function MissionRules.StepSize(step: StepDef, players: number): number
	local total = 0
	for _, wave in step.Waves or {} :: { WaveDef } do
		total += MissionRules.WaveSize(wave, players)
	end
	return total
end

-- Markers ----------------------------------------------------------------------------

-- "Marker": a marker named Name; "Spawns": an EnemySpawns folder (or Phase 2
-- Spawn_<Name>_n markers); "Gate": a gate or door; "Numbered": markers
-- Name_1..Count
export type RequirementKind = "Marker" | "Spawns" | "Gate" | "Numbered"

export type Requirement = {
	Kind: RequirementKind,
	Name: string,
	Count: number?,
	Where: string,
	-- Look only inside this marker folder (a boss arena).
	Arena: string?,
}

-- Everything a map must contain for `activity` to run (checked by tests and
-- by MapBuilders/Generate in Studio).
function MissionRules.Requirements(activity: ActivityDef): { Requirement }
	local list: { Requirement } = {}
	local function need(kind: RequirementKind, name: string, where: string, count: number?, arena: string?)
		table.insert(list, { Kind = kind, Name = name, Count = count, Where = where, Arena = arena })
	end
	need("Marker", "PlayerStart", activity.Id)
	for _, entry in MissionRules.ZoneList(activity) do
		local zone = entry.Zone
		local where = `{activity.Id}/{zone.Id}`
		-- Every zone moves the checkpoint: Checkpoint, or the marker CP_<zone Id>.
		need("Marker", zone.Checkpoint or `CP_{zone.Id}`, where)
		if zone.Gate then
			need("Gate", zone.Gate, where)
		end
		for index, step in zone.Steps do
			local label = `{where}/step {index}`
			local spawns = step.Spawns or zone.Id
			if step.Kind == "Travel" or step.Kind == "Defend" or step.Kind == "Interact" then
				need("Marker", step.Target or "?", label)
			end
			if step.Kind == "Destroy" then
				need("Numbered", step.Target or "?", label, step.Count or 1)
			end
			if step.Waves ~= nil or step.Kind == "Boss" then
				need("Spawns", spawns, label)
			end
			for _, wave in step.Waves or {} :: { WaveDef } do
				if wave.Spawns and wave.Spawns ~= spawns then
					need("Spawns", wave.Spawns, label)
				end
			end
			if step.Kind == "Boss" then
				local arena = step.Arena
				need("Marker", "BossSpawn", label, nil, arena)
				local boss = BossConfig.ById[step.Boss or ""]
				if boss then
					for _, immune in boss.Immune do
						if immune.Break == "Pylons" then
							need("Numbered", "Pylon", label, immune.Count or 3, arena)
						end
					end
					for _, attack in boss.Attacks do
						if attack.Kind == "Teleport" then
							need("Numbered", "Teleport", label, 2, arena)
						elseif attack.Kind == "Nova" then
							need("Numbered", "Safe", label, 1, arena)
						end
					end
					if boss.Script == "EchoPlates" then
						need("Numbered", "Plate", label, 3, arena)
					elseif boss.Script == "EchoDeposit" then
						need("Numbered", "Room", label, 3, arena)
						need("Marker", "EchoWell", label, nil, arena)
					end
				end
			end
		end
	end
	return list
end

-- Medals ----------------------------------------------------------------------------

-- "Gold" | "Silver" | "Bronze" for finishing in `seconds`, or nil.
function MissionRules.Medal(activity: ActivityDef, seconds: number): string?
	local medals = activity.Medals
	if medals == nil then
		return nil
	end
	if seconds <= medals.Gold then
		return "Gold"
	elseif seconds <= medals.Silver then
		return "Silver"
	elseif seconds <= medals.Bronze then
		return "Bronze"
	end
	return nil
end

-- The best medal still reachable at `seconds` and its time limit, or nil.
function MissionRules.NextMedal(activity: ActivityDef, seconds: number): (string?, number?)
	local medals = activity.Medals
	if medals == nil then
		return nil, nil
	end
	local order: { { Name: string, Limit: number } } = {
		{ Name = "Gold", Limit = medals.Gold },
		{ Name = "Silver", Limit = medals.Silver },
		{ Name = "Bronze", Limit = medals.Bronze },
	}
	for _, entry in order do
		if seconds <= entry.Limit then
			return entry.Name, entry.Limit
		end
	end
	return nil, nil
end

-- Formatting ------------------------------------------------------------------------

-- 125 -> "2:05"
function MissionRules.FormatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Zone timing log kept on the run folder for the Studio debug HUD:
-- "Name=seconds;Name=seconds".
function MissionRules.AppendZoneLog(log: string, name: string, seconds: number): string
	local entry = `{string.gsub(name, "[;=]", " ")}={math.floor(seconds + 0.5)}`
	return if log == "" then entry else `{log};{entry}`
end

function MissionRules.ParseZoneLog(log: string): { { Name: string, Seconds: number } }
	local list: { { Name: string, Seconds: number } } = {}
	for _, part in string.split(log, ";") do
		local name, seconds = string.match(part, "^(.-)=(%d+)$")
		if name and seconds then
			table.insert(list, { Name = name, Seconds = tonumber(seconds) or 0 })
		end
	end
	return list
end

return MissionRules
