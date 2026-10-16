--!strict
--[[
	Client entry point.

	Runs once for each player when they join and starts the client systems
	in order. Gameplay decisions (who owns which bike, mounting, validation)
	stay on the server; the client handles input, the physics of the bike
	you are riding (you own it), camera, visuals, audio and UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local AudioController = require(script.Parent.Audio.AudioController)
local BikeVisuals = require(script.Parent.Vehicle.BikeVisuals)
local RideController = require(script.Parent.Controllers.RideController)
local DebugHud = require(script.Parent.UI.DebugHud)
local Hud = require(script.Parent.UI.Hud)
local MainMenu = require(script.Parent.UI.MainMenu)

print(`[RYDE] Client starting - version {GameConfig.VERSION}`)

AudioController.start() -- sound groups first: other systems create sounds in them
BikeVisuals.start()
RideController.start()
Hud.start(RideController, MainMenu.reopen)
DebugHud.start(GameConfig.DEBUG_HUD_ENABLED, RideController)
MainMenu.start(RideController)
