--!strict
--[[
	VehicleService (server, authoritative)

	Responsibilities:
	  * Spawn one bike per player (validated: the vehicle must exist, have a
	    model, and be one the player is allowed to use).
	  * Mount / dismount. Mounting happens through the bike's ProximityPrompt
	    (handled here, on the server) or right after spawning. Only the
	    bike's owner can ride it.
	  * Network ownership: the rider's client simulates their bike
	    (responsive controls); the server takes it back when they get off.
	  * Rider state: while riding, the character is massless (the bike's
	    tuned mass already includes the rider) and in a collision group that
	    doesn't collide with the world (the bike's collision box does that).
	  * Parking: a riderless bike that has come to rest is stood upright and
	    anchored (kickstand), so it never ends up lost or stuck on its side.
	  * Sanity check: a ridden bike far above its top speed is taken back.
	  * Cleanup when players leave.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)
local VehicleMath = require(Shared.Vehicle.VehicleMath)

local VEHICLE_TAG = "RYDEVehicle"
local RIDER_GROUP = "RYDERiders"
local VEHICLE_GROUP = "RYDEVehicles"
local ACTION_COOLDOWN = 0.75 -- seconds between remote requests per player
local PARK_AFTER = 1.5 -- seconds at rest before a riderless bike is parked
local SPEED_TOLERANCE = 1.35 -- x top speed allowed before the server intervenes

local VehicleService = {}

type BikeRecord = {
	model: Model,
	chassis: BasePart,
	seat: Seat,
	prompt: ProximityPrompt,
	owner: Player,
	spec: VehicleMath.Spec,
	rider: Player?,
	restTime: number,
	overSpeedTime: number,
	savedCharacterState: { [BasePart]: { massless: boolean, group: string } }?,
}

local bikesByOwner: { [Player]: BikeRecord } = {}
local lastAction: { [Player]: number } = {}
local vehiclesFolder: Folder
local notice: RemoteEvent

local function notify(player: Player, message: string)
	notice:FireClient(player, message)
end

local function setupCollisionGroups()
	PhysicsService:RegisterCollisionGroup(RIDER_GROUP)
	PhysicsService:RegisterCollisionGroup(VEHICLE_GROUP)
	-- Riders are carried by their bike's collision box; their limbs must not
	-- snag the ground, other bikes or other riders.
	PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, RIDER_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(RIDER_GROUP, VEHICLE_GROUP, false)
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

-- Can this player use this vehicle? (Purchases arrive in Milestone 7.)
local function canUse(_player: Player, vehicleId: string): boolean
	local config = VehicleCatalog.get(vehicleId)
	if not config or config.status == "Planned" then
		return false
	end
	if config.price == 0 then
		return true
	end
	return GameConfig.DEV_UNLOCK_ALL_IN_STUDIO and RunService:IsStudio()
end

local function groundHeightAt(position: Vector3, exclude: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else position.Y
end

-- Stand the bike on its wheels at a position, facing a horizontal direction.
local function placeUpright(record: BikeRecord, position: Vector3, facing: Vector3)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local exclude: { Instance } = { vehiclesFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local y = groundHeightAt(position, exclude) + record.spec.comHeight + 0.05
	local target = Vector3.new(position.X, y, position.Z)
	record.chassis.AssemblyLinearVelocity = Vector3.zero
	record.chassis.AssemblyAngularVelocity = Vector3.zero
	record.model:PivotTo(CFrame.lookAt(target, target + flat.Unit))
end

local function park(record: BikeRecord)
	placeUpright(record, record.chassis.Position, record.chassis.CFrame.LookVector)
	record.chassis.Anchored = true
	record.model:SetAttribute("Parked", true)
end

local function unpark(record: BikeRecord)
	if record.chassis.Anchored then
		record.chassis.Anchored = false
	end
	record.model:SetAttribute("Parked", false)
	record.restTime = 0
end

local function setRiderState(record: BikeRecord, character: Model, riding: boolean)
	if riding then
		local saved = {}
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				saved[d] = { massless = d.Massless, group = d.CollisionGroup }
				d.Massless = true
				d.CollisionGroup = RIDER_GROUP
			end
		end
		record.savedCharacterState = saved
	else
		local saved = record.savedCharacterState
		if saved then
			for part, state in saved do
				if part.Parent then
					part.Massless = state.massless
					part.CollisionGroup = state.group
				end
			end
		end
		record.savedCharacterState = nil
	end
end

local function mount(record: BikeRecord, player: Player): boolean
	if record.owner ~= player then
		notify(player, "That's not your bike.")
		return false
	end
	if record.rider then
		return false
	end
	local humanoid, root = getHumanoid(player)
	if not humanoid or not root or humanoid.SeatPart then
		return false
	end

	-- Pick the bike up if it fell over, then release the kickstand.
	if record.chassis.CFrame.UpVector.Y < 0.8 then
		placeUpright(record, record.chassis.Position, record.chassis.CFrame.LookVector)
	end
	unpark(record)

	setRiderState(record, player.Character :: Model, true)
	root.CFrame = record.seat.CFrame * CFrame.new(0, 3, 0)
	record.seat:Sit(humanoid)
	local deadline = os.clock() + 1
	while record.seat.Occupant ~= humanoid and os.clock() < deadline do
		task.wait()
	end
	if record.seat.Occupant ~= humanoid then
		setRiderState(record, player.Character :: Model, false)
		return false
	end

	record.rider = player
	record.prompt.Enabled = false
	record.model:SetAttribute("RiderUserId", player.UserId)
	local ok, err = pcall(function()
		record.chassis:SetNetworkOwner(player)
	end)
	if not ok then
		warn(`[RYDE] Could not give {player.Name} ownership of their bike: {err}`)
	end
	return true
end

-- Called whenever the seat's occupant changes to nobody (dismount request,
-- jump-off, death, reset, or the character being removed).
local function onRiderLeft(record: BikeRecord)
	local player = record.rider
	if not player then
		return
	end
	record.rider = nil
	record.model:SetAttribute("RiderUserId", nil)
	record.prompt.Enabled = true

	local character = player.Character
	if character then
		setRiderState(record, character, false)
		-- Step the rider off to the left of the bike, keeping their momentum.
		local _, root = getHumanoid(player)
		if root then
			local side = record.chassis.CFrame * CFrame.new(-3, 0.5, 0)
			root.CFrame = CFrame.lookAt(side.Position, side.Position + record.chassis.CFrame.LookVector)
			root.AssemblyLinearVelocity = record.chassis.AssemblyLinearVelocity
		end
	else
		record.savedCharacterState = nil
	end

	if record.chassis.Parent then
		if not record.chassis.Anchored then
			pcall(function()
				record.chassis:SetNetworkOwner(nil)
			end)
		end
		-- Stepping off a (nearly) stopped bike: put it straight on its kickstand.
		if record.chassis.AssemblyLinearVelocity.Magnitude < 4 then
			park(record)
		end
	end
	record.restTime = 0
end

local function dismount(player: Player)
	local record = bikesByOwner[player]
	if not record or record.rider ~= player then
		return
	end
	local weld = record.seat:FindFirstChild("SeatWeld")
	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.Sit = false
	end
	if weld then
		weld:Destroy()
	end
	-- Occupant change fires onRiderLeft; call directly too in case it already ran.
	onRiderLeft(record)
end

local function destroyBike(player: Player)
	local record = bikesByOwner[player]
	if not record then
		return
	end
	if record.rider then
		dismount(player)
	end
	bikesByOwner[player] = nil
	record.model:Destroy()
end

local function findSpawnCFrame(player: Player): CFrame
	local slotsFolder = Workspace:FindFirstChild("BikeSlots", true)
	if slotsFolder then
		local slots = slotsFolder:GetChildren()
		table.sort(slots, function(a, b)
			return a.Name < b.Name
		end)
		for _, slot in slots do
			if slot:IsA("BasePart") then
				local free = true
				for _, record in bikesByOwner do
					if (record.chassis.Position - slot.Position).Magnitude < 4 then
						free = false
						break
					end
				end
				if free then
					return slot.CFrame
				end
			end
		end
	end
	-- Fallback: in front of the player.
	local _, root = getHumanoid(player)
	if root then
		return root.CFrame * CFrame.new(0, 0, -8)
	end
	return CFrame.new(0, 5, 0)
end

local function spawnBike(player: Player, vehicleId: string): BikeRecord?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Vehicles") and assets.Vehicles:FindFirstChild(vehicleId)
	local config = VehicleCatalog.get(vehicleId)
	if not template or not config then
		warn(`[RYDE] No model for vehicle {vehicleId}`)
		return nil
	end

	destroyBike(player)

	local model = (template :: Model):Clone()
	model.Name = `{vehicleId}_{player.UserId}`
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	local seat = model:FindFirstChild("Seat") :: Seat
	local promptAttachment = chassis:FindFirstChild("PromptAttachment") :: Attachment

	chassis.CollisionGroup = VEHICLE_GROUP
	chassis.Anchored = true

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RidePrompt"
	prompt.ActionText = "Ride"
	prompt.ObjectText = `{config.displayName} ({player.DisplayName})`
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAttachment

	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("OwnerUserId", player.UserId)
	CollectionService:AddTag(model, VEHICLE_TAG)

	local record: BikeRecord = {
		model = model,
		chassis = chassis,
		seat = seat,
		prompt = prompt,
		owner = player,
		spec = VehicleMath.derive(config, Workspace.Gravity),
		rider = nil,
		restTime = 0,
		overSpeedTime = 0,
		savedCharacterState = nil,
	}

	local slot = findSpawnCFrame(player)
	model.Parent = vehiclesFolder
	placeUpright(record, slot.Position, slot.LookVector)
	record.chassis.Anchored = true
	model:SetAttribute("Parked", true)

	prompt.Triggered:Connect(function(triggeringPlayer)
		mount(record, triggeringPlayer)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			onRiderLeft(record)
		end
	end)

	bikesByOwner[player] = record
	return record
end

local function onAction(player: Player, action: unknown, payload: unknown)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now

	if action == "Spawn" then
		if type(payload) ~= "string" or #payload > 40 then
			return
		end
		if not canUse(player, payload) then
			notify(player, "That vehicle isn't available yet.")
			return
		end
		local humanoid = getHumanoid(player)
		if not humanoid then
			return
		end
		local record = spawnBike(player, payload)
		if record then
			mount(record, player)
		end
	elseif action == "Dismount" then
		dismount(player)
	end
end

local function monitor(dt: number)
	for _, record in bikesByOwner do
		local chassis = record.chassis
		if not chassis.Parent then
			continue
		end
		local speed = chassis.AssemblyLinearVelocity.Magnitude
		if record.rider then
			-- Exploit / glitch guard.
			if speed > record.spec.topSpeed * SPEED_TOLERANCE + 15 then
				record.overSpeedTime += dt
				if record.overSpeedTime > 2 then
					warn(`[RYDE] {record.rider.Name}'s bike exceeded its speed limit; taking control back`)
					local rider = record.rider
					dismount(rider)
					chassis.AssemblyLinearVelocity = Vector3.zero
					record.overSpeedTime = 0
				end
			else
				record.overSpeedTime = 0
			end
		elseif not chassis.Anchored then
			-- Riderless and loose: park it once it has come to rest.
			if speed < 1.5 and chassis.AssemblyAngularVelocity.Magnitude < 1.5 then
				record.restTime += dt
				if record.restTime > PARK_AFTER then
					park(record)
				end
			else
				record.restTime = 0
			end
			-- Fell out of the world: bring it back to its owner.
			if chassis.Position.Y < Workspace.FallenPartsDestroyHeight + 50 then
				local _, root = getHumanoid(record.owner)
				placeUpright(record, if root then root.Position + Vector3.new(0, 0, -6) else Vector3.new(0, 5, 0), Vector3.new(0, 0, -1))
				record.chassis.Anchored = true
			end
		end
	end
end

function VehicleService.start()
	setupCollisionGroups()

	vehiclesFolder = Instance.new("Folder")
	vehiclesFolder.Name = "Vehicles"
	vehiclesFolder.Parent = Workspace

	local action = Remotes.get("VehicleAction")
	notice = Remotes.get("VehicleNotice")
	action.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		destroyBike(player)
		lastAction[player] = nil
	end)

	RunService.Heartbeat:Connect(monitor)
end

return VehicleService
