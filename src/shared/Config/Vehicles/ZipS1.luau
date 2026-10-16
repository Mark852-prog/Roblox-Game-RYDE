--!strict
-- Zip S1: compact stand-up electric scooter with small wheels.
-- Fictional brand. Planned for Milestone 7; values are first estimates.
local VehicleSchema = require(script.Parent.Parent.Parent.Vehicle.VehicleSchema)

local config: VehicleSchema.VehicleConfig = {
	id = "ZipS1",
	displayName = "Zip S1",
	manufacturer = "Zip",
	category = "Scooter",
	status = "Planned",
	price = 2000,
	riderPose = "Standing",

	chassis = { massKg = 22, wheelbaseM = 0.95, comHeightM = 1.0, comFromRearM = 0.45 },
	wheels = { frontRadiusM = 0.127, rearRadiusM = 0.127 },
	motor = {
		peakPowerW = 1000,
		maxDriveForceN = 350,
		topSpeedKmh = 40,
		throttleRiseTime = 0.35,
		throttleFallTime = 0.2,
		regenForceN = 30,
	},
	brakes = { frontMaxForceN = 600, rearMaxForceN = 500 },
	steering = {
		maxSteerDegLowSpeed = 30,
		maxSteerDegHighSpeed = 4,
		steerFadeSpeedKmh = 35,
		steerRateDegPerSec = 200,
		maxLeanDeg = 35,
	},
	suspension = {
		front = { travelM = 0.05, frequencyHz = 3.0, dampingRatio = 0.6 },
		rear = { travelM = 0.04, frequencyHz = 3.2, dampingRatio = 0.6 },
	},
	tires = { longitudinalGrip = 0.85, lateralGrip = 0.85 },
	wheelie = { riderShiftM = 0.2, maxPitchDeg = 60 },
	air = { pitchControl = 0.35, rollControl = 0.25 },
	battery = { capacityWh = 700 },
	damage = { minorImpactKmh = 8, majorImpactKmh = 25, crashImpactKmh = 18 },
}

return config
