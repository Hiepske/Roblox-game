--!strict
--[[
	DevCommandController
	Developer chat commands (players with debug access only: everyone in
	Studio, and the experience owner). They're TextChatCommands, so the text
	never shows up in chat; each one sends a DebugCommand to the server,
	which checks access again.

	  /setpower <n>          set every equipped item to power n
	  /give <weaponId|name>  roll a weapon/armor at your power and equip it
	  /giveall               one of every weapon (overflow in the vault)
	  /launch <activity> [difficulty]
	                         story | nightfall [adept|hero|legend] | raid
	                         (ignores unlocks)
	  /god                   toggle taking no damage
	  /resetweek             reset weekly rewards (Powerful/Pinnacle again)
	  /wipe                  wipe your save and start over at 350
	  /skip                  skip the current objective
	  /heavy                 drop a heavy ammo box
	  /kill                  die (test respawns)
	  /leave                 return to the hub
	  /help                  list the commands
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local HudController = require(script.Parent.HudController)

local DevCommandController = {}

local player = Players.LocalPlayer

type Command = { Alias: string, Server: string?, Usage: string, Run: ((args: { string }) -> ())? }

local function send(command: string, text: string?, number: number?)
	ClientNet.Fire("DebugCommand", command, text, number)
end

local commands: { Command } = {
	{
		Alias = "/setpower",
		Usage = "/setpower 480",
		Run = function(args)
			local value = tonumber(args[1])
			if value == nil then
				HudController.Toast("Usage: /setpower <number>", "Error")
				return
			end
			send("SetPower", nil, value)
		end,
	},
	{
		Alias = "/give",
		Usage = "/give W_LAST_EMBER",
		Run = function(args)
			if #args == 0 then
				HudController.Toast("Usage: /give <weaponId or name>", "Error")
				return
			end
			send("Give", table.concat(args, " "))
		end,
	},
	{
		Alias = "/launch",
		Usage = "/launch nightfall legend",
		Run = function(args)
			local activity = args[1] or ""
			local difficulty = args[2]
			send("Launch", if difficulty then `{activity}:{difficulty}` else activity)
		end,
	},
	{ Alias = "/giveall", Server = "GiveAll", Usage = "/giveall" },
	{ Alias = "/god", Server = "God", Usage = "/god" },
	{ Alias = "/resetweek", Server = "ExpireResets", Usage = "/resetweek" },
	{ Alias = "/wipe", Server = "ResetProfile", Usage = "/wipe" },
	{ Alias = "/skip", Server = "Skip", Usage = "/skip" },
	{ Alias = "/heavy", Server = "Heavy", Usage = "/heavy" },
	{ Alias = "/kill", Server = "Kill", Usage = "/kill" },
	{ Alias = "/leave", Server = "Leave", Usage = "/leave" },
}

local function help()
	local usages: { string } = {}
	for _, command in commands do
		table.insert(usages, command.Usage)
	end
	HudController.Toast("Dev: " .. table.concat(usages, "   "), "Info")
end

local function register()
	local folder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local all = table.clone(commands)
	table.insert(all, {
		Alias = "/help",
		Usage = "/help",
		Run = function(_args)
			help()
		end,
	})
	for _, command in all do
		local instance = Instance.new("TextChatCommand")
		instance.Name = "LL" .. string.sub(command.Alias, 2)
		instance.PrimaryAlias = command.Alias
		instance.Parent = folder
		instance.Triggered:Connect(function(_source: TextSource, text: string)
			local args = string.split(text, " ")
			table.remove(args, 1)
			for index = #args, 1, -1 do
				if args[index] == "" then
					table.remove(args, index)
				end
			end
			if command.Run then
				command.Run(args)
			elseif command.Server then
				send(command.Server)
			end
		end)
	end
end

function DevCommandController.Init() end

function DevCommandController.Start()
	if not player:GetAttribute("DebugAccess") then
		player:GetAttributeChangedSignal("DebugAccess"):Wait()
	end
	if not player:GetAttribute("DebugAccess") then
		return
	end
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[DevCommands] Chat commands need TextChatService.ChatVersion = TextChatService")
		return
	end
	register()
	HudController.Toast("Dev commands on. Type /help in chat.", "Info")
end

return DevCommandController
