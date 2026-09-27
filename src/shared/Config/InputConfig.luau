--!strict
--[[
	InputConfig
	Default keybinds per action (KeyCode / UserInputType names) for keyboard
	and mouse, and gamepad. Players can override keyboard binds; overrides are
	saved in ProfileData.Settings.Keybinds. Touch controls are built by the
	HUD (Phase 2/10) from TouchButtons.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Actions = {
	"Fire",
	"Aim",
	"Reload",
	"Jump",
	"Sprint",
	"Crouch",
	"Interact",
	"Grenade",
	"Melee",
	"ClassAbility",
	"Super",
	"WeaponKinetic",
	"WeaponEnergy",
	"WeaponHeavy",
	"CycleWeapon",
	"CharacterScreen",
	"StarChart",
	"Emote",
	"Pause",
}

local Keyboard: { [string]: string } = {
	Fire = "MouseButton1",
	Aim = "MouseButton2",
	Reload = "R",
	Jump = "Space",
	Sprint = "LeftShift",
	Crouch = "LeftControl",
	Interact = "E",
	Grenade = "Q",
	Melee = "F",
	ClassAbility = "C",
	Super = "X",
	WeaponKinetic = "One",
	WeaponEnergy = "Two",
	WeaponHeavy = "Three",
	CycleWeapon = "Tab",
	CharacterScreen = "I",
	StarChart = "M",
	Emote = "G",
	Pause = "P",
}

-- Shared buttons (Reload/Interact, Crouch/ClassAbility) are split by tap vs
-- hold in the input controller, like most console shooters.
local Gamepad: { [string]: string } = {
	Fire = "ButtonR2",
	Aim = "ButtonL2",
	Reload = "ButtonX",
	Jump = "ButtonA",
	Sprint = "ButtonL3",
	Crouch = "ButtonB",
	Interact = "ButtonX",
	Grenade = "ButtonL1",
	Melee = "ButtonR3",
	ClassAbility = "ButtonB",
	Super = "ButtonR1",
	CycleWeapon = "ButtonY",
	CharacterScreen = "ButtonSelect",
	StarChart = "DPadUp",
	Emote = "DPadDown",
	Pause = "ButtonStart",
}

-- On-screen buttons for touch devices, in layout order (right thumb cluster).
local TouchButtons = { "Fire", "Aim", "Jump", "Reload", "Grenade", "Melee", "ClassAbility", "Super", "CycleWeapon" }

return TableUtil.DeepFreeze({
	Actions = Actions,
	Keyboard = Keyboard,
	Gamepad = Gamepad,
	TouchButtons = TouchButtons,
	-- Actions players may not rebind (menus need a guaranteed way out).
	Locked = { "Pause" },
})
