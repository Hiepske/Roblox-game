--!strict
--[[
	Gates
	Opens a zone's gate when the zone is cleared (MapKit.Gate builds them):
	  Door    the slab slides up out of the way
	  Shield  the force field fades out
	  Bridge  the ghostly bridge becomes solid and lights up
	A Phase 2 door part (Doors/<name>) simply disappears.
	Collision changes happen at once; the motion is only for show.
]]

local TweenService = game:GetService("TweenService")

local MapMarkers = require(script.Parent.MapMarkers)
local MissionKit = require(script.Parent.MissionKit)
local RunTypes = require(script.Parent.RunTypes)

type Run = RunTypes.Run

local Gates = {}

local function tween(part: BasePart, seconds: number, goal: { [string]: any })
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function partsOf(gate: Instance): { BasePart }
	local list: { BasePart } = {}
	if gate:IsA("BasePart") then
		table.insert(list, gate)
	end
	for _, descendant in gate:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- Opens gate `name` in the run's map. Returns false if the map has no such gate.
function Gates.Open(run: Run, name: string): boolean
	local gate = MapMarkers.Gate(run.Map, name)
	if gate == nil then
		return false
	end
	local parts = partsOf(gate)
	if #parts == 0 then
		return false
	end
	local style = gate:GetAttribute("GateStyle")
	local center = parts[1].Position
	if gate:IsA("BasePart") then
		gate.CanCollide = false
		gate.CanQuery = false
		gate.Transparency = 1
	elseif style == "Door" then
		local height = 0
		for _, part in parts do
			height = math.max(height, part.Size.Y)
		end
		for _, part in parts do
			part.CanCollide = false
			part.CanQuery = false
			tween(part, 1.8, { CFrame = part.CFrame + Vector3.new(0, height + 1, 0) })
		end
	elseif style == "Bridge" then
		for _, part in parts do
			part.CanCollide = true
			part.CanQuery = true
			tween(part, 1.2, { Transparency = 0 })
		end
	else
		for _, part in parts do
			part.CanCollide = false
			part.CanQuery = false
			tween(part, 0.9, { Transparency = 1 })
		end
	end
	gate:SetAttribute("Open", true)
	MissionKit.Cue(run, "GateOpen", center, style or "Door")
	return true
end

return Gates
