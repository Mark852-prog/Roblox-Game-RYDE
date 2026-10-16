--!strict
-- Kestrel Sting: heavier, more powerful electric dirt bike.
-- Fictional brand. Rideable in Studio for testing; purchasable in Milestone 7.
local VehicleSchema = require(script.Parent.Parent.Parent.Vehicle.VehicleSchema)

local config: VehicleSchema.VehicleConfig = {
	id = "KestrelSting",
	displayName = "Kestrel Sting",
	manufacturer = "Kestrel",
	category = "ElectricDirtBike",
	status = "Prototype",
	price = 12000,
	riderPose = "Seated",

	chassis = { massKg = 66, wheelbaseM = 1.30, comHeightM = 0.88, comFromRearM = 0.64, dragAreaM2 = 0.62 },
	wheels = { frontRadiusM = 0.34, rearRadiusM = 0.33 },
	motor = {
		peakPowerW = 8000,
		maxDriveForceN = 1200,
		topSpeedKmh = 85,
		throttleRiseTime = 0.22,
		throttleFallTime = 0.15,
		regenForceN = 80,
	},
	brakes = { frontMaxForceN = 1400, rearMaxForceN = 650 },
	steering = {
		maxSteerDegLowSpeed = 33,
		maxSteerDegHighSpeed = 3.5,
		steerFadeSpeedKmh = 65,
		steerRateDegPerSec = 170,
		maxLeanDeg = 45,
	},
	suspension = {
		front = { travelM = 0.21, frequencyHz = 2.1, dampingRatio = 0.65 },
		rear = { travelM = 0.23, frequencyHz = 2.3, dampingRatio = 0.72 },
	},
	tires = { longitudinalGrip = 1.05, lateralGrip = 1.0 },
	wheelie = { riderShiftM = 0.25, maxPitchDeg = 75 },
	air = { pitchControl = 0.55, rollControl = 0.3 },
	battery = { capacityWh = 2700 },
	damage = { minorImpactKmh = 13, majorImpactKmh = 42, crashImpactKmh = 30 },
}

return config
