--!strict
--[[
	LabController (client, PhysicsLab place only)

	Runs scripted riding scenarios on the real Roblox physics and measures
	them against the targets in docs/QUALITY_AUDIT.md section 3.4.

	How it works: the bike is placed on a start marker with an exact speed,
	then RideController's input is replaced by a script (the "autopilot")
	for a fixed time while telemetry is sampled every frame. Results appear
	in the panel (PASS / FAIL / INFO) and are printed to Output as lines
	starting with "RYDE_LAB," so they can be copied and pasted.

	"Simulated FPS" makes the frame rate drop to 30 or 20 by keeping the
	CPU busy each frame, to test low-end devices on any PC.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local Units = require(Shared.Util.Units)

local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.UI.Theme)

local C = Theme.Colors
local F = Theme.Fonts

local LabController = {}

type Rides = { getSession: () -> any, setInputOverride: ((() -> any)?) -> () }
type Input = { throttle: number, brake: number, frontBrake: number, steer: number, lean: number }
type Sample = {
	t: number,
	dt: number,
	speed: number, -- studs/s forward
	pitch: number, -- degrees
	yawRate: number, -- rad/s, + right
	frontGrounded: boolean,
	rearGrounded: boolean,
	load: number, -- total suspension load, x weight
	anyBottomed: boolean,
	airborne: boolean,
	position: Vector3,
	upY: number,
	minCornerY: number,
}
type Result = { metric: string, value: string, target: string, status: "PASS" | "FAIL" | "INFO" }
type Scenario = {
	name: string,
	label: string,
	start: string,
	speedKmh: number,
	lift: number, -- studs above resting height
	duration: number,
	input: (t: number, s: Sample?) -> Input,
	evaluate: (samples: { Sample }, vehicleId: string, assist: string) -> { Result },
}

local NONE: Input = { throttle = 0, brake = 0, frontBrake = 0, steer = 0, lean = 0 }
local function input(overrides: { [string]: number }): Input
	local i = table.clone(NONE)
	for k, v in overrides do
		(i :: any)[k] = v
	end
	return i
end

local function kmh(studsPerSec: number): number
	return Units.studsPerSecToKmh(studsPerSec)
end

local function holdSpeed(targetKmh: number, s: Sample?): number
	if not s then
		return 0.5
	end
	return math.clamp((targetKmh - kmh(s.speed)) * 0.15, 0, 1)
end

local function result(metric: string, value: string, target: string, ok: boolean?): Result
	return { metric = metric, value = value, target = target, status = if ok == nil then "INFO" elseif ok then "PASS" else "FAIL" }
end

local function countBounces(values: { number }, centre: number, tol: number): number
	local n, last = 0, 0
	for _, v in values do
		local side = if v > centre + tol then 1 elseif v < centre - tol then -1 else 0
		if side ~= 0 and side ~= last then
			n += 1
			last = side
		end
	end
	return math.max(0, n - 1) // 2
end

local SCENARIOS: { Scenario } = {
	{
		name = "accel",
		label = "Acceleration & top speed",
		start = "Straight",
		speedKmh = 0,
		lift = 0,
		duration = 14,
		input = function()
			return input({ throttle = 1 })
		end,
		evaluate = function(samples, vehicleId)
			local t50, vmax = nil, 0
			for _, s in samples do
				vmax = math.max(vmax, kmh(s.speed))
				if not t50 and kmh(s.speed) >= 50 then
					t50 = s.t
				end
			end
			local isVoltra = vehicleId == "VoltraStorm"
			return {
				result("0-50 km/h", if t50 then string.format("%.2f s", t50) else "not reached", if isVoltra then "3.0-4.0 s" else "-", if isVoltra then (t50 ~= nil and t50 >= 3 and t50 <= 4) else nil),
				result("top speed", string.format("%.1f km/h", vmax), if isVoltra then "72-77 km/h" else "-", if isVoltra then vmax >= 72 and vmax <= 77 else nil),
			}
		end,
	},
	{
		name = "brake",
		label = "Braking 50-0 km/h (S)",
		start = "Straight",
		speedKmh = 50,
		lift = 0,
		duration = 6,
		input = function(t)
			return if t >= 0.2 then input({ brake = 1 }) else NONE
		end,
		evaluate = function(samples)
			local startX, stopX, lift = nil, nil, 0
			for _, s in samples do
				if s.t >= 0.2 and not startX then
					startX = s.position.X
				end
				if startX and not stopX and s.speed < 0.5 then
					stopX = s.position.X
				end
				if s.t >= 0.2 and s.frontGrounded and not s.rearGrounded then
					lift += s.dt
				end
			end
			local dist = if startX and stopX then Units.studsToMeters(stopX - startX) else nil
			return {
				result("stopping distance", if dist then string.format("%.1f m", dist) else "did not stop", "12-16 m", dist ~= nil and dist >= 12 and dist <= 16),
				result("rear wheel lifted", string.format("%.2f s", lift), "0 s", lift < 0.05),
			}
		end,
	},
	{
		name = "stoppie",
		label = "Stoppie (front brake 0.8 s)",
		start = "Straight",
		speedKmh = 40,
		lift = 0,
		duration = 4,
		input = function(t)
			if t >= 0.2 and t < 1.0 then
				return input({ frontBrake = 1 })
			end
			return if t >= 1.0 then input({ brake = 1 }) else NONE
		end,
		evaluate = function(samples)
			local minPitch, flipped = 0, false
			for _, s in samples do
				minPitch = math.min(minPitch, s.pitch)
				if s.upY < 0 or s.pitch < -70 then
					flipped = true
				end
			end
			return {
				result("rear lift (min pitch)", string.format("%.1f deg", minPitch), "<= -5 deg", minPitch <= -5),
				result("flipped over", tostring(flipped), "false", not flipped),
			}
		end,
	},
	{
		name = "wheelieTap",
		label = "Wheelie tap (0.4 s)",
		start = "Straight",
		speedKmh = 15,
		lift = 0,
		duration = 4,
		input = function(t)
			return if t < 0.4 then input({ throttle = 1, lean = 1 }) else NONE
		end,
		evaluate = function(samples)
			local peak = 0
			for _, s in samples do
				peak = math.max(peak, s.pitch)
			end
			local final = samples[#samples].pitch
			return {
				result("peak pitch", string.format("%.1f deg", peak), "5-45 deg", peak >= 5 and peak <= 45),
				result("front back down", string.format("%.1f deg", final), "< 3 deg", math.abs(final) < 3),
			}
		end,
	},
	{
		name = "wheelieHold",
		label = "Wheelie hold (W+Shift 6 s)",
		start = "Straight",
		speedKmh = 15,
		lift = 0,
		duration = 6,
		input = function()
			return input({ throttle = 1, lean = 1 })
		end,
		evaluate = function(samples, _, assist)
			local window, maxPitch = 0, -90
			for _, s in samples do
				maxPitch = math.max(maxPitch, s.pitch)
				if s.pitch >= 15 and s.pitch <= 45 and not s.frontGrounded then
					window += s.dt
				end
			end
			local looped = maxPitch > 70
			local standard = assist == "Standard"
			return {
				result("time at 15-45 deg", string.format("%.1f s", window), if standard then ">= 4 s" else "-", if standard then window >= 4 else nil),
				result("looped out", tostring(looped), if standard then "false" else "-", if standard then not looped else nil),
			}
		end,
	},
	{
		name = "wheelieDrop",
		label = "Wheelie then S to drop it",
		start = "Straight",
		speedKmh = 15,
		lift = 0,
		duration = 5,
		input = function(t)
			return if t < 3 then input({ throttle = 1, lean = 1 }) else input({ brake = 1 })
		end,
		evaluate = function(samples)
			local down = nil
			for _, s in samples do
				if s.t >= 3 and s.frontGrounded then
					down = s.t - 3
					break
				end
			end
			return { result("front down after S", if down then string.format("%.2f s", down) else "not down", "< 1 s", down ~= nil and down < 1) }
		end,
	},
	{
		name = "settle",
		label = "Settle (dropped 14 cm)",
		start = "Pad",
		speedKmh = 0,
		lift = 0.5,
		duration = 3,
		input = function()
			return NONE
		end,
		evaluate = function(samples)
			local ys = {}
			for _, s in samples do
				table.insert(ys, s.position.Y)
			end
			local b = countBounces(ys, ys[#ys], 0.03)
			return { result("bounces", tostring(b), "<= 2", b <= 2) }
		end,
	},
	{
		name = "drop",
		label = "Drop 1.5 m onto flat",
		start = "Pad",
		speedKmh = 10,
		lift = Units.metersToStuds(1.5),
		duration = 3,
		input = function()
			return NONE
		end,
		evaluate = function(samples)
			local peak, clearance, bottomed = 0, math.huge, false
			local landed = false
			for _, s in samples do
				peak = math.max(peak, s.load)
				if not s.airborne then
					landed = true
				end
				if landed then
					clearance = math.min(clearance, s.minCornerY)
				end
				bottomed = bottomed or s.anyBottomed
			end
			return {
				result("peak suspension load", string.format("%.1f g", peak), "<= 10 g", peak <= 10),
				result("chassis clearance", string.format("%.2f studs", clearance), "> 0.1", clearance > 0.1),
				result("hit bump stop", tostring(bottomed), "-", nil),
			}
		end,
	},
	{
		name = "steer",
		label = "Step steer at 30 km/h",
		start = "Straight",
		speedKmh = 30,
		lift = 0,
		duration = 4,
		input = function(t, s)
			return input({ throttle = holdSpeed(30, s), steer = if t > 0.5 then 1 else 0 })
		end,
		evaluate = function(samples)
			local values = {}
			local upset = false
			for _, s in samples do
				if s.t > 1.5 then
					table.insert(values, s.yawRate)
				end
				upset = upset or s.upY < 0.8
			end
			local lo, hi, sum = math.huge, -math.huge, 0
			for _, v in values do
				lo, hi, sum = math.min(lo, v), math.max(hi, v), sum + v
			end
			local mean = if #values > 0 then sum / #values else 0
			local ripple = if math.abs(mean) > 1e-3 then (hi - lo) / math.abs(mean) else math.huge
			return {
				result("yaw rate", string.format("%.2f rad/s", mean), "-", nil),
				result("yaw ripple", string.format("%.0f %%", ripple * 100), "< 25 %", ripple < 0.25),
				result("stayed upright", tostring(not upset), "true", not upset),
			}
		end,
	},
	{
		name = "kerb",
		label = "15 cm kerb at 15 km/h",
		start = "Kerb",
		speedKmh = 15,
		lift = 0,
		duration = 9,
		input = function(_, s)
			return input({ throttle = holdSpeed(15, s) })
		end,
		evaluate = function(samples)
			local air, upset, crossed = 0, false, false
			for _, s in samples do
				if s.airborne then
					air += s.dt
				end
				upset = upset or s.upY < 0.8
				crossed = crossed or s.position.X > 35
			end
			return {
				result("got over the kerb", tostring(crossed), "true", crossed),
				result("airborne time", string.format("%.2f s", air), "< 0.3 s", air < 0.3),
				result("stayed upright", tostring(not upset), "true", not upset),
			}
		end,
	},
	{
		name = "reverse",
		label = "Reverse (hold S when stopped)",
		start = "Pad",
		speedKmh = 0,
		lift = 0,
		duration = 3,
		input = function()
			return input({ brake = 1 })
		end,
		evaluate = function(samples)
			local minSpeed = 0
			for _, s in samples do
				minSpeed = math.min(minSpeed, s.speed)
			end
			return { result("reverse speed", string.format("%.1f studs/s", minSpeed), "-2.5 to -4.5", minSpeed <= -2.5 and minSpeed >= -4.5) }
		end,
	},
}

------------------------------------------------------------------------------
-- Running
------------------------------------------------------------------------------

local rides: Rides
local running = false
local simulatedFps: number? = nil
local currentInput: Input = NONE
local resultsList: ScrollingFrame
local statusLabel: TextLabel
local fpsLabel: TextLabel
local rowCount = 0

local function startMarker(name: string): BasePart?
	local lab = Workspace:FindFirstChild("PhysicsLab")
	return lab and lab:FindFirstChild("Start_" .. name) :: BasePart?
end

local function boxCornerMinY(part: BasePart): number
	local cf, s = part.CFrame, part.Size / 2
	local minY = math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				minY = math.min(minY, (cf * Vector3.new(s.X * x, s.Y * y, s.Z * z)).Y)
			end
		end
	end
	return minY
end

local function addRow(scenario: string, r: Result)
	rowCount += 1
	local color = if r.status == "PASS" then C.accent elseif r.status == "FAIL" then C.danger else C.textDim
	local row = Theme.new("Frame", { Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1, LayoutOrder = rowCount, Parent = resultsList })
	Theme.label(`{scenario}: {r.metric}`, F.body, 12, { Size = UDim2.new(0.5, 0, 1, 0), Parent = row, TextTruncate = Enum.TextTruncate.AtEnd })
	Theme.label(r.value, F.bodyBold, 12, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.22, 0, 1, 0), Parent = row })
	Theme.label(r.target, F.body, 12, { Position = UDim2.fromScale(0.72, 0), Size = UDim2.new(0.16, 0, 1, 0), TextColor3 = C.textDim, Parent = row })
	Theme.label(r.status, F.bodyBold, 12, { Position = UDim2.fromScale(0.88, 0), Size = UDim2.new(0.12, 0, 1, 0), TextColor3 = color, Parent = row })
end

local function runScenario(scenario: Scenario): boolean
	local session = rides.getSession()
	if not session then
		statusLabel.Text = "Get on your bike first (it spawns automatically - wait a moment or press F then E)."
		return false
	end
	local marker = startMarker(scenario.start)
	if not marker then
		statusLabel.Text = `Missing start marker {scenario.start}`
		return false
	end
	local chassis: BasePart = session.chassis
	local physics = session.physics
	local spec = session.spec
	local vehicleId = spec.config.id
	local assist = Settings.get("wheelieAssist")
	statusLabel.Text = `Running: {scenario.label}...`

	-- Place the bike exactly.
	local rest = marker.CFrame + Vector3.new(0, spec.comHeight + 0.05 + scenario.lift, 0)
	physics.throttle = 0
	currentInput = NONE
	rides.setInputOverride(function()
		return currentInput
	end)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.CFrame = rest
	task.wait(0.3) -- let the suspension settle at the start (no input)
	chassis.CFrame = rest
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.AssemblyLinearVelocity = rest.LookVector * Units.kmhToStudsPerSec(scenario.speedKmh)

	local samples: { Sample } = {}
	local t = 0
	local fpsSum, fpsCount = 0, 0
	local done = false
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		t += dt
		fpsSum += 1 / math.max(dt, 1e-3)
		fpsCount += 1
		local tel = physics.telemetry
		local cf = chassis.CFrame
		local last = samples[#samples]
		table.insert(samples, {
			t = t,
			dt = dt,
			speed = tel.speed,
			pitch = math.deg(tel.pitch),
			yawRate = -chassis.AssemblyAngularVelocity:Dot(cf.UpVector),
			frontGrounded = tel.front.grounded,
			rearGrounded = tel.rear.grounded,
			load = tel.front.load + tel.rear.load,
			anyBottomed = tel.front.bottomed or tel.rear.bottomed,
			airborne = tel.airborne,
			position = cf.Position,
			upY = cf.UpVector.Y,
			minCornerY = boxCornerMinY(chassis),
		})
		currentInput = scenario.input(t, last)
		if t >= scenario.duration then
			done = true
			connection:Disconnect()
		end
	end)
	while not done do
		task.wait()
	end
	rides.setInputOverride(nil)
	currentInput = NONE

	local fps = fpsSum / math.max(fpsCount, 1)
	local results = scenario.evaluate(samples, vehicleId, assist)
	for _, r in results do
		addRow(scenario.label, r)
		print(string.format("RYDE_LAB,%s,%s,%s,%s,%s,%s,%s,%s,fps=%.0f", GameConfig.VERSION, vehicleId, assist, scenario.name, r.metric, r.value, r.target, r.status, fps))
	end
	-- Park on the pad afterwards.
	local pad = startMarker("Pad")
	if pad then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		chassis.CFrame = pad.CFrame + Vector3.new(0, spec.comHeight + 0.3, 0)
	end
	return true
end

local function runAll()
	if running then
		return
	end
	running = true
	local session = rides.getSession()
	print(`RYDE_LAB,header,version={GameConfig.VERSION},vehicle={session and session.spec.config.id or "?"},assist={Settings.get("wheelieAssist")},simulatedFps={simulatedFps or "off"}`)
	for _, scenario in SCENARIOS do
		if not runScenario(scenario) then
			break
		end
		task.wait(0.5)
	end
	statusLabel.Text = "Done. Copy the RYDE_LAB lines from Output and paste them to Claude."
	running = false
end

------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------

local function button(parent: Instance, text: string, width: number, onClick: () -> ()): TextButton
	local b = Theme.new("TextButton", {
		Size = UDim2.fromOffset(width, 28),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		FontFace = F.bodyBold,
		TextSize = 12,
		TextColor3 = C.text,
		Text = text,
		Parent = parent,
	}, { Theme.corner(4) })
	Theme.bindButton(b, onClick)
	return b
end

local function row(parent: Instance, order: number, labelText: string): Frame
	local r = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Theme.label(labelText, F.bodyBold, 12, { Size = UDim2.fromOffset(90, 30), TextColor3 = C.textDim, Parent = r })
	local holder = Theme.new("Frame", { Position = UDim2.fromOffset(92, 1), Size = UDim2.new(1, -92, 1, 0), BackgroundTransparency = 1, Parent = r })
	Theme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = holder })
	return holder
end

function LabController.start(rideSource: Rides)
	rides = rideSource
	local gui = Theme.new("ScreenGui", { Name = "RYDELab", ResetOnSpawn = false, DisplayOrder = 30, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	local panel = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 520, 1, -24),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = gui,
	}, { Theme.corner(4), Theme.padding(12) })
	Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })
	Theme.label("PHYSICS LAB", F.heading, 20, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), Parent = panel })
	statusLabel = Theme.label("Wait for your bike, then press RUN ALL.", F.body, 12, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextColor3 = C.textDim,
		Parent = panel,
	})

	local vehicles = row(panel, 3, "VEHICLE")
	for _, id in { "VoltraStorm", "KestrelSting" } do
		button(vehicles, id, 110, function()
			if not running then
				Remotes.get("VehicleAction"):FireServer("Spawn", id)
			end
		end)
	end
	local assist = row(panel, 4, "ASSIST")
	for _, level in { "Off", "Light", "Standard" } do
		button(assist, level, 80, function()
			Settings.set("wheelieAssist", level)
			statusLabel.Text = `Wheelie assist: {level}`
		end)
	end
	local fpsRow = row(panel, 5, "SIM FPS")
	for _, value in { "Off", "30", "20" } do
		button(fpsRow, value, 60, function()
			simulatedFps = tonumber(value)
			statusLabel.Text = `Simulated frame rate: {value}`
		end)
	end
	fpsLabel = Theme.label("", F.mono, 12, { Size = UDim2.fromOffset(120, 28), TextColor3 = C.textDim, Parent = fpsRow })

	local runRow = row(panel, 6, "RUN")
	button(runRow, "RUN ALL", 100, function()
		task.spawn(runAll)
	end)
	button(runRow, "CLEAR", 70, function()
		for _, child in resultsList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end)
	local single = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, LayoutOrder = 7, Parent = panel })
	Theme.new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 26), CellPadding = UDim2.fromOffset(4, 4), Parent = single })
	for _, scenario in SCENARIOS do
		button(single, scenario.name, 120, function()
			if not running then
				running = true
				task.spawn(function()
					runScenario(scenario)
					running = false
					statusLabel.Text = "Done."
				end)
			end
		end)
	end

	resultsList = Theme.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -300),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		LayoutOrder = 8,
		Parent = panel,
	})
	Theme.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = resultsList })

	-- Simulated low frame rate: keep the CPU busy until the frame has taken long enough.
	local lastFrame = os.clock()
	local smoothed = 60
	RunService.RenderStepped:Connect(function(dt)
		if simulatedFps then
			local frameTime = 1 / simulatedFps
			local spins = 0
			while os.clock() - lastFrame < frameTime do
				spins += 1 -- busy wait (intentional)
			end
		end
		lastFrame = os.clock()
		smoothed += (1 / math.max(dt, 1e-3) - smoothed) * 0.1
		fpsLabel.Text = string.format("now %.0f fps", smoothed)
	end)
end

return LabController
