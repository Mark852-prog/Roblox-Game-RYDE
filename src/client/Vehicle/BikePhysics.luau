--!strict
--[[
	BikePhysics

	Runs on the RIDER'S client only (the server gives the rider network
	ownership of the bike, so this machine simulates it and Roblox
	replicates the result to everyone else).

	Model: one rigid body (the Chassis box) driven by forces:
	  * Suspension: spring + damper per wheel, from a tyre-sized sphere cast
	    (WheelProbe). Applied at the contact patch along the bike's up axis.
	  * Longitudinal tyre force (drive, brakes, rolling resistance) at the
	    contact patch. Because these act below the centre of mass, hard
	    acceleration lifts the front (wheelie) and hard front braking lifts
	    the rear (stoppie) - the physics does it, not an animation.
	  * Lateral tyre force at centre-of-mass height above each contact patch
	    (produces turning without tipping the body over).
	  * Each tyre's combined force is limited by load x surface grip
	    (friction circle), so tyres can spin, slide and lock.
	  * Rider weight shift (lean back/forward) as a pitch torque.
	  * Balance: a roll controller keeps the body upright the way a rider
	    balances a real bike; the visible lean is drawn by BikeVisuals.
	    In the air it is weak, so a bad take-off stays bad.

	All forces use VectorForce / Torque constraints created locally on this
	client (create.roblox.com/docs/physics/mover-constraints). They are
	recomputed every frame in RunService.PreSimulation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SurfaceConfig = require(Shared.Config.SurfaceConfig)
local VehicleMath = require(Shared.Vehicle.VehicleMath)
local WheelProbe = require(Shared.Vehicle.WheelProbe)

-- How strongly each tyre cancels sideways sliding per frame (0..1).
local LATERAL_STIFFNESS = 0.75
-- Ground roll controller: natural frequency (Hz) and damping ratio.
local ROLL_HZ_GROUND = 2.2
local ROLL_DAMPING = 0.9
-- Air controls.
local AIR_PITCH_ACCEL = 7 -- rad/s^2 at full input and pitchControl = 1
local AIR_ROLL_HZ = 0.5
-- Safety: never apply more than this many g of force on any one constraint.
local MAX_G = 12

export type Input = {
	throttle: number, -- 0..1
	brake: number, -- 0..1 (both brakes, mostly rear)
	frontBrake: number, -- 0..1 (front only; stoppies)
	steer: number, -- -1 (left) .. 1 (right)
	lean: number, -- -1 (forward) .. 1 (back)
}

export type WheelState = {
	compression: number,
	grounded: boolean,
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
	airborne: boolean,
	airTime: number,
	landingImpact: number, -- studs/s of vertical speed at the last touchdown (resets after read)
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
	lastCompression: number,
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
		telemetry: Telemetry,
		wasAirborne: boolean,
		lastVerticalSpeed: number,
	},
	BikePhysics
))

local function newWheelState(): WheelState
	return { compression = 0, grounded = false, slip = 0, spin = 0, surface = "-", material = Enum.Material.Air }
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
			lastCompression = 0,
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
		telemetry = {
			speed = 0,
			throttle = 0,
			brake = 0,
			steer = 0,
			pitch = 0,
			airborne = false,
			airTime = 0,
			landingImpact = 0,
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

function BikePhysics.step(self: BikePhysics, dt: number, input: Input)
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local chassis = self.chassis
	local spec = self.spec
	local config = spec.config
	local cf = chassis.CFrame
	local mass = chassis.AssemblyMass
	local g = Workspace.Gravity
	local maxForce = mass * g * MAX_G

	local up = cf.UpVector
	local look = cf.LookVector
	local right = cf.RightVector
	local velocity = chassis.AssemblyLinearVelocity
	local angular = chassis.AssemblyAngularVelocity
	local forwardSpeed = velocity:Dot(look)
	local speed = math.abs(forwardSpeed)

	-- Throttle response (electric motors are quick, but not instant).
	local motor = config.motor
	local riseRate = 1 / math.max(motor.throttleRiseTime, 0.01)
	local fallRate = 1 / math.max(motor.throttleFallTime, 0.01)
	local targetThrottle = math.clamp(input.throttle, 0, 1)
	self.throttle = approach(self.throttle, targetThrottle, (if targetThrottle > self.throttle then riseRate else fallRate) * dt)

	-- Steering: speed-dependent lock, limited by the grip of the front surface.
	local frontGrip = SurfaceConfig.getByName(self.front.state.surface).grip
	if self.front.state.surface == "-" then
		frontGrip = 1
	end
	local steerLimit = VehicleMath.maxSteer(spec, speed, frontGrip * config.tires.lateralGrip)
	local steerTarget = math.clamp(input.steer, -1, 1) * steerLimit
	self.steer = approach(self.steer, steerTarget, math.rad(config.steering.steerRateDegPerSec) * dt)

	local frontBrakeAccel, rearBrakeAccel = VehicleMath.brakeAccels(spec, math.clamp(input.brake, 0, 1), math.clamp(input.frontBrake, 0, 1))
	local driveAccel = VehicleMath.motorAccel(spec, math.max(forwardSpeed, 0), self.throttle)
	-- Gentle regenerative braking when off the throttle.
	local regenAccel = if self.throttle < 0.05 then VehicleMath.forceToAccel(spec, motor.regenForceN) else 0

	local groundedCount = 0

	local function wheelStep(w: WheelRig)
		local ws = w.state
		local contact = WheelProbe.probe(cf, w.spec, self.params)
		ws.grounded = contact.grounded
		ws.material = contact.material

		local cornerMass = mass * w.spec.loadShare

		-- Wheel spin for visuals (free-spinning wheel keeps its last rate in the air).
		local hubVelocity = chassis:GetVelocityAtPosition(cf:PointToWorldSpace(w.spec.hubRest))

		if not contact.grounded then
			w.mainForce.Force = Vector3.zero
			w.lateralForce.Force = Vector3.zero
			ws.compression = 0
			ws.slip = 0
			ws.surface = "-"
			w.lastCompression = 0
			if not w.isFront and self.throttle > 0.1 then
				ws.spin -= self.throttle * 40 * dt
			end
			return
		end
		groundedCount += 1

		local surface = SurfaceConfig.resolve(contact.instance, contact.material)
		ws.surface = surface.name

		-- Suspension spring + damper (constants scale with mass, so tuning is in Hz).
		local omega = math.sqrt(w.spec.omegaSq)
		local k = cornerMass * w.spec.omegaSq
		local c = 2 * w.spec.dampingRatio * cornerMass * omega
		local compressionRate = (contact.compression - w.lastCompression) / dt
		w.lastCompression = contact.compression
		ws.compression = contact.compression
		local suspension = k * contact.compression + c * compressionRate
		if contact.bottomedBy > 0 then
			-- Bump stop: very stiff once the suspension runs out of travel.
			suspension += k * 12 * contact.bottomedBy + c * 2 * math.max(compressionRate, 0)
		end
		suspension = math.clamp(suspension, 0, maxForce)

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
		local longitudinal = 0
		if not w.isFront then
			longitudinal += mass * driveAccel
		end
		local resist = surface.rollingResistance * suspension
			+ mass * (if w.isFront then frontBrakeAccel else rearBrakeAccel)
		if not w.isFront then
			resist += mass * regenAccel
		end
		-- Resistive forces oppose motion but never push the bike backwards.
		local stopForce = math.abs(vLong) * cornerMass / dt
		longitudinal -= math.sign(vLong) * math.min(resist, stopForce)

		-- Lateral: cancel sideways sliding.
		local lateral = -vLat * cornerMass / dt * LATERAL_STIFFNESS

		-- Friction circle.
		local mu = surface.grip * (if w.isFront then config.tires.lateralGrip else config.tires.longitudinalGrip)
		local maxGrip = mu * suspension
		local demand = math.sqrt(longitudinal * longitudinal + lateral * lateral)
		ws.slip = if maxGrip > 0 then demand / maxGrip else 0
		if demand > maxGrip and demand > 0 then
			local scale = maxGrip / demand
			longitudinal *= scale
			lateral *= scale
		end

		-- Apply. Suspension + longitudinal at the contact patch (pitch effects),
		-- lateral at centre-of-mass height above it (no tipping torque).
		local localContact = cf:PointToObjectSpace(contact.position)
		w.contactAttachment.Position = localContact
		w.lateralAttachment.Position = Vector3.new(0, 0, localContact.Z)
		w.mainForce.Force = clampMagnitude(up * suspension + tyreForward * longitudinal, maxForce)
		w.lateralForce.Force = clampMagnitude(tyreSide * lateral, maxForce)

		-- Wheel spin: rolling, or spinning up when the rear breaks traction.
		local rollRate = hubVelocity:Dot(tyreForward) / w.spec.radius
		if not w.isFront and ws.slip > 1 and driveAccel > 0 then
			rollRate += (ws.slip - 1) * 15
		end
		if w.isFront and frontBrakeAccel > 0 and ws.slip > 1 then
			rollRate *= 0.2 -- locked front
		end
		ws.spin -= rollRate * dt
	end

	wheelStep(self.front)
	wheelStep(self.rear)

	local airborne = groundedCount == 0

	-- Aerodynamic drag at the centre of mass.
	if speed > 0.5 then
		local drag = VehicleMath.dragAccel(spec, velocity.Magnitude) * mass
		self.dragForce.Force = -velocity.Unit * drag
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
	if targetUp.Magnitude < 1e-3 then
		targetUp = up
	end
	targetUp = targetUp.Unit
	local rollError = math.asin(math.clamp(up:Cross(targetUp):Dot(look), -1, 1))
	local rollRate = angular:Dot(look)
	local rollHz = if airborne then AIR_ROLL_HZ * config.air.rollControl else ROLL_HZ_GROUND
	local rollOmega = 2 * math.pi * rollHz
	local rollTorque = rollInertia * (rollOmega * rollOmega * rollError - 2 * ROLL_DAMPING * rollOmega * rollRate)

	-- Pitch: rider weight shift (both on the ground and in the air).
	local lean = math.clamp(input.lean, -1, 1)
	local pitchTorque = lean * mass * spec.riderFraction * g * spec.riderShift
	if airborne then
		pitchTorque = lean * pitchInertia * AIR_PITCH_ACCEL * config.air.pitchControl
		-- A little air damping so rotation settles once the rider stops leaning.
		pitchTorque -= pitchInertia * 0.6 * angular:Dot(right)
	end

	self.torque.Torque = clampMagnitude(look * rollTorque + right * pitchTorque, maxForce * size.Z)

	-- Telemetry -------------------------------------------------------------------
	local t = self.telemetry
	t.speed = forwardSpeed
	t.throttle = self.throttle
	t.brake = math.max(input.brake, input.frontBrake)
	t.steer = self.steer
	t.pitch = math.asin(math.clamp(look.Y, -1, 1))
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

-- Put the bike back on its wheels where it is (R key). Only the owning client can do this.
function BikePhysics.reset(self: BikePhysics)
	local chassis = self.chassis
	local position = chassis.Position
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local params = self.params
	local hit = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
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
