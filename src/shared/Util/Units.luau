--!strict
--[[
	Units

	One place that defines how Roblox "studs" relate to real-world units.

	The game stores vehicle data in real-world units (metres, kilograms,
	newtons, km/h) because those are easy to compare against real bikes.
	Anything that talks to the Roblox physics engine converts through here.

	Scale decision: 1 stud = 0.35 m.
	  Roblox's own documentation uses 0.28 m, but the default R15 character is
	  about 5 studs tall; at 0.35 m/stud that is ~1.75 m, a typical adult, so
	  bikes built to real dimensions look correctly sized next to the rider.

	Workspace.Gravity must equal GRAVITY_STUDS (set in default.project.json).
	The server checks this at startup and a unit test checks the project file.
]]

local Units = {}

Units.METERS_PER_STUD = 0.35
Units.STUDS_PER_METER = 1 / Units.METERS_PER_STUD

Units.GRAVITY_MPS2 = 9.81
-- 9.81 / 0.35 = 28.03 studs/s^2 (Roblox's default 196.2 is ~7x real gravity at this scale).
Units.GRAVITY_STUDS = math.floor(Units.GRAVITY_MPS2 / Units.METERS_PER_STUD * 100 + 0.5) / 100

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
