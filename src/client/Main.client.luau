--!strict
--[[
	Client entry point.

	Runs once for each player when they join and starts the client systems
	in order. Gameplay decisions (who owns which bike, mounting, validation)
	stay on the server; the client handles input, the physics of the bike
	you are riding (you own it), camera, visuals, audio and UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local AudioController = require(script.Parent.Audio.AudioController)
local BikeVisuals = require(script.Parent.Vehicle.BikeVisuals)
local RideController = require(script.Parent.Controllers.RideController)
local DebugHud = require(script.Parent.UI.DebugHud)
local Hud = require(script.Parent.UI.Hud)
local MainMenu = require(script.Parent.UI.MainMenu)

print(`[RYDE] Client starting - version {GameConfig.VERSION}`)

local isLab = Workspace:GetAttribute("RYDE_Lab") == true

AudioController.start() -- sound groups first: other systems create sounds in them
BikeVisuals.start()
RideController.start()
if isLab then
	-- PhysicsLab test place: no lobby; the lab panel drives scripted tests.
	local LabController = require(script.Parent.Lab.LabController)
	Hud.start(RideController, function() end)
	DebugHud.start(true, RideController)
	LabController.start(RideController)
else
	Hud.start(RideController, MainMenu.reopen)
	DebugHud.start(GameConfig.DEBUG_HUD_ENABLED, RideController)
	MainMenu.start(RideController)
end
