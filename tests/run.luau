--[[
	Test runner: `lune run tests/run` from the repository root.
	Optional filter: `lune run tests/run Power` runs only spec files whose
	name contains "Power".
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local TestKit = require("./harness/TestKit")
local VirtualGame = require("./harness/VirtualGame")

local filter = nil
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
		break
	end
end

local specs = {}
for _, entry in fs.readDir("tests/specs") do
	if entry:match("%.spec%.luau$") and (filter == nil or entry:find(filter, 1, true)) then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, spec in specs do
	VirtualGame.ResetModules()
	local ok, err = pcall(VirtualGame.RunFile, "tests/specs/" .. spec, {
		describe = TestKit.describe,
		it = TestKit.it,
		expect = TestKit.expect,
		VirtualGame = VirtualGame,
	})
	if not ok then
		TestKit.it(spec .. " (file failed to load)", function()
			error(err)
		end)
	end
end

local results = TestKit.Results()
for _, failure in results.failures do
	print(`\nFAIL {failure.name}\n{failure.err}`)
end
print(`\n{results.passed} passed, {results.failed} failed ({#specs} spec files)`)
-- Exit explicitly: specs may leave simulated game threads waiting.
process.exit(if results.failed > 0 then 1 else 0)
