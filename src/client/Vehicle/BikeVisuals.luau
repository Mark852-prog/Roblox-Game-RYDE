--!strict
--[[
	BikeVisuals (every client, every nearby bike)

	Presentation only - nothing here changes gameplay.

	  * Lean: rolls the bike + rider into turns (tan(lean) = v * yawRate / g).
	  * Steering, suspension travel and wheel spin via the model's Motor6D
	    joints (Motor6D.Transform is local to each client and not replicated,
	    so every client computes these from the bike's replicated motion).
	  * Brake light.
	  * Rider hands on the grips and feet on the pegs (IKControl, R15 only).
	  * 3D vehicle sounds: motor whine, tyre roll (paved / loose), skids,
	    landings.
	  * Hides the "Ride" prompt on bikes you don't own (the server enforces
	    ownership anyway).

	For the bike the local player is riding, the exact physics values are
	used (setLocal); for everyone else's bike they are estimated.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Config.SoundConfig)
local SurfaceConfig = require(Shared.Config.SurfaceConfig)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)
local VehicleMath = require(Shared.Vehicle.VehicleMath)
local WheelProbe = require(Shared.Vehicle.WheelProbe)

local BikePhysics = require(Shared.Vehicle.BikePhysics)
local VehicleEffects = require(script.Parent.VehicleEffects)

local VEHICLE_TAG = "RYDEVehicle"
local UPDATE_DISTANCE = 450
local PROBE_DISTANCE = 160
local SOUND_DISTANCE = 220
local KICKSTAND_LEAN = math.rad(-7)
local PAVED_EFFECTS = { none = true }

local BikeVisuals = {}

type Entry = {
	model: Model,
	chassis: BasePart,
	spec: VehicleMath.Spec,
	lean: Motor6D?,
	steerJoint: Motor6D?,
	frontJoint: Motor6D?,
	rearJoint: Motor6D?,
	taillight: BasePart?,
	prompt: ProximityPrompt?,
	params: RaycastParams,
	state: {
		lean: number,
		steer: number,
		frontSpin: number,
		rearSpin: number,
		frontCompression: number,
		rearCompression: number,
		lastSpeed: number,
		accel: number,
		grounded: boolean,
		lastVy: number,
	},
	sounds: { [string]: Sound },
	ik: { Instance },
	ikRiderId: number?,
	effects: VehicleEffects.VehicleEffects,
}

local entries: { [Model]: Entry } = {}
local localModel: Model? = nil
local localPhysics: BikePhysics.BikePhysics? = nil

local function findSoundGroup(name: string): SoundGroup?
	return SoundService:FindFirstChild(name) :: SoundGroup?
end

local function makeSound(parent: Instance, key: string): Sound
	local d = SoundConfig.Sounds[key]
	local s = Instance.new("Sound")
	s.Name = "RYDE_" .. key
	s.SoundId = SoundConfig.assetUri(d.id)
	s.Looped = d.looped
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = d.minDistance or 10
	s.RollOffMaxDistance = d.maxDistance or 150
	s.SoundGroup = findSoundGroup(d.group)
	s.Parent = parent
	return s
end

local function playOneShot(parent: Instance, key: string, volumeScale: number)
	local d = SoundConfig.Sounds[key]
	local s = makeSound(parent, key)
	s.Volume = d.volume * math.clamp(volumeScale, 0, 1.5)
	s.PlaybackSpeed = 0.9 + math.random() * 0.2
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(10, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function excludeList(model: Model): { Instance }
	local list: { Instance } = { model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	return list
end

local function addEntry(model: Model)
	if entries[model] or not model:IsA("Model") then
		return
	end
	local config = VehicleCatalog.get(model:GetAttribute("VehicleId") :: string? or "")
	local chassis = model:FindFirstChild("Chassis")
	if not config or not chassis or not chassis:IsA("BasePart") then
		return
	end
	local function joint(partName: string, jointName: string): Motor6D?
		local part = model:FindFirstChild(partName)
		local j = part and part:FindFirstChild(jointName)
		return if j and j:IsA("Motor6D") then j else nil
	end
	local taillight = model:FindFirstChild("Taillight")
	local promptAttachment = chassis:FindFirstChild("PromptAttachment")
	local entry: Entry = {
		model = model,
		chassis = chassis,
		spec = VehicleMath.derive(config, Workspace.Gravity),
		lean = joint("LeanRoot", "LeanJoint"),
		steerJoint = joint("SteerRoot", "SteerJoint"),
		frontJoint = joint("FrontTire", "FrontWheelJoint"),
		rearJoint = joint("RearTire", "RearWheelJoint"),
		taillight = if taillight and taillight:IsA("BasePart") then taillight else nil,
		prompt = nil,
		params = WheelProbe.newParams(excludeList(model)),
		state = {
			lean = 0,
			steer = 0,
			frontSpin = 0,
			rearSpin = 0,
			frontCompression = 0,
			rearCompression = 0,
			lastSpeed = 0,
			accel = 0,
			grounded = true,
			lastVy = 0,
		},
		sounds = {},
		ik = {},
		ikRiderId = nil,
		effects = VehicleEffects.new(chassis, VehicleMath.derive(config, Workspace.Gravity), excludeList(model)),
	}
	if promptAttachment then
		local prompt = promptAttachment:FindFirstChildOfClass("ProximityPrompt")
		entry.prompt = prompt
	end
	for _, key in { "MotorWhine", "TireRoad", "TireDirt", "TireSkid" } do
		local s = makeSound(chassis, key)
		entry.sounds[key] = s
	end
	entries[model] = entry
end

local function clearIK(entry: Entry)
	for _, inst in entry.ik do
		inst:Destroy()
	end
	table.clear(entry.ik)
	entry.ikRiderId = nil
end

local function removeEntry(model: Model)
	local entry = entries[model]
	if not entry then
		return
	end
	clearIK(entry)
	for _, s in entry.sounds do
		s:Destroy()
	end
	entry.effects:destroy()
	entries[model] = nil
end

-- Put the rider's hands on the grips and feet on the pegs.
local function updateIK(entry: Entry)
	local riderId = entry.model:GetAttribute("RiderUserId") :: number?
	if riderId == entry.ikRiderId then
		return
	end
	clearIK(entry)
	if not riderId then
		return
	end
	local player = Players:GetPlayerByUserId(riderId)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		entry.ikRiderId = riderId
		return
	end
	local bars = entry.model:FindFirstChild("Handlebar")
	local pegs = {}
	for _, d in entry.model:GetDescendants() do
		if d:IsA("Attachment") and (d.Name == "LeftPeg" or d.Name == "RightPeg") then
			pegs[d.Name] = d
		end
	end
	local function ik(root: string, effector: string, target: Instance?)
		local rootPart = character:FindFirstChild(root)
		local endPart = character:FindFirstChild(effector)
		if not rootPart or not endPart or not target then
			return
		end
		local control = Instance.new("IKControl")
		control.Name = "RYDE_IK_" .. effector
		control.Type = Enum.IKControlType.Position
		control.ChainRoot = rootPart
		control.EndEffector = endPart
		control.Target = target
		control.SmoothTime = 0.05
		control.Parent = humanoid
		table.insert(entry.ik, control)
	end
	ik("LeftUpperArm", "LeftHand", bars and bars:FindFirstChild("LeftGrip"))
	ik("RightUpperArm", "RightHand", bars and bars:FindFirstChild("RightGrip"))
	ik("LeftUpperLeg", "LeftFoot", pegs.LeftPeg)
	ik("RightUpperLeg", "RightFoot", pegs.RightPeg)
	entry.ikRiderId = riderId
end

local function update(entry: Entry, dt: number, cameraPos: Vector3)
	local chassis = entry.chassis
	local s = entry.state
	local spec = entry.spec
	local distance = (chassis.Position - cameraPos).Magnitude
	if distance > UPDATE_DISTANCE then
		for _, sound in entry.sounds do
			if sound.Playing then
				sound:Stop()
			end
		end
		return
	end

	local cf = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local speed = velocity:Dot(cf.LookVector)
	local yawRate = -chassis.AssemblyAngularVelocity:Dot(cf.UpVector) -- + = turning right
	local parked = entry.model:GetAttribute("Parked") == true
	local isLocal = entry.model == localModel and localPhysics ~= nil

	-- Acceleration estimate (for remote throttle / brake-light guesses).
	local rawAccel = (speed - s.lastSpeed) / math.max(dt, 1 / 240)
	s.lastSpeed = speed
	s.accel += (rawAccel - s.accel) * math.min(dt * 6, 1)

	local throttle, braking, slip, surfaceEffect = 0, false, 0, "none"
	local steerTarget = 0
	local frontComp, rearComp = spec.front.sag, spec.rear.sag
	local grounded = true

	if isLocal then
		local t = (localPhysics :: BikePhysics.BikePhysics).telemetry
		throttle = t.throttle
		braking = t.brake > 0.1
		slip = math.max(t.front.slip, t.rear.slip)
		steerTarget = t.steer
		frontComp, rearComp = t.front.compression, t.rear.compression
		grounded = not t.airborne
		surfaceEffect = SurfaceConfig.getByName(t.rear.surface).effect
		if t.rear.surface == "-" then
			surfaceEffect = "none"
		end
		s.frontSpin, s.rearSpin = t.front.spin, t.rear.spin
	else
		throttle = math.clamp(s.accel / 8, 0, 1)
		braking = s.accel < -6 and speed > 2
		if math.abs(speed) > 2 then
			steerTarget = math.clamp(math.atan(spec.wheelbase * yawRate / speed), -0.6, 0.6)
		end
		slip = math.clamp((math.abs(velocity:Dot(cf.RightVector)) - 5) / 6, 0, 1.5)
		if not parked and distance < PROBE_DISTANCE then
			local front = WheelProbe.probe(cf, spec.front, entry.params)
			local rear = WheelProbe.probe(cf, spec.rear, entry.params)
			frontComp, rearComp = front.compression, rear.compression
			grounded = front.grounded or rear.grounded
			if rear.grounded then
				surfaceEffect = SurfaceConfig.resolve(rear.instance, rear.material).effect
			end
			-- Landing thump for other riders' bikes.
			if grounded and not s.grounded and s.lastVy < -15 then
				playOneShot(chassis, if PAVED_EFFECTS[surfaceEffect] then "Landing" else "LandingDirt", -s.lastVy / 40)
			end
		end
		s.frontSpin -= speed / spec.front.radius * dt
		s.rearSpin -= (speed / spec.rear.radius + throttle * slip * 20) * dt
	end
	s.grounded = grounded
	s.lastVy = velocity.Y
	if distance < PROBE_DISTANCE then
		entry.effects:update(dt, {
			speed = speed,
			slip = slip,
			grounded = grounded,
			surfaceEffect = surfaceEffect,
			parked = parked,
		})
	end

	-- Lean & steer targets
	local leanTarget = 0
	if parked then
		leanTarget = KICKSTAND_LEAN
		steerTarget = math.rad(-18)
	elseif grounded then
		leanTarget = VehicleMath.leanAngle(spec, math.abs(speed), yawRate) * math.sign(speed + 0.001)
	else
		leanTarget = s.lean -- hold lean in the air
	end
	local blend = math.min(dt * 8, 1)
	s.lean += (leanTarget - s.lean) * blend
	s.steer += (steerTarget - s.steer) * math.min(dt * 14, 1)
	s.frontCompression += (frontComp - s.frontCompression) * math.min(dt * 25, 1)
	s.rearCompression += (rearComp - s.rearCompression) * math.min(dt * 25, 1)

	if entry.lean then
		entry.lean.Transform = CFrame.Angles(0, 0, -s.lean)
	end
	if entry.steerJoint then
		entry.steerJoint.Transform = CFrame.Angles(0, -s.steer, 0)
	end
	if entry.frontJoint then
		entry.frontJoint.Transform = CFrame.new(0, (s.frontCompression - spec.front.sag) / 0.9, 0) * CFrame.Angles(s.frontSpin, 0, 0)
	end
	if entry.rearJoint then
		entry.rearJoint.Transform = CFrame.new(0, s.rearCompression - spec.rear.sag, 0) * CFrame.Angles(s.rearSpin, 0, 0)
	end
	if entry.taillight then
		entry.taillight.Color = if braking then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(110, 10, 10)
	end

	-- Prompt: only the owner sees "Ride".
	local prompt = entry.prompt
	if prompt and prompt.Enabled and entry.model:GetAttribute("OwnerUserId") ~= Players.LocalPlayer.UserId then
		prompt.Enabled = false
	end

	updateIK(entry)

	-- Sounds ----------------------------------------------------------------------
	local sounds = entry.sounds
	if distance > SOUND_DISTANCE or parked then
		for _, sound in sounds do
			if sound.Playing then
				sound:Stop()
			end
		end
		return
	end
	local speedFrac = math.clamp(math.abs(speed) / spec.topSpeed, 0, 1.2)
	local defs = SoundConfig.Sounds
	local function loop(key: string, volume: number, pitch: number)
		local sound = sounds[key]
		if volume > 0.01 then
			sound.Volume = volume
			sound.PlaybackSpeed = pitch
			if not sound.Playing then
				sound:Play()
			end
		elseif sound.Playing then
			sound:Stop()
		end
	end
	local riding = entry.model:GetAttribute("RiderUserId") ~= nil
	local motorLoad = math.max(throttle, speedFrac * 0.5)
	loop("MotorWhine", if riding then defs.MotorWhine.volume * (0.15 + 0.85 * motorLoad) else 0, 0.55 + 1.15 * speedFrac + 0.2 * throttle)
	local rolling = if grounded then math.clamp(speedFrac * 1.6, 0, 1) else 0
	local paved = PAVED_EFFECTS[surfaceEffect] == true
	loop("TireRoad", if paved then defs.TireRoad.volume * rolling else 0, 0.8 + 0.5 * speedFrac)
	loop("TireDirt", if not paved then defs.TireDirt.volume * rolling else 0, 0.8 + 0.4 * speedFrac)
	loop("TireSkid", if grounded and slip > 1 and math.abs(speed) > 4 then defs.TireSkid.volume * math.clamp(slip - 1, 0.2, 1) else 0, 1)
end

-- The local player's bike: use exact physics values (and play its landings).
function BikeVisuals.setLocal(model: Model?, physics: BikePhysics.BikePhysics?)
	localModel = model
	localPhysics = physics
end

function BikeVisuals.playLanding(model: Model, impact: number, paved: boolean)
	local chassis = model:FindFirstChild("Chassis")
	if chassis then
		playOneShot(chassis, if paved then "Landing" else "LandingDirt", impact / 40)
	end
end

function BikeVisuals.start()
	for _, model in CollectionService:GetTagged(VEHICLE_TAG) do
		addEntry(model :: Model)
	end
	CollectionService:GetInstanceAddedSignal(VEHICLE_TAG):Connect(function(model)
		addEntry(model :: Model)
	end)
	CollectionService:GetInstanceRemovedSignal(VEHICLE_TAG):Connect(function(model)
		removeEntry(model :: Model)
	end)

	RunService.PreSimulation:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
		for model, entry in entries do
			if not model.Parent or not entry.chassis.Parent then
				removeEntry(model)
			else
				update(entry, dt, cameraPos)
			end
		end
	end)
end

return BikeVisuals
