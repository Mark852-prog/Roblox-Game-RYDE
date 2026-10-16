--!strict
-- Voltra Storm: lightweight electric dirt bike (the main prototype).
-- Fictional brand. Tuned to the light electric dirt bike class: ~57 kg, ~6 kW peak.
local VehicleSchema = require(script.Parent.Parent.Parent.Vehicle.VehicleSchema)

local config: VehicleSchema.VehicleConfig = {
	id = "VoltraStorm",
	displayName = "Light Bee X",
	manufacturer = "Sur-Ron",
	category = "ElectricDirtBike",
	status = "Prototype",
	price = 0,
	riderPose = "Seated",

	chassis = { massKg = 57, wheelbaseM = 1.26, comHeightM = 0.85, comFromRearM = 0.62, dragAreaM2 = 0.60 },
	wheels = { frontRadiusM = 0.33, rearRadiusM = 0.33 },
	motor = {
		peakPowerW = 6000,
		maxDriveForceN = 900, -- Just below the no-lean wheelie threshold: lean back to lift the front
		topSpeedKmh = 75,
		throttleRiseTime = 0.25,
		throttleFallTime = 0.15,
		regenForceN = 60,
	},
	brakes = { frontMaxForceN = 1300, rearMaxForceN = 600 },
	steering = {
		maxSteerDegLowSpeed = 35,
		maxSteerDegHighSpeed = 4,
		steerFadeSpeedKmh = 60,
		steerRateDegPerSec = 180,
		maxLeanDeg = 45,
	},
	suspension = {
		front = { travelM = 0.20, frequencyHz = 2.0, dampingRatio = 0.65 },
		rear = { travelM = 0.22, frequencyHz = 2.2, dampingRatio = 0.72 },
	},
	tires = { longitudinalGrip = 1.0, lateralGrip = 1.0 },
	wheelie = { riderShiftM = 0.25, maxPitchDeg = 75 },
	air = { pitchControl = 0.6, rollControl = 0.3 },
	battery = { capacityWh = 2000 },
	damage = { minorImpactKmh = 12, majorImpactKmh = 40, crashImpactKmh = 28 },
}

return config
