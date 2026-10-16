-- Prints a vehicle's derived physics spec as JSON (used by tools/analysis).
--   lune run tools/print-spec VoltraStorm
local process = require("@lune/process")
local serde = require("@lune/serde")
local ModuleLoader = require("../tests/lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local VehicleCatalog = ModuleLoader.require(Shared.Config.VehicleCatalog)
local VehicleMath = ModuleLoader.require(Shared.Vehicle.VehicleMath)
local Units = ModuleLoader.require(Shared.Util.Units)

local config = VehicleCatalog.get(process.args[1] or "VoltraStorm")
local spec = VehicleMath.derive(config)
local function w(x)
	return { radius = x.radius, travel = x.travel, sag = x.sag, omegaSq = x.omegaSq, dampingRatio = x.dampingRatio, loadShare = x.loadShare, hubRestY = x.hubRest.Y, hubRestZ = x.hubRest.Z, mountY = x.mount.Y }
end
local out = {
	id = config.id, gravity = spec.gravity, totalMassKg = spec.totalMassKg, riderFraction = spec.riderFraction,
	wheelbase = spec.wheelbase, comHeight = spec.comHeight, comFromRear = spec.comFromRear,
	box = { spec.boxSize.X, spec.boxSize.Y, spec.boxSize.Z }, topSpeed = spec.topSpeed, riderShift = spec.riderShift,
	front = w(spec.front), rear = w(spec.rear),
	maxDriveAccel = VehicleMath.motorAccel(spec, 0, 1), dragAt60kmh = VehicleMath.dragAccel(spec, Units.kmhToStudsPerSec(60)),
	frontBrakeFull = select(1, VehicleMath.brakeAccels(spec, 0, 1)),
	steer = { low = config.steering.maxSteerDegLowSpeed, high = config.steering.maxSteerDegHighSpeed, fade = config.steering.steerFadeSpeedKmh, rate = config.steering.steerRateDegPerSec },
}
print(serde.encode("json", out, true))
