--!strict
--[[
	WeaponService
	Server side of shooting. Clients send intents (fire at this aim point,
	reload, switch slot); the server owns every number:

	  * magazines and reserves per slot (primary ammo has infinite reserves;
	    special ammo is refilled by green boxes, heavy ammo by purple ones)
	  * fire rate (with a small jitter tolerance), swap and reload timers
	  * the shot itself, by fire mode: one ray (auto/semi), a burst of rays
	    (pulse rifles), a cone of pellets (shotguns) or bolts (fusion rifles,
	    after their charge time), a projectile (rockets; grenades arc), or a
	    sword swing in front of the player. Rays start at the character's
	    head and go toward the aim point, capped at the weapon's range.
	  * exotic perks (Sixth Toll, Choir of Cinders, Perpetual Motion,
	    Collapse Point, Phantom Mark, Ember Oath)
	  * damage through CombatService

	The equipped weapon's model is built from parts and welded to the right
	hand. The owning client gets WeaponState updates; everyone else sees
	ShotEffect tracers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CombatConfig = require(Shared.Config.CombatConfig)
local ElementConfig = require(Shared.Config.ElementConfig)
local Guard = require(Shared.Net.Guard)
local WeaponStats = require(Shared.Weapons.WeaponStats)

local WeaponModels = require(script.Parent.Parent.Weapons.WeaponModels)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local NetService = require(script.Parent.NetService)
local ProjectileService = require(script.Parent.ProjectileService)
local WorldService = require(script.Parent.WorldService)

local SLOTS = { "Kinetic", "Energy", "Heavy" }

type SlotState = {
	Uid: string,
	Stats: WeaponStats.WeaponStats,
	Mag: number,
	-- nil = infinite (primary ammo).
	Reserve: number?,
	LastShot: number,
	ReloadingUntil: number,
	ReloadToken: number,
	-- Exotic bookkeeping: RPM ramp (0..1), hit counter, consecutive-hit streak.
	Ramp: number,
	Hits: number,
	Streak: number,
}

type Loadout = {
	Active: string,
	Slots: { [string]: SlotState },
	SwapReadyAt: number,
	Model: Model?,
}

local WeaponService = {}

local loadouts: { [Player]: Loadout } = {}

local function getLoadout(player: Player): Loadout
	local loadout = loadouts[player]
	if loadout == nil then
		local created: Loadout = { Active = "Kinetic", Slots = {}, SwapReadyAt = 0, Model = nil }
		loadouts[player] = created
		return created
	end
	return loadout
end

local function sendState(player: Player)
	local loadout = loadouts[player]
	if loadout == nil or player.Parent ~= Players then
		return
	end
	local slots: { [string]: any } = {}
	for slot, state in loadout.Slots do
		slots[slot] = {
			Uid = state.Uid,
			Mag = state.Mag,
			Reserve = state.Reserve,
			Reloading = state.ReloadingUntil > os.clock(),
		}
	end
	NetService.FireClient(player, "WeaponState", { Active = loadout.Active, Slots = slots })
end

local function startingReserve(stats: WeaponStats.WeaponStats): number?
	if stats.Reserves == nil then
		return nil
	end
	if stats.AmmoType == "Heavy" then
		return math.min(stats.Reserves, CombatConfig.Weapons.HeavyStartingReserve)
	elseif stats.AmmoType == "Special" then
		return math.min(stats.Reserves, stats.Magazine * CombatConfig.Weapons.SpecialStartingMagazines)
	end
	return stats.Reserves
end

-- Rebuilds slot states from the equipped items, keeping ammo for unchanged weapons.
local function rebuildSlots(player: Player)
	local loadout = getLoadout(player)
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	local slots: { [string]: SlotState } = {}
	for _, slot in SLOTS do
		local uid = data.Equipped[slot]
		local item = if uid then data.Items[uid] else nil
		local stats = if item then WeaponStats.Compute(item) else nil
		if item and stats then
			local previous = loadout.Slots[slot]
			if previous and previous.Uid == item.Uid then
				previous.Stats = stats
				previous.Mag = math.min(previous.Mag, stats.Magazine)
				slots[slot] = previous
			else
				slots[slot] = {
					Uid = item.Uid,
					Stats = stats,
					Mag = stats.Magazine,
					Reserve = startingReserve(stats),
					LastShot = 0,
					ReloadingUntil = 0,
					ReloadToken = 0,
					Ramp = 0,
					Hits = 0,
					Streak = 0,
				}
			end
		end
	end
	loadout.Slots = slots
	if slots[loadout.Active] == nil then
		for _, slot in SLOTS do
			if slots[slot] then
				loadout.Active = slot
				break
			end
		end
	end
end

-- Weapons are holstered in the hub outside the firing range (HubService).
local function isDrawn(player: Player): boolean
	return player:GetAttribute("WeaponsDrawn") == true
end

local function equipModel(player: Player)
	local loadout = getLoadout(player)
	if loadout.Model then
		loadout.Model:Destroy()
		loadout.Model = nil
	end
	local character = CharacterService.GetCharacter(player)
	local state = loadout.Slots[loadout.Active]
	if character == nil or state == nil or not isDrawn(player) then
		return
	end
	local model = WeaponModels.Build(state.Stats.DefId)
	if model and WeaponModels.Attach(character, model) then
		loadout.Model = model
	elseif model then
		model:Destroy()
	end
end

-- Call after the equipped weapons change (equip, /give, /setpower...).
function WeaponService.RefreshLoadout(player: Player)
	rebuildSlots(player)
	equipModel(player)
	sendState(player)
end

-- Full magazines, and heavy reserves back to the starting amount.
function WeaponService.ResetAmmo(player: Player)
	local loadout = getLoadout(player)
	for _, state in loadout.Slots do
		state.Mag = state.Stats.Magazine
		state.Reserve = startingReserve(state.Stats)
		state.ReloadingUntil = 0
		state.ReloadToken += 1
	end
	sendState(player)
end

-- Adds a share of `ammoType` ("Special"/"Heavy") reserves to every weapon
-- that uses it (ammo box pickup). Returns rounds gained.
function WeaponService.AddAmmo(player: Player, ammoType: string, fraction: number): number
	local loadout = loadouts[player]
	if loadout == nil then
		return 0
	end
	local gained = 0
	for _, state in loadout.Slots do
		local maximum = state.Stats.Reserves
		if state.Stats.AmmoType == ammoType and state.Reserve ~= nil and maximum ~= nil then
			local before = state.Reserve :: number
			state.Reserve = math.min(maximum, before + math.max(1, math.ceil(maximum * fraction)))
			gained += (state.Reserve :: number) - before
		end
	end
	if gained > 0 then
		sendState(player)
	end
	return gained
end

function WeaponService.AddHeavyAmmo(player: Player, fraction: number): number
	return WeaponService.AddAmmo(player, "Heavy", fraction)
end

function WeaponService.GetActiveStats(player: Player): WeaponStats.WeaponStats?
	local loadout = loadouts[player]
	local state = if loadout then loadout.Slots[loadout.Active] else nil
	return if state then state.Stats else nil
end

-- Intents --------------------------------------------------------------------------

local function playerCharacters(): { Instance }
	local list = WorldService.PlayerCharacters()
	table.insert(list, WorldService.Folder("Pickups"))
	return list
end

local rng = Random.new()
-- Phantom Mark: enemies marked by precision hits, and when the mark expires.
local marks: { [any]: number } = {}

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Exotic effects that trigger on each enemy hit.
local function exoticOnHit(
	player: Player,
	state: SlotState,
	stats: WeaponStats.WeaponStats,
	enemy: any,
	result: any,
	precision: boolean
)
	local exotic = stats.Exotic
	if exotic == nil then
		return
	end
	if exotic.Kind == "RpmRampAndChain" then
		state.Hits += 1
		if state.Hits % math.max(1, exotic.Every) == 0 then
			CombatService.Chain(player, enemy, exotic.Radius, stats.Damage * 1.5, stats.Element, 3)
		end
	elseif exotic.Kind == "Singularity" and result and result.Killed then
		CombatService.Singularity(
			player,
			enemy.Root.Position,
			exotic.Radius,
			exotic.Value,
			stats.Element,
			exotic.Duration
		)
	elseif exotic.Kind == "MarkAndSeek" then
		if precision and not enemy.Dead then
			marks[enemy] = os.clock() + exotic.Duration
		end
		if result and result.Killed and (marks[enemy] or 0) > os.clock() then
			marks[enemy] = nil
			-- A seeker drone darts to the nearest other enemy and bursts.
			local from = enemy.Root.Position + Vector3.new(0, 2, 0)
			for _, other in CombatService.Nearby(player, from, exotic.Radius) do
				if other ~= enemy then
					CombatService.Effect("Arc", from, other.Root.Position, Color3.fromRGB(230, 240, 255))
					CombatService.ExplodeAt(player, other.Root.Position, 5, stats.Damage * 3, stats.Element, true)
					break
				end
			end
		end
	end
end

local function onFire(player: Player, slot: string, aimPoint: Vector3, _shotId: number?)
	local loadout = loadouts[player]
	if loadout == nil or loadout.Active ~= slot then
		return
	end
	local state = loadout.Slots[slot]
	local character = CharacterService.GetCharacter(player)
	local head = if character then character:FindFirstChild("Head") else nil
	if state == nil or character == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local stats = state.Stats
	local exotic = stats.Exotic
	local now = os.clock()
	if not isDrawn(player) then
		return
	end
	if now < loadout.SwapReadyAt - 0.1 or now < state.ReloadingUntil - 0.1 then
		return
	end
	local interval = stats.FireInterval
	if stats.FireMode == "Charge" then
		interval = math.max(interval, stats.ChargeTime)
	end
	if exotic and exotic.Kind == "RpmRampAndChain" then
		-- Perpetual Motion: sustained fire spins up to +Value fire rate.
		state.Ramp = if now - state.LastShot < stats.FireInterval * 2.5 then math.min(1, state.Ramp + 0.06) else 0
		interval /= 1 + exotic.Value * state.Ramp
	end
	if now - state.LastShot < interval * CombatConfig.Weapons.FireRateTolerance then
		NetService.Flag(player, 0.25, "firing faster than the weapon allows")
		return
	end
	if state.Mag <= 0 then
		return
	end
	local rounds = math.min(stats.BurstCount, state.Mag)
	state.Mag -= rounds
	state.LastShot = now

	local element = ElementConfig.Elements[stats.Element]
	local color = if element then element.Color else Color3.new(1, 1, 1)

	if stats.FireMode == "Melee" then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local toAim = aimPoint - root.Position
			local flat = Vector3.new(toAim.X, 0, toAim.Z)
			local facing = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
			local origin = CFrame.lookAt(root.Position, root.Position + facing)
			CombatService.Melee(player, origin, stats)
			state.Hits += 1
			if exotic and exotic.Kind == "FireWave" and state.Hits % 3 == 0 then
				-- Ember Oath: every third swing sends fire racing forward.
				for step = 1, 3 do
					local point = root.Position + facing * (exotic.Radius * step / 3)
					CombatService.ExplodeAt(player, point, 6, stats.Damage * 0.6, stats.Element, true)
				end
			end
		end
		return
	end

	local origin = head.Position
	local offset = aimPoint - origin
	if offset.Magnitude < 0.5 then
		return
	end
	local direction = offset.Unit
	local reach = math.min(offset.Magnitude + 5, stats.MaxRange)

	local projectile = stats.Projectile
	if projectile then
		local gravity = projectile.Gravity or 0
		local velocity = direction * projectile.Speed
		if gravity > 0 then
			-- Loft grenades so they land near the aim point.
			local flight = math.min(offset.Magnitude, stats.MaxRange) / projectile.Speed
			velocity += Vector3.new(0, math.min(gravity * flight * 0.5, projectile.Speed * 0.6), 0)
		end
		ProjectileService.Spawn({
			Origin = origin + direction * 2.5,
			Velocity = velocity,
			MaxDistance = stats.MaxRange,
			Style = if gravity > 0 then "Grenade" else "Rocket",
			Color = color,
			Exclude = playerCharacters(),
			BlastRadius = projectile.BlastRadius,
			Gravity = if gravity > 0 then gravity else nil,
			OnHit = function(_result: RaycastResult?, position: Vector3)
				CombatService.Explode(player, position, stats)
			end,
		})
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = playerCharacters()
	-- Shotguns and fusion rifles fire a cone; pulse rifles fire tight bursts.
	local rays = if stats.FireMode == "Burst" then rounds else stats.Pellets
	local cone = if stats.Pellets > 1 then stats.SpreadHip * 0.9 elseif stats.FireMode == "Burst" then 0.35 else 0
	local firstHit: Vector3? = nil
	local hitAnyEnemy = false
	local lastEnemyPosition: Vector3? = nil
	for index = 1, rays do
		local rayDirection = if cone > 0 and (stats.Pellets > 1 or index > 1)
			then spreadDirection(direction, cone)
			else direction
		local result = Workspace:Raycast(origin, rayDirection * reach, params)
		local hitPosition = if result then result.Position else origin + rayDirection * reach
		firstHit = firstHit or hitPosition
		if result then
			local enemy, damageResult = CombatService.HitscanHit(
				player,
				result.Instance,
				result.Position,
				(result.Position - origin).Magnitude,
				stats
			)
			if enemy then
				hitAnyEnemy = true
				lastEnemyPosition = result.Position
				exoticOnHit(
					player,
					state,
					stats,
					enemy,
					damageResult,
					EnemyService.IsPrecisionPart(enemy, result.Instance)
				)
			end
		end
	end

	if exotic and exotic.Kind == "Explosion" then
		-- Sixth Toll: every Nth consecutive hit detonates.
		state.Streak = if hitAnyEnemy then state.Streak + 1 else 0
		if hitAnyEnemy and lastEnemyPosition and state.Streak % math.max(1, exotic.Every) == 0 then
			CombatService.ExplodeAt(
				player,
				lastEnemyPosition,
				exotic.Radius,
				stats.Damage * exotic.Value,
				stats.Element,
				true
			)
		end
	end

	local hitPosition = firstHit or (origin + direction * reach)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			NetService.FireClient(other, "ShotEffect", player.UserId, hitPosition, color)
		end
	end
end

local function onReload(player: Player, slot: string)
	local loadout = loadouts[player]
	local state = if loadout then loadout.Slots[slot] else nil
	if loadout == nil or state == nil or loadout.Active ~= slot then
		return
	end
	local stats = state.Stats
	local now = os.clock()
	if state.Mag >= stats.Magazine or state.ReloadingUntil > now then
		return
	end
	if state.Reserve ~= nil and state.Reserve <= 0 then
		return
	end
	state.ReloadToken += 1
	local token = state.ReloadToken
	state.ReloadingUntil = now + stats.ReloadTime
	task.delay(stats.ReloadTime, function()
		if state.ReloadToken ~= token or loadouts[player] ~= loadout then
			return
		end
		local needed = stats.Magazine - state.Mag
		if state.Reserve == nil then
			state.Mag = stats.Magazine
		else
			local taken = math.min(needed, state.Reserve :: number)
			state.Mag += taken
			state.Reserve = (state.Reserve :: number) - taken
		end
		state.ReloadingUntil = 0
		sendState(player)
	end)
end

local function onSwitch(player: Player, slot: string)
	local loadout = loadouts[player]
	if loadout == nil or loadout.Slots[slot] == nil or loadout.Active == slot then
		return
	end
	local current = loadout.Slots[loadout.Active]
	if current then
		-- Swapping away cancels a reload in progress.
		current.ReloadToken += 1
		current.ReloadingUntil = 0
	end
	loadout.Active = slot
	loadout.SwapReadyAt = os.clock() + loadout.Slots[slot].Stats.SwapTime
	equipModel(player)
	sendState(player)
end

-- Lifecycle ------------------------------------------------------------------------

function WeaponService.Init()
	local slotCheck = Guard.OneOf(SLOTS)
	NetService.OnEvent("WeaponFire", { slotCheck, Guard.Vector3(1e6), Guard.Optional(Guard.Number(0, 1e12)) }, onFire)
	NetService.OnEvent("WeaponReload", { slotCheck }, onReload)
	NetService.OnEvent("WeaponSwitch", { slotCheck }, onSwitch)
end

function WeaponService.Start()
	CharacterService.CharacterSpawned:Connect(function(player: Player)
		rebuildSlots(player)
		local loadout = getLoadout(player)
		for _, state in loadout.Slots do
			state.Mag = state.Stats.Magazine
			state.ReloadingUntil = 0
			state.ReloadToken += 1
		end
		equipModel(player)
		sendState(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		loadouts[player] = nil
	end)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("WeaponsDrawn"):Connect(function()
			equipModel(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return WeaponService
