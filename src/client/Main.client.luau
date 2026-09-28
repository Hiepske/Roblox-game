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
	require(Controllers:WaitForChild("ActivityController")) :: any,
	require(Controllers:WaitForChild("CameraController")) :: any,
	require(Controllers:WaitForChild("EffectsController")) :: any,
	require(Controllers:WaitForChild("WeaponController")) :: any,
	require(Controllers:WaitForChild("HudController")) :: any,
	require(Controllers:WaitForChild("WorldMotionController")) :: any,
	require(Controllers:WaitForChild("AreaController")) :: any,
	require(Controllers:WaitForChild("DirectorController")) :: any,
	require(Controllers:WaitForChild("CharacterScreenController")) :: any,
	require(Controllers:WaitForChild("LootController")) :: any,
	require(Controllers:WaitForChild("DevCommandController")) :: any,
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
