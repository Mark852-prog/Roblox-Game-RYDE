--!strict
--[[
	VehicleSchema

	Describes what every vehicle config must contain and checks configs for
	mistakes. All values are real-world units; Units converts to studs.

	validate(config) returns a list of human-readable problems (empty = valid).
	The server runs this for every vehicle at startup and prints any problems
	to the Output window, and the unit tests run it too.
]]

export type SuspensionSettings = {
	travelM: number, -- Total usable suspension travel
	frequencyHz: number, -- Natural frequency of the spring (stiffness independent of mass)
	dampingRatio: number, -- 1.0 = critically damped; bikes are usually 0.3 - 0.7
}

export type VehicleConfig = {
	id: string,
	displayName: string,
	manufacturer: string, -- Fictional brand
	category: "ElectricDirtBike" | "EBike" | "Scooter",
	status: "Prototype" | "Planned" | "Released",
	price: number, -- In-game currency; 0 = starter vehicle
	riderPose: "Seated" | "Standing",

	chassis: {
		massKg: number, -- Bike only, without rider
		wheelbaseM: number,
		comHeightM: number, -- Centre of mass height with rider aboard
		comFromRearM: number, -- Horizontal distance from rear axle to centre of mass
		dragAreaM2: number, -- Drag coefficient x frontal area (bike + rider)
	},

	wheels: {
		frontRadiusM: number,
		rearRadiusM: number,
	},

	motor: {
		peakPowerW: number,
		maxDriveForceN: number, -- Peak force at the rear contact patch (low speed)
		topSpeedKmh: number,
		throttleRiseTime: number, -- Seconds from closed to fully open throttle
		throttleFallTime: number,
		regenForceN: number, -- Gentle engine braking when off throttle
	},

	brakes: {
		frontMaxForceN: number,
		rearMaxForceN: number,
	},

	steering: {
		maxSteerDegLowSpeed: number,
		maxSteerDegHighSpeed: number,
		steerFadeSpeedKmh: number, -- Speed at which steering reaches its high-speed limit
		steerRateDegPerSec: number,
		maxLeanDeg: number,
	},

	suspension: {
		front: SuspensionSettings,
		rear: SuspensionSettings,
	},

	tires: {
		longitudinalGrip: number, -- Multiplied by the surface grip
		lateralGrip: number,
	},

	wheelie: {
		riderShiftM: number, -- How far the rider can move their weight fore/aft
		maxPitchDeg: number, -- Beyond this the bike loops out (crash)
	},

	air: {
		pitchControl: number, -- 0..1 how much the rider can rotate the bike in the air
		rollControl: number,
	},

	battery: {
		capacityWh: number,
	},

	damage: {
		minorImpactKmh: number, -- Impact speed that starts causing damage
		majorImpactKmh: number, -- Heavy component damage
		crashImpactKmh: number, -- Rider is thrown off (can be below majorImpactKmh)
	},
}

local VehicleSchema = {}

VehicleSchema.CATEGORIES = { ElectricDirtBike = true, EBike = true, Scooter = true }
VehicleSchema.STATUSES = { Prototype = true, Planned = true, Released = true }
VehicleSchema.RIDER_POSES = { Seated = true, Standing = true }

-- Allowed range for every numeric field. Wide on purpose: they catch typos
-- (e.g. 5000 kg instead of 50) rather than enforce a particular tuning.
VehicleSchema.RANGES = {
	price = { 0, 10_000_000 },
	["chassis.massKg"] = { 5, 400 },
	["chassis.wheelbaseM"] = { 0.5, 2.0 },
	["chassis.comHeightM"] = { 0.2, 1.5 },
	["chassis.comFromRearM"] = { 0.1, 1.5 },
	["chassis.dragAreaM2"] = { 0.1, 2 },
	["wheels.frontRadiusM"] = { 0.05, 0.6 },
	["wheels.rearRadiusM"] = { 0.05, 0.6 },
	["motor.peakPowerW"] = { 100, 100_000 },
	["motor.maxDriveForceN"] = { 20, 10_000 },
	["motor.topSpeedKmh"] = { 5, 250 },
	["motor.throttleRiseTime"] = { 0, 3 },
	["motor.throttleFallTime"] = { 0, 3 },
	["motor.regenForceN"] = { 0, 2_000 },
	["brakes.frontMaxForceN"] = { 10, 10_000 },
	["brakes.rearMaxForceN"] = { 10, 10_000 },
	["steering.maxSteerDegLowSpeed"] = { 1, 60 },
	["steering.maxSteerDegHighSpeed"] = { 0.5, 30 },
	["steering.steerFadeSpeedKmh"] = { 1, 200 },
	["steering.steerRateDegPerSec"] = { 10, 1000 },
	["steering.maxLeanDeg"] = { 5, 65 },
	["suspension.front.travelM"] = { 0.01, 0.5 },
	["suspension.front.frequencyHz"] = { 0.5, 6 },
	["suspension.front.dampingRatio"] = { 0.05, 2 },
	["suspension.rear.travelM"] = { 0.01, 0.5 },
	["suspension.rear.frequencyHz"] = { 0.5, 6 },
	["suspension.rear.dampingRatio"] = { 0.05, 2 },
	["tires.longitudinalGrip"] = { 0.1, 2 },
	["tires.lateralGrip"] = { 0.1, 2 },
	["wheelie.riderShiftM"] = { 0, 0.6 },
	["wheelie.maxPitchDeg"] = { 30, 120 },
	["air.pitchControl"] = { 0, 1 },
	["air.rollControl"] = { 0, 1 },
	["battery.capacityWh"] = { 50, 10_000 },
	["damage.minorImpactKmh"] = { 1, 200 },
	["damage.majorImpactKmh"] = { 1, 200 },
	["damage.crashImpactKmh"] = { 1, 200 },
}

local function getPath(config: any, path: string): any
	local value = config
	for key in string.gmatch(path, "[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[key]
	end
	return value
end

function VehicleSchema.validate(config: any): { string }
	local problems = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	if type(config) ~= "table" then
		return { "config is not a table" }
	end

	local label = if type(config.id) == "string" then config.id else "<missing id>"

	if type(config.id) ~= "string" or config.id == "" then
		problem("id must be a non-empty string")
	elseif not string.match(config.id, "^[%a][%w]*$") then
		problem(`{label}: id must be letters/digits only and start with a letter`)
	end
	if type(config.displayName) ~= "string" or config.displayName == "" then
		problem(`{label}: displayName must be a non-empty string`)
	end
	if type(config.manufacturer) ~= "string" or config.manufacturer == "" then
		problem(`{label}: manufacturer must be a non-empty string`)
	end
	if not VehicleSchema.CATEGORIES[config.category] then
		problem(`{label}: unknown category {tostring(config.category)}`)
	end
	if not VehicleSchema.STATUSES[config.status] then
		problem(`{label}: unknown status {tostring(config.status)}`)
	end
	if not VehicleSchema.RIDER_POSES[config.riderPose] then
		problem(`{label}: unknown riderPose {tostring(config.riderPose)}`)
	end

	-- Sorted so the output order is stable.
	local paths = {}
	for path in VehicleSchema.RANGES do
		table.insert(paths, path)
	end
	table.sort(paths)

	for _, path in paths do
		local range = VehicleSchema.RANGES[path]
		local value = getPath(config, path)
		if type(value) ~= "number" or value ~= value then
			problem(`{label}: {path} must be a number (got {tostring(value)})`)
		elseif value < range[1] or value > range[2] then
			problem(`{label}: {path} = {value} is outside the allowed range {range[1]}..{range[2]}`)
		end
	end

	-- Cross-field checks
	local wheelbase = getPath(config, "chassis.wheelbaseM")
	local comFromRear = getPath(config, "chassis.comFromRearM")
	if type(wheelbase) == "number" and type(comFromRear) == "number" and comFromRear >= wheelbase then
		problem(`{label}: chassis.comFromRearM must be less than chassis.wheelbaseM`)
	end

	local minor = getPath(config, "damage.minorImpactKmh")
	local major = getPath(config, "damage.majorImpactKmh")
	local crash = getPath(config, "damage.crashImpactKmh")
	if type(minor) == "number" and type(major) == "number" and type(crash) == "number" then
		if not (minor < major and minor < crash) then
			problem(`{label}: damage.minorImpactKmh must be below majorImpactKmh and crashImpactKmh`)
		end
	end

	local low = getPath(config, "steering.maxSteerDegLowSpeed")
	local high = getPath(config, "steering.maxSteerDegHighSpeed")
	if type(low) == "number" and type(high) == "number" and high > low then
		problem(`{label}: steering.maxSteerDegHighSpeed must not exceed maxSteerDegLowSpeed`)
	end

	return problems
end

return VehicleSchema
