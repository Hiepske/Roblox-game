--!strict
--[[
	Migrations
	Versioned schema upgrades for saved player data.

	Every save stores SchemaVersion. When the shape of ProfileData changes:
	  1. bump CurrentVersion
	  2. add Steps[oldVersion] = function(data) ... end that upgrades data
	     from oldVersion to oldVersion + 1 in place
	  3. add the new fields to ProfileTemplate (Reconcile fills them for old
	     saves, so a migration is only needed for renames, moves and reshapes)

	Data saved by a NEWER build (SchemaVersion > CurrentVersion) is never
	loaded or overwritten: during a rolling update an old server would
	otherwise silently drop the new fields. DataService kicks the player with
	a "please rejoin" message instead.
]]

export type Step = (data: { [string]: any }) -> ()

local Migrations = {}

Migrations.CurrentVersion = 1

-- Steps[n] upgrades data from version n to n + 1.
-- Example for a future v2 that renames a currency:
--
--   [1] = function(data)
--       data.Currencies.Credits = data.Currencies.Quanta
--       data.Currencies.Quanta = nil
--   end,
Migrations.Steps = {} :: { [number]: Step }

export type Result = {
	Ok: boolean,
	FromVersion: number,
	ToVersion: number,
	Error: string?,
}

-- Upgrades `data` in place to `targetVersion` (defaults to CurrentVersion)
-- using `steps` (defaults to Migrations.Steps). Data with no version is
-- treated as version 1, the first shipped schema.
function Migrations.Run(data: { [string]: any }, steps: { [number]: Step }?, targetVersion: number?): Result
	local stepList = steps or Migrations.Steps
	local target = targetVersion or Migrations.CurrentVersion
	local version = if type(data.SchemaVersion) == "number" then data.SchemaVersion else 1
	local from = version

	if version > target then
		return {
			Ok = false,
			FromVersion = from,
			ToVersion = version,
			Error = `data is version {version}, newer than this server's {target}`,
		}
	end

	while version < target do
		local step = stepList[version]
		if step == nil then
			return {
				Ok = false,
				FromVersion = from,
				ToVersion = version,
				Error = `missing migration step from version {version}`,
			}
		end
		-- (cast: the checker expects pcall to return what `step` returns)
		local ok, err = pcall(step :: any, data)
		if not ok then
			return {
				Ok = false,
				FromVersion = from,
				ToVersion = version,
				Error = `migration from version {version} failed: {err}`,
			}
		end
		version += 1
		data.SchemaVersion = version
	end

	data.SchemaVersion = version
	return { Ok = true, FromVersion = from, ToVersion = version }
end

return Migrations
