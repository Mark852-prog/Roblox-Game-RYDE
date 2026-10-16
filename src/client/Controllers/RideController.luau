--!strict
--[[
	RideController (client)

	Starts a riding session when the local character is seated on a RYDE
	bike, and ends it when they get off (for any reason). During a session:
	  * steps BikePhysics every frame with the current input,
	  * runs the chase camera (speed-sensitive field of view, mouse orbit,
	    wall avoidance, landing shake),
	  * plays the rider's wind noise and landing thumps,
	  * handles F (get off) and R (reset upright).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local SoundConfig = require(Shared.Config.SoundConfig)
local SurfaceConfig = require(Shared.Config.SurfaceConfig)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)
local VehicleMath = require(Shared.Vehicle.VehicleMath)

local Settings = require(script.Parent.Parent.Settings)
local BikePhysics = require(Shared.Vehicle.BikePhysics)
local BikeVisuals = require(script.Parent.Parent.Vehicle.BikeVisuals)
local InputController = require(script.Parent.InputController)

local VEHICLE_TAG = "RYDEVehicle"
local RESET_COOLDOWN = 2

local CAMERA_DISTANCE = 12
local CAMERA_HEIGHT = 4.5
local CAMERA_STIFFNESS = 7
local BASE_FOV = 70
local MAX_EXTRA_FOV = 20

local RideController = {}

export type Session = {
	model: Model,
	chassis: BasePart,
	spec: VehicleMath.Spec,
	physics: BikePhysics.BikePhysics,
	connections: { RBXScriptConnection },
	lastReset: number,
	camYaw: number,
	camPitch: number,
	camPosition: Vector3?,
	shake: number,
	wind: Sound,
}

local session: Session? = nil
local vehicleAction: RemoteEvent

local NEUTRAL_INPUT = { throttle = 0, brake = 0, frontBrake = 0, steer = 0, lean = 0 }
-- PhysicsLab's autopilot replaces the player's input with scripted input.
local inputOverride: (() -> any)? = nil

function RideController.setInputOverride(provider: (() -> any)?)
	inputOverride = provider
end

function RideController.getSession(): Session?
	return session
end

local function endSession()
	local s = session
	if not s then
		return
	end
	session = nil
	for _, c in s.connections do
		c:Disconnect()
	end
	s.physics:destroy()
	s.wind:Destroy()
	BikeVisuals.setLocal(nil, nil)
	InputController.unbindRiding()

	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function updateCamera(s: Session, dt: number)
	local camera = Workspace.CurrentCamera
	if not camera or Settings.menuOpen then
		return -- the menu drives the camera while it is open
	end
	if not Settings.get("chaseCamera") then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
		end
		camera.CameraSubject = s.chassis
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	-- Mouse orbit while the right button is held; drifts back behind the bike otherwise.
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		local delta = UserInputService:GetMouseDelta()
		s.camYaw -= delta.X * 0.006
		s.camPitch = math.clamp(s.camPitch - delta.Y * 0.004, -0.3, 0.9)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local decay = math.min(dt * 2, 1)
		s.camYaw -= s.camYaw * decay
		s.camPitch -= (s.camPitch - 0.12) * decay
	end

	local chassisCF = s.chassis.CFrame
	local look = chassisCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.2 then
		flat = Vector3.new(0, 0, -1)
	end
	local yawCF = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(0, s.camYaw, 0) * CFrame.Angles(-s.camPitch, 0, 0)
	local target = chassisCF.Position + Vector3.new(0, CAMERA_HEIGHT * 0.55, 0)
	local desired = target + yawCF:VectorToWorldSpace(Vector3.new(0, CAMERA_HEIGHT * 0.45, CAMERA_DISTANCE))

	-- Keep the camera out of walls.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { s.model }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(target, desired - target, params)
	if hit then
		desired = hit.Position + hit.Normal * 0.8
	end

	local alpha = 1 - math.exp(-CAMERA_STIFFNESS * dt)
	local current = s.camPosition or desired
	current = current:Lerp(desired, alpha)
	s.camPosition = current

	local shakeOffset = Vector3.zero
	if s.shake > 0.01 then
		shakeOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * s.shake
		s.shake *= math.exp(-10 * dt)
	end

	camera.CFrame = CFrame.lookAt(current + shakeOffset, target + flat.Unit * 3)
	local speedFrac = math.clamp(math.abs(s.physics.telemetry.speed) / s.spec.topSpeed, 0, 1)
	local fov = BASE_FOV + MAX_EXTRA_FOV * speedFrac * speedFrac
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(dt * 3, 1)
end

local function startSession(model: Model)
	endSession()
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	local config = VehicleCatalog.get(model:GetAttribute("VehicleId") :: string? or "")
	if not chassis or not config then
		return
	end
	local spec = VehicleMath.derive(config, Workspace.Gravity)
	local exclude: { Instance } = { model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local physics = BikePhysics.new(model, spec, exclude)
	physics:setWheelieAssist(Settings.get("wheelieAssist"))

	local wind = Instance.new("Sound")
	wind.Name = "RYDE_Wind"
	wind.SoundId = SoundConfig.assetUri(SoundConfig.Sounds.Wind.id)
	wind.Looped = true
	wind.Volume = 0
	wind.SoundGroup = SoundService:FindFirstChild("Vehicles") :: SoundGroup?
	wind.Parent = SoundService
	wind:Play()

	local s: Session = {
		model = model,
		chassis = chassis,
		spec = spec,
		physics = physics,
		connections = {},
		lastReset = 0,
		camYaw = 0,
		camPitch = 0.12,
		camPosition = nil,
		shake = 0,
		wind = wind,
	}
	session = s
	BikeVisuals.setLocal(model, physics)

	InputController.bindRiding(function()
		vehicleAction:FireServer("Dismount")
	end, function()
		local now = os.clock()
		if now - s.lastReset > RESET_COOLDOWN then
			s.lastReset = now
			physics:reset()
		end
	end)

	table.insert(
		s.connections,
		RunService.PreSimulation:Connect(function(dt)
			if not chassis.Parent then
				endSession()
				return
			end
			local input = if Settings.menuOpen then NEUTRAL_INPUT else (inputOverride or InputController.read)()
			physics:setWheelieAssist(Settings.get("wheelieAssist"))
			physics:step(dt, input)

			local t = physics.telemetry
			if t.landingImpact > 0 then
				if t.landingImpact > 10 then
					local paved = SurfaceConfig.getByName(t.rear.surface).effect == "none"
					BikeVisuals.playLanding(model, t.landingImpact, paved)
					s.shake = math.min(t.landingImpact / 60, 0.8)
				end
				t.landingImpact = 0
			end
			local speedFrac = math.clamp(math.abs(t.speed) / spec.topSpeed, 0, 1.2)
			wind.Volume = 0.9 * speedFrac * speedFrac
			wind.PlaybackSpeed = 0.8 + 0.5 * speedFrac
		end)
	)
	table.insert(
		s.connections,
		RunService.RenderStepped:Connect(function(dt)
			updateCamera(s, dt)
		end)
	)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local seat = humanoid.SeatPart
		local model = seat and seat.Parent
		if model and model:IsA("Model") and model:HasTag(VEHICLE_TAG) then
			startSession(model)
		else
			endSession()
		end
	end)
	humanoid.Died:Connect(endSession)
end

function RideController.start()
	vehicleAction = Remotes.get("VehicleAction")
	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(endSession)
end

return RideController
