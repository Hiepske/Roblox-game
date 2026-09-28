-- Elevator / moving platform timing (WorldMotionController.MoverProgress).
local Proxy = VirtualGame.Proxy
VirtualGame.Services.CollectionService = {}
VirtualGame.Services.RunService = { PreSimulation = Proxy.Signal(), RenderStepped = Proxy.Signal() }
VirtualGame.Services.Workspace = {}

local WorldMotionController = require(game.StarterPlayer.StarterPlayerScripts.Controllers.WorldMotionController)
local progress = WorldMotionController.MoverProgress

describe("Moving platforms", function()
	it("waits at the bottom, rises, waits at the top and comes back", function()
		-- 30 s cycle, 4 s dwell at each end: rises during 4..15, falls 19..30.
		expect(progress(30, 4, 0, 0)).toBe(0)
		expect(progress(30, 4, 0, 3.9)).toBe(0)
		expect(progress(30, 4, 0, 9.5)).toBeNear(0.5, 1e-6)
		expect(progress(30, 4, 0, 15.5)).toBe(1)
		expect(progress(30, 4, 0, 18.9)).toBe(1)
		expect(progress(30, 4, 0, 24.5)).toBeNear(0.5, 1e-6)
		expect(progress(30, 4, 0, 29.99)).toBeNear(0, 1e-3)
	end)

	it("repeats every period and honors the phase offset", function()
		expect(progress(30, 4, 0, 9.5 + 300)).toBeNear(0.5, 1e-6)
		expect(progress(30, 4, 0.5, 0)).toBe(1)
	end)
end)
