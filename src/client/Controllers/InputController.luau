--!strict
--[[
	InputController

	Turns keyboard / gamepad input into one platform-independent table the
	bike understands (BikePhysics.Input). Key bindings live in BINDINGS so
	they can be changed in one place (a rebinding menu can edit this later).

	Default PC controls:
	  W / S          throttle / brake
	  A / D          steer
	  Space          front brake (stoppies)
	  Left Shift     lean back   (wheelies)
	  Left Ctrl      lean forward
	  F              get off       R   reset bike upright
	Gamepad:
	  RT / LT        throttle / brake
	  Left stick     steer (X) and lean (Y: pull back = lean back)
	  X              front brake   B  get off   Y  reset

	Touch controls are planned for the mobile milestone; the bike only reads
	this table, so they will plug in here without touching the physics.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputController = {}

InputController.BINDINGS = {
	throttle = { Enum.KeyCode.W, Enum.KeyCode.Up },
	brake = { Enum.KeyCode.S, Enum.KeyCode.Down },
	steerLeft = { Enum.KeyCode.A, Enum.KeyCode.Left },
	steerRight = { Enum.KeyCode.D, Enum.KeyCode.Right },
	frontBrake = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX },
	leanBack = { Enum.KeyCode.LeftShift },
	leanForward = { Enum.KeyCode.LeftControl },
	dismount = { Enum.KeyCode.F, Enum.KeyCode.ButtonB },
	reset = { Enum.KeyCode.R, Enum.KeyCode.ButtonY },
}

local STICK_DEADZONE = 0.15
local SINK_ACTION = "RYDE_RideSink"

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	local gamepad = UserInputService.GamepadEnabled
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
		if gamepad and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key) then
			return true
		end
	end
	return false
end

local function deadzone(value: number): number
	if math.abs(value) < STICK_DEADZONE then
		return 0
	end
	return math.sign(value) * (math.abs(value) - STICK_DEADZONE) / (1 - STICK_DEADZONE)
end

local gamepadState = {
	throttle = 0,
	brake = 0,
	stick = Vector2.zero,
}

local function readGamepad()
	gamepadState.throttle = 0
	gamepadState.brake = 0
	gamepadState.stick = Vector2.zero
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadState.throttle = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			gamepadState.brake = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadState.stick = Vector2.new(deadzone(input.Position.X), deadzone(input.Position.Y))
		end
	end
end

-- Current riding input (call every frame while riding).
function InputController.read(): { throttle: number, brake: number, frontBrake: number, steer: number, lean: number }
	readGamepad()
	local b = InputController.BINDINGS
	local throttle = if anyKeyDown(b.throttle) then 1 else gamepadState.throttle
	local brake = if anyKeyDown(b.brake) then 1 else gamepadState.brake
	local frontBrake = if anyKeyDown(b.frontBrake) then 1 else 0
	local steer = 0
	if anyKeyDown(b.steerLeft) then
		steer -= 1
	end
	if anyKeyDown(b.steerRight) then
		steer += 1
	end
	if steer == 0 then
		steer = gamepadState.stick.X
	end
	local lean = 0
	if anyKeyDown(b.leanBack) then
		lean += 1
	end
	if anyKeyDown(b.leanForward) then
		lean -= 1
	end
	if lean == 0 then
		lean = -gamepadState.stick.Y -- stick pulled back (down) = lean back
	end
	return { throttle = throttle, brake = brake, frontBrake = frontBrake, steer = steer, lean = lean }
end

--[[
	While riding, swallow keys that Roblox would otherwise use (Space = jump
	out of the seat, Shift = shift-lock, gamepad A = jump) and route the
	one-shot actions to callbacks.
]]
function InputController.bindRiding(onDismount: () -> (), onReset: () -> ())
	local b = InputController.BINDINGS
	local sinkKeys = { Enum.KeyCode.ButtonA }
	for _, list in { b.frontBrake, b.leanBack, b.leanForward } do
		for _, key in list do
			table.insert(sinkKeys, key)
		end
	end
	ContextActionService:BindActionAtPriority(SINK_ACTION, function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(sinkKeys))

	ContextActionService:BindActionAtPriority("RYDE_Dismount", function(_, state)
		if state == Enum.UserInputState.Begin then
			onDismount()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(b.dismount))

	ContextActionService:BindActionAtPriority("RYDE_Reset", function(_, state)
		if state == Enum.UserInputState.Begin then
			onReset()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(b.reset))
end

function InputController.unbindRiding()
	ContextActionService:UnbindAction(SINK_ACTION)
	ContextActionService:UnbindAction("RYDE_Dismount")
	ContextActionService:UnbindAction("RYDE_Reset")
end

return InputController
