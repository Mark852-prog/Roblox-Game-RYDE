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

-- PhysicsLab is a separate test place (physicslab.project.json) sharing this code.
local isLab = Workspace:GetAttribute("RYDE_Lab") == true
local mapName = if isLab then "PhysicsLab" else "World"
if not Workspace:FindFirstChild(mapName) then
	healthy = false
	warn(`{PREFIX} Workspace.{mapName} is missing - the map did not load`)
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
local vehicleModels = assets and assets:FindFirstChild("Vehicles")
if not vehicleModels or #vehicleModels:GetChildren() == 0 then
	healthy = false
	warn(`{PREFIX} ReplicatedStorage.Assets.Vehicles is missing - no bikes can spawn`)
end

-- Start game systems.
if not isLab then
	local ok, err = pcall(WorldService.start)
	if not ok then
		healthy = false
		warn(`{PREFIX} WorldService failed: {err}`)
	end
end
VehicleService.start()

if isLab then
	-- In the lab everyone gets the starter bike as soon as they spawn.
	local Players = game:GetService("Players")
	local function onCharacter(player: Player)
		task.wait(1)
		VehicleService.spawnAndMount(player, "VoltraStorm")
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(onCharacter, player)
		end
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end
	print(`{PREFIX} PhysicsLab mode`)
end

-- Clients read this to confirm they are talking to a correctly started server.
Workspace:SetAttribute("RYDEServerVersion", GameConfig.VERSION)
Workspace:SetAttribute("RYDEServerHealthy", healthy)

if healthy then
	print(`{PREFIX} Server ready - all startup checks passed`)
else
	warn(`{PREFIX} Server started WITH PROBLEMS - see the warnings above`)
end
