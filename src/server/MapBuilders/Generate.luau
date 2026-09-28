--!strict
--[[
	Generate
	Builds a map into Workspace from Studio's command bar so you can look at
	it, save it and hand-edit it.

	  require(game.ServerScriptService.MapBuilders.Generate)("Hub")
	  require(game.ServerScriptService.MapBuilders.Generate)("FirstLight")

	The model appears in Workspace (the hub as Workspace.Hub, activity maps
	as Workspace.<Name>) with its terrain filled in, and is selected.

	To keep a hand-edited version:
	  * Hub: leave it in Workspace named "Hub". WorldService uses an existing
	    Workspace.Hub instead of generating one.
	  * Activity map: move it to ServerStorage.Activities (keep the name).
	    WorldService only generates maps that aren't there. Its terrain comes
	    from the invisible parts in its Terrain folder (move/resize them to
	    reshape it), applied wherever each activity copy is placed.
	    Clear the preview terrain in Workspace with:
	    require(game.ServerScriptService.MapBuilders.MapKit).ClearTerrain(workspace.FirstLight)
	    (before moving it).
	Game logic only reads the Markers folder, so you can move markers freely.
]]

local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)

return function(name: string, skipTerrain: boolean?): Model?
	local module = script.Parent:FindFirstChild(`{name}Builder`)
	if module == nil or not module:IsA("ModuleScript") then
		warn(`[Generate] No MapBuilders/{name}Builder`)
		return nil
	end
	local builder = require(module) :: any
	local existing = Workspace:FindFirstChild(name)
	if existing then
		warn(`[Generate] Workspace.{name} already exists; the new copy is named {name}_New`)
	end
	local model: Model = builder.Build()
	model.Name = if existing then `{name}_New` else name
	model.Parent = Workspace
	if not skipTerrain then
		MapKit.ApplyTerrain(model)
	end
	pcall(function()
		(game:GetService("Selection") :: any):Set({ model })
	end)
	print(`[Generate] Built {model.Name}: {MapKit.CountParts(model)} parts`)
	return model
end
