--!strict
--[[
	ClientNet
	Client side of Shared.Net.Remotes. Waits for the server-created remotes
	and enforces direction so client code can only listen to ToClient remotes
	and only fire/invoke ToServer ones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))

local ClientNet = {}

local folder: Instance? = nil

local function getRemote(name: string): Instance
	local def = Remotes.Definitions[name]
	assert(def, `Unknown remote {name}`)
	if folder == nil then
		folder = ReplicatedStorage:WaitForChild(Remotes.FolderName)
	end
	return (folder :: Instance):WaitForChild(name)
end

-- Listens to a server -> client remote.
function ClientNet.On(name: string, handler: (...any) -> ()): RBXScriptConnection
	local def = Remotes.Definitions[name]
	assert(def and def.Direction == "ToClient", `{name} is not a ToClient remote`)
	local remote = getRemote(name)
	if remote:IsA("UnreliableRemoteEvent") then
		return remote.OnClientEvent:Connect(handler)
	end
	return (remote :: RemoteEvent).OnClientEvent:Connect(handler)
end

-- Fires a client -> server event.
function ClientNet.Fire(name: string, ...: any)
	local def = Remotes.Definitions[name]
	assert(def and def.Direction == "ToServer" and def.Kind ~= "Function", `{name} is not a ToServer event`)
	local remote = getRemote(name)
	if remote:IsA("UnreliableRemoteEvent") then
		remote:FireServer(...)
	else
		(remote :: RemoteEvent):FireServer(...)
	end
end

-- Invokes a client -> server function and returns its results.
function ClientNet.Invoke(name: string, ...: any): ...any
	local def = Remotes.Definitions[name]
	assert(def and def.Kind == "Function", `{name} is not a RemoteFunction`)
	return (getRemote(name) :: RemoteFunction):InvokeServer(...)
end

return ClientNet
