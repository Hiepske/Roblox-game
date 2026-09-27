--!strict
--[[
	Server bootstrap.
	1. Validates every config module (fails fast in Studio).
	2. Initializes services in dependency order (Init: create remotes,
	   connect handlers; no yielding).
	3. Starts them (Start: begin loops, hook players).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigValidator = require(ReplicatedStorage.Shared.ConfigValidator)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Services = script.Parent.Services

local problems = ConfigValidator.Validate()
if #problems > 0 then
	local message = `[Config] {#problems} problem(s):\n  ` .. table.concat(problems, "\n  ")
	if RunService:IsStudio() then
		error(message)
	end
	warn(message)
end

type Service = { Init: (() -> ())?, Start: (() -> ())? }

-- Order matters: later services may use earlier ones in Init.
local order: { { Name: string, Module: Service } } = {
	{ Name = "NetService", Module = require(Services.NetService) :: any },
	{ Name = "DataService", Module = require(Services.DataService) :: any },
	{ Name = "WorldService", Module = require(Services.WorldService) :: any },
	{ Name = "CharacterService", Module = require(Services.CharacterService) :: any },
	{ Name = "ProjectileService", Module = require(Services.ProjectileService) :: any },
	{ Name = "EnemyService", Module = require(Services.EnemyService) :: any },
	{ Name = "CombatService", Module = require(Services.CombatService) :: any },
	{ Name = "WeaponService", Module = require(Services.WeaponService) :: any },
	{ Name = "LootService", Module = require(Services.LootService) :: any },
	{ Name = "InventoryService", Module = require(Services.InventoryService) :: any },
	{ Name = "ActivityService", Module = require(Services.ActivityService) :: any },
	{ Name = "DebugService", Module = require(Services.DebugService) :: any },
}

for _, entry in order do
	local init = entry.Module.Init
	if init then
		init()
	end
end

for _, entry in order do
	local start = entry.Module.Start
	if start then
		task.spawn(start)
	end
end

print(`[{GameConfig.Title}] server v{GameConfig.Version} started`)
