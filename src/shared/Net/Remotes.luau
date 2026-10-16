--!strict
--[[
	Remotes

	The game's RemoteEvents, defined in one place. The server creates them;
	clients wait for them. Every message a client sends is validated on the
	server (see VehicleService) - never trust the client.

	VehicleAction (client -> server)
	    ("Spawn", vehicleId: string, styleKey: string?)   spawn/replace your bike (optional visual style) and get on it
	    ("Dismount")                   get off your bike
	VehicleNotice (server -> client)
	    (message: string)              short message to show the player
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local EVENTS = { "VehicleAction", "VehicleNotice" }

local Remotes = {}

local function folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		for _, name in EVENTS do
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = f
		end
		f.Parent = ReplicatedStorage
		return f
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.get(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `unknown remote {name}`)
	return folder():WaitForChild(name) :: RemoteEvent
end

return Remotes
