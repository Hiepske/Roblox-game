--!strict
--[[
	BossFight
	Runs one boss fight from BossConfig (see its header for the data):

	  * spawns the boss at BossArena/BossSpawn; the HUD bar follows it
	  * immune phases: damage can't push the boss past the next threshold
	    (EnemyService health floor); at the threshold it raises a shield
	    bubble until the phase's Break is done (adds or pylons), and the
	    floor can collapse under the fireteam
	  * special attacks on cooldowns (barrage, slam with a warning circle,
	    teleport, nova with safe circles), a trickle of adds, heavy ammo
	    dropped at BossArena/Ammo_n, and an enrage timer for raid bosses
	  * on death: a huge explosion and a moment of slow motion on every
	    client, the arena is cleared and the loot chest's spot is recorded
	  * Script "EchoPlates" swaps the loop for the raid's plate mechanic
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local BossConfig = require(Shared.Config.BossConfig)
local CombatConfig = require(Shared.Config.CombatConfig)

local Services = script.Parent.Parent.Services
local CharacterService = require(Services.CharacterService)
local EnemyService = require(Services.EnemyService)
local LootService = require(Services.LootService)
local MapMarkers = require(script.Parent.MapMarkers)
local MissionKit = require(script.Parent.MissionKit)
local RunTypes = require(script.Parent.RunTypes)
local Spawner = require(script.Parent.Spawner)

type Run = RunTypes.Run
type Enemy = EnemyService.Enemy
type BossDef = BossConfig.BossDef
type AttackDef = BossConfig.AttackDef
type ImmuneDef = BossConfig.ImmuneDef

local BossFight = {}

local rng = Random.new()
local now = MissionKit.Now

type ImmuneState = {
	Def: ImmuneDef,
	Tag: string,
	WavesLeft: number,
	WaveSize: number,
}

-- Helpers ------------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Hurts every living player within `radius` of `center` (falls off to 60% at the edge).
local function blast(run: Run, boss: Enemy, center: Vector3, radius: number, damage: number)
	for _, player in MissionKit.AlivePlayers(run) do
		local root = MissionKit.RootOf(player)
		if root then
			local distance = flatDistance(root.Position, center)
			if distance <= radius and math.abs(root.Position.Y - center.Y) <= CombatConfig.Boss.HitHeight then
				local falloff = 1 - 0.4 * (distance / radius)
				CharacterService.DamagePlayer(player, damage * boss.DamageScale * falloff, boss.Def.Name)
			end
		end
	end
end

local function spawnsFor(immune: ImmuneDef): ActivityConfig.WaveDef
	return { Enemies = immune.Enemies or {}, Arrival = "Portal" }
end

-- Pieces of the map named `name` flash red, then fall away.
local function collapse(run: Run, name: string)
	local target = run.Map:FindFirstChild(name, true)
	if target == nil then
		warn(`[BossFight] {run.Activity.Id}: nothing named {name} to collapse`)
		return
	end
	local parts: { BasePart } = {}
	if target:IsA("BasePart") then
		table.insert(parts, target)
	end
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	local warning = CombatConfig.Boss.CollapseWarning
	local center = if target:IsA("Model")
		then target:GetPivot().Position
		elseif #parts > 0 then parts[1].Position
		else run.Origin
	MissionKit.Cue(run, "Collapse", center, warning)
	for _, part in parts do
		part.Color = Color3.fromRGB(255, 70, 40)
		part.Material = Enum.Material.Neon
	end
	task.delay(warning, function()
		for _, part in parts do
			if part.Parent then
				part.CanCollide = false
				part.CanQuery = false
				local spin =
					CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6))
				local goal = (part.CFrame + Vector3.new(0, -120, 0)) * spin
				TweenService:Create(part, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = goal,
					Transparency = 1,
				}):Play()
			end
		end
	end)
end

-- Attacks -------------------------------------------------------------------------------

local function barrage(run: Run, token: number, boss: Enemy, attack: AttackDef)
	local windup = attack.Windup or 1.2
	local count = attack.Count or 12
	EnemyService.SetBusy(boss, windup + 1.8)
	MissionKit.Cue(run, "Charge", boss.Head.Position, windup)
	task.wait(windup)
	for index = 1, count do
		if not MissionKit.IsActive(run, token) or boss.Dead then
			return
		end
		local roots = MissionKit.AliveRoots(run)
		if #roots == 0 then
			return
		end
		local root = roots[index % #roots + 1]
		local lead = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-1, 2), rng:NextNumber(-4, 4))
		EnemyService.FireVolley(boss, {
			Targets = { root.Position + lead },
			Damage = (attack.Damage or 10) * boss.DamageScale,
			Spread = 3,
			Style = "BossOrb",
		})
		task.wait(1.5 / count)
	end
end

local function slam(run: Run, token: number, boss: Enemy, attack: AttackDef)
	local roots = MissionKit.AliveRoots(run)
	if #roots == 0 then
		return
	end
	local target = roots[rng:NextInteger(1, #roots)]
	local center = MissionKit.GroundAt(target.Position)
	local radius = attack.Radius or 15
	local windup = attack.Windup or 1.8
	local leap = attack.Leap == true and boss.Def.MoveSpeed > 0
	EnemyService.SetBusy(boss, windup + 1)
	MissionKit.Cue(run, "Telegraph", center, radius, windup)
	if leap then
		task.wait(math.max(0, windup - 0.45))
		if not MissionKit.IsActive(run, token) or boss.Dead then
			return
		end
		EnemyService.Leap(boss, center, 0.45)
	else
		task.wait(windup)
	end
	if not MissionKit.IsActive(run, token) or boss.Dead then
		return
	end
	MissionKit.Cue(run, "Shockwave", center, radius)
	blast(run, boss, center, radius, attack.Damage or 50)
end

local function teleport(run: Run, token: number, boss: Enemy)
	local spots = MapMarkers.Numbered(run.Markers, "Teleport")
	if #spots == 0 then
		return
	end
	-- Anywhere but where it is now.
	local here = boss.Root.Position
	local choices: { BasePart } = {}
	for _, spot in spots do
		if (spot.Position - here).Magnitude > 12 then
			table.insert(choices, spot)
		end
	end
	if #choices == 0 then
		return
	end
	local spot = choices[rng:NextInteger(1, #choices)]
	EnemyService.SetBusy(boss, 1.4)
	MissionKit.Cue(run, "Blink", here)
	task.wait(0.5)
	if not MissionKit.IsActive(run, token) or boss.Dead then
		return
	end
	EnemyService.Relocate(boss, spot.CFrame + Vector3.new(0, 3, 0))
	MissionKit.Cue(run, "Blink", spot.Position)
end

local function nova(run: Run, token: number, boss: Enemy, attack: AttackDef)
	local safes = MapMarkers.Numbered(run.Markers, "Safe")
	if #safes == 0 then
		return
	end
	local windup = attack.Windup or 8
	local radius = attack.Radius or 10
	-- One or two of the safe circles light up.
	local chosen: { BasePart } = {}
	local pool = table.clone(safes)
	for _ = 1, math.min(#pool, if #pool >= 3 then 2 else 1) do
		table.insert(chosen, table.remove(pool, rng:NextInteger(1, #pool)) :: BasePart)
	end
	EnemyService.SetBusy(boss, windup + 1)
	for _, safe in chosen do
		MissionKit.Cue(run, "SafeZone", safe.Position, radius, windup)
	end
	MissionKit.Cue(run, "Charge", boss.Head.Position, windup)
	MissionKit.SetPhase(run, "Get inside a safe circle!", now() + windup)
	task.wait(windup)
	if not MissionKit.IsActive(run, token) or boss.Dead then
		return
	end
	MissionKit.SetPhase(run, nil, nil)
	MissionKit.Cue(run, "Nova", boss.Root.Position)
	for _, player in MissionKit.AlivePlayers(run) do
		local root = MissionKit.RootOf(player)
		local safe = false
		if root then
			for _, spot in chosen do
				if
					flatDistance(root.Position, spot.Position) <= radius
					and math.abs(root.Position.Y - spot.Position.Y) <= CombatConfig.Boss.HitHeight
				then
					safe = true
				end
			end
		end
		if not safe then
			CharacterService.DamagePlayer(player, (attack.Damage or 9999) * boss.DamageScale, boss.Def.Name)
		end
	end
end

local function perform(run: Run, token: number, boss: Enemy, attack: AttackDef)
	if attack.Kind == "Barrage" then
		barrage(run, token, boss, attack)
	elseif attack.Kind == "Slam" then
		slam(run, token, boss, attack)
	elseif attack.Kind == "Teleport" then
		teleport(run, token, boss)
	elseif attack.Kind == "Nova" then
		nova(run, token, boss, attack)
	end
end

-- Immune phases ------------------------------------------------------------------------

local function startImmune(
	run: Run,
	token: number,
	boss: Enemy,
	immune: ImmuneDef,
	index: number,
	spawns: string
): ImmuneState
	local tag = `bossImmune{index}_{token}`
	EnemyService.SetImmune(boss, true)
	MissionKit.SyncBoss(run)
	MissionKit.Cue(run, "ShieldUp", boss.Root.Position)
	if immune.Collapse then
		collapse(run, immune.Collapse)
	end
	local state: ImmuneState = { Def = immune, Tag = tag, WavesLeft = 0, WaveSize = 0 }
	if immune.Break == "Pylons" then
		local markers = MapMarkers.Numbered(run.Markers, "Pylon")
		for pylonIndex = 1, math.min(immune.Count or #markers, #markers) do
			local marker = markers[pylonIndex]
			MissionKit.Cue(run, "Portal", marker.Position, 0.6)
			Spawner.SpawnAt(run, immune.Enemy or "RUST_PYLON", marker.CFrame, tag, false)
		end
	else
		state.WaveSize = Spawner.SpawnWave(run, token, spawnsFor(immune), spawns, tag)
		state.WavesLeft = math.max(0, (immune.Waves or 1) - 1)
	end
	return state
end

-- Advances an immune phase. Returns true once its Break is done.
local function updateImmune(run: Run, token: number, state: ImmuneState, spawns: string): boolean
	local alive = MissionKit.AliveWithTag(run, state.Tag) + MissionKit.PendingWithTag(run, state.Tag)
	if state.WavesLeft > 0 and alive <= math.floor(state.WaveSize * 0.2) then
		state.WavesLeft -= 1
		state.WaveSize = Spawner.SpawnWave(run, token, spawnsFor(state.Def), spawns, state.Tag)
		alive += state.WaveSize
	end
	local left = if state.WavesLeft > 0 then "" else `  ({alive} left)`
	MissionKit.SetPhase(run, state.Def.Text .. left, nil)
	return state.WavesLeft == 0 and alive == 0
end

-- The raid's plate mechanic ----------------------------------------------------------------

local function echoPlates(run: Run, token: number, boss: Enemy, def: BossDef, spawns: string)
	local raid = CombatConfig.Raid
	local plates = MapMarkers.Numbered(run.Markers, "Plate")
	if #plates == 0 then
		for plateIndex = 1, 3 do
			local plate = run.Map:FindFirstChild(`Plate_{plateIndex}`, true)
			if plate and plate:IsA("BasePart") then
				table.insert(plates, plate)
			end
		end
	end
	local baseColors: { [BasePart]: Color3 } = {}
	for _, plate in plates do
		baseColors[plate] = plate.Color
	end

	local enrageAt = now() + (if def.Enrage then def.Enrage.After else raid.EnrageSeconds)
	MissionKit.SetAttr(run, "EnrageAt", enrageAt)
	local phase = "Immune"
	local charge = 0
	local phaseEndsAt = 0
	local adds = def.Adds
	local nextAdds = now() + (if adds then adds.Interval * 0.6 else math.huge)
	local lastTick = now()
	EnemyService.SetImmune(boss, true)
	MissionKit.SyncBoss(run)

	while MissionKit.IsActive(run, token) and not boss.Dead do
		local current = now()
		local dt = current - lastTick
		lastTick = current
		local solo = #run.Players <= 1
		local required = if solo then 1 else math.min(#plates, #run.Players)
		local chargeSeconds = if solo then raid.SoloPlateHoldSeconds else raid.PlateChargeSeconds

		local held = 0
		for _, plate in plates do
			local occupied = false
			for _, player in run.Players do
				local root = MissionKit.RootOf(player)
				if root then
					local offset = root.Position - plate.Position
					local reach = math.max(plate.Size.X, plate.Size.Z) / 2 + 1
					if Vector2.new(offset.X, offset.Z).Magnitude <= reach and math.abs(offset.Y) < 8 then
						occupied = true
						break
					end
				end
			end
			if occupied then
				held += 1
			end
			plate.Color = if occupied then Color3.fromRGB(255, 255, 255) else baseColors[plate]
		end

		if phase == "Immune" then
			if held >= required then
				charge += dt
			else
				charge = math.max(0, charge - dt * 2)
			end
			MissionKit.SetAttr(run, "Charge", math.min(1, charge / chargeSeconds))
			local what = if solo then "Hold an echo plate" else `Hold {required} echo plates at once`
			MissionKit.SetPhase(run, `{what} ({held}/{required})`, nil)
			if charge >= chargeSeconds then
				phase = "Damage"
				charge = 0
				phaseEndsAt = now() + raid.DamagePhaseSeconds
				run.DamageBuff = raid.DamageBuff
				EnemyService.SetImmune(boss, false)
				MissionKit.Cue(run, "ShieldBreak", boss.Root.Position)
				MissionKit.SetAttr(run, "Charge", 0)
				MissionKit.SetPhase(run, "ECHO RESONANCE: damage the Engine!", phaseEndsAt)
				MissionKit.SyncBoss(run)
			end
		elseif now() >= phaseEndsAt then
			phase = "Immune"
			run.DamageBuff = 1
			EnemyService.SetImmune(boss, true)
			MissionKit.SyncBoss(run)
		end

		if adds and current >= nextAdds then
			nextAdds = current + adds.Interval
			if MissionKit.AliveWithTag(run, "raidAdds") < adds.MaxAlive then
				Spawner.SpawnWave(run, token, { Enemies = adds.Enemies }, spawns, "raidAdds")
			end
		end

		if now() >= enrageAt then
			MissionKit.SetPhase(run, if def.Enrage then def.Enrage.Text else "ENRAGE", nil)
			EnemyService.SetEnraged(boss, true)
			task.wait(1.5)
			if MissionKit.IsActive(run, token) and not boss.Dead then
				run.Wipe("The Echo Engine overloaded")
			end
			break
		end
		task.wait(0.2)
	end

	run.DamageBuff = 1
	if run.Status == "Closed" then
		return
	end
	for _, plate in plates do
		plate.Color = baseColors[plate]
	end
	MissionKit.SetAttr(run, "Charge", 0)
	MissionKit.SetAttr(run, "EnrageAt", 0)
end

-- The standard fight --------------------------------------------------------------------

local function phaseAllowed(attack: AttackDef, phase: number): boolean
	return attack.Phases == nil or table.find(attack.Phases, phase) ~= nil
end

local function fight(run: Run, token: number, boss: Enemy, def: BossDef, spawns: string)
	local start = now()
	local phase = 1
	local nextImmune = 1
	local immune: ImmuneState? = nil
	local busyUntil = 0
	local attackAt: { number } = {}
	for index, attack in def.Attacks do
		attackAt[index] = start + (attack.FirstAt or attack.Cooldown)
	end
	local adds = def.Adds
	local nextAdds = start + (if adds then adds.Interval else math.huge)
	local nextAmmo = start + def.HeavyAmmoEvery * 0.5
	local enrageAt = if def.Enrage then start + def.Enrage.After else math.huge
	if def.Enrage then
		MissionKit.SetAttr(run, "EnrageAt", enrageAt)
	end
	local ammoSpots = MapMarkers.Numbered(run.Markers, "Ammo")
	local addsTag = `bossAdds_{token}`

	local function setFloor()
		local upcoming = def.Immune[nextImmune]
		EnemyService.SetHealthFloor(boss, if upcoming then boss.MaxHealth * upcoming.At else 0)
	end
	setFloor()

	while MissionKit.IsActive(run, token) and not boss.Dead do
		local t = now()

		if immune == nil then
			local upcoming = def.Immune[nextImmune]
			if upcoming and boss.Health <= boss.MaxHealth * upcoming.At + 0.5 then
				immune = startImmune(run, token, boss, upcoming, nextImmune, spawns)
				nextImmune += 1
				setFloor()
			end
		elseif updateImmune(run, token, immune, spawns) then
			immune = nil
			phase += 1
			EnemyService.SetImmune(boss, false)
			MissionKit.Cue(run, "ShieldBreak", boss.Root.Position)
			MissionKit.SetPhase(run, nil, nil)
			MissionKit.SyncBoss(run)
		end

		if t >= busyUntil then
			for index, attack in def.Attacks do
				if t >= attackAt[index] and phaseAllowed(attack, phase) then
					attackAt[index] = t + attack.Cooldown
					busyUntil = t + (attack.Windup or 1) + 2
					task.spawn(perform, run, token, boss, attack)
					break
				end
			end
		end

		if adds and t >= nextAdds then
			nextAdds = t + adds.Interval
			if MissionKit.AliveWithTag(run, addsTag) < adds.MaxAlive then
				Spawner.SpawnWave(run, token, { Enemies = adds.Enemies }, spawns, addsTag)
			end
		end

		if t >= nextAmmo then
			nextAmmo = t + def.HeavyAmmoEvery
			local spot = if #ammoSpots > 0 then ammoSpots[rng:NextInteger(1, #ammoSpots)] else nil
			local position = if spot then spot.Position else MissionKit.MarkerCFrame(run, run.Checkpoint).Position
			LootService.DropAmmo(position, run.Id, "Heavy", CombatConfig.Boss.ArenaAmmoLifetime)
			MissionKit.Cue(run, "AmmoDrop", position)
		end

		if t >= enrageAt then
			MissionKit.SetPhase(run, if def.Enrage then def.Enrage.Text else "ENRAGE", nil)
			EnemyService.SetEnraged(boss, true)
			task.wait(1.5)
			if MissionKit.IsActive(run, token) and not boss.Dead then
				run.Wipe(`{boss.Def.Name} enraged`)
			end
			break
		end
		task.wait(0.2)
	end
	EnemyService.SetHealthFloor(boss, 0)
	MissionKit.SetAttr(run, "EnrageAt", 0)
end

-- Death --------------------------------------------------------------------------------

local function death(run: Run, boss: Enemy)
	local position = boss.Root.Position
	MissionKit.Cue(run, "BossDeath", position, boss.Def.Name)
	local ground = MissionKit.GroundAt(position)
	run.ChestAt = CFrame.new(ground) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	-- The rest of the arena falls with its master.
	task.delay(1.2, function()
		if run.Status ~= "Closed" then
			EnemyService.DespawnInstance(run.Id)
		end
	end)
end

-- Runs the boss step. Returns true when the boss is dead.
function BossFight.Run(run: Run, token: number, step: ActivityConfig.StepDef, spawns: string): boolean
	local def = BossConfig.ById[step.Boss or ""]
	if def == nil then
		warn(`[BossFight] Unknown boss {step.Boss}`)
		return true
	end
	local marker = MissionKit.Marker(run, "BossSpawn")
	local at = if marker then marker.CFrame else CFrame.new(run.Origin)
	local boss = EnemyService.Spawn(def.Enemy, at, MissionKit.SpawnOptions(run, "boss", false, true))
	if boss == nil then
		return true
	end
	run.Boss = boss
	local thresholds: { string } = {}
	for _, immune in def.Immune do
		table.insert(thresholds, tostring(immune.At))
	end
	MissionKit.SetAttr(run, "BossThresholds", table.concat(thresholds, ","))
	MissionKit.SetObjective(run, step.Text, nil, nil, nil)
	MissionKit.SyncBoss(run)
	MissionKit.Cue(run, "BossIntro", boss.Root.Position, boss.Def.Name, boss.Def.Title or "")

	if def.Script == "EchoPlates" then
		echoPlates(run, token, boss, def, spawns)
	else
		fight(run, token, boss, def, spawns)
	end
	MissionKit.SetPhase(run, nil, nil)

	local won = MissionKit.IsActive(run, token) and boss.Dead
	if won then
		death(run, boss)
	end
	run.Boss = nil
	MissionKit.SyncBoss(run)
	return won
end

return BossFight
