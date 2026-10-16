--!strict
--[[
	Hud (client) - what you see while playing.

	Following the hierarchy-of-information guidance (create.roblox.com/docs/
	production/game-design/ui-ux-design): while riding, the speed is the
	biggest thing on screen; trick feedback appears only when it happens;
	everything else is small and out of the way.

	  * Arc speedometer (bottom right) with throttle/brake bars, surface chip
	  * Trick pills (top centre): WHEELIE 34°, STOPPIE, AIR 1.4s, SLIDE
	  * Controls hint (bottom left, can be hidden in Settings)
	  * Menu button (top left, or press M)
	  * Toast notifications from the server
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Units = require(Shared.Util.Units)

local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local F = Theme.Fonts

local ARC_SEGMENTS = 34
local ARC_START = math.rad(150) -- degrees from +X, clockwise in screen space
local ARC_SWEEP = math.rad(240)
local GAUGE_SIZE = 230

local Hud = {}

type RideSource = { getSession: () -> any }

local function speedText(studsPerSec: number): (string, string)
	if Settings.get("units") == "mph" then
		return tostring(math.floor(Units.studsPerSecToMph(studsPerSec) + 0.5)), "MPH"
	end
	return tostring(math.floor(Units.studsPerSecToKmh(studsPerSec) + 0.5)), "KM/H"
end

local function keycap(text: string): Frame
	local width = math.max(28, 10 + #text * 9)
	return Theme.new("Frame", {
		Size = UDim2.fromOffset(width, 26),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
	}, {
		Theme.corner(6),
		Theme.stroke(0.75),
		Theme.label(text, F.bodyBold, 13, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

local function controlsHint(parent: Instance): Frame
	local rows = {
		{ { "W" }, "Throttle" },
		{ { "S" }, "Brake" },
		{ { "A", "D" }, "Steer" },
		{ { "Space" }, "Front brake" },
		{ { "Shift" }, "Lean back / wheelie" },
		{ { "Ctrl" }, "Lean forward" },
		{ { "R" }, "Reset bike" },
		{ { "F" }, "Get off" },
		{ { "M" }, "Menu" },
	}
	local panel = Theme.panel({
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(220, 26 + #rows * 30),
		BackgroundTransparency = 0.3,
		Parent = parent,
	})
	Theme.padding(10).Parent = panel
	Theme.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })
	for i, row in rows do
		local line = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = i, Parent = panel })
		local keys = Theme.new("Frame", { Size = UDim2.fromOffset(90, 26), BackgroundTransparency = 1, Parent = line })
		Theme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = keys })
		for _, key in row[1] do
			keycap(key).Parent = keys
		end
		Theme.label(row[2], F.body, 13, {
			Position = UDim2.fromOffset(92, 0),
			Size = UDim2.new(1, -92, 1, 0),
			TextColor3 = C.textDim,
			Parent = line,
		})
	end
	return panel
end

local function buildGauge(parent: Instance)
	local gauge = Theme.new("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -20),
		Size = UDim2.fromOffset(GAUGE_SIZE, GAUGE_SIZE),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Soft dark disc behind the gauge for contrast over bright scenery.
	Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		BackgroundColor3 = C.background,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = gauge,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })

	local segments = {}
	local radius = GAUGE_SIZE * 0.42
	for i = 0, ARC_SEGMENTS - 1 do
		local a = ARC_START + ARC_SWEEP * (i / (ARC_SEGMENTS - 1))
		local x = 0.5 + math.cos(a) * radius / GAUGE_SIZE
		local y = 0.5 + math.sin(a) * radius / GAUGE_SIZE
		local seg = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(14, 5),
			Rotation = math.deg(a),
			BackgroundColor3 = C.panelLight,
			BorderSizePixel = 0,
			Parent = gauge,
		}, { Theme.corner(2) })
		table.insert(segments, seg)
	end

	local speed = Theme.label("0", F.display, 64, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(180, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = gauge,
	})
	local unit = Theme.label("KM/H", F.heading, 15, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(120, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.accent,
		Parent = gauge,
	})
	local name = Theme.label("", F.bodyBold, 12, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.25),
		Size = UDim2.fromOffset(160, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.textDim,
		Parent = gauge,
	})
	local surface = Theme.label("", F.bodyBold, 11, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(120, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.textDim,
		Parent = gauge,
	})

	local function bar(xScale: number, color: Color3): Frame
		local back = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(xScale, 0.93),
			Size = UDim2.fromOffset(46, 5),
			BackgroundColor3 = C.panelLight,
			BorderSizePixel = 0,
			Parent = gauge,
		}, { Theme.corner(3) })
		return Theme.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = back,
		}, { Theme.corner(3) })
	end
	local throttleBar = bar(0.38, C.accent)
	local brakeBar = bar(0.62, C.danger)

	return {
		frame = gauge,
		segments = segments,
		speed = speed,
		unit = unit,
		name = name,
		surface = surface,
		throttle = throttleBar,
		brake = brakeBar,
	}
end

function Hud.start(rides: RideSource, openMenu: () -> ())
	local player = Players.LocalPlayer
	local gui = Theme.new("ScreenGui", {
		Name = "RYDEHud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- Scale everything down a little on small screens.
	local scale = Theme.new("UIScale", { Parent = gui })
	local function rescale()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.65, 1.15)
	end
	rescale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local gauge = buildGauge(gui)
	local controls = controlsHint(gui)

	-- Menu button
	local menuButton = Theme.new("TextButton", {
		Name = "MenuButton",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(96, 36),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		FontFace = F.heading,
		TextSize = 16,
		TextColor3 = C.text,
		Text = "MENU",
		Parent = gui,
	}, { Theme.corner(18), Theme.stroke(0.85) })
	Theme.bindButton(menuButton, openMenu, function(hovered)
		Theme.tween(menuButton, 0.15, { TextColor3 = if hovered then C.accent else C.text })
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M and not Settings.menuOpen then
			openMenu()
		end
	end)

	-- Trick pills
	local pills = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(600, 44),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = pills,
	})
	local function pill(color: Color3): TextLabel
		return Theme.new("TextLabel", {
			Size = UDim2.fromOffset(170, 40),
			BackgroundColor3 = C.background,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			FontFace = F.display,
			TextSize = 22,
			TextColor3 = color,
			Visible = false,
			Parent = pills,
		}, { Theme.corner(20), Theme.stroke(0.4, color, 2) })
	end
	local wheeliePill = pill(C.accent)
	local airPill = pill(C.warning)
	local slidePill = pill(C.danger)

	-- Toasts
	local toast = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 40),
		Visible = false,
		Parent = gui,
	})
	local toastText = Theme.label("", F.bodyBold, 15, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = toast,
	})
	local toastId = 0
	function Hud.toast(message: string)
		toastId += 1
		local id = toastId
		toastText.Text = message
		toast.Visible = true
		task.delay(3, function()
			if toastId == id then
				toast.Visible = false
			end
		end)
	end
	Remotes.get("VehicleNotice").OnClientEvent:Connect(function(message)
		if type(message) == "string" then
			Hud.toast(message)
		end
	end)

	local displayedSpeed = 0
	RunService.RenderStepped:Connect(function(dt)
		local session = rides.getSession()
		local riding = session ~= nil and not Settings.menuOpen
		gauge.frame.Visible = riding
		controls.Visible = riding and Settings.get("showControls")
		menuButton.Visible = not Settings.menuOpen
		pills.Visible = riding
		if not riding then
			return
		end
		local t = session.physics.telemetry
		local spec = session.spec
		displayedSpeed += (math.abs(t.speed) - displayedSpeed) * math.min(dt * 10, 1)
		local text, unitText = speedText(displayedSpeed)
		gauge.speed.Text = text
		gauge.unit.Text = unitText
		gauge.name.Text = string.upper(spec.config.displayName)
		gauge.surface.Text = if t.airborne then "AIRBORNE" else string.upper(t.rear.surface)

		local frac = math.clamp(displayedSpeed / spec.topSpeed, 0, 1)
		local lit = math.floor(frac * #gauge.segments + 0.5)
		for i, seg in gauge.segments do
			if i <= lit then
				seg.BackgroundColor3 = if i > #gauge.segments * 0.85 then C.warning else C.accent
			else
				seg.BackgroundColor3 = C.panelLight
			end
		end
		gauge.throttle.Size = UDim2.fromScale(t.throttle, 1)
		gauge.brake.Size = UDim2.fromScale(math.clamp(t.brake, 0, 1), 1)

		local pitchDeg = math.deg(t.pitch)
		local frontUp = not t.front.grounded and t.rear.grounded
		local rearUp = t.front.grounded and not t.rear.grounded
		if frontUp and pitchDeg > 4 then
			wheeliePill.Visible = true
			wheeliePill.Text = string.format("WHEELIE %d°", math.floor(pitchDeg + 0.5))
		elseif rearUp and pitchDeg < -4 then
			wheeliePill.Visible = true
			wheeliePill.Text = string.format("STOPPIE %d°", math.floor(-pitchDeg + 0.5))
		else
			wheeliePill.Visible = false
		end
		airPill.Visible = t.airborne and t.airTime > 0.35
		airPill.Text = string.format("AIR %.1fs", t.airTime)
		local slip = math.max(t.front.slip, t.rear.slip)
		slidePill.Visible = not t.airborne and slip > 1.05 and math.abs(t.speed) > 6
		slidePill.Text = "SLIDE"
	end)
end

return Hud
