--!strict
-- Metro Glide: commuter electric bicycle (pedal-assist class).
-- Fictional brand. Planned for Milestone 7; values are first estimates.
local VehicleSchema = require(script.Parent.Parent.Parent.Vehicle.VehicleSchema)

local config: VehicleSchema.VehicleConfig = {
	id = "MetroGlide",
	displayName = "Metro Glide",
	manufacturer = "Metro",
	category = "EBike",
	status = "Planned",
	price = 3500,
	riderPose = "Seated",

	chassis = { massKg = 26, wheelbaseM = 1.12, comHeightM = 1.05, comFromRearM = 0.45, dragAreaM2 = 0.50 },
	wheels = { frontRadiusM = 0.36, rearRadiusM = 0.36 },
	motor = {
		peakPowerW = 750,
		maxDriveForceN = 220,
		topSpeedKmh = 45,
		throttleRiseTime = 0.6,
		throttleFallTime = 0.3,
		regenForceN = 10,
	},
	brakes = { frontMaxForceN = 800, rearMaxForceN = 380 },
	steering = {
		maxSteerDegLowSpeed = 30,
		maxSteerDegHighSpeed = 5,
		steerFadeSpeedKmh = 40,
		steerRateDegPerSec = 150,
		maxLeanDeg = 40,
	},
	suspension = {
		front = { travelM = 0.08, frequencyHz = 2.8, dampingRatio = 0.78 },
		rear = { travelM = 0.02, frequencyHz = 4.5, dampingRatio = 1.0 },
	},
	tires = { longitudinalGrip = 0.9, lateralGrip = 0.9 },
	wheelie = { riderShiftM = 0.2, maxPitchDeg = 70 },
	air = { pitchControl = 0.4, rollControl = 0.25 },
	battery = { capacityWh = 600 },
	damage = { minorImpactKmh = 10, majorImpactKmh = 30, crashImpactKmh = 22 },
}

return config
