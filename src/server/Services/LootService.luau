--!strict
--[[
	LootService
	Everything that hands out gear or ammo.

	  * Enemy deaths: heavy ammo boxes (purple, picked up by walking over
	    them) and a small chance of a gear drop for each player in the
	    activity (LootConfig.EnemyGearChance / AmmoDrops).
	  * Activity completion: end-of-activity drops, weekly Powerful/Pinnacle
	    milestones (once per weekly reset) and raid-exclusive rolls.
	  * Every award is saved through DataService.GiveItem and announced with
	    LootAwarded so the client can show the loot screen or a toast.

	Drops roll from the activity's LootSource (LootConfig) relative to the
	player's highest possible power, so soft/powerful/pinnacle caps apply.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ActivityConfig = require(Shared.Config.ActivityConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local LootConfig = require(Shared.Config.LootConfig)
local ItemRoller = require(Shared.Items.ItemRoller)
local LootRoller = require(Shared.Items.LootRoller)
local MilestoneConfig = require(Shared.Config.MilestoneConfig)
local PowerMath = require(Shared.Power.PowerMath)
local Types = require(Shared.Types)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local NetService = require(script.Parent.NetService)
local WeaponService = require(script.Parent.WeaponService)
local WorldService = require(script.Parent.WorldService)

type ItemInstance = Types.ItemInstance

export type Award = {
	Item: ItemInstance,
	Location: Types.ItemLocation,
	-- "Drop", "Powerful", "Pinnacle", "Exclusive"
	Reason: string,
}

type AmmoBox = {
	Part: BasePart,
	InstanceId: string?,
	ExpiresAt: number,
	AmmoType: string,
	Fraction: number,
}

local AMMO_LOOK: { [string]: { Color: Color3, Text: Color3, Label: string } } = {
	Heavy = { Color = Color3.fromRGB(170, 80, 255), Text = Color3.fromRGB(215, 170, 255), Label = "HEAVY AMMO" },
	Special = { Color = Color3.fromRGB(70, 220, 110), Text = Color3.fromRGB(170, 255, 190), Label = "SPECIAL AMMO" },
}

local LootService = {}

local rng = Random.new()
local boxes: { AmmoBox } = {}

-- Called by ActivityService to know which activity (and modifiers) an
-- instance belongs to: returns (lootSource, ammoMultiplier, players).
local instanceResolver: ((string) -> (string?, number, { Player }))? = nil

function LootService.SetInstanceResolver(fn: (string) -> (string?, number, { Player }))
	instanceResolver = fn
end

-- Awarding ------------------------------------------------------------------------------

-- Rolls one item for `player` and saves it. nil when nothing could be rolled
-- or there's no room anywhere (a notification explains).
function LootService.Roll(
	player: Player,
	sourceId: string,
	rewardKind: Types.RewardKind,
	tier: number?,
	options: LootRoller.RollOptions?
): ItemInstance?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local highest = PowerMath.HighestPossible(data.Items)
	local item = LootRoller.RollItem(
		sourceId,
		highest,
		rewardKind,
		tier,
		rng,
		DataService.NewUid(),
		os.time(),
		data.Class,
		options
	)
	if item == nil then
		return nil
	end
	local ok = DataService.GiveItem(player, item)
	if not ok then
		NetService.Notify(player, "Your inventory and postmaster are full. Dismantle something!", "Error")
		return nil
	end
	return item
end

-- Sends awards to the client. `screen` = true shows the full loot screen
-- (end of activity); otherwise a small toast per item.
function LootService.Announce(player: Player, awards: { Award }, title: string, screen: boolean)
	local data = DataService.GetData(player)
	local power = if data then PowerMath.CharacterPower(data.Items, data.Equipped) else 0
	local highest = if data then PowerMath.HighestPossible(data.Items) else 0
	local list = {}
	for _, award in awards do
		table.insert(list, { Item = award.Item, Location = award.Location, Reason = award.Reason })
	end
	NetService.FireClient(player, "LootAwarded", {
		Title = title,
		Screen = screen,
		Awards = list,
		Power = power,
		HighestPower = highest,
	})
end

local function award(awards: { Award }, item: ItemInstance?, reason: string)
	if item then
		table.insert(awards, { Item = item, Location = item.Location, Reason = reason })
	end
end

-- Claims a weekly milestone if it hasn't paid out this week. Returns the
-- rewarded item (Powerful/Pinnacle, rolled from `sourceId`).
function LootService.ClaimMilestone(player: Player, milestoneId: string, sourceId: string, awards: { Award }): boolean
	local data = DataService.GetData(player)
	local milestone = MilestoneConfig.ById[milestoneId]
	if data == nil or milestone == nil then
		return false
	end
	local claimed = data.Weekly.ClaimedRewards[milestoneId] or 0
	if claimed >= (milestone.WeeklyLimit or 1) then
		return false
	end
	local progress = (data.Weekly.MilestoneProgress[milestoneId] or 0) + 1
	DataService.Set(player, { "Weekly", "MilestoneProgress", milestoneId }, progress)
	if progress < milestone.Goal then
		return false
	end
	DataService.Set(player, { "Weekly", "ClaimedRewards", milestoneId }, claimed + 1)
	local reward = milestone.Reward
	award(awards, LootService.Roll(player, sourceId, reward.Kind, reward.Tier), reward.Kind)
	return true
end

-- A weapon from `sourceId`'s pool the player doesn't own yet (any if they own
-- them all), at World power.
function LootService.NewWeapon(player: Player, sourceId: string): ItemInstance?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local owned: { [string]: boolean } = {}
	for _, item in data.Items do
		owned[item.DefId] = true
	end
	local pool = LootRoller.PoolWeapons(sourceId)
	local fresh: { string } = {}
	for _, defId in pool do
		if not owned[defId] then
			table.insert(fresh, defId)
		end
	end
	local choices = if #fresh > 0 then fresh else pool
	if #choices == 0 then
		return nil
	end
	local defId = choices[rng:NextInteger(1, #choices)]
	local highest = PowerMath.HighestPossible(data.Items)
	local item = ItemRoller.Roll(
		defId,
		PowerMath.RollDropPower(highest, "World", nil, rng),
		rng,
		DataService.NewUid(),
		os.time(),
		"Random"
	)
	if item == nil or not DataService.GiveItem(player, item) then
		return nil
	end
	return item
end

export type CompletionInfo = {
	Activity: ActivityConfig.ActivityDef,
	Difficulty: ActivityConfig.DifficultyDef?,
	-- Encounters cleared this run (raids).
	Encounters: { ActivityConfig.EncounterDef },
	Title: string,
}

-- End-of-activity rewards for one player. Returns what was awarded.
function LootService.AwardCompletion(player: Player, info: CompletionInfo): { Award }
	local activity = info.Activity
	local rewards = activity.Rewards
	local source = activity.LootSource
	local awards: { Award } = {}

	local dropCount = 0
	if rewards then
		dropCount = rng:NextInteger(rewards.Drops.Min, rewards.Drops.Max)
	end
	if info.Difficulty and info.Difficulty.BonusDrops then
		dropCount += info.Difficulty.BonusDrops
	end

	-- Weekly milestones: difficulty milestones (Nightfall) and encounter milestones (raid).
	local milestones: { string } = {}
	if info.Difficulty and info.Difficulty.Milestones then
		for _, id in info.Difficulty.Milestones do
			table.insert(milestones, id)
		end
	end
	for _, encounter in info.Encounters do
		if encounter.Milestone then
			table.insert(milestones, encounter.Milestone)
		end
	end
	local claimedAny = false
	for _, id in milestones do
		if LootService.ClaimMilestone(player, id, source, awards) then
			claimedAny = true
		end
	end
	if not claimedAny and #milestones > 0 and rewards and rewards.FallbackDrops then
		dropCount += rewards.FallbackDrops
	end

	local options: LootRoller.RollOptions? = if rewards and rewards.Rarities
		then { Rarities = rewards.Rarities, NoExotic = true }
		else nil
	for _ = 1, dropCount do
		award(awards, LootService.Roll(player, source, "World", nil, options), "Drop")
	end

	if rewards and rewards.NewWeapon then
		award(awards, LootService.NewWeapon(player, source), "NewWeapon")
	end

	if rewards and rewards.ExclusiveChance and rng:NextNumber() < rewards.ExclusiveChance then
		local kind: Types.RewardKind = if claimedAny then "Pinnacle" else "World"
		award(
			awards,
			LootService.Roll(player, source, kind, nil, { ExclusiveOnly = true, NoExotic = true }),
			"Exclusive"
		)
	end

	LootService.Announce(player, awards, info.Title, true)
	return awards
end

-- Enemy drops ---------------------------------------------------------------------------

local function makeBox(position: Vector3, instanceId: string?, ammoType: string, fraction: number)
	local look = AMMO_LOOK[ammoType] or AMMO_LOOK.Heavy
	local part = Instance.new("Part")
	part.Name = `{ammoType}Ammo`
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Color = look.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 10
	light.Brightness = 2
	light.Parent = part
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 22)
	gui.StudsOffset = Vector3.new(0, 1.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = look.Label
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = look.Text
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = part
	part.Parent = WorldService.Folder("Pickups")
	table.insert(boxes, {
		Part = part :: BasePart,
		InstanceId = instanceId,
		ExpiresAt = os.clock() + CombatConfig.Ammo.BoxLifetime,
		AmmoType = ammoType,
		Fraction = fraction,
	})
end

-- Drops an ammo box ("Special" green or "Heavy" purple) at `position`.
function LootService.DropAmmo(position: Vector3, instanceId: string?, ammoType: string)
	local fraction = (LootConfig.AmmoBrickFraction :: any)[ammoType] or 0.25
	makeBox(position, instanceId, ammoType, fraction)
end

function LootService.DropHeavyAmmo(position: Vector3, instanceId: string?)
	LootService.DropAmmo(position, instanceId, "Heavy")
end

local function onEnemyKilled(enemy: EnemyService.Enemy, _killer: Player?)
	if enemy.Def.Dummy then
		return
	end
	local instanceId = enemy.InstanceId
	local source: string? = "World"
	local ammoMultiplier = 1
	local players: { Player } = {}
	if instanceId and instanceResolver then
		source, ammoMultiplier, players = instanceResolver(instanceId)
	end

	local tier = enemy.Def.Tier
	local heavyChance = ((LootConfig.AmmoDrops.Heavy :: any)[tier] or 0) * ammoMultiplier
	local specialChance = ((LootConfig.AmmoDrops.Special :: any)[tier] or 0) * ammoMultiplier
	local roll = rng:NextNumber()
	if roll < heavyChance then
		LootService.DropAmmo(enemy.Root.Position, instanceId, "Heavy")
	elseif roll < heavyChance + specialChance then
		LootService.DropAmmo(enemy.Root.Position, instanceId, "Special")
	end

	-- Bosses drop their loot at the end-of-activity screen instead.
	if source == nil or enemy.IsBoss then
		return
	end
	local gearChance = (LootConfig.EnemyGearChance :: any)[tier] or 0
	for _, player in players do
		if rng:NextNumber() < gearChance then
			local item = LootService.Roll(player, source, "World", nil, { NoExotic = true })
			if item then
				LootService.Announce(player, { { Item = item, Location = item.Location, Reason = "Drop" } }, "", false)
			end
		end
	end
end

local function updateBoxes()
	local now = os.clock()
	local radius = CombatConfig.Ammo.PickupRadius
	for index = #boxes, 1, -1 do
		local box = boxes[index]
		local taken = false
		if now >= box.ExpiresAt or box.Part.Parent == nil then
			taken = true
		else
			box.Part.CFrame = box.Part.CFrame * CFrame.Angles(0, 0.06, 0)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("InstanceId") == box.InstanceId and CharacterService.IsAlive(player) then
					local character = CharacterService.GetCharacter(player)
					local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
					if
						root
						and root:IsA("BasePart")
						and (root.Position - box.Part.Position).Magnitude <= radius
						and WeaponService.AddAmmo(player, box.AmmoType, box.Fraction) > 0
					then
						NetService.Notify(player, `{box.AmmoType} ammo`, "Info")
						taken = true
						break
					end
				end
			end
		end
		if taken then
			box.Part:Destroy()
			table.remove(boxes, index)
		end
	end
end

-- Removes every ammo box belonging to an instance (activity ended).
function LootService.ClearInstance(instanceId: string)
	for index = #boxes, 1, -1 do
		if boxes[index].InstanceId == instanceId then
			boxes[index].Part:Destroy()
			table.remove(boxes, index)
		end
	end
end

function LootService.Init() end

function LootService.Start()
	EnemyService.EnemyKilled:Connect(onEnemyKilled)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			updateBoxes()
		end
	end)
end

return LootService
