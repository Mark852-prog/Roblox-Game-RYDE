--!strict
--[[
	VehicleCatalog

	The list of every vehicle in the game. To add a vehicle:
	  1. Copy an existing file in Config/Vehicles and change its values.
	  2. Add one line to the list below.
	  3. Run the game - the server prints any config mistakes to Output.

	Status "Planned" means the vehicle has data but no model/handling yet.
]]

local VehicleSchema = require(script.Parent.Parent.Vehicle.VehicleSchema)
local Vehicles = script.Parent.Vehicles

local VehicleCatalog = {}

-- Display order in menus.
VehicleCatalog.List = {
	require(Vehicles.VoltraStorm),
	require(Vehicles.KestrelSting),
	require(Vehicles.MetroGlide),
	require(Vehicles.ZipS1),
} :: { VehicleSchema.VehicleConfig }

VehicleCatalog.ById = {} :: { [string]: VehicleSchema.VehicleConfig }
for _, config in VehicleCatalog.List do
	VehicleCatalog.ById[config.id] = config
end

function VehicleCatalog.get(id: string): VehicleSchema.VehicleConfig?
	return VehicleCatalog.ById[id]
end

-- Returns every problem found across the catalog (empty = all good).
function VehicleCatalog.validateAll(): { string }
	local problems = {}
	local seen = {}
	for _, config in VehicleCatalog.List do
		for _, message in VehicleSchema.validate(config) do
			table.insert(problems, message)
		end
		if seen[config.id] then
			table.insert(problems, `duplicate vehicle id {config.id}`)
		end
		seen[config.id] = true
	end
	return problems
end

return VehicleCatalog
