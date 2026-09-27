--!strict
--[[
	TableUtil
	Small, dependency-free table helpers shared by server and client.
]]

local TableUtil = {}

-- Returns a deep copy of `value`. Non-table values are returned as-is.
-- Cycles are not supported (saved data and configs never contain them).
function TableUtil.DeepCopy<T>(value: T): T
	local original: any = value
	if type(original) ~= "table" then
		return original
	end
	local copy = {}
	for key, child in original do
		copy[key] = TableUtil.DeepCopy(child)
	end
	return copy :: any
end

-- Freezes `value` and every nested table so config data can't be mutated at
-- runtime by accident. Returns the same table for convenient `return` usage.
function TableUtil.DeepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			TableUtil.DeepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

-- Fills in keys that exist in `template` but are missing from `target`,
-- recursing into nested tables. Existing values are never overwritten.
-- Used to add newly introduced fields to old saves.
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.DeepCopy(templateValue)
		elseif type(current) == "table" and type(templateValue) == "table" then
			TableUtil.Reconcile(current, templateValue)
		end
	end
end

function TableUtil.DeepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not TableUtil.DeepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function TableUtil.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.Keys<K>(t: { [K]: any }): { K }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	return keys
end

-- Reads a nested value, e.g. GetPath(data, { "Currencies", "Quanta" }).
function TableUtil.GetPath(root: any, path: { string }): any
	local node = root
	for _, key in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

-- Writes a nested value, creating intermediate tables. A nil value deletes.
-- An empty path is a no-op (use a whole-table replacement instead).
function TableUtil.SetPath(root: { [string]: any }, path: { string }, value: any)
	local count = #path
	if count == 0 then
		return
	end
	local node = root
	for i = 1, count - 1 do
		local key = path[i]
		local nextNode = node[key]
		if type(nextNode) ~= "table" then
			nextNode = {}
			node[key] = nextNode
		end
		node = nextNode
	end
	node[path[count]] = value
end

local function isFiniteNumber(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Checks that `value` can be stored in a DataStore without silent data loss:
-- no functions/Instances/userdata, no NaN/inf, no cycles, string keys or a
-- proper 1..n array, never a mix of both. Returns (ok, errorMessage).
function TableUtil.ValidateDataStoreValue(value: any, path: string?): (boolean, string?)
	local seen: { [any]: boolean } = {}

	local function check(v: any, at: string): (boolean, string?)
		local kind = type(v)
		if kind == "nil" or kind == "boolean" then
			return true, nil
		elseif kind == "number" then
			if not isFiniteNumber(v) then
				return false, `{at}: number is NaN or infinite`
			end
			return true, nil
		elseif kind == "string" then
			if utf8.len(v) == nil then
				return false, `{at}: string is not valid UTF-8`
			end
			return true, nil
		elseif kind == "table" then
			if seen[v] then
				return false, `{at}: table appears twice (cycle or shared reference)`
			end
			seen[v] = true

			local count = 0
			local hasStringKeys = false
			local hasNumberKeys = false
			for key in v do
				count += 1
				if type(key) == "string" then
					hasStringKeys = true
				elseif type(key) == "number" then
					hasNumberKeys = true
				else
					return false, `{at}: key of type {type(key)} is not allowed`
				end
			end
			if hasStringKeys and hasNumberKeys then
				return false, `{at}: table mixes array and dictionary keys`
			end
			if hasNumberKeys and #v ~= count then
				return false, `{at}: array has holes or non-integer keys`
			end
			for key, child in v do
				local ok, err = check(child, `{at}.{tostring(key)}`)
				if not ok then
					return false, err
				end
			end
			return true, nil
		end
		return false, `{at}: value of type {kind} cannot be saved`
	end

	return check(value, path or "root")
end

return TableUtil
