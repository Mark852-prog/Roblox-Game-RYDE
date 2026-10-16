--!strict
--[[
	Server entry point.

	Runs once when a server starts. For now it checks that the project is set
	up correctly and reports the result in the Output window. Game systems
	(vehicles, traffic, police, economy, saving) are started from here as they
	are added in later milestones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Util.Units)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)

local VehicleService = require(script.Parent.Services.VehicleService)
local WorldService = require(script.Parent.Services.WorldService)

local PREFIX = "[RYDE]"

print(`{PREFIX} Server starting - version {GameConfig.VERSION} ({GameConfig.MILESTONE})`)

local healthy = true

-- Gravity must match the unit scale used by vehicle physics.
if math.abs(Workspace.Gravity - Units.GRAVITY_STUDS) > 0.05 then
	healthy = false
	warn(
		`{PREFIX} Workspace.Gravity is {Workspace.Gravity} but the game expects {Units.GRAVITY_STUDS}. `
			.. "Vehicle physics will feel wrong. Was it changed in Game Settings > World?"
	)
end

-- Every vehicle config must be valid.
local problems = VehicleCatalog.validateAll()
if #problems > 0 then
	healthy = false
	for _, message in problems do
		warn(`{PREFIX} Vehicle config problem: {message}`)
	end
else
	print(`{PREFIX} {#VehicleCatalog.List} vehicle configs validated OK`)
end

if not Workspace:FindFirstChild("World") then
	healthy = false
	warn(`{PREFIX} Workspace.World is missing - the map did not load`)
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
local vehicleModels = assets and assets:FindFirstChild("Vehicles")
if not vehicleModels or #vehicleModels:GetChildren() == 0 then
	healthy = false
	warn(`{PREFIX} ReplicatedStorage.Assets.Vehicles is missing - no bikes can spawn`)
end

-- Start game systems.
local ok, err = pcall(WorldService.start)
if not ok then
	healthy = false
	warn(`{PREFIX} WorldService failed: {err}`)
end
VehicleService.start()

-- Clients read this to confirm they are talking to a correctly started server.
Workspace:SetAttribute("RYDEServerVersion", GameConfig.VERSION)
Workspace:SetAttribute("RYDEServerHealthy", healthy)

if healthy then
	print(`{PREFIX} Server ready - all startup checks passed`)
else
	warn(`{PREFIX} Server started WITH PROBLEMS - see the warnings above`)
end
