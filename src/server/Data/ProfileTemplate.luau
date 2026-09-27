--!strict
--[[
	ProfileTemplate
	The shape of a fresh save, new-player setup, and a sanitizer that repairs
	anything invalid in loaded data (removed config ids, bad equips, NaN
	currencies) so one bad field can never break a player's session.

	When you add a field to ProfileData, add it here too: TableUtil.Reconcile
	copies missing template fields into older saves on load.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ClassConfig = require(Shared.Config.ClassConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRoller = require(Shared.Items.ItemRoller)
local PowerConfig = require(Shared.Config.PowerConfig)
local PowerMath = require(Shared.Power.PowerMath)
local RarityConfig = require(Shared.Config.RarityConfig)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)

local Migrations = require(script.Parent.Migrations)

type ProfileData = Types.ProfileData

local ProfileTemplate = {}

local function buildTemplate(): ProfileData
	local currencies: { [string]: number } = {}
	for _, currency in EconomyConfig.Order do
		currencies[currency] = 0
	end
	local defaults = GameConfig.DefaultSettings
	return {
		SchemaVersion = Migrations.CurrentVersion,
		CreatedAt = 0,
		LastLoginAt = 0,
		LoginCount = 0,
		Class = GameConfig.NewPlayer.Class,
		Subclasses = TableUtil.DeepCopy(GameConfig.NewPlayer.Subclasses) :: { [string]: string },
		Items = {},
		Equipped = {},
		Currencies = currencies,
		Progress = {
			StoryCompleted = {},
			ActivityClears = {},
			Unlocks = {},
		},
		Weekly = {
			ResetAt = 0,
			ClaimedRewards = {},
			MilestoneProgress = {},
		},
		Daily = {
			ResetAt = 0,
			ClaimedRewards = {},
		},
		Bounties = {
			Active = {},
		},
		Artifact = {
			Level = 0,
			Xp = 0,
		},
		Lifetime = {
			HighestPower = PowerConfig.StartingPower,
			Kills = 0,
			PrecisionKills = 0,
			ActivitiesCompleted = 0,
			PlaytimeSeconds = 0,
		},
		Settings = {
			MouseSensitivity = defaults.MouseSensitivity,
			AimSensitivityScale = defaults.AimSensitivityScale,
			ControllerSensitivity = defaults.ControllerSensitivity,
			FieldOfView = defaults.FieldOfView,
			InvertY = defaults.InvertY,
			ShowDamageNumbers = defaults.ShowDamageNumbers,
			Keybinds = {},
		},
		Flags = {},
	}
end

ProfileTemplate.Template = TableUtil.DeepFreeze(buildTemplate())

-- Rolls and equips the starter loadout at starting power.
function ProfileTemplate.GrantStarterLoadout(data: ProfileData, now: number, makeUid: () -> string, rng: Random)
	for _, slot in PowerMath.AllSlots do
		local defId = GameConfig.NewPlayer.StarterLoadout[slot]
		local item = if defId
			then ItemRoller.Roll(defId, PowerConfig.StartingPower, rng, makeUid(), now, "Base")
			else nil
		if item then
			data.Items[item.Uid] = item
			data.Equipped[slot] = item.Uid
		end
	end
	data.Flags.StarterLoadoutGranted = true
end

-- A brand-new save with starting currencies and the starter loadout equipped.
function ProfileTemplate.CreateNew(now: number, makeUid: () -> string, rng: Random): ProfileData
	local data = TableUtil.DeepCopy(ProfileTemplate.Template)
	data.CreatedAt = now
	for currency, amount in GameConfig.NewPlayer.Currencies do
		data.Currencies[currency] = amount
	end
	ProfileTemplate.GrantStarterLoadout(data, now, makeUid, rng)
	return data
end

local VALID_LOCATIONS = { Inventory = true, Vault = true, Postmaster = true }

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Repairs invalid data in place. Returns a description of each fix made.
function ProfileTemplate.Sanitize(data: ProfileData): { string }
	local fixes: { string } = {}
	local function fixed(message: string)
		table.insert(fixes, message)
	end

	-- Class and subclasses
	if ClassConfig.ById[data.Class] == nil then
		fixed(`unknown class {tostring(data.Class)}`)
		data.Class = GameConfig.NewPlayer.Class
	end
	for classId, subclassId in data.Subclasses do
		if ClassConfig.SubclassOwner[subclassId] ~= classId then
			fixed(`invalid subclass {tostring(subclassId)} for {classId}`)
			data.Subclasses[classId] = GameConfig.NewPlayer.Subclasses[classId]
		end
	end

	-- Items
	for uid, item in data.Items do
		if type(item) ~= "table" or type(item.DefId) ~= "string" then
			fixed(`removed malformed item {uid}`)
			data.Items[uid] = nil
			continue
		end
		if item.Uid ~= uid then
			fixed(`item uid mismatch {uid}`)
			item.Uid = uid
		end
		if not VALID_LOCATIONS[item.Location] then
			fixed(`item {uid} had invalid location`)
			item.Location = "Inventory"
		end
		if not isFiniteNumber(item.Power) then
			fixed(`item {uid} had invalid power`)
			item.Power = PowerConfig.StartingPower
		end
		item.Power = math.clamp(math.floor(item.Power), 1, PowerConfig.PinnacleCap)
		local entry = ItemCatalog.Get(item.DefId)
		if entry then
			-- The def is the source of truth for slot and kind.
			item.Slot = entry.Slot
			item.Kind = entry.Kind
		end
		if RarityConfig.Tiers[item.Rarity] == nil then
			fixed(`item {uid} had invalid rarity`)
			item.Rarity = if entry then entry.Rarity else "Rare"
		end
		if type(item.Stats) ~= "table" then
			item.Stats = {}
		end
		if type(item.Perks) ~= "table" then
			item.Perks = {}
		end
	end

	-- Equipped: must reference a known item on the character in the right slot,
	-- usable by the current class.
	for slot, uid in data.Equipped do
		local item = data.Items[uid]
		local entry = if item then ItemCatalog.Get(item.DefId) else nil
		local restriction = if entry and entry.Armor then entry.Armor.ClassRestriction else nil
		if
			table.find(PowerMath.AllSlots, slot) == nil
			or item == nil
			or entry == nil
			or item.Slot ~= slot
			or item.Location ~= "Inventory"
			or (restriction ~= nil and restriction ~= data.Class)
		then
			fixed(`unequipped invalid {slot}`)
			data.Equipped[slot] = nil
		end
	end

	-- At most one exotic weapon and one exotic armor piece equipped.
	for _, category in { PowerConfig.WeaponSlots, PowerConfig.ArmorSlots } do
		local seenLimited = false
		for _, slot in category do
			local uid = data.Equipped[slot]
			local item = if uid then data.Items[uid] else nil
			if item and RarityConfig.Tiers[item.Rarity].EquipLimitPerCategory ~= nil then
				if seenLimited then
					fixed(`unequipped extra exotic in {slot}`)
					data.Equipped[slot] = nil
				end
				seenLimited = true
			end
		end
	end

	-- Currencies: finite, non-negative, within cap.
	for currency, amount in data.Currencies do
		local def = EconomyConfig.Currencies[currency]
		if not isFiniteNumber(amount) then
			fixed(`currency {currency} was invalid`)
			data.Currencies[currency] = 0
		elseif def then
			local clamped = math.clamp(math.floor(amount), 0, def.Cap)
			if clamped ~= amount then
				fixed(`currency {currency} clamped`)
				data.Currencies[currency] = clamped
			end
		end
	end

	return fixes
end

return ProfileTemplate
