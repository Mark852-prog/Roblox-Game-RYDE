--!strict
--[[
	BikePhysics (v3)

	Simulates one bike. Normally runs on the RIDER'S client (the server gives
	the rider network ownership, so this machine simulates the bike and
	Roblox replicates it). It only uses engine APIs that also work on the
	server, so the server can run it too (scripted test scenarios).

	Model: one rigid body (the Chassis box) driven by forces, recomputed
	every frame in RunService.PreSimulation and applied with VectorForce /
	Torque constraints (create.roblox.com/docs/physics/mover-constraints):

	  * Suspension per wheel from a tyre-sized sphere cast (WheelProbe):
	      - spring, getting stiffer over the last 40% of travel (progressive)
	      - damper driven by the hub's real velocity (frame-rate independent),
	        digressive above ~1.1 m/s like a real fork/shock (big hits are
	        not met with a wall of damping)
	      - on the frame a wheel touches down, the force is computed for where
	        the suspension will be by the end of the frame, so hard landings
	        don't bottom out on slow devices
	      - pushes along the ground normal (as a real tyre does), so a lifted
	        front wheel doesn't make the rear shove the bike backwards
	  * Tyre forces at the contact patch: drive, brakes, rolling resistance
	    (below the centre of mass -> real wheelies and stoppies), sideways
	    grip at centre-of-mass height, all limited by a friction ellipse
	    using the tyre's longitudinal and lateral grip.
	  * Rider weight shift as a pitch torque; balance roll controller
	    (weak in the air).
	  * Wheelie control ("Off", "Light", "Standard"): like electronic
	    wheelie control on real bikes - trims motor power instantly and dabs
	    the rear brake to keep the front near a target angle.
	  * Slow reverse: hold the brake while stopped.
	  * Rear-lift protection on the normal brake (the Space front brake stays
	    fully manual, for stoppies).

	Numbers were chosen with tools/analysis/bike_sim_v3.py (an offline model
	of these exact laws) and are verified in Roblox with PhysicsLab.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SurfaceConfig = require(Shared.Config.SurfaceConfig)
local VehicleMath = require(script.Parent.VehicleMath)
local WheelProbe = require(script.Parent.WheelProbe)

-- Tyres --------------------------------------------------------------------
local LATERAL_STIFFNESS = 0.75 -- fraction of sideways sliding cancelled per frame

-- Suspension -----------------------------------------------------------------
local PROGRESSIVE_START = 0.6 -- fraction of travel where the spring starts stiffening
local PROGRESSIVE_GAIN = 3.0
local BUMPSTOP_STIFFNESS = 6.0 -- x spring rate, beyond full travel
local DAMPER_KNEE = 4.0 -- studs/s; above this the damper is digressive
local DAMPER_HIGH_RATIO = 0.35 -- damping slope above the knee
local LOOKAHEAD_FRAMES = 1.5

-- Balance / air ------------------------------------------------------------------
local ROLL_HZ_GROUND = 2.2
local ROLL_DAMPING = 0.9
local AIR_PITCH_ACCEL = 7 -- rad/s^2 at full input and pitchControl = 1
local AIR_ROLL_HZ = 0.5

-- Wheelie control -------------------------------------------------------------------
export type WheelieAssist = "Off" | "Light" | "Standard"
local WHEELIE_CONTROL = {
	Light = { target = 34, kp = 0.12, kd = 0.05, brakeGain = 1.0 },
	Standard = { target = 30, kp = 0.24, kd = 0.08, brakeGain = 1.5 },
}
local WHEELIE_BASE_TRIM = 0.35

-- Reverse ------------------------------------------------------------------------------
local REVERSE_HOLD_TIME = 0.4 -- seconds of brake while stopped before reversing
local REVERSE_SPEED = 3.5 -- studs/s (~3.5 km/h)
local REVERSE_FORCE_N = 180

-- Rear-lift protection (normal brake only, like motorcycle ABS): below this
-- rear load (x bike weight) the front share of the normal brake is eased.
local REAR_LIFT_LOAD = 0.08
local REAR_LIFT_MIN_SCALE = 0.3

local MAX_G = 12 -- safety cap on any one force

export type Input = {
	throttle: number, -- 0..1
	brake: number, -- 0..1 (both brakes; also reverse when held while stopped)
	frontBrake: number, -- 0..1 (front only; stoppies)
	steer: number, -- -1 (left) .. 1 (right)
	lean: number, -- -1 (forward) .. 1 (back)
}

export type WheelState = {
	compression: number,
	grounded: boolean,
	load: number, -- suspension force in multiples of the bike's weight
	bottomed: boolean,
	slip: number, -- 0..1+ how hard the tyre is working vs. its grip
	spin: number, -- wheel rotation angle (radians), for visuals
	surface: string,
	material: Enum.Material,
}

export type Telemetry = {
	speed: number, -- forward speed, studs/s (negative = rolling back)
	throttle: number,
	brake: number,
	steer: number, -- radians, + right
	pitch: number, -- radians, + nose up
	pitchRate: number, -- rad/s, + nose rising
	airborne: boolean,
	airTime: number,
	landingImpact: number, -- vertical speed at the last touchdown (studs/s); reset by the reader
	wheelieControl: boolean, -- wheelie control is trimming power right now
	reversing: boolean,
	front: WheelState,
	rear: WheelState,
}

type WheelRig = {
	spec: VehicleMath.WheelSpec,
	isFront: boolean,
	contactAttachment: Attachment,
	lateralAttachment: Attachment,
	mainForce: VectorForce,
	lateralForce: VectorForce,
	state: WheelState,
}

local BikePhysics = {}
BikePhysics.__index = BikePhysics

export type BikePhysics = typeof(setmetatable(
	{} :: {
		model: Model,
		chassis: BasePart,
		spec: VehicleMath.Spec,
		params: RaycastParams,
		instances: { Instance },
		front: WheelRig,
		rear: WheelRig,
		dragForce: VectorForce,
		torque: Torque,
		throttle: number,
		steer: number,
		brakeHeldStopped: number,
		wheelieAssist: WheelieAssist,
		telemetry: Telemetry,
		wasAirborne: boolean,
		lastVerticalSpeed: number,
	},
	BikePhysics
))

local function newWheelState(): WheelState
	return {
		compression = 0,
		grounded = false,
		load = 0,
		bottomed = false,
		slip = 0,
		spin = 0,
		surface = "-",
		material = Enum.Material.Air,
	}
end

local function makeForce(name: string, chassis: BasePart, attachment: Attachment, atCenter: boolean): VectorForce
	local force = Instance.new("VectorForce")
	force.Name = name
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = atCenter
	force.Force = Vector3.zero
	force.Parent = chassis
	return force
end

function BikePhysics.new(model: Model, spec: VehicleMath.Spec, exclude: { Instance }): BikePhysics
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	assert(chassis, "vehicle has no Chassis")

	local instances: { Instance } = {}
	local function track<T>(inst: T): T
		table.insert(instances, inst :: any)
		return inst
	end

	local function rig(wheelSpec: VehicleMath.WheelSpec, isFront: boolean): WheelRig
		local prefix = if isFront then "RYDE_Front" else "RYDE_Rear"
		local contact = track(Instance.new("Attachment"))
		contact.Name = prefix .. "Contact"
		contact.Parent = chassis
		local lateral = track(Instance.new("Attachment"))
		lateral.Name = prefix .. "Lateral"
		lateral.Parent = chassis
		return {
			spec = wheelSpec,
			isFront = isFront,
			contactAttachment = contact,
			lateralAttachment = lateral,
			mainForce = track(makeForce(prefix .. "Force", chassis, contact, false)),
			lateralForce = track(makeForce(prefix .. "LateralForce", chassis, lateral, false)),
			state = newWheelState(),
		}
	end

	local center = track(Instance.new("Attachment"))
	center.Name = "RYDE_Center"
	center.Parent = chassis

	local torque = track(Instance.new("Torque"))
	torque.Name = "RYDE_Torque"
	torque.Attachment0 = center
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = chassis

	local self = setmetatable({
		model = model,
		chassis = chassis,
		spec = spec,
		params = WheelProbe.newParams(exclude),
		instances = instances,
		front = rig(spec.front, true),
		rear = rig(spec.rear, false),
		dragForce = track(makeForce("RYDE_Drag", chassis, center, true)),
		torque = torque,
		throttle = 0,
		steer = 0,
		brakeHeldStopped = 0,
		wheelieAssist = "Standard" :: WheelieAssist,
		telemetry = {
			speed = 0,
			throttle = 0,
			brake = 0,
			steer = 0,
			pitch = 0,
			pitchRate = 0,
			airborne = false,
			airTime = 0,
			landingImpact = 0,
			wheelieControl = false,
			reversing = false,
			front = newWheelState(),
			rear = newWheelState(),
		},
		wasAirborne = false,
		lastVerticalSpeed = 0,
	}, BikePhysics)
	self.telemetry.front = self.front.state
	self.telemetry.rear = self.rear.state
	return self
end

local function approach(current: number, target: number, maxStep: number): number
	if current < target then
		return math.min(current + maxStep, target)
	end
	return math.max(current - maxStep, target)
end

local function clampMagnitude(v: Vector3, max: number): Vector3
	local m = v.Magnitude
	if m > max and m > 0 then
		return v * (max / m)
	end
	return v
end

-- Spring + damper force for a compression and compression rate (studs, studs/s).
local function suspensionForce(spec: VehicleMath.WheelSpec, cornerMass: number, compression: number, bottomedBy: number, rate: number): number
	local k = cornerMass * spec.omegaSq
	local c = 2 * spec.dampingRatio * cornerMass * math.sqrt(spec.omegaSq)
	local force = k * compression
	local fraction = compression / spec.travel
	if fraction > PROGRESSIVE_START then
		local u = (fraction - PROGRESSIVE_START) / (1 - PROGRESSIVE_START)
		force += k * PROGRESSIVE_GAIN * u * u * (compression - PROGRESSIVE_START * spec.travel) / 3
	end
	local speed = math.abs(rate)
	local damped = if speed > DAMPER_KNEE then DAMPER_KNEE + (speed - DAMPER_KNEE) * DAMPER_HIGH_RATIO else speed
	force += c * damped * math.sign(rate)
	if bottomedBy > 0 then
		force += k * BUMPSTOP_STIFFNESS * bottomedBy + c * math.max(rate, 0)
	end
	return math.max(force, 0)
end

function BikePhysics.step(self: BikePhysics, dt: number, input: Input)
	dt = math.clamp(dt, 1 / 240, 1 / 15)
	local chassis = self.chassis
	local spec = self.spec
	local config = spec.config
	local cf = chassis.CFrame
	local mass = chassis.AssemblyMass
	local g = Workspace.Gravity
	local maxForce = mass * g * MAX_G
	local weight = mass * g

	local up = cf.UpVector
	local look = cf.LookVector
	local right = cf.RightVector
	local velocity = chassis.AssemblyLinearVelocity
	local angular = chassis.AssemblyAngularVelocity
	local forwardSpeed = velocity:Dot(look)
	local speed = math.abs(forwardSpeed)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local pitchRate = angular:Dot(right)

	local throttleInput = math.clamp(input.throttle, 0, 1)
	local brakeInput = math.clamp(input.brake, 0, 1)

	-- Reverse: hold the brake while (nearly) stopped and off the throttle.
	if brakeInput > 0.5 and throttleInput < 0.05 and forwardSpeed < 1.5 then
		self.brakeHeldStopped += dt
	else
		self.brakeHeldStopped = 0
	end
	local reversing = self.brakeHeldStopped > REVERSE_HOLD_TIME
	if reversing then
		brakeInput = 0
	end

	-- Throttle response (electric motors are quick, but not instant).
	local motor = config.motor
	local riseRate = 1 / math.max(motor.throttleRiseTime, 0.01)
	local fallRate = 1 / math.max(motor.throttleFallTime, 0.01)
	self.throttle = approach(self.throttle, throttleInput, (if throttleInput > self.throttle then riseRate else fallRate) * dt)

	-- Steering: speed-dependent lock, limited by the grip of the front surface.
	local frontGrip = if self.front.state.surface == "-" then 1 else SurfaceConfig.getByName(self.front.state.surface).grip
	local steerLimit = VehicleMath.maxSteer(spec, speed, frontGrip * config.tires.lateralGrip)
	self.steer = approach(self.steer, math.clamp(input.steer, -1, 1) * steerLimit, math.rad(config.steering.steerRateDegPerSec) * dt)

	-- Wheelie control: trims motor power instantly and dabs the rear brake.
	local frontUp = not self.front.state.grounded and self.rear.state.grounded
	local trim = 1
	local wheelieBrake = 0
	local control = WHEELIE_CONTROL[self.wheelieAssist]
	local controlActive = false
	if control and frontUp and pitch > math.rad(3) and brakeInput < 0.1 then
		controlActive = true
		local u = control.kp * (control.target - math.deg(pitch)) - control.kd * math.deg(pitchRate)
		trim = math.clamp(WHEELIE_BASE_TRIM + u, 0, 1)
		if WHEELIE_BASE_TRIM + u < 0 then
			wheelieBrake = math.min(1, -(WHEELIE_BASE_TRIM + u) * control.brakeGain)
		end
	end

	local rearLoad = if self.rear.state.grounded then self.rear.state.load else 0
	local frontScale = if rearLoad < REAR_LIFT_LOAD then math.max(REAR_LIFT_MIN_SCALE, rearLoad / REAR_LIFT_LOAD) else 1
	local frontBrakeAccel, rearBrakeAccel = VehicleMath.brakeAccels(spec, brakeInput, math.clamp(input.frontBrake, 0, 1), frontScale)
	if wheelieBrake > 0 then
		rearBrakeAccel = math.max(rearBrakeAccel, VehicleMath.forceToAccel(spec, config.brakes.rearMaxForceN * wheelieBrake))
	end
	local driveAccel = VehicleMath.motorAccel(spec, math.max(forwardSpeed, 0), self.throttle) * trim
	if reversing then
		driveAccel = if forwardSpeed > -REVERSE_SPEED then -VehicleMath.forceToAccel(spec, REVERSE_FORCE_N) else 0
	end
	local regenAccel = if self.throttle < 0.05 and not reversing then VehicleMath.forceToAccel(spec, motor.regenForceN) else 0

	-- How far to look below the wheels for ground we'll reach this frame.
	local lookAhead = math.max(-velocity:Dot(up), 0) * dt * LOOKAHEAD_FRAMES

	local groundedCount = 0

	local function wheelStep(w: WheelRig)
		local ws = w.state
		local wasGrounded = ws.grounded
		local contact = WheelProbe.probe(cf, w.spec, self.params, lookAhead)
		local cornerMass = mass * w.spec.loadShare
		local mountWorld = cf:PointToWorldSpace(w.spec.mount)
		-- Compression rate from the real velocity of the mount along the suspension axis.
		local rate = -chassis:GetVelocityAtPosition(mountWorld):Dot(up)

		local hubVelocity = chassis:GetVelocityAtPosition(cf:PointToWorldSpace(w.spec.hubRest))

		-- Touchdown this frame? (ground found by the look-ahead and closing fast enough)
		local compression = contact.compression
		local bottomedBy = contact.bottomedBy
		local touching = contact.grounded
		if not wasGrounded and rate > 0 then
			local predicted = compression - contact.gap + rate * dt
			if contact.grounded or (contact.gap < math.huge and predicted > 0) then
				touching = true
				bottomedBy += math.max(predicted - w.spec.travel, 0)
				compression = math.clamp(predicted, 0, w.spec.travel)
			end
		end

		ws.grounded = contact.grounded
		ws.material = contact.material

		if not touching then
			w.mainForce.Force = Vector3.zero
			w.lateralForce.Force = Vector3.zero
			ws.compression = 0
			ws.load = 0
			ws.bottomed = false
			ws.slip = 0
			ws.surface = "-"
			if not w.isFront and self.throttle > 0.1 then
				ws.spin -= self.throttle * 40 * dt
			end
			return
		end
		groundedCount += 1

		local surface = SurfaceConfig.resolve(contact.instance, contact.material)
		ws.surface = surface.name
		ws.compression = compression
		ws.bottomed = bottomedBy > 0

		local suspension = math.min(suspensionForce(w.spec, cornerMass, compression, bottomedBy, rate), maxForce)
		ws.load = suspension / weight

		-- Tyre frame on the ground plane.
		local n = contact.normal
		local heading = look
		if w.isFront then
			heading = CFrame.fromAxisAngle(up, -self.steer):VectorToWorldSpace(look)
		end
		local tyreForward = heading - n * heading:Dot(n)
		if tyreForward.Magnitude < 1e-3 then
			tyreForward = look
		end
		tyreForward = tyreForward.Unit
		local tyreSide = tyreForward:Cross(n).Unit

		local contactVelocity = chassis:GetVelocityAtPosition(contact.position)
		local vLong = contactVelocity:Dot(tyreForward)
		local vLat = contactVelocity:Dot(tyreSide)

		-- Longitudinal: drive (rear), brakes, regen, rolling resistance.
		local longitudinal = if w.isFront then 0 else mass * driveAccel
		local resist = surface.rollingResistance * suspension + mass * (if w.isFront then frontBrakeAccel else rearBrakeAccel + regenAccel)
		-- Resistive forces oppose motion but never push the bike backwards.
		local stopForce = math.abs(vLong) * cornerMass / dt
		longitudinal -= math.sign(vLong) * math.min(resist, stopForce)

		-- Lateral: cancel sideways sliding.
		local lateral = -vLat * cornerMass / dt * LATERAL_STIFFNESS

		-- Friction ellipse: each direction has its own grip.
		local maxLong = surface.grip * config.tires.longitudinalGrip * suspension
		local maxLat = surface.grip * config.tires.lateralGrip * suspension
		local usage = 0
		if maxLong > 0 and maxLat > 0 then
			usage = math.sqrt((longitudinal / maxLong) ^ 2 + (lateral / maxLat) ^ 2)
		end
		ws.slip = usage
		if usage > 1 then
			longitudinal /= usage
			lateral /= usage
		end

		-- Apply: suspension along the ground normal + longitudinal at the contact
		-- patch (pitch effects); lateral at centre-of-mass height (no tipping torque).
		local localContact = cf:PointToObjectSpace(contact.position)
		w.contactAttachment.Position = localContact
		w.lateralAttachment.Position = Vector3.new(0, 0, localContact.Z)
		w.mainForce.Force = clampMagnitude(n * suspension + tyreForward * longitudinal, maxForce)
		w.lateralForce.Force = clampMagnitude(tyreSide * lateral, maxForce)

		-- Wheel spin: rolling, or spinning up when the rear breaks traction.
		local rollRate = hubVelocity:Dot(tyreForward) / w.spec.radius
		if not w.isFront and usage > 1 and driveAccel > 0 then
			rollRate += (usage - 1) * 15
		end
		if w.isFront and frontBrakeAccel > 0 and usage > 1 then
			rollRate *= 0.2 -- locked front
		end
		ws.spin -= rollRate * dt
	end

	wheelStep(self.front)
	wheelStep(self.rear)

	local airborne = groundedCount == 0

	-- Aerodynamic drag at the centre of mass.
	if speed > 0.5 then
		self.dragForce.Force = -velocity.Unit * VehicleMath.dragAccel(spec, velocity.Magnitude) * mass
	else
		self.dragForce.Force = Vector3.zero
	end

	-- Torques ----------------------------------------------------------------
	local size = chassis.Size
	local rollInertia = mass * (size.X * size.X + size.Y * size.Y) / 12
	local pitchInertia = mass * (size.Y * size.Y + size.Z * size.Z) / 12

	-- Roll: keep the body upright (relative to gravity), like a balancing rider.
	local worldUp = Vector3.yAxis
	local targetUp = worldUp - look * worldUp:Dot(look)
	targetUp = if targetUp.Magnitude < 1e-3 then up else targetUp.Unit
	local rollError = math.asin(math.clamp(up:Cross(targetUp):Dot(look), -1, 1))
	local rollRate = angular:Dot(look)
	local rollOmega = 2 * math.pi * (if airborne then AIR_ROLL_HZ * config.air.rollControl else ROLL_HZ_GROUND)
	local rollTorque = rollInertia * (rollOmega * rollOmega * rollError - 2 * ROLL_DAMPING * rollOmega * rollRate)

	-- Pitch: rider weight shift (ground) or limited body control (air).
	local lean = math.clamp(input.lean, -1, 1)
	local pitchTorque
	if airborne then
		pitchTorque = lean * pitchInertia * AIR_PITCH_ACCEL * config.air.pitchControl - pitchInertia * 0.6 * pitchRate
	else
		pitchTorque = lean * mass * spec.riderFraction * g * spec.riderShift
	end

	self.torque.Torque = clampMagnitude(look * rollTorque + right * pitchTorque, maxForce * size.Z)

	-- Telemetry -------------------------------------------------------------------
	local t = self.telemetry
	t.speed = forwardSpeed
	t.throttle = self.throttle * trim
	t.brake = math.max(brakeInput, input.frontBrake, wheelieBrake)
	t.steer = self.steer
	t.pitch = pitch
	t.pitchRate = pitchRate
	t.wheelieControl = controlActive and trim < 0.99
	t.reversing = reversing
	if airborne then
		t.airTime += dt
		self.lastVerticalSpeed = velocity.Y
	elseif self.wasAirborne then
		t.landingImpact = math.max(-self.lastVerticalSpeed, 0)
		t.airTime = 0
	end
	t.airborne = airborne
	self.wasAirborne = airborne
end

function BikePhysics.setWheelieAssist(self: BikePhysics, level: WheelieAssist)
	self.wheelieAssist = level
end

-- Put the bike back on its wheels where it is (R key). Only the owning machine can do this.
function BikePhysics.reset(self: BikePhysics)
	local chassis = self.chassis
	local position = chassis.Position
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local hit = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), self.params)
	local groundY = if hit then hit.Position.Y else position.Y - self.spec.comHeight
	local target = Vector3.new(position.X, groundY + self.spec.comHeight + 0.5, position.Z)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.CFrame = CFrame.lookAt(target, target + flat.Unit)
	self.throttle = 0
end

function BikePhysics.destroy(self: BikePhysics)
	for _, inst in self.instances do
		inst:Destroy()
	end
	table.clear(self.instances)
end

return BikePhysics
