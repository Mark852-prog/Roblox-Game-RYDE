--!strict
--[[
	Units

	One place that defines how Roblox "studs" relate to real-world units.

	The game stores vehicle data in real-world units (metres, kilograms,
	newtons, km/h) because those are easy to compare against real bikes.
	Anything that talks to the Roblox physics engine converts through here.

	Scale: Roblox's standard units (create.roblox.com/docs/physics/units):
	  1 stud = 0.28 m, 1 RMU (mass unit) = 21.952 kg, realistic gravity = 35 studs/s^2.
	  Roblox recommends these so the game behaves as expected everywhere.

	Workspace.Gravity must equal GRAVITY_STUDS (set in default.project.json).
	The server checks this at startup and a unit test checks the project file.
]]

local Units = {}

Units.METERS_PER_STUD = 0.28
Units.STUDS_PER_METER = 1 / Units.METERS_PER_STUD

Units.GRAVITY_MPS2 = 9.81
-- Roblox's "Realistic" preset. (The engine default, 196.2, is ~5.6x real gravity.)
Units.GRAVITY_STUDS = 35

Units.KG_PER_RMU = 21.952

function Units.kgToRmu(kg: number): number
	return kg / Units.KG_PER_RMU
end

function Units.metersToStuds(meters: number): number
	return meters * Units.STUDS_PER_METER
end

function Units.studsToMeters(studs: number): number
	return studs * Units.METERS_PER_STUD
end

-- Speeds -----------------------------------------------------------------

function Units.mpsToStudsPerSec(mps: number): number
	return mps * Units.STUDS_PER_METER
end

function Units.studsPerSecToMps(studsPerSec: number): number
	return studsPerSec * Units.METERS_PER_STUD
end

function Units.kmhToStudsPerSec(kmh: number): number
	return Units.mpsToStudsPerSec(kmh / 3.6)
end

function Units.studsPerSecToKmh(studsPerSec: number): number
	return Units.studsPerSecToMps(studsPerSec) * 3.6
end

function Units.studsPerSecToMph(studsPerSec: number): number
	return Units.studsPerSecToMps(studsPerSec) * 2.236936
end

return Units
