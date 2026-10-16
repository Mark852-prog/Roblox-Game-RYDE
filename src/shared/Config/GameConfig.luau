--!strict
--[[
	GameConfig

	Game-wide settings that are not specific to one vehicle or surface.
]]

local GameConfig = {}

GameConfig.VERSION = "0.3.0-dev"
GameConfig.MILESTONE = "Quality overhaul - physics v3 + PhysicsLab"

-- Typical rider + riding gear. Vehicle handling adds this to the bike's own mass
-- so a bike config only lists the bike itself.
GameConfig.RIDER_MASS_KG = 75

-- Show the developer HUD (physics telemetry, FPS) at start. Toggle in game with F2.
GameConfig.DEBUG_HUD_ENABLED = false

-- In Roblox Studio only: let testers ride every vehicle that has a model,
-- without buying it. Has no effect in a published game.
GameConfig.DEV_UNLOCK_ALL_IN_STUDIO = true

return GameConfig
