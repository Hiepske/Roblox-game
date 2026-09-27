local Shared = game.ReplicatedStorage.Shared
local Server = game.ServerScriptService
local GameConfig = require(Shared.Config.GameConfig)
local Inventory = require(Shared.Items.Inventory)
local Migrations = require(Server.Data.Migrations)
local PowerConfig = require(Shared.Config.PowerConfig)
local PowerMath = require(Shared.Power.PowerMath)
local ProfileTemplate = require(Server.Data.ProfileTemplate)
local Resets = require(Server.Data.Resets)
local TableUtil = require(Shared.Util.TableUtil)
local TimeUtil = require(Shared.Util.TimeUtil)

local counter = 0
local function uid()
	counter += 1
	return string.format("00000000-0000-0000-0000-%012d", counter)
end

local NOW = 1790467200 + 12 * 3600 -- Sunday 2026-09-27 12:00 UTC

local function newProfile()
	return ProfileTemplate.CreateNew(NOW, uid, VirtualGame.Random.new(1))
end

describe("ProfileTemplate", function()
	it("creates a new save with the starter loadout equipped at starting power", function()
		local data = newProfile()
		expect(data.SchemaVersion).toBe(Migrations.CurrentVersion)
		expect(data.Class).toBe(GameConfig.NewPlayer.Class)
		expect(TableUtil.Count(data.Items)).toBe(8)
		for _, slot in PowerMath.AllSlots do
			local item = data.Items[data.Equipped[slot]]
			expect(item.DefId).toBe(GameConfig.NewPlayer.StarterLoadout[slot])
			expect(item.Slot).toBe(slot)
		end
		expect(PowerMath.CharacterPower(data.Items, data.Equipped)).toBe(PowerConfig.StartingPower)
		expect(data.Currencies.Quanta).toBe(GameConfig.NewPlayer.Currencies.Quanta)
		expect(data.Flags.StarterLoadoutGranted).toBe(true)
	end)

	it("produces data a DataStore can store", function()
		local ok, err = TableUtil.ValidateDataStoreValue(newProfile())
		if not ok then
			error(err)
		end
	end)

	it("fills fields added after an old save was written", function()
		local old = newProfile()
		old.Artifact = nil
		old.Settings.Keybinds = nil
		TableUtil.Reconcile(old, ProfileTemplate.Template)
		expect(old.Artifact.Level).toBe(0)
		expect(old.Settings.Keybinds).toEqual({})
		expect(TableUtil.Count(old.Items)).toBe(8) -- existing data untouched
	end)

	it("repairs broken equips, extra exotics, bad currencies and unknown classes", function()
		local data = newProfile()
		data.Class = "Wizard"
		data.Currencies.Quanta = 0 / 0
		data.Currencies.Starglass = 1e9
		data.Equipped.Kinetic = "missing-uid"
		-- Two exotic weapons equipped at once.
		local energy = data.Items[data.Equipped.Energy]
		local heavy = data.Items[data.Equipped.Heavy]
		energy.Rarity = "Exotic"
		heavy.Rarity = "Exotic"
		-- An item whose stored slot disagrees with its def.
		local chest = data.Items[data.Equipped.Chest]
		chest.Slot = "Legs"

		local fixes = ProfileTemplate.Sanitize(data)
		expect(#fixes).toBeAtLeast(4)
		expect(data.Class).toBe(GameConfig.NewPlayer.Class)
		expect(data.Currencies.Quanta).toBe(0)
		expect(data.Currencies.Starglass).toBe(50)
		expect(data.Equipped.Kinetic).toBeNil()
		expect(data.Equipped.Energy).toBe(energy.Uid)
		expect(data.Equipped.Heavy).toBeNil()
		expect(chest.Slot).toBe("Chest") -- restored from the def
		expect(data.Equipped.Chest).toBe(chest.Uid)
	end)

	it("unequips class-locked exotic armor on the wrong class", function()
		local data = newProfile()
		local helmet = data.Items[data.Equipped.Helmet]
		helmet.DefId = "A_EXO_EMBER_CROWN" -- Mystic only
		helmet.Rarity = "Exotic"
		data.Class = "Bulwark"
		ProfileTemplate.Sanitize(data)
		expect(data.Equipped.Helmet).toBeNil()
	end)
end)

describe("Migrations", function()
	it("is a no-op for current data", function()
		local data = newProfile()
		local result = Migrations.Run(data)
		expect(result.Ok).toBe(true)
		expect(result.FromVersion).toBe(Migrations.CurrentVersion)
	end)

	it("runs steps in order up to the target version", function()
		local calls = {}
		local steps = {
			[1] = function(d)
				table.insert(calls, 1)
				d.Renamed = d.Old
				d.Old = nil
			end,
			[2] = function(d)
				table.insert(calls, 2)
				d.Added = true
			end,
		}
		local data = { SchemaVersion = 1, Old = "x" }
		local result = Migrations.Run(data, steps, 3)
		expect(result.Ok).toBe(true)
		expect(calls).toEqual({ 1, 2 })
		expect(data.SchemaVersion).toBe(3)
		expect(data.Renamed).toBe("x")
		expect(data.Added).toBe(true)
	end)

	it("treats unversioned data as version 1", function()
		local data = {}
		local result = Migrations.Run(data, { [1] = function() end }, 2)
		expect(result.Ok).toBe(true)
		expect(result.FromVersion).toBe(1)
		expect(data.SchemaVersion).toBe(2)
	end)

	it("refuses data from a newer game version", function()
		local result = Migrations.Run({ SchemaVersion = 99 })
		expect(result.Ok).toBe(false)
		expect(result.FromVersion).toBe(99)
	end)

	it("reports missing and failing steps", function()
		expect(Migrations.Run({ SchemaVersion = 1 }, {}, 2).Ok).toBe(false)
		local failing = Migrations.Run({ SchemaVersion = 1 }, {
			[1] = function()
				error("boom")
			end,
		}, 2)
		expect(failing.Ok).toBe(false)
		expect(failing.Error:find("boom", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Resets", function()
	local config = GameConfig.Resets

	it("resets weekly and daily data once the boundary passes", function()
		local data = newProfile()
		Resets.Apply(data, NOW, config)
		data.Weekly.ClaimedRewards.RAID_ENCOUNTER_1 = 1
		data.Daily.ClaimedRewards.SOMETHING = 1

		-- Same week: nothing resets.
		local sameWeek = Resets.Apply(data, NOW + 3600, config)
		expect(sameWeek.Weekly).toBe(false)
		expect(data.Weekly.ClaimedRewards.RAID_ENCOUNTER_1).toBe(1)

		-- Tuesday 17:00 UTC passes.
		local nextReset = TimeUtil.GetNextWeeklyReset(NOW, config.WeeklyWeekday, config.HourUtc)
		local after = Resets.Apply(data, nextReset + 1, config)
		expect(after.Weekly).toBe(true)
		expect(after.Daily).toBe(true)
		expect(data.Weekly.ClaimedRewards.RAID_ENCOUNTER_1).toBeNil()
		expect(data.Weekly.ResetAt).toBe(nextReset)
		expect(data.Daily.ClaimedRewards.SOMETHING).toBeNil()
	end)

	it("expires bounties", function()
		local data = newProfile()
		data.Bounties.Active = {
			{ Id = "B_D_RUST_CULL", Progress = 3, AcquiredAt = NOW - 10, ExpiresAt = NOW - 1 },
			{ Id = "B_W_STRIKES", Progress = 1, AcquiredAt = NOW - 10, ExpiresAt = NOW + 1000 },
		}
		local result = Resets.Apply(data, NOW, config)
		expect(result.BountiesExpired).toBe(1)
		expect(#data.Bounties.Active).toBe(1)
		expect(data.Bounties.Active[1].Id).toBe("B_W_STRIKES")
	end)
end)

describe("Inventory capacity", function()
	it("fills the character slot, then the postmaster, then refuses", function()
		local data = newProfile()
		local template = data.Items[data.Equipped.Kinetic]
		local function addKinetic(location)
			local copy = TableUtil.DeepCopy(template)
			copy.Uid = uid()
			copy.Location = location
			data.Items[copy.Uid] = copy
		end

		-- The equipped item does not count against the 9 spare slots.
		expect(Inventory.Count(data, "Inventory", "Kinetic")).toBe(0)
		for _ = 1, GameConfig.Inventory.SlotCapacity do
			expect(Inventory.ResolveDropLocation(data, "Kinetic")).toBe("Inventory")
			addKinetic("Inventory")
		end
		expect(Inventory.ResolveDropLocation(data, "Kinetic")).toBe("Postmaster")
		-- Other slots are unaffected.
		expect(Inventory.ResolveDropLocation(data, "Energy")).toBe("Inventory")

		for _ = 1, GameConfig.Inventory.PostmasterCapacity do
			addKinetic("Postmaster")
		end
		expect(Inventory.ResolveDropLocation(data, "Kinetic")).toBeNil()
	end)
end)
