--!strict
--[[
	ProjectileService
	Server-authoritative projectiles (player rockets, enemy bolts, boss orbs).

	The server simulates each projectile as a point moving in a straight line,
	raycasting every frame; the hit is decided here. Clients only draw it:
	ProjectileSpawned tells every client where it starts and how fast it
	moves, so they render a smooth local copy, and ProjectileEnded tells them
	where it stopped (and whether to show an explosion).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NetService = require(script.Parent.NetService)

export type Spec = {
	Origin: Vector3,
	Velocity: Vector3,
	MaxDistance: number,
	-- "Rocket" | "EnemyBolt" | "BossOrb" (clients pick visuals by style)
	Style: string,
	Color: Color3?,
	-- Instances the projectile passes through.
	Exclude: { Instance },
	-- Explosion radius for the end effect (0 = no explosion).
	BlastRadius: number?,
	-- Called once with the raycast result (nil if it ran out of range).
	OnHit: (result: RaycastResult?, position: Vector3) -> (),
}

type Active = {
	Spec: Spec,
	Position: Vector3,
	Traveled: number,
	Params: RaycastParams,
}

local ProjectileService = {}

local active: { [number]: Active } = {}
local nextId = 0

local function finish(id: number, projectile: Active, position: Vector3, result: RaycastResult?)
	active[id] = nil
	local radius = projectile.Spec.BlastRadius or 0
	NetService.FireAllClients("ProjectileEnded", id, position, radius)
	-- Deferred so hit handlers never add projectiles while we iterate.
	task.defer(projectile.Spec.OnHit, result, position)
end

function ProjectileService.Spawn(spec: Spec): number
	nextId += 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = spec.Exclude
	params.IgnoreWater = true
	active[nextId] = {
		Spec = spec,
		Position = spec.Origin,
		Traveled = 0,
		Params = params,
	}
	NetService.FireAllClients("ProjectileSpawned", nextId, spec.Origin, spec.Velocity, spec.Style, spec.Color)
	return nextId
end

function ProjectileService.Init() end

function ProjectileService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		for id, projectile in active do
			local step = projectile.Spec.Velocity * dt
			local result = Workspace:Raycast(projectile.Position, step, projectile.Params)
			if result then
				finish(id, projectile, result.Position, result)
			else
				projectile.Position += step
				projectile.Traveled += step.Magnitude
				if projectile.Traveled >= projectile.Spec.MaxDistance then
					finish(id, projectile, projectile.Position, nil)
				end
			end
		end
	end)
end

return ProjectileService
