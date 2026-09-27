-- Builds enemy rigs (blocky fallback path) and every weapon model with Lune's
-- real Roblox Instance implementation, which rejects invalid properties.
local roblox = require("@lune/roblox")
VirtualGame.SetGlobal("Instance", roblox.Instance)
VirtualGame.Services.ServerStorage = roblox.Instance.new("Folder")
VirtualGame.Services.Players = {
	CreateHumanoidModelFromDescriptionAsync = function()
		error("not available outside Roblox")
	end,
}

local Shared = game.ReplicatedStorage.Shared
local EnemyConfig = require(Shared.Config.EnemyConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local EnemyRigs = require(game.ServerScriptService.Enemies.EnemyRigs)
local WeaponModels = require(game.ServerScriptService.Weapons.WeaponModels)

describe("Enemy rigs", function()
	for _, id in { "RUST_GUNNER", "RUST_SCRAPPER", "RANGE_DUMMY", "VEIL_HUSK", "CONC_SENTRY" } do
		it("builds " .. id, function()
			local def = EnemyConfig.ById[id]
			local model = EnemyRigs.Create(def)
			expect(model:FindFirstChildOfClass("Humanoid") ~= nil).toBe(true)
			expect(model:FindFirstChild("HumanoidRootPart") ~= nil).toBe(true)
			expect(model:FindFirstChild("Head") ~= nil).toBe(true)
			expect(model.PrimaryPart ~= nil).toBe(true)
			local eyes = 0
			for _, part in model:GetChildren() do
				if part.Name == "Eye" then
					eyes += 1
				end
			end
			expect(eyes).toBe(2)
			expect(model:GetAttribute("EnemyId")).toBe(id)
		end)
	end
end)

describe("Weapon models", function()
	it("builds a model with a grip and muzzle for every weapon", function()
		for _, weapon in WeaponConfig.List do
			local model = WeaponModels.Build(weapon.Id)
			expect(model ~= nil).toBe(true)
			expect(model.PrimaryPart ~= nil).toBe(true)
			expect(model.PrimaryPart:FindFirstChild("Muzzle") ~= nil).toBe(true)
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					expect(part.CanCollide).toBe(false)
					expect(part.CanQuery).toBe(false)
				end
			end
		end
	end)
end)
