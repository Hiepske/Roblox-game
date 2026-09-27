--!strict
--[[
	UIState
	Tracks which full-screen menus are open and whether the player is dead,
	so the camera and weapons know when to release the mouse and stop
	shooting. Only one menu is open at a time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local UIState = {}

local openMenu: string? = nil
local dead = false

-- Fires with the name of the open menu (nil when all menus close).
local menuChanged: Signal.Signal<string?> = Signal.new()
UIState.MenuChanged = menuChanged

function UIState.OpenMenu(name: string)
	if openMenu ~= name then
		openMenu = name
		menuChanged:Fire(name)
	end
end

function UIState.CloseMenu(name: string)
	if openMenu == name then
		openMenu = nil
		menuChanged:Fire(nil)
	end
end

function UIState.ToggleMenu(name: string)
	if openMenu == name then
		UIState.CloseMenu(name)
	else
		UIState.OpenMenu(name)
	end
end

function UIState.GetOpenMenu(): string?
	return openMenu
end

function UIState.SetDead(isDead: boolean)
	dead = isDead
end

function UIState.IsDead(): boolean
	return dead
end

-- True when gameplay input (aiming, shooting) should be ignored.
function UIState.InputBlocked(): boolean
	return openMenu ~= nil or dead
end

return UIState
