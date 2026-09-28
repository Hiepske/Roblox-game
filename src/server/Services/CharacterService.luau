--!strict
--[[
	CharacterService
	Owns player characters: spawning, health + shields, damage, death and
	respawning.

	  * Players.CharacterAutoLoads is off (default.project.json), so nobody
	    spawns until their data has loaded. Then they appear in the hub.
	  * Shields (character attributes Shield/MaxShield) absorb damage first.
	    After CombatConfig.Player.ShieldRegenDelay seconds without damage,
	    shields refill, then health. (StarterCharacterScripts/Health replaces
	    Roblox's default health regen.)
	  * Incoming damage is scaled by the power gap (CombatContext) and reduced
	    by the Fortitude armor stat.
	  * On death, a resolver installed by ActivityService decides what
	    happens: respawn after a delay (hub, checkpoint) or wait for a revive
	    or wipe. Where to respawn is asked again at respawn time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ArmorConfig = require(Shared.Config.ArmorConfig)
local ClassConfig = require(Shared.Config.ClassConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local PowerMath = require(Shared.Power.PowerMath)
local Signal = require(Shared.Util.Signal)

local CombatContext = require(script.Parent.Parent.Combat.CombatContext)
local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)
local WorldService = require(script.Parent.WorldService)

export type DeathPolicy = {
	-- Seconds until an automatic respawn; nil = wait (a revive or wipe decides).
	Delay: number?,
	-- Shown on the death screen.
	Message: string,
}

type State = {
	Character: Model?,
	Humanoid: Humanoid?,
	Alive: boolean,
	Shield: number,
	MaxShield: number,
	DamageReduction: number,
	LastDamageAt: number,
	-- What hurt the player last (an enemy name, "Laser"...), for the kill feed.
	LastSource: string?,
	ProtectedUntil: number,
	God: boolean,
	-- Bumped on every spawn/death so stale respawn timers do nothing.
	SpawnToken: number,
}

local CharacterService = {}

local characterSpawned: Signal.Signal<Player, Model> = Signal.new()
CharacterService.CharacterSpawned = characterSpawned
local playerDied: Signal.Signal<Player, Vector3> = Signal.new()
CharacterService.PlayerDied = playerDied

local states: { [Player]: State } = {}
local deathResolver: ((Player, Vector3) -> DeathPolicy)? = nil
local spawnResolver: ((Player) -> CFrame)? = nil

local function getState(player: Player): State
	local state = states[player]
	if state == nil then
		local created: State = {
			Character = nil,
			Humanoid = nil,
			Alive = false,
			Shield = 0,
			MaxShield = 0,
			DamageReduction = 0,
			LastDamageAt = 0,
			LastSource = nil,
			ProtectedUntil = 0,
			God = false,
			SpawnToken = 0,
		}
		states[player] = created
		return created
	end
	return state
end

type DerivedStats = { MaxHealth: number, MaxShield: number, WalkSpeed: number, DamageReduction: number }

-- Class base stats plus armor Fortitude (damage reduction) and Agility (speed).
local function deriveStats(player: Player): DerivedStats
	local data = DataService.GetData(player)
	local class = ClassConfig.List[1]
	local fortitude, agility = 0, 0
	if data then
		class = ClassConfig.ById[data.Class] or class
		for _, slot in ArmorConfig.Slots do
			local uid = data.Equipped[slot]
			local item = if uid then data.Items[uid] else nil
			if item then
				fortitude += item.Stats.Fortitude or 0
				agility += item.Stats.Agility or 0
			end
		end
	end
	local effects = ArmorConfig.TierEffects
	local fortitudeTier = math.min(ArmorConfig.MaxTier, fortitude // ArmorConfig.PointsPerTier)
	local agilityTier = math.min(ArmorConfig.MaxTier, agility // ArmorConfig.PointsPerTier)
	return {
		MaxHealth = class.Health,
		MaxShield = class.Shield,
		WalkSpeed = class.WalkSpeed + agilityTier * effects.Agility.WalkSpeedBonus,
		DamageReduction = fortitudeTier * effects.Fortitude.DamageReductionPerTier,
	}
end

local function sendStatus(player: Player, status: { [string]: any })
	if player.Parent == Players then
		NetService.FireClient(player, "PlayerStatus", status)
	end
end

local function onDied(player: Player, character: Model)
	local state = states[player]
	if state == nil or state.Character ~= character or not state.Alive then
		return
	end
	state.Alive = false
	state.SpawnToken += 1
	local token = state.SpawnToken

	local root = character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else character:GetPivot().Position
	playerDied:Fire(player, position)

	local policy: DeathPolicy = if deathResolver
		then deathResolver(player, position)
		else { Delay = CombatConfig.Respawn.Hub, Message = "Respawning" }

	local delay = policy.Delay
	sendStatus(player, {
		Alive = false,
		RespawnAt = if delay then Workspace:GetServerTimeNow() + delay else nil,
		Message = policy.Message,
	})
	if delay then
		task.delay(delay, function()
			if state.SpawnToken == token and player.Parent == Players then
				CharacterService.Spawn(player)
			end
		end)
	end
end

-- Hooks for ActivityService: what happens on death, and where to respawn.
function CharacterService.SetResolvers(onDeath: (Player, Vector3) -> DeathPolicy, spawnAt: (Player) -> CFrame)
	deathResolver = onDeath
	spawnResolver = spawnAt
end

-- (Re)spawns the player at `at`, or wherever the spawn resolver says.
-- Yields while the character loads.
function CharacterService.Spawn(player: Player, at: CFrame?)
	local state = getState(player)
	state.SpawnToken += 1
	local token = state.SpawnToken

	local target = at or (if spawnResolver then spawnResolver(player) else WorldService.GetHubSpawn())
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	if player.Parent ~= Players or state.SpawnToken ~= token then
		return
	end

	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok and string.find(tostring(err), "not a valid member", 1, true) then
		-- Older engine builds only have the synchronous LoadCharacter.
		ok, err = pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
	local character = player.Character
	if not ok or character == nil or state.SpawnToken ~= token then
		if not ok then
			warn(`[CharacterService] LoadCharacter failed for {player.Name}: {err}`)
		end
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	local stats = deriveStats(player)
	humanoid.MaxHealth = stats.MaxHealth
	humanoid.Health = stats.MaxHealth
	humanoid.WalkSpeed = stats.WalkSpeed
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = true
	character:PivotTo(target)

	state.Character = character
	state.Humanoid = humanoid
	state.Alive = true
	state.MaxShield = stats.MaxShield
	state.Shield = stats.MaxShield
	state.DamageReduction = stats.DamageReduction
	state.LastDamageAt = 0
	state.ProtectedUntil = os.clock() + CombatConfig.Player.SpawnProtection
	character:SetAttribute("MaxShield", stats.MaxShield)
	character:SetAttribute("Shield", stats.MaxShield)

	humanoid.Died:Connect(function()
		onDied(player, character)
	end)

	sendStatus(player, { Alive = true })
	characterSpawned:Fire(player, character)
end

-- Moves a living player (streams the destination in first). Dead players
-- are respawned there instead.
function CharacterService.Teleport(player: Player, cframe: CFrame)
	local state = states[player]
	local character = if state then state.Character else nil
	if state == nil or not state.Alive or character == nil or character.Parent == nil then
		task.spawn(CharacterService.Spawn, player, cframe)
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cframe.Position, 5)
	end)
	if character.Parent then
		character:PivotTo(cframe)
	end
	state.ProtectedUntil = os.clock() + CombatConfig.Player.SpawnProtection
end

-- Enemy damage enters here. Returns the damage actually taken.
function CharacterService.DamagePlayer(player: Player, amount: number, source: string?): number
	local state = states[player]
	if state == nil or not state.Alive or state.God or amount <= 0 then
		return 0
	end
	local humanoid = state.Humanoid
	local character = state.Character
	if humanoid == nil or character == nil or humanoid.Health <= 0 then
		return 0
	end
	local now = os.clock()
	if now < state.ProtectedUntil then
		return 0
	end

	local context = CombatContext.Get(player)
	local _, incoming = PowerMath.CombatMultipliers({
		CharacterPower = context.CharacterPower,
		ArtifactLevel = context.ArtifactLevel,
		ActivityPower = context.ActivityPower,
		PowerEnabled = context.PowerEnabled,
		DeltaCap = context.DeltaCap,
	})
	local damage = amount * incoming * (1 - state.DamageReduction)
	state.LastDamageAt = now
	state.LastSource = source

	local remaining = damage
	if state.Shield > 0 then
		local absorbed = math.min(state.Shield, remaining)
		state.Shield -= absorbed
		remaining -= absorbed
		character:SetAttribute("Shield", state.Shield)
	end
	if remaining > 0 then
		humanoid.Health = math.max(0, humanoid.Health - remaining)
	end
	return damage
end

function CharacterService.HealFull(player: Player)
	local state = states[player]
	if state and state.Alive and state.Humanoid and state.Character then
		state.Humanoid.Health = state.Humanoid.MaxHealth
		state.Shield = state.MaxShield
		state.Character:SetAttribute("Shield", state.Shield)
	end
end

-- Recomputes armor-derived stats after gear changes.
function CharacterService.RefreshStats(player: Player)
	local state = states[player]
	if state == nil or not state.Alive or state.Humanoid == nil or state.Character == nil then
		return
	end
	local stats = deriveStats(player)
	state.DamageReduction = stats.DamageReduction
	state.MaxShield = stats.MaxShield
	state.Shield = math.min(state.Shield, stats.MaxShield)
	state.Humanoid.WalkSpeed = stats.WalkSpeed
	state.Character:SetAttribute("MaxShield", stats.MaxShield)
	state.Character:SetAttribute("Shield", state.Shield)
end

function CharacterService.Kill(player: Player)
	local state = states[player]
	if state and state.Alive and state.Humanoid then
		state.Humanoid.Health = 0
	end
end

-- What last damaged the player, if that was within the last few seconds.
function CharacterService.LastDamageSource(player: Player): string?
	local state = states[player]
	if state == nil or os.clock() - state.LastDamageAt > 5 then
		return nil
	end
	return state.LastSource
end

function CharacterService.IsAlive(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Alive
end

function CharacterService.GetCharacter(player: Player): Model?
	local state = states[player]
	return if state and state.Alive then state.Character else nil
end

function CharacterService.SetGodMode(player: Player, enabled: boolean)
	getState(player).God = enabled
end

function CharacterService.IsGodMode(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.God
end

-- Updates the death screen text (e.g. "Revived by ..." or "Encounter wiped").
function CharacterService.SendStatus(player: Player, status: { [string]: any })
	sendStatus(player, status)
end

function CharacterService.Init() end

function CharacterService.Start()
	DataService.PlayerLoaded:Connect(function(player: Player)
		CharacterService.Spawn(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) and player.Character == nil then
			task.spawn(CharacterService.Spawn, player, nil)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	-- Shield and health regeneration.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		local tuning = CombatConfig.Player
		for _, state in states do
			local humanoid = state.Humanoid
			local character = state.Character
			if state.Alive and humanoid and character and humanoid.Health > 0 then
				if now - state.LastDamageAt >= tuning.ShieldRegenDelay then
					if state.Shield < state.MaxShield then
						state.Shield = math.min(state.MaxShield, state.Shield + tuning.ShieldRegenPerSecond * step)
						character:SetAttribute("Shield", state.Shield)
					elseif humanoid.Health < humanoid.MaxHealth then
						humanoid.Health =
							math.min(humanoid.MaxHealth, humanoid.Health + tuning.HealthRegenPerSecond * step)
					end
				end
			end
		end
	end)
end

return CharacterService
