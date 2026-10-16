--!strict
--[[
	VehicleMath

	Pure maths for two-wheeler handling, shared by the physics controller,
	the model generator, the HUD and the unit tests. No Roblox services are
	used here, so everything can be tested outside the engine.

	derive(config) turns a real-world vehicle config into a Spec in studs:
	geometry (relative to the centre of mass), suspension constants per unit
	mass, and the numbers the controller needs every frame.

	Conventions (Roblox local space of the chassis part):
	  +X right, +Y up, -Z forward. The chassis part's centre IS the centre
	  of mass, because it is the only part with mass in the assembly.

	Forces are expressed as ACCELERATIONS (studs/s^2). The controller
	multiplies by the assembly's real mass at runtime, so these numbers are
	independent of Roblox's mass units.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Units = require(script.Parent.Parent.Util.Units)
local VehicleSchema = require(script.Parent.VehicleSchema)

type VehicleConfig = VehicleSchema.VehicleConfig

local VehicleMath = {}

local AIR_DENSITY = 1.225 -- kg/m^3

-- Share of the front brake used by the normal brake input. Kept low so a
-- normal hard stop does not throw the bike over the bars; the separate
-- front-brake input uses 100% and is how you do a stoppie.
VehicleMath.NORMAL_BRAKE_FRONT_SHARE = 0.25

-- Lateral grip usable for steering assistance (fraction of mu * g).
VehicleMath.STEER_GRIP_FRACTION = 0.85

export type WheelSpec = {
	radius: number, -- studs
	travel: number, -- studs of suspension travel
	sag: number, -- studs of static compression
	hubRest: Vector3, -- hub position at static sag (chassis local)
	mount: Vector3, -- hub position at full compression (chassis local)
	loadShare: number, -- fraction of the weight on this wheel at rest
	frequency: number, -- Hz
	dampingRatio: number,
	omegaSq: number, -- (2*pi*f)^2, spring stiffness per unit corner mass
}

export type Spec = {
	config: VehicleConfig,
	gravity: number,
	totalMassKg: number,
	riderFraction: number, -- rider mass / total mass
	wheelbase: number,
	comHeight: number,
	comFromRear: number,
	front: WheelSpec,
	rear: WheelSpec,
	boxSize: Vector3, -- collision box, centred on the centre of mass
	seatTop: Vector3, -- top of the seat (chassis local)
	topSpeed: number, -- studs/s
	riderShift: number, -- studs
}

local function wheelSpec(
	radiusM: number,
	susp: VehicleSchema.SuspensionSettings,
	forwardFromRear: number, -- studs, + forward
	comFromRear: number,
	comHeight: number,
	loadShare: number,
	gravity: number
): WheelSpec
	local radius = Units.metersToStuds(radiusM)
	local travel = Units.metersToStuds(susp.travelM)
	local omega = 2 * math.pi * susp.frequencyHz
	local omegaSq = omega * omega
	-- Static sag: spring force k*x equals the corner weight m*g  =>  x = g / omega^2
	local sag = math.min(gravity / omegaSq, travel * 0.6)
	local hubRest = Vector3.new(0, radius - comHeight, -(forwardFromRear - comFromRear))
	return {
		radius = radius,
		travel = travel,
		sag = sag,
		hubRest = hubRest,
		mount = hubRest + Vector3.new(0, travel - sag, 0),
		loadShare = loadShare,
		frequency = susp.frequencyHz,
		dampingRatio = susp.dampingRatio,
		omegaSq = omegaSq,
	}
end

function VehicleMath.derive(config: VehicleConfig, gravityStuds: number?): Spec
	local gravity = gravityStuds or Units.GRAVITY_STUDS
	local chassis = config.chassis
	local wheelbase = Units.metersToStuds(chassis.wheelbaseM)
	local comFromRear = Units.metersToStuds(chassis.comFromRearM)
	local comHeight = Units.metersToStuds(chassis.comHeightM)
	local totalMassKg = chassis.massKg + GameConfig.RIDER_MASS_KG

	-- Static weight split from the centre of mass position.
	local rearShare = (wheelbase - comFromRear) / wheelbase
	local front = wheelSpec(config.wheels.frontRadiusM, config.suspension.front, wheelbase, comFromRear, comHeight, 1 - rearShare, gravity)
	local rear = wheelSpec(config.wheels.rearRadiusM, config.suspension.rear, 0, comFromRear, comHeight, rearShare, gravity)

	-- Collision box: spans the wheels front to back, sits above the ground
	-- clearance, and is centred on the centre of mass.
	local maxRadius = math.max(front.radius, rear.radius)
	local halfLength = math.max(comFromRear + rear.radius * 0.75, (wheelbase - comFromRear) + front.radius * 0.75)
	local clearance = maxRadius * 1.15
	local halfHeight = math.max(comHeight - clearance, 0.6)
	local boxSize = Vector3.new(Units.metersToStuds(0.42), halfHeight * 2, halfLength * 2)

	-- Seat top a little behind the centre of mass. Standing vehicles get a deck instead.
	local seatHeight = if config.riderPose == "Seated" then comHeight * 1.0 else maxRadius * 1.3
	local seatTop = Vector3.new(0, seatHeight - comHeight, Units.metersToStuds(0.12))

	return {
		config = config,
		gravity = gravity,
		totalMassKg = totalMassKg,
		riderFraction = GameConfig.RIDER_MASS_KG / totalMassKg,
		wheelbase = wheelbase,
		comHeight = comHeight,
		comFromRear = comFromRear,
		front = front,
		rear = rear,
		boxSize = boxSize,
		seatTop = seatTop,
		topSpeed = Units.kmhToStudsPerSec(config.motor.topSpeedKmh),
		riderShift = Units.metersToStuds(config.wheelie.riderShiftM),
	}
end

-- Converts a real-world force on the whole vehicle (N) to an acceleration in studs/s^2.
function VehicleMath.forceToAccel(spec: Spec, newtons: number): number
	return Units.mpsToStudsPerSec(newtons / spec.totalMassKg)
end

--[[
	Drive force at the rear tyre (as acceleration, studs/s^2) for a given
	speed and throttle (0..1). Constant force at low speed, power-limited
	above, and fading to zero at the configured top speed.
]]
function VehicleMath.motorAccel(spec: Spec, speed: number, throttle: number): number
	if throttle <= 0 then
		return 0
	end
	local motor = spec.config.motor
	local mps = math.max(Units.studsPerSecToMps(math.abs(speed)), 0.5)
	local force = math.min(motor.maxDriveForceN, motor.peakPowerW / mps)
	local fadeStart = spec.topSpeed * 0.92
	if speed > fadeStart then
		force *= math.clamp((spec.topSpeed - speed) / (spec.topSpeed - fadeStart), 0, 1)
	end
	return VehicleMath.forceToAccel(spec, force * throttle)
end

-- Aerodynamic drag deceleration magnitude (studs/s^2) at a speed in studs/s.
function VehicleMath.dragAccel(spec: Spec, speed: number): number
	local mps = Units.studsPerSecToMps(speed)
	local newtons = 0.5 * AIR_DENSITY * spec.config.chassis.dragAreaM2 * mps * mps
	return VehicleMath.forceToAccel(spec, newtons)
end

-- Brake decelerations (studs/s^2) for the normal brake (0..1) and the front-brake input (0..1).
function VehicleMath.brakeAccels(spec: Spec, brake: number, frontBrake: number): (number, number)
	local brakes = spec.config.brakes
	local frontShare = math.max(brake * VehicleMath.NORMAL_BRAKE_FRONT_SHARE, frontBrake)
	return VehicleMath.forceToAccel(spec, brakes.frontMaxForceN * frontShare),
		VehicleMath.forceToAccel(spec, brakes.rearMaxForceN * brake)
end

local function smoothstep(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[
	Maximum steering angle (radians) at a speed. Blends from the low-speed
	limit to the high-speed limit, and never asks for more cornering than
	the tyres can deliver (so full lock at speed leans hard instead of
	instantly washing out the front).
]]
function VehicleMath.maxSteer(spec: Spec, speed: number, gripMu: number): number
	local steering = spec.config.steering
	local fade = smoothstep(speed / Units.kmhToStudsPerSec(steering.steerFadeSpeedKmh))
	local limitDeg = steering.maxSteerDegLowSpeed + (steering.maxSteerDegHighSpeed - steering.maxSteerDegLowSpeed) * fade
	local limit = math.rad(limitDeg)
	if speed > 1 then
		local maxLateral = VehicleMath.STEER_GRIP_FRACTION * gripMu * spec.gravity
		limit = math.min(limit, math.atan(spec.wheelbase * maxLateral / (speed * speed)))
	end
	return limit
end

-- The lean angle (radians) a rider needs for a turn: tan(lean) = v * yawRate / g.
function VehicleMath.leanAngle(spec: Spec, speed: number, yawRate: number): number
	local maxLean = math.rad(spec.config.steering.maxLeanDeg)
	return math.clamp(math.atan(speed * yawRate / spec.gravity), -maxLean, maxLean)
end

--[[
	Forward acceleration (m/s^2) above which the front wheel lifts, for a
	rider weight shift in -1 (fully forward) .. +1 (fully back).
	Balance of moments about the rear contact patch: a * h = g * Lr.
]]
function VehicleMath.wheelieThreshold(spec: Spec, lean: number): number
	local chassis = spec.config.chassis
	local lr = chassis.comFromRearM - lean * spec.config.wheelie.riderShiftM * spec.riderFraction
	return Units.GRAVITY_MPS2 * lr / chassis.comHeightM
end

-- Deceleration (m/s^2) above which the rear wheel lifts (stoppie), same lean convention.
function VehicleMath.stoppieThreshold(spec: Spec, lean: number): number
	local chassis = spec.config.chassis
	local lf = (chassis.wheelbaseM - chassis.comFromRearM) + lean * spec.config.wheelie.riderShiftM * spec.riderFraction
	return Units.GRAVITY_MPS2 * lf / chassis.comHeightM
end

return VehicleMath
