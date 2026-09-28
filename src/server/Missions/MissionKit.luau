--!strict
--[[
	MissionKit
	Small helpers shared by the mission modules (steps, waves, gates, boss
	fights): the run clock, live HUD attributes, player queries, enemy
	spawn options and world cues (visual effects sent to the run's players).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MissionRules = require(Shared.Activities.MissionRules)
local PowerMath = require(Shared.Power.PowerMath)

local Services = script.Parent.Parent.Services
local CharacterService = require(Services.CharacterService)
local EnemyService = require(Services.EnemyService)
local NetService = require(Services.NetService)
local WorldService = require(Services.WorldService)
local MapMarkers = require(script.Parent.MapMarkers)
local RunTypes = require(script.Parent.RunTypes)

type Run = RunTypes.Run

local MissionKit = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

function MissionKit.Now(): number
	return Workspace:GetServerTimeNow()
end

function MissionKit.IsActive(run: Run, token: number): boolean
	return run.Status == "Active" and run.Token == token
end

function MissionKit.RootOf(player: Player): BasePart?
	local character = CharacterService.GetCharacter(player)
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

function MissionKit.AlivePlayers(run: Run): { Player }
	local list: { Player } = {}
	for _, player in run.Players do
		if CharacterService.IsAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

-- Root parts of every living player in the run.
function MissionKit.AliveRoots(run: Run): { BasePart }
	local list: { BasePart } = {}
	for _, player in run.Players do
		local root = if CharacterService.IsAlive(player) then MissionKit.RootOf(player) else nil
		if root then
			table.insert(list, root)
		end
	end
	return list
end

-- HUD state -----------------------------------------------------------------------------

function MissionKit.SetAttr(run: Run, name: string, value: any)
	if run.Status ~= "Closed" then
		run.Folder:SetAttribute(name, value)
	end
end

function MissionKit.SetObjective(run: Run, text: string, count: string?, progress: number?, waypoint: Vector3?)
	MissionKit.SetAttr(run, "ObjectiveText", text)
	MissionKit.SetAttr(run, "ObjectiveCount", count or "")
	MissionKit.SetAttr(run, "ObjectiveProgress", progress or -1)
	MissionKit.SetAttr(run, "HasWaypoint", waypoint ~= nil)
	if waypoint then
		MissionKit.SetAttr(run, "Waypoint", waypoint)
	end
end

function MissionKit.SetPhase(run: Run, text: string?, endsAt: number?)
	MissionKit.SetAttr(run, "Phase", text or "")
	MissionKit.SetAttr(run, "PhaseEndsAt", endsAt or 0)
end

function MissionKit.SyncBoss(run: Run)
	local boss = run.Boss
	if boss == nil or boss.Dead then
		MissionKit.SetAttr(run, "BossActive", false)
		return
	end
	MissionKit.SetAttr(run, "BossActive", true)
	MissionKit.SetAttr(run, "BossName", boss.Def.Name)
	MissionKit.SetAttr(run, "BossTitle", boss.Def.Title or "")
	MissionKit.SetAttr(run, "BossHealth", boss.Health)
	MissionKit.SetAttr(run, "BossMaxHealth", boss.MaxHealth)
	MissionKit.SetAttr(run, "BossShield", boss.Shield)
	MissionKit.SetAttr(run, "BossMaxShield", boss.MaxShield)
	MissionKit.SetAttr(run, "BossImmune", boss.Immune)
end

-- Markers --------------------------------------------------------------------------------

function MissionKit.Marker(run: Run, name: string?): BasePart?
	return MapMarkers.Find(run.Markers, name)
end

-- Where a player standing on marker `name` goes (falls back to the start).
function MissionKit.MarkerCFrame(run: Run, name: string?): CFrame
	local marker = MissionKit.Marker(run, name) or MissionKit.Marker(run, "PlayerStart")
	if marker then
		return marker.CFrame + Vector3.new(0, 1.5, 0)
	end
	return CFrame.new(run.Origin + Vector3.new(0, 6, 0))
end

-- Living players inside a zone box marker (MapKit.Zone).
function MissionKit.PlayersInZone(run: Run, zone: BasePart): { Player }
	local inside: { Player } = {}
	local half = zone.Size / 2
	for _, player in run.Players do
		local root = MissionKit.RootOf(player)
		if root then
			local offset = zone.CFrame:PointToObjectSpace(root.Position)
			local horizontal = Vector2.new(offset.X, offset.Z).Magnitude
			if horizontal <= half.X and math.abs(offset.Y) <= half.Y + 4 then
				table.insert(inside, player)
			end
		end
	end
	return inside
end

-- Ground under a point (the point itself over a hole).
function MissionKit.GroundAt(position: Vector3): Vector3
	groundParams.FilterDescendantsInstances = {
		WorldService.Folder("Enemies"),
		WorldService.Folder("Pickups"),
		table.unpack(WorldService.PlayerCharacters()),
	}
	local result = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), groundParams)
	return if result then result.Position else position
end

-- Enemies ----------------------------------------------------------------------------------

-- Health and damage scaling for enemies spawned in this run.
function MissionKit.SpawnOptions(run: Run, tag: string, aggro: boolean, boss: boolean?): EnemyService.SpawnOptions
	local healthScale, damageScale = PowerMath.ActivityEnemyScale(run.Power)
	return {
		InstanceId = run.Id,
		Tag = tag,
		HealthScale = healthScale * run.Effects.EnemyHealth * MissionRules.HealthScale(#run.Players, boss == true),
		DamageScale = damageScale * run.Effects.EnemyDamage,
		ExtraShields = run.Effects.ExtraShields,
		Aggro = aggro,
	}
end

-- Living enemies whose tag is `tag` (or starts with it when `prefix`).
function MissionKit.AliveWithTag(run: Run, tag: string, prefix: boolean?): number
	local count = 0
	for _, enemy in EnemyService.GetEnemies(run.Id) do
		local enemyTag = enemy.Tag
		if enemyTag == tag or (prefix and enemyTag and string.sub(enemyTag, 1, #tag) == tag) then
			count += 1
		end
	end
	return count
end

-- Enemies still arriving (spawn effect playing) for a tag or tag prefix.
function MissionKit.PendingWithTag(run: Run, tag: string, prefix: boolean?): number
	local count = 0
	for pendingTag, pending in run.Pending do
		if pendingTag == tag or (prefix and string.sub(pendingTag, 1, #tag) == tag) then
			count += pending
		end
	end
	return count
end

function MissionKit.KillsWithTag(run: Run, tag: string, prefix: boolean?): number
	local count = 0
	for killTag, kills in run.Kills do
		if killTag == tag or (prefix and string.sub(killTag, 1, #tag) == tag) then
			count += kills
		end
	end
	return count
end

function MissionKit.AliveInRun(run: Run): number
	return #EnemyService.GetEnemies(run.Id)
end

-- World cues -------------------------------------------------------------------------------

-- Tells the run's players to play a visual effect ("Portal", "Dropship",
-- "Telegraph", "Shockwave", "SafeZone", "Nova", "Blink", "Charge",
-- "ShieldUp", "ShieldBreak", "GateOpen", "BossDeath"...). See EffectsController.
function MissionKit.Cue(run: Run, kind: string, ...: any)
	for _, player in run.Players do
		NetService.FireClient(player, "WorldCue", kind, ...)
	end
end

return MissionKit
