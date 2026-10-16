--!strict
--[[
	Client entry point.

	Runs once for each player when they join. Starts client-side systems:
	input, camera and UI. Gameplay decisions stay on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local DebugHud = require(script.Parent.UI.DebugHud)

print(`[RYDE] Client starting - version {GameConfig.VERSION}`)

DebugHud.start(GameConfig.DEBUG_HUD_ENABLED)
