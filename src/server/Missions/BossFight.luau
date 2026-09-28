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
	  * Script "EchoPlates" / "EchoDeposit" swap the loop for the raid's
	    plate and echo-carrying mechanics
	A step's Arena names the marker folder holding the fight's markers
	(BossSpawn, Ammo_n, Pylon_n, Teleport_n, Safe_n, Room_n, EchoWell,
	Chest), for maps with more than one boss.
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

-- Everything about the fight in progress.
type Fight = {
	Run: Run,
	Token: number,
	Boss: Enemy,
	Def: BossDef,
	Spawns: string,
	Arena: string?,
}

-- Special attacks, adds and arena ammo on their timers.
type Scheduler = {
	AttackAt: { number },
	BusyUntil: number,
	NextAdds: number,
	NextAmmo: number,
	AddsTag: string,
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

local function active(fight: Fight): boolean
	return MissionKit.IsActive(fight.Run, fight.Token) and not fight.Boss.Dead
end

local function barrage(fight: Fight, attack: AttackDef)
	local run, boss = fight.Run, fight.Boss
	local windup = attack.Windup or 1.2
	local count = attack.Count or 12
	EnemyService.SetBusy(boss, windup + 1.8)
	MissionKit.Cue(run, "Charge", boss.Head.Position, windup)
	task.wait(windup)
	for index = 1, count do
		if not active(fight) then
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

local function slam(fight: Fight, attack: AttackDef)
	local run, boss = fight.Run, fight.Boss
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
		if not active(fight) then
			return
		end
		EnemyService.Leap(boss, center, 0.45)
	else
		task.wait(windup)
	end
	if not active(fight) then
		return
	end
	MissionKit.Cue(run, "Shockwave", center, radius)
	blast(run, boss, center, radius, attack.Damage or 50)
end

local function teleport(fight: Fight)
	local run, boss = fight.Run, fight.Boss
	local spots = MissionKit.ArenaNumbered(run, fight.Arena, "Teleport")
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
	if not active(fight) then
		return
	end
	EnemyService.Relocate(boss, spot.CFrame + Vector3.new(0, 3, 0))
	MissionKit.Cue(run, "Blink", spot.Position)
end

local function nova(fight: Fight, attack: AttackDef)
	local run, boss = fight.Run, fight.Boss
	local safes = MissionKit.ArenaNumbered(run, fight.Arena, "Safe")
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
	if not active(fight) then
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

local function perform(fight: Fight, attack: AttackDef)
	if attack.Kind == "Barrage" then
		barrage(fight, attack)
	elseif attack.Kind == "Slam" then
		slam(fight, attack)
	elseif attack.Kind == "Teleport" then
		teleport(fight)
	elseif attack.Kind == "Nova" then
		nova(fight, attack)
	end
end

-- Attacks, adds and ammo run on a shared schedule in every kind of fight.
local function newScheduler(fight: Fight): Scheduler
	local start = now()
	local attackAt: { number } = {}
	for index, attack in fight.Def.Attacks do
		attackAt[index] = start + (attack.FirstAt or attack.Cooldown)
	end
	local adds = fight.Def.Adds
	return {
		AttackAt = attackAt,
		BusyUntil = 0,
		NextAdds = start + (if adds then adds.Interval else math.huge),
		NextAmmo = start + fight.Def.HeavyAmmoEvery * 0.5,
		AddsTag = `bossAdds_{fight.Token}`,
	}
end

local function phaseAllowed(attack: AttackDef, phase: number): boolean
	return attack.Phases == nil or table.find(attack.Phases, phase) ~= nil
end

local function tickScheduler(fight: Fight, schedule: Scheduler, phase: number)
	local run, def = fight.Run, fight.Def
	local t = now()
	if t >= schedule.BusyUntil then
		for index, attack in def.Attacks do
			if t >= schedule.AttackAt[index] and phaseAllowed(attack, phase) then
				schedule.AttackAt[index] = t + attack.Cooldown
				schedule.BusyUntil = t + (attack.Windup or 1) + 2
				task.spawn(perform, fight, attack)
				break
			end
		end
	end
	local adds = def.Adds
	if adds and t >= schedule.NextAdds then
		schedule.NextAdds = t + adds.Interval
		if MissionKit.AliveWithTag(run, schedule.AddsTag) < adds.MaxAlive then
			Spawner.SpawnWave(run, fight.Token, { Enemies = adds.Enemies }, fight.Spawns, schedule.AddsTag)
		end
	end
	if t >= schedule.NextAmmo then
		schedule.NextAmmo = t + def.HeavyAmmoEvery
		local spots = MissionKit.ArenaNumbered(run, fight.Arena, "Ammo")
		local spot = if #spots > 0 then spots[rng:NextInteger(1, #spots)] else nil
		local position = if spot then spot.Position else MissionKit.MarkerCFrame(run, run.Checkpoint).Position
		LootService.DropAmmo(position, run.Id, "Heavy", CombatConfig.Boss.ArenaAmmoLifetime)
		MissionKit.Cue(run, "AmmoDrop", position)
	end
end

-- Returns true (after wiping the fireteam) once the enrage timer runs out.
local function enraged(fight: Fight, enrageAt: number): boolean
	if now() < enrageAt then
		return false
	end
	local def = fight.Def
	MissionKit.SetPhase(fight.Run, if def.Enrage then def.Enrage.Text else "ENRAGE", nil)
	EnemyService.SetEnraged(fight.Boss, true)
	task.wait(1.5)
	if active(fight) then
		fight.Run.Wipe(`{fight.Boss.Def.Name} enraged`)
	end
	return true
end

local function startEnrage(fight: Fight, fallback: number?): number
	local def = fight.Def
	local after = if def.Enrage then def.Enrage.After else fallback
	if after == nil then
		return math.huge
	end
	local at = now() + after
	MissionKit.SetAttr(fight.Run, "EnrageAt", at)
	return at
end

-- Immune phases ------------------------------------------------------------------------

local function startImmune(fight: Fight, immune: ImmuneDef, index: number): ImmuneState
	local run, boss = fight.Run, fight.Boss
	local tag = `bossImmune{index}_{fight.Token}`
	EnemyService.SetImmune(boss, true)
	MissionKit.SyncBoss(run)
	MissionKit.Cue(run, "ShieldUp", boss.Root.Position)
	if immune.Collapse then
		collapse(run, immune.Collapse)
	end
	local state: ImmuneState = { Def = immune, Tag = tag, WavesLeft = 0, WaveSize = 0 }
	if immune.Break == "Pylons" then
		local markers = MissionKit.ArenaNumbered(run, fight.Arena, "Pylon")
		for pylonIndex = 1, math.min(immune.Count or #markers, #markers) do
			local marker = markers[pylonIndex]
			MissionKit.Cue(run, "Portal", marker.Position, 0.6)
			Spawner.SpawnAt(run, immune.Enemy or "RUST_PYLON", marker.CFrame, tag, false)
		end
	else
		state.WaveSize = Spawner.SpawnWave(run, fight.Token, spawnsFor(immune), fight.Spawns, tag)
		state.WavesLeft = math.max(0, (immune.Waves or 1) - 1)
	end
	return state
end

-- Advances an immune phase. Returns true once its Break is done.
local function updateImmune(fight: Fight, state: ImmuneState): boolean
	local run = fight.Run
	local alive = MissionKit.AliveWithTag(run, state.Tag) + MissionKit.PendingWithTag(run, state.Tag)
	if state.WavesLeft > 0 and alive <= math.floor(state.WaveSize * 0.2) then
		state.WavesLeft -= 1
		state.WaveSize = Spawner.SpawnWave(run, fight.Token, spawnsFor(state.Def), fight.Spawns, state.Tag)
		alive += state.WaveSize
	end
	local left = if state.WavesLeft > 0 then "" else `  ({alive} left)`
	MissionKit.SetPhase(run, state.Def.Text .. left, nil)
	return state.WavesLeft == 0 and alive == 0
end

-- The standard fight --------------------------------------------------------------------

local function standard(fight: Fight)
	local run, boss, def = fight.Run, fight.Boss, fight.Def
	local phase = 1
	local nextImmune = 1
	local immune: ImmuneState? = nil
	local schedule = newScheduler(fight)
	local enrageAt = startEnrage(fight, nil)

	local function setFloor()
		local upcoming = def.Immune[nextImmune]
		EnemyService.SetHealthFloor(boss, if upcoming then boss.MaxHealth * upcoming.At else 0)
	end
	setFloor()

	while active(fight) do
		if immune == nil then
			local upcoming = def.Immune[nextImmune]
			if upcoming and boss.Health <= boss.MaxHealth * upcoming.At + 0.5 then
				immune = startImmune(fight, upcoming, nextImmune)
				nextImmune += 1
				setFloor()
			end
		elseif updateImmune(fight, immune) then
			immune = nil
			phase += 1
			EnemyService.SetImmune(boss, false)
			MissionKit.Cue(run, "ShieldBreak", boss.Root.Position)
			MissionKit.SetPhase(run, nil, nil)
			MissionKit.SyncBoss(run)
		end
		MissionKit.SetAttr(run, "BossPhase", phase)
		tickScheduler(fight, schedule, phase)
		if enraged(fight, enrageAt) then
			break
		end
		task.wait(0.2)
	end
	EnemyService.SetHealthFloor(boss, 0)
end

-- Raid encounter 1: the echo plates --------------------------------------------------------

local LIT = Color3.fromRGB(255, 200, 80)
local HELD = Color3.fromRGB(255, 255, 255)

local function findPlates(fight: Fight): { BasePart }
	local plates = MissionKit.ArenaNumbered(fight.Run, fight.Arena, "Plate")
	if #plates == 0 then
		for index = 1, 3 do
			local plate = fight.Run.Map:FindFirstChild(`Plate_{index}`, true)
			if plate and plate:IsA("BasePart") then
				table.insert(plates, plate)
			end
		end
	end
	return plates
end

local function echoPlates(fight: Fight)
	local run, boss = fight.Run, fight.Boss
	local raid = CombatConfig.Raid
	local plates = findPlates(fight)
	local baseColors: { [BasePart]: Color3 } = {}
	for _, plate in plates do
		baseColors[plate] = plate.Color
	end

	-- Which plates count this cycle: as many as the fireteam can hold (up to
	-- all of them), never the same set twice in a row when there's a choice.
	local lit: { [BasePart]: boolean } = {}
	local function relight()
		local required = if #run.Players <= 1 then 1 else math.min(#plates, #run.Players)
		-- Plates that weren't lit last time come first, each group shuffled.
		local fresh: { BasePart } = {}
		local stale: { BasePart } = {}
		for _, plate in plates do
			table.insert(if lit[plate] then stale else fresh, plate)
		end
		for _, group in { fresh, stale } do
			for index = #group, 2, -1 do
				local pick = rng:NextInteger(1, index)
				group[index], group[pick] = group[pick], group[index]
			end
		end
		local order = table.clone(fresh)
		table.move(stale, 1, #stale, #order + 1, order)
		lit = {}
		for index = 1, math.min(required, #order) do
			lit[order[index]] = true
		end
		for _, plate in plates do
			plate:SetAttribute("Lit", lit[plate] == true)
		end
	end
	relight()

	local enrageAt = startEnrage(fight, raid.EnrageSeconds)
	local schedule = newScheduler(fight)
	local phase = "Immune"
	local charge = 0
	local phaseEndsAt = 0
	local lastTick = now()
	EnemyService.SetImmune(boss, true)
	MissionKit.SyncBoss(run)

	while active(fight) do
		local current = now()
		local dt = current - lastTick
		lastTick = current
		local solo = #run.Players <= 1
		local chargeSeconds = if solo then raid.SoloPlateHoldSeconds else raid.PlateChargeSeconds

		local required, held = 0, 0
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
			if lit[plate] then
				required += 1
				if occupied then
					held += 1
				end
			end
			plate.Color = if lit[plate] and occupied then HELD elseif lit[plate] then LIT else baseColors[plate]
		end

		if phase == "Immune" then
			if held >= required and required > 0 then
				charge += dt
			else
				charge = math.max(0, charge - dt * 2)
			end
			MissionKit.SetAttr(run, "Charge", math.min(1, charge / chargeSeconds))
			local what = if required == 1 then "Hold the lit echo plate" else `Hold all {required} lit echo plates`
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
			MissionKit.Cue(run, "ShieldUp", boss.Root.Position)
			relight()
			MissionKit.SyncBoss(run)
		end

		tickScheduler(fight, schedule, 1)
		if enraged(fight, enrageAt) then
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
		plate:SetAttribute("Lit", false)
	end
	MissionKit.SetAttr(run, "Charge", 0)
end

-- Raid encounter 2: carrying echoes to the well ----------------------------------------------

type Carry = { Room: number, Until: number }

local function echoDeposit(fight: Fight)
	local run, boss, def = fight.Run, fight.Boss, fight.Def
	local tuning = def.Deposit or { Bearer = "RUST_ECHO_BEARER", Needed = 3, ChargeSeconds = 30, DamageSeconds = 25 }
	local rooms = MissionKit.ArenaNumbered(run, fight.Arena, "Room")
	local well = MissionKit.ArenaMarker(run, fight.Arena, "EchoWell")
	local needed = math.min(tuning.Needed, #rooms)
	if well == nil or needed == 0 then
		warn(`[BossFight] {run.Activity.Id}: EchoDeposit needs Room_n and EchoWell markers`)
		return
	end
	local wellZone = well :: BasePart

	local bearers: { [number]: Enemy? } = {}
	local delivered: { [number]: boolean } = {}
	local respawnAt: { [number]: number } = {}
	local carriers: { [Player]: Carry } = {}
	local deposits = 0
	local phase = "Sealed"
	local phaseEndsAt = 0
	local enrageAt = startEnrage(fight, nil)
	local schedule = newScheduler(fight)

	local function carried(room: number): boolean
		for _, carry in carriers do
			if carry.Room == room then
				return true
			end
		end
		return false
	end

	local function spawnBearer(room: number): Enemy?
		local marker = rooms[room]
		MissionKit.Cue(run, "Portal", marker.Position, 0.6)
		local bearer = Spawner.SpawnAt(run, tuning.Bearer, marker.CFrame, `bearer_{fight.Token}`, true)
		if bearer and bearer.Model then
			local mark = Instance.new("Highlight")
			mark.Name = "EchoMark"
			mark.FillColor = LIT
			mark.OutlineColor = Color3.new(1, 1, 1)
			mark.FillTransparency = 0.55
			mark.Parent = bearer.Model
		end
		return bearer
	end

	local function drop(player: Player, faded: boolean)
		local carry = carriers[player]
		carriers[player] = nil
		if player.Parent then
			player:SetAttribute("EchoChargeUntil", nil)
		end
		if carry and faded then
			respawnAt[carry.Room] = now() + 6
			MissionKit.Notify(player, "The echo faded. Another Bearer will come.", "Error")
		end
	end

	-- The nearest living player takes the echo when nobody got the kill.
	local function nearestTo(position: Vector3): Player?
		local best, bestDistance = nil, math.huge
		for _, player in MissionKit.AlivePlayers(run) do
			local root = MissionKit.RootOf(player)
			if root and (root.Position - position).Magnitude < bestDistance then
				best, bestDistance = player, (root.Position - position).Magnitude
			end
		end
		return best
	end

	EnemyService.SetImmune(boss, true)
	MissionKit.SyncBoss(run)

	while active(fight) do
		local t = now()
		if phase == "Sealed" then
			for room = 1, needed do
				local bearer = bearers[room]
				if bearer and bearer.Dead then
					bearers[room] = nil
					local killer = bearer.Killer
					local carrier = if killer
							and table.find(run.Players, killer)
							and MissionKit.RootOf(killer)
						then killer
						else nearestTo(bearer.Root.Position)
					if carrier then
						if carriers[carrier] then
							drop(carrier, true) -- one echo at a time
						end
						carriers[carrier] = { Room = room, Until = t + tuning.ChargeSeconds }
						carrier:SetAttribute("EchoChargeUntil", t + tuning.ChargeSeconds)
						MissionKit.Notify(carrier, "You carry an echo: bring it to the well!", "Success")
					else
						respawnAt[room] = t + 4
					end
				elseif bearer == nil and not delivered[room] and not carried(room) and t >= (respawnAt[room] or 0) then
					bearers[room] = spawnBearer(room)
				end
			end
			local inWell = MissionKit.PlayersInZone(run, wellZone)
			for player, carry in carriers do
				if t > carry.Until or not table.find(run.Players, player) or MissionKit.RootOf(player) == nil then
					drop(player, true)
				elseif table.find(inWell, player) then
					delivered[carry.Room] = true
					deposits += 1
					drop(player, false)
					MissionKit.Cue(run, "Deposit", wellZone.Position)
				end
			end
			MissionKit.SetPhase(
				run,
				`Kill the marked Bearers and bring their echoes to the well ({deposits}/{needed})`,
				nil
			)
			MissionKit.SetAttr(run, "Charge", deposits / needed)
			if deposits >= needed then
				phase = "Open"
				phaseEndsAt = t + tuning.DamageSeconds
				run.DamageBuff = CombatConfig.Raid.DamageBuff
				EnemyService.SetImmune(boss, false)
				MissionKit.Cue(run, "ShieldBreak", boss.Root.Position)
				MissionKit.SetAttr(run, "Charge", 0)
				MissionKit.SetPhase(run, "THE WARDEN IS EXPOSED: burn her!", phaseEndsAt)
				MissionKit.SyncBoss(run)
			end
		elseif t >= phaseEndsAt then
			phase = "Sealed"
			deposits = 0
			delivered = {}
			respawnAt = {}
			run.DamageBuff = 1
			EnemyService.SetImmune(boss, true)
			MissionKit.Cue(run, "ShieldUp", boss.Root.Position)
			MissionKit.SyncBoss(run)
		end
		tickScheduler(fight, schedule, 1)
		if enraged(fight, enrageAt) then
			break
		end
		task.wait(0.2)
	end

	run.DamageBuff = 1
	for player in carriers do
		drop(player, false)
	end
	if run.Status ~= "Closed" then
		MissionKit.SetAttr(run, "Charge", 0)
	end
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
	local marker = MissionKit.ArenaMarker(run, step.Arena, "BossSpawn")
	local at = if marker then marker.CFrame else CFrame.new(run.Origin)
	local boss = EnemyService.Spawn(def.Enemy, at, MissionKit.SpawnOptions(run, "boss", false, true))
	if boss == nil then
		return true
	end
	run.Boss = boss
	run.Arena = step.Arena
	run.BossSpawn = at
	local thresholds: { string } = {}
	for _, immune in def.Immune do
		table.insert(thresholds, tostring(immune.At))
	end
	MissionKit.SetAttr(run, "BossThresholds", table.concat(thresholds, ","))
	MissionKit.SetAttr(run, "BossPhase", 1)
	MissionKit.SetObjective(run, step.Text, nil, nil, nil)
	MissionKit.SyncBoss(run)
	MissionKit.Cue(run, "BossIntro", boss.Root.Position, boss.Def.Name, boss.Def.Title or "")

	local fight: Fight = { Run = run, Token = token, Boss = boss, Def = def, Spawns = spawns, Arena = step.Arena }
	if def.Script == "EchoPlates" then
		echoPlates(fight)
	elseif def.Script == "EchoDeposit" then
		echoDeposit(fight)
	else
		standard(fight)
	end
	MissionKit.SetPhase(run, nil, nil)
	MissionKit.SetAttr(run, "EnrageAt", 0)

	local won = MissionKit.IsActive(run, token) and boss.Dead
	if won then
		death(run, boss)
	end
	run.Boss = nil
	run.BossSpawn = nil
	MissionKit.SyncBoss(run)
	return won
end

return BossFight
