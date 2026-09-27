--!strict
--[[
	Client bootstrap. Initializes controllers in order (Init: connect remote
	listeners, no yielding), then starts them (Start: may yield, each in its
	own thread).
]]

local Controllers = script.Parent:WaitForChild("Controllers")

type Controller = { Init: (() -> ())?, Start: (() -> ())? }

local order: { Controller } = {
	require(Controllers:WaitForChild("DataController")) :: any,
	require(Controllers:WaitForChild("DebugPanelController")) :: any,
}

for _, controller in order do
	if controller.Init then
		controller.Init()
	end
end

for _, controller in order do
	if controller.Start then
		task.spawn(controller.Start)
	end
end
