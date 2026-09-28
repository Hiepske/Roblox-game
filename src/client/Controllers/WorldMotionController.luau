--!strict
--[[
	WorldMotionController
	Moves decorative and gameplay parts on the client, driven by the
	server clock so every player sees the same thing:

	  LL_Mover   elevators and moving platforms (MapKit.Mover). They travel
	             between their position and position + MoveOffset, waiting
	             MoveDwell seconds at each end. Moving them on the client is
	             what lets riders stand on them smoothly (a character's
	             physics runs on its own client); horizontal motion is also
	             given to the part as velocity, so players are carried along.
	  LL_Spin    models rotating around SpinCenter/SpinAxis at SpinSpeed
	             degrees per second (the Lantern's rings, holograms)
	  LL_Flyer   ships flying circles around FlightCenter
	  LL_Laser   laser traps that blink (LaserPeriod, LaserOn, LaserPhase):
	             hidden while off. The server applies their damage using
	             the same timing (shared/World/Motion).

	Tags come from CollectionService, so parts that stream in later (or
	stream back in) are picked up automatically.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World"):WaitForChild("Motion"))

local WorldMotionController = {}

type Mover = { Part: BasePart, Base: CFrame, Offset: Vector3, Period: number, Dwell: number, Phase: number }
type Spinner = { Model: Model, Center: Vector3, Axis: Vector3, Speed: number, Relative: CFrame }
type Flyer = { Model: Model, Center: Vector3, Radius: number, Speed: number, Phase: number, Bob: number }

type Laser = { Part: BasePart, Period: number, On: number, Phase: number, Transparency: number }

local movers: { [BasePart]: Mover } = {}
local spinners: { [Model]: Spinner } = {}
local flyers: { [Model]: Flyer } = {}
local lasers: { [BasePart]: Laser } = {}

-- 0..1 progress along a mover's path at `time`, and its rate (per second).
local function moverProgress(mover: Mover, time: number): (number, number)
	return Motion.Progress(mover.Period, mover.Dwell, mover.Phase, time)
end

-- Exposed for tests: where a mover is at `time` (0 = base, 1 = base + offset).
WorldMotionController.MoverProgress = function(period: number, dwell: number, phase: number, time: number): number
	local progress = moverProgress({
		Part = nil :: any,
		Base = CFrame.new(),
		Offset = Vector3.zero,
		Period = period,
		Dwell = dwell,
		Phase = phase,
	}, time)
	return progress
end

local function addMover(instance: Instance)
	if not instance:IsA("BasePart") or movers[instance] then
		return
	end
	local offset = instance:GetAttribute("MoveOffset")
	if typeof(offset) ~= "Vector3" then
		return
	end
	movers[instance] = {
		Part = instance,
		Base = instance.CFrame,
		Offset = offset,
		Period = tonumber(instance:GetAttribute("MovePeriod")) or 10,
		Dwell = tonumber(instance:GetAttribute("MoveDwell")) or 0,
		Phase = tonumber(instance:GetAttribute("MovePhase")) or 0,
	}
end

local function addSpinner(instance: Instance)
	if not instance:IsA("Model") or spinners[instance] then
		return
	end
	local center = instance:GetAttribute("SpinCenter")
	local axis = instance:GetAttribute("SpinAxis")
	if typeof(center) ~= "Vector3" or typeof(axis) ~= "Vector3" then
		return
	end
	spinners[instance] = {
		Model = instance,
		Center = center,
		Axis = if axis.Magnitude > 0 then axis.Unit else Vector3.yAxis,
		Speed = math.rad(tonumber(instance:GetAttribute("SpinSpeed")) or 10),
		Relative = CFrame.new(center):Inverse() * instance:GetPivot(),
	}
end

local function addFlyer(instance: Instance)
	if not instance:IsA("Model") or flyers[instance] then
		return
	end
	local center = instance:GetAttribute("FlightCenter")
	if typeof(center) ~= "Vector3" then
		return
	end
	flyers[instance] = {
		Model = instance,
		Center = center,
		Radius = tonumber(instance:GetAttribute("FlightRadius")) or 300,
		Speed = tonumber(instance:GetAttribute("FlightSpeed")) or 0.05,
		Phase = tonumber(instance:GetAttribute("FlightPhase")) or 0,
		Bob = (tonumber(instance:GetAttribute("FlightPhase")) or 0) * 1.7,
	}
end

local function addLaser(instance: Instance)
	if not instance:IsA("BasePart") or lasers[instance] then
		return
	end
	local period = tonumber(instance:GetAttribute("LaserPeriod")) or 0
	if period <= 0 then
		return -- always on
	end
	lasers[instance] = {
		Part = instance,
		Period = period,
		On = tonumber(instance:GetAttribute("LaserOn")) or 0.5,
		Phase = tonumber(instance:GetAttribute("LaserPhase")) or 0,
		Transparency = instance.Transparency,
	}
end

local function watch(tag: string, add: (Instance) -> (), remove: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
end

function WorldMotionController.Init() end

function WorldMotionController.Start()
	watch("LL_Mover", addMover, function(instance)
		movers[instance :: any] = nil
	end)
	watch("LL_Spin", addSpinner, function(instance)
		spinners[instance :: any] = nil
	end)
	watch("LL_Flyer", addFlyer, function(instance)
		flyers[instance :: any] = nil
	end)
	watch("LL_Laser", addLaser, function(instance)
		lasers[instance :: any] = nil
	end)

	-- Movers update before physics so riders are carried this frame.
	RunService.PreSimulation:Connect(function()
		local time = Workspace:GetServerTimeNow()
		for part, mover in movers do
			if part.Parent == nil then
				movers[part] = nil
			else
				local progress, rate = moverProgress(mover, time)
				part.CFrame = mover.Base + mover.Offset * progress
				local velocity = mover.Offset * rate
				part.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local time = Workspace:GetServerTimeNow()
		for part, laser in lasers do
			if part.Parent == nil then
				lasers[part] = nil
			else
				part.Transparency = if Motion.LaserOn(laser.Period, laser.On, laser.Phase, time)
					then laser.Transparency
					else 1
			end
		end
		for model, spinner in spinners do
			if model.Parent == nil then
				spinners[model] = nil
			else
				local rotation = CFrame.fromAxisAngle(spinner.Axis, (time * spinner.Speed) % (math.pi * 2))
				model:PivotTo(CFrame.new(spinner.Center) * rotation * spinner.Relative)
			end
		end
		for model, flyer in flyers do
			if model.Parent == nil then
				flyers[model] = nil
			else
				local angle = flyer.Phase + time * flyer.Speed
				local position = flyer.Center
					+ Vector3.new(
						math.cos(angle) * flyer.Radius,
						math.sin(time * 0.3 + flyer.Bob) * 6,
						math.sin(angle) * flyer.Radius
					)
				local direction = if flyer.Speed >= 0
					then Vector3.new(-math.sin(angle), 0, math.cos(angle))
					else Vector3.new(math.sin(angle), 0, -math.cos(angle))
				local bank = CFrame.Angles(0, 0, if flyer.Speed >= 0 then -0.25 else 0.25)
				model:PivotTo(CFrame.lookAt(position, position + direction) * bank)
			end
		end
	end)
end

return WorldMotionController
