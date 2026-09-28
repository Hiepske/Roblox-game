--!strict
--[[
	WeaponService
	Server side of shooting. Clients send intents (fire at this aim point,
	reload, switch slot); the server owns every number:

	  * magazines and reserves per slot (primary ammo has infinite reserves,
	    heavy ammo is limited and refilled by purple ammo boxes)
	  * fire rate (with a small jitter tolerance), swap and reload timers
	  * the shot itself: a ray from the character's head toward the aim
	    point, capped at the weapon's range; rockets become server projectiles
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

-- Adds a share of heavy ammo (ammo box pickup). Returns rounds gained.
function WeaponService.AddHeavyAmmo(player: Player, fraction: number): number
	local loadout = loadouts[player]
	local state = if loadout then loadout.Slots.Heavy else nil
	if state == nil or state.Reserve == nil or state.Stats.Reserves == nil then
		return 0
	end
	local maximum = state.Stats.Reserves :: number
	local gain = math.max(1, math.ceil(maximum * fraction))
	local before = state.Reserve :: number
	state.Reserve = math.min(maximum, before + gain)
	sendState(player)
	return (state.Reserve :: number) - before
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

local function onFire(player: Player, slot: string, aimPoint: Vector3, _shotId: number?)
	local loadout = loadouts[player]
	if loadout == nil or loadout.Active ~= slot then
		return
	end
	local state = loadout.Slots[slot]
	local character = CharacterService.GetCharacter(player)
	local head = if character then character:FindFirstChild("Head") else nil
	if state == nil or head == nil or not head:IsA("BasePart") then
		return
	end
	local stats = state.Stats
	local now = os.clock()
	if not isDrawn(player) then
		return
	end
	if now < loadout.SwapReadyAt - 0.1 or now < state.ReloadingUntil - 0.1 then
		return
	end
	if now - state.LastShot < stats.FireInterval * CombatConfig.Weapons.FireRateTolerance then
		NetService.Flag(player, 0.25, "firing faster than the weapon allows")
		return
	end
	if state.Mag <= 0 then
		return
	end
	state.Mag -= 1
	state.LastShot = now

	local origin = head.Position
	local offset = aimPoint - origin
	if offset.Magnitude < 0.5 then
		return
	end
	local direction = offset.Unit
	local reach = math.min(offset.Magnitude + 5, stats.MaxRange)
	local element = ElementConfig.Elements[stats.Element]
	local color = if element then element.Color else Color3.new(1, 1, 1)

	local projectile = stats.Projectile
	if projectile then
		ProjectileService.Spawn({
			Origin = origin + direction * 2.5,
			Velocity = direction * projectile.Speed,
			MaxDistance = stats.MaxRange,
			Style = "Rocket",
			Color = color,
			Exclude = playerCharacters(),
			BlastRadius = projectile.BlastRadius,
			OnHit = function(_result: RaycastResult?, position: Vector3)
				CombatService.Explode(player, position, stats)
			end,
		})
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = playerCharacters()
	local result = Workspace:Raycast(origin, direction * reach, params)
	local hitPosition = if result then result.Position else origin + direction * reach
	if result then
		CombatService.HitscanHit(player, result.Instance, result.Position, (result.Position - origin).Magnitude, stats)
	end

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
