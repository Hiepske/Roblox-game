--!strict
--[[
	MapMarkers
	Finds the named markers of an activity map (see MapKit): every part under
	the map's Markers folder, at any depth, indexed by name. Game logic only
	ever uses markers, so a hand-edited map keeps working as long as the
	marker names stay the same.

	  Find(index, "Checkpoint_Outpost")   a marker by name (first found)
	  SpawnPoints(index, "Zone2")        EnemySpawns/Zone2/* (or the Phase 2
	                                     markers Spawn_Zone2_1, _2, ...)
	  Numbered(index, "Pylon")           Pylon_1, Pylon_2, ... in order
	  Gate(map, "Gate_Zone2")            a gate model or Phase 2 door part
	  InFolder / NumberedIn              the same, only inside one folder
	                                     (a boss arena when a map has several)
]]

local MissionRules = require(game:GetService("ReplicatedStorage").Shared.Activities.MissionRules)

local MapMarkers = {}

export type Index = {
	ByName: { [string]: BasePart },
	Folders: { [string]: { BasePart } },
}

local function byName(a: BasePart, b: BasePart): boolean
	-- Natural order so Spawn_10 sorts after Spawn_9.
	local prefixA, numberA = string.match(a.Name, "^(.-)(%d+)$")
	local prefixB, numberB = string.match(b.Name, "^(.-)(%d+)$")
	if prefixA and prefixB and prefixA == prefixB then
		return (tonumber(numberA) or 0) < (tonumber(numberB) or 0)
	end
	return a.Name < b.Name
end

function MapMarkers.Index(map: Instance): Index
	local index: Index = { ByName = {}, Folders = {} }
	local root = map:FindFirstChild("Markers")
	if root == nil then
		return index
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			if not index.ByName[descendant.Name] then
				index.ByName[descendant.Name] = descendant
			end
			local parent = descendant.Parent
			if parent and parent ~= root and parent:IsA("Folder") then
				local list = index.Folders[parent.Name]
				if list == nil then
					list = {}
					index.Folders[parent.Name] = list
				end
				table.insert(list, descendant)
			end
		end
	end
	for _, list in index.Folders do
		table.sort(list, byName)
	end
	return index
end

function MapMarkers.Find(index: Index, name: string?): BasePart?
	if name == nil then
		return nil
	end
	return index.ByName[name]
end

-- Markers name_1, name_2, ... until one is missing.
function MapMarkers.Numbered(index: Index, name: string): { BasePart }
	local list: { BasePart } = {}
	local n = 1
	while index.ByName[`{name}_{n}`] do
		table.insert(list, index.ByName[`{name}_{n}`])
		n += 1
	end
	return list
end

-- A marker named `name` directly inside folder `folder`.
function MapMarkers.InFolder(index: Index, folder: string, name: string): BasePart?
	for _, part in (index.Folders[folder] or {}) :: { BasePart } do
		if part.Name == name then
			return part
		end
	end
	return nil
end

-- Markers name_1, name_2, ... inside folder `folder`.
function MapMarkers.NumberedIn(index: Index, folder: string, name: string): { BasePart }
	local list: { BasePart } = {}
	local n = 1
	while true do
		local part = MapMarkers.InFolder(index, folder, `{name}_{n}`)
		if part == nil then
			break
		end
		table.insert(list, part)
		n += 1
	end
	return list
end

-- Enemy spawn points of a folder under EnemySpawns (or legacy Spawn_<folder>_n).
function MapMarkers.SpawnPoints(index: Index, folder: string): { BasePart }
	local list = index.Folders[folder]
	if list and #list > 0 then
		return list
	end
	return MapMarkers.Numbered(index, `Spawn_{folder}`)
end

-- A zone gate: Gates/<name> (a Model with a GateStyle attribute) or a Phase 2
-- door part Doors/<name>.
function MapMarkers.Gate(map: Instance, name: string): Instance?
	for _, folderName in { "Gates", "Doors" } do
		local folder = map:FindFirstChild(folderName)
		local gate = if folder then folder:FindFirstChild(name) else nil
		if gate then
			return gate
		end
	end
	return nil
end

-- Which of an activity's required markers are missing from `map` (empty = ok).
function MapMarkers.Missing(map: Instance, activity: any): { string }
	local index = MapMarkers.Index(map)
	local missing: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, need in MissionRules.Requirements(activity) do
		local ok = true
		local arena = need.Arena
		local kind: string = need.Kind
		if arena and kind == "Marker" then
			ok = MapMarkers.InFolder(index, arena, need.Name) ~= nil
		elseif arena and kind == "Numbered" then
			ok = #MapMarkers.NumberedIn(index, arena, need.Name) >= (need.Count or 1)
			if not ok then
				ok = true
				for n = 1, need.Count or 1 do
					ok = ok and map:FindFirstChild(`{need.Name}_{n}`, true) ~= nil
				end
			end
		elseif kind == "Marker" then
			ok = MapMarkers.Find(index, need.Name) ~= nil
		elseif kind == "Spawns" then
			ok = #MapMarkers.SpawnPoints(index, need.Name) > 0
		elseif kind == "Gate" then
			ok = MapMarkers.Gate(map, need.Name) ~= nil
		elseif kind == "Numbered" then
			-- Markers, or (raid plates) visible parts with those names.
			ok = #MapMarkers.Numbered(index, need.Name) >= (need.Count or 1)
			if not ok then
				ok = true
				for n = 1, need.Count or 1 do
					ok = ok and map:FindFirstChild(`{need.Name}_{n}`, true) ~= nil
				end
			end
		end
		local label = `{need.Kind} {if arena then arena .. "/" else ""}{need.Name} ({need.Where})`
		if not ok and not seen[label] then
			seen[label] = true
			table.insert(missing, label)
		end
	end
	return missing
end

return MapMarkers
