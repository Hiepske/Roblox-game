--!strict
--[[
	AreaController
	Shows the name of the area you walk into:
	  * in the hub: the Markers/Areas boxes of Workspace.Hub (DisplayName
	    attribute), e.g. "The Bazaar" under "The Spire"
	  * in an activity: the current zone (run folder attribute ZoneName),
	    under the activity's name
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ActivityController = require(script.Parent.ActivityController)
local HudController = require(script.Parent.HudController)

local AreaController = {}

local player = Players.LocalPlayer
local currentArea: string? = nil
local currentZone: string? = nil

local function inside(box: BasePart, point: Vector3): boolean
	local offset = box.CFrame:PointToObjectSpace(point)
	local half = box.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- The smallest area box containing `point` (areas can overlap).
local function hubAreaAt(point: Vector3): (string?, string?)
	local hub = Workspace:FindFirstChild("Hub")
	local markers = if hub then hub:FindFirstChild("Markers") else nil
	local areas = if markers then markers:FindFirstChild("Areas") else nil
	if areas == nil then
		return nil, nil
	end
	local best: BasePart? = nil
	local bestVolume = math.huge
	for _, box in areas:GetChildren() do
		if box:IsA("BasePart") and inside(box, point) then
			local volume = box.Size.X * box.Size.Y * box.Size.Z
			if volume < bestVolume then
				best, bestVolume = box, volume
			end
		end
	end
	if best == nil then
		return nil, nil
	end
	local display = best:GetAttribute("DisplayName")
	local hubName = if hub then hub:GetAttribute("DisplayName") else nil
	return if type(display) == "string" then display else best.Name, if type(hubName) == "string" then hubName else nil
end

local function update()
	local info = ActivityController.Get()
	if info.InActivity then
		currentArea = nil
		local folder = ActivityController.GetFolder()
		local zone = if folder then folder:GetAttribute("ZoneName") else nil
		if type(zone) == "string" and zone ~= "" and zone ~= currentZone then
			currentZone = zone
			HudController.ShowLocation(zone, info.Name)
		end
		return
	end
	currentZone = nil
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local area, subtitle = hubAreaAt(root.Position)
	if area and area ~= currentArea then
		HudController.ShowLocation(area, subtitle)
	end
	currentArea = area
end

function AreaController.Init() end

function AreaController.Start()
	while true do
		task.wait(0.3)
		local ok, err = pcall(update :: any)
		if not ok then
			warn(`[AreaController] {err}`)
		end
	end
end

return AreaController
