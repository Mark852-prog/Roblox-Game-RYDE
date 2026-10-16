--!strict
--[[
	GameConfig

	Game-wide settings that are not specific to one vehicle or surface.
]]

local GameConfig = {}

GameConfig.VERSION = "0.1.0"
GameConfig.MILESTONE = "Milestone 1 - Project setup and test track"

-- Typical rider + riding gear. Vehicle handling adds this to the bike's own mass
-- so a bike config only lists the bike itself.
GameConfig.RIDER_MASS_KG = 75

-- Show the developer HUD (speed, surface, FPS). Toggle in game with F2.
GameConfig.DEBUG_HUD_ENABLED = true

return GameConfig
