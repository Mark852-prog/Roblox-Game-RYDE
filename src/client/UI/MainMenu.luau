--!strict
--[[
	MainMenu / Lobby (client)

	The first thing players see. The camera sits in the RYDE garage
	showroom (built into the map) looking at the selected bike on a
	rotating turntable, with the menu over the left of the screen:

	  PLAY      spawn the selected bike and ride (fade transition)
	  GARAGE    choose a bike - stats come straight from the vehicle configs
	  SETTINGS  units, camera, controls hint, debug overlay, volume mix
	  CONTROLS  keyboard and gamepad layout

	Reopen any time with the MENU button or M.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Net.Remotes)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)
local VehicleMath = require(Shared.Vehicle.VehicleMath)
local ImportedAssets = require(Shared.Config.ImportedAssets)

local Settings = require(script.Parent.Parent.Settings)
local AudioController = require(script.Parent.Parent.Audio.AudioController)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local F = Theme.Fonts

local MainMenu = {}

type RideSource = { getSession: () -> any }

local gui: ScreenGui
local fade: Frame
local panels: { [string]: Frame } = {}
local navButtons: { [string]: TextButton } = {}
local activePanel: string? = nil
local selectedVehicle = "VoltraStorm"
local selectedStyle: { [string]: string } = table.clone(ImportedAssets.DefaultStyle) -- vehicle id -> style key
local styleLabel: TextLabel? = nil
local showroomModel: Model? = nil
local turntableAngle = 0
local cameraConnection: RBXScriptConnection? = nil
local infoCard: { name: TextLabel, maker: TextLabel, bars: { [string]: Frame }, values: { [string]: TextLabel } }
local rides: RideSource
local garageRefresh: () -> () = function() end

local function isUnlocked(config: any): boolean
	if config.status == "Planned" then
		return false
	end
	if config.price == 0 then
		return true
	end
	return GameConfig.DEV_UNLOCK_ALL_IN_STUDIO and RunService:IsStudio()
end

local function hasModel(id: string): boolean
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vehicles = assets and assets:FindFirstChild("Vehicles")
	return vehicles ~= nil and vehicles:FindFirstChild(id) ~= nil
end

-- Stats shown in the garage (0..1 bars), derived from real config numbers.
local function stats(config: any): { [string]: number }
	local spec = VehicleMath.derive(config, Workspace.Gravity)
	local accel = config.motor.maxDriveForceN / spec.totalMassKg -- m/s^2
	return {
		SPEED = math.clamp(config.motor.topSpeedKmh / 100, 0, 1),
		ACCEL = math.clamp(accel / 10, 0, 1),
		POWER = math.clamp(config.motor.peakPowerW / 10000, 0, 1),
		WEIGHT = math.clamp(config.chassis.massKg / 80, 0, 1),
	}
end

local function statText(config: any, key: string): string
	if key == "SPEED" then
		return `{config.motor.topSpeedKmh} km/h`
	elseif key == "ACCEL" then
		return `{config.motor.maxDriveForceN} N`
	elseif key == "POWER" then
		return `{string.format("%.1f", config.motor.peakPowerW / 1000)} kW`
	end
	return `{config.chassis.massKg} kg`
end

------------------------------------------------------------------------------
-- Showroom (3D)
------------------------------------------------------------------------------

local cachedTurntable: BasePart? = nil
local cachedCameraPart: BasePart? = nil
local function showroom(): (BasePart?, BasePart?)
	if not (cachedTurntable and cachedTurntable.Parent and cachedCameraPart and cachedCameraPart.Parent) then
		local world = Workspace:FindFirstChild("World")
		local garage = world and world:FindFirstChild("Garage")
		if not garage then
			return nil, nil
		end
		cachedTurntable = garage:FindFirstChild("Turntable") :: BasePart?
		cachedCameraPart = garage:FindFirstChild("MenuCamera") :: BasePart?
	end
	return cachedTurntable, cachedCameraPart
end

local function showBike(id: string)
	if showroomModel then
		showroomModel:Destroy()
		showroomModel = nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	-- Imported Creator Store style if it has loaded, else the built-in model.
	local styles = assets and assets:FindFirstChild("Styles")
	local styleSet = styles and styles:FindFirstChild(id)
	local template = styleSet and selectedStyle[id] and styleSet:FindFirstChild(selectedStyle[id])
	if not template then
		template = assets and assets:FindFirstChild("Vehicles") and assets.Vehicles:FindFirstChild(id)
	end
	local turntable = showroom()
	local config = VehicleCatalog.get(id)
	if not template or not turntable or not config then
		return
	end
	local model = (template :: Model):Clone()
	model.Name = "ShowroomBike"
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	chassis.Anchored = true
	chassis.CanCollide = false
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt:Destroy()
	end
	showroomModel = model
	local spec = VehicleMath.derive(config, Workspace.Gravity)
	model:SetAttribute("Height", spec.comHeight)
	model.Parent = Workspace
end

local function updateShowroom(dt: number)
	local turntable, cameraPart = showroom()
	local camera = Workspace.CurrentCamera
	if not turntable or not cameraPart or not camera then
		return
	end
	turntableAngle += dt * 0.35
	local top = turntable.Position + Vector3.new(0, turntable.Size.Y / 2, 0)
	if showroomModel and showroomModel.PrimaryPart then
		local height = showroomModel:GetAttribute("Height") :: number? or 3
		showroomModel:PivotTo(CFrame.new(top + Vector3.new(0, height, 0)) * CFrame.Angles(0, turntableAngle, 0))
	end
	camera.CameraType = Enum.CameraType.Scriptable
	-- Slow cinematic drift around the bike.
	local t = os.clock()
	local base = cameraPart.CFrame
	local drift = Vector3.new(math.sin(t * 0.15) * 1.5, math.sin(t * 0.21) * 0.4, 0)
	local position = base.Position + base:VectorToWorldSpace(drift)
	camera.CFrame = CFrame.lookAt(position, top + Vector3.new(0, 2.6, 0) + base.RightVector * -3)
	camera.FieldOfView = 50
end

------------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------------

local function segmented(options: { string }, values: { any }, settingKey: string): Frame
	local frame = Theme.new("Frame", { Size = UDim2.fromOffset(180, 32), BackgroundColor3 = C.panelLight, BorderSizePixel = 0 }, { Theme.corner(16) })
	Theme.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Parent = frame })
	local buttons = {}
	local function refresh()
		for i, b in buttons do
			local on = Settings.get(settingKey) == values[i]
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then C.background else C.textDim
		end
	end
	for i, text in options do
		local b = Theme.new("TextButton", {
			Size = UDim2.new(1 / #options, 0, 1, 0),
			BackgroundColor3 = C.accent,
			BorderSizePixel = 0,
			FontFace = F.bodyBold,
			TextSize = 13,
			Text = text,
			Parent = frame,
		}, { Theme.corner(16) })
		Theme.bindButton(b, function()
			Settings.set(settingKey, values[i])
			refresh()
		end)
		table.insert(buttons, b)
	end
	refresh()
	return frame
end

local function toggle(settingKey: string): TextButton
	local button = Theme.new("TextButton", { Size = UDim2.fromOffset(52, 28), BorderSizePixel = 0, Text = "" }, { Theme.corner(14) })
	local knob = Theme.new("Frame", { Size = UDim2.fromOffset(22, 22), BackgroundColor3 = C.text, BorderSizePixel = 0, Parent = button }, { Theme.corner(11) })
	local function refresh(animate: boolean)
		local on = Settings.get(settingKey) == true
		local goal = { Position = if on then UDim2.fromOffset(27, 3) else UDim2.fromOffset(3, 3) }
		if animate then
			Theme.tween(knob, 0.18, goal)
		else
			knob.Position = goal.Position
		end
		button.BackgroundColor3 = if on then C.accent else C.panelLight
	end
	Theme.bindButton(button, function()
		Settings.set(settingKey, not Settings.get(settingKey))
		refresh(true)
	end)
	refresh(false)
	return button
end

local function slider(settingKey: string): Frame
	local track = Theme.new("Frame", { Size = UDim2.fromOffset(180, 6), BackgroundColor3 = C.panelLight, BorderSizePixel = 0 }, { Theme.corner(3) })
	local fill = Theme.new("Frame", { BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = track }, { Theme.corner(3) })
	local knob = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		Parent = track,
	}, { Theme.corner(8) })
	local hit = Theme.new("TextButton", {
		Size = UDim2.new(1, 16, 0, 28),
		Position = UDim2.fromOffset(-8, -11),
		BackgroundTransparency = 1,
		Text = "",
		Parent = track,
	})
	local function refresh()
		local v = math.clamp(Settings.get(settingKey), 0, 1)
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
	end
	local dragging = false
	local function setFromX(x: number)
		local v = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		Settings.set(settingKey, math.floor(v * 20 + 0.5) / 20)
		refresh()
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	refresh()
	return track
end

local function settingRow(parent: Instance, order: number, labelText: string, control: GuiObject)
	local row = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Theme.label(labelText, F.body, 15, { Size = UDim2.new(0.5, 0, 1, 0), TextColor3 = C.text, Parent = row })
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.new(1, 0, 0.5, 0)
	control.Parent = row
end

local function sectionTitle(parent: Instance, order: number, text: string)
	Theme.label(text, F.heading, 13, { TextColor3 = C.accent, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), Parent = parent })
end

local function contentPanel(name: string, title: string): Frame
	local panel = Theme.panel({
		Name = name,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -40, 0.5, 0),
		Size = UDim2.fromOffset(440, 560),
		Visible = false,
		Parent = gui,
	})
	Theme.padding(24).Parent = panel
	Theme.label(title, F.display, 34, { Size = UDim2.new(1, 0, 0, 40), Parent = panel })
	local body = Theme.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	panels[name] = panel
	return body
end

------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------

local function refreshInfoCard()
	local config = VehicleCatalog.get(selectedVehicle)
	if not config or not infoCard then
		return
	end
	infoCard.name.Text = string.upper(config.displayName)
	infoCard.maker.Text = `{string.upper(config.manufacturer)}  ·  {if config.category == "ElectricDirtBike" then "ELECTRIC DIRT BIKE" elseif config.category == "EBike" then "E-BIKE" else "SCOOTER"}`
	local s = stats(config)
	for key, bar in infoCard.bars do
		Theme.tween(bar, 0.4, { Size = UDim2.fromScale(s[key], 1) })
		infoCard.values[key].Text = statText(config, key)
	end
end

local function buildInfoCard()
	local card = Theme.panel({
		Name = "InfoCard",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -40),
		Size = UDim2.fromOffset(380, 230),
		Parent = gui,
	})
	Theme.padding(20).Parent = card
	local name = Theme.label("", F.display, 30, { Size = UDim2.new(1, 0, 0, 34), Parent = card })
	local maker = Theme.label("", F.bodyBold, 12, { Position = UDim2.fromOffset(0, 36), TextColor3 = C.accent, Parent = card })
	local bars, values = {}, {}
	for i, key in { "SPEED", "ACCEL", "POWER", "WEIGHT" } do
		local y = 64 + (i - 1) * 30
		Theme.label(key, F.bodyBold, 12, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(70, 16), TextColor3 = C.textDim, Parent = card })
		local back = Theme.new("Frame", {
			Position = UDim2.fromOffset(74, y + 5),
			Size = UDim2.new(1, -164, 0, 6),
			BackgroundColor3 = C.panelLight,
			BorderSizePixel = 0,
			Parent = card,
		}, { Theme.corner(3) })
		bars[key] = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = back }, { Theme.corner(3) })
		values[key] = Theme.label("", F.bodyBold, 12, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, y),
			Size = UDim2.fromOffset(80, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end
	infoCard = { name = name, maker = maker, bars = bars, values = values }
	refreshInfoCard()
end

-- Styles (Creator Store bikes) that loaded for a vehicle, in config order.
local function availableStyles(id: string): { ImportedAssets.Style }
	local list = {}
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local styles = assets and assets:FindFirstChild("Styles")
	local set = styles and styles:FindFirstChild(id)
	if set then
		for _, style in ImportedAssets.BikeStyles do
			if set:FindFirstChild(style.key) then
				table.insert(list, style)
			end
		end
	end
	return list
end

local function refreshStyleLabel()
	if not styleLabel then
		return
	end
	local list = availableStyles(selectedVehicle)
	if #list == 0 then
		styleLabel.Text = "Built-in model (styles loading...)"
		return
	end
	local current = ImportedAssets.getStyle(selectedStyle[selectedVehicle] or "")
	local found = false
	for _, style in list do
		if current and style.key == current.key then
			found = true
		end
	end
	if not found then
		selectedStyle[selectedVehicle] = list[1].key
		current = list[1]
	end
	styleLabel.Text = if current then current.name else list[1].name
end

local function cycleStyle(direction: number)
	local list = availableStyles(selectedVehicle)
	if #list == 0 then
		return
	end
	local index = 1
	for i, style in list do
		if style.key == selectedStyle[selectedVehicle] then
			index = i
		end
	end
	index = (index - 1 + direction) % #list + 1
	selectedStyle[selectedVehicle] = list[index].key
	refreshStyleLabel()
	showBike(selectedVehicle)
end

local function buildGaragePanel()
	local body = contentPanel("GARAGE", "GARAGE")
	-- Style picker: which Creator Store bike model to show/ride.
	local styleRow = Theme.new("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = C.panelLight, BorderSizePixel = 0, LayoutOrder = 0, Parent = body }, { Theme.corner(4) })
	Theme.label("STYLE", F.bodyBold, 11, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(50, 44), TextColor3 = C.textDim, Parent = styleRow })
	styleLabel = Theme.label("", F.bodyBold, 14, {
		Position = UDim2.fromOffset(62, 0),
		Size = UDim2.new(1, -150, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = styleRow,
	})
	for i, arrow in { "<", ">" } do
		local b = Theme.new("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, if i == 1 then -46 else -8, 0.5, 0),
			Size = UDim2.fromOffset(34, 30),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			FontFace = F.bodyBold,
			TextSize = 16,
			TextColor3 = C.text,
			Text = arrow,
			Parent = styleRow,
		}, { Theme.corner(4) })
		Theme.bindButton(b, function()
			cycleStyle(if i == 1 then -1 else 1)
		end)
	end
	refreshStyleLabel()
	task.spawn(function()
		-- Styles load on the server in the background; update when they arrive.
		local assets = ReplicatedStorage:WaitForChild("Assets")
		local styles = assets:WaitForChild("Styles", 60)
		if styles then
			styles.DescendantAdded:Connect(function()
				refreshStyleLabel()
			end)
			task.wait(1)
			refreshStyleLabel()
			if Settings.menuOpen then
				showBike(selectedVehicle)
			end
		end
	end)
	local cards = {}
	local function refresh()
		for id, card in cards do
			local selected = id == selectedVehicle
			card.stroke.Color = if selected then C.accent else C.stroke
			card.stroke.Transparency = if selected then 0 else 0.88
			card.stroke.Thickness = if selected then 2 else 1
		end
	end
	garageRefresh = refresh
	for i, config in VehicleCatalog.List do
		local usable = isUnlocked(config) and hasModel(config.id)
		local card = Theme.new("TextButton", {
			Size = UDim2.new(1, -8, 0, 76),
			BackgroundColor3 = C.panelLight,
			BorderSizePixel = 0,
			Text = "",
			LayoutOrder = i,
			Parent = body,
		}, { Theme.corner(12) })
		local stroke = Theme.stroke(0.88)
		stroke.Parent = card
		Theme.label(string.upper(config.displayName), F.heading, 20, {
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -140, 0, 24),
			TextColor3 = if usable then C.text else C.locked,
			Parent = card,
		})
		Theme.label(`{config.manufacturer}  ·  {config.motor.topSpeedKmh} km/h  ·  {string.format("%.1f", config.motor.peakPowerW / 1000)} kW`, F.body, 13, {
			Position = UDim2.fromOffset(16, 42),
			Size = UDim2.new(1, -140, 0, 18),
			TextColor3 = C.textDim,
			Parent = card,
		})
		local tagText, tagColor
		if config.status == "Planned" or not hasModel(config.id) then
			tagText, tagColor = "COMING SOON", C.locked
		elseif not isUnlocked(config) then
			tagText, tagColor = `🔒 {config.price}`, C.warning
		elseif config.price == 0 then
			tagText, tagColor = "OWNED", C.accent
		else
			tagText, tagColor = "TEST RIDE", C.warning
		end
		Theme.label(tagText, F.bodyBold, 12, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(120, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = tagColor,
			Parent = card,
		})
		cards[config.id] = { stroke = stroke }
		Theme.bindButton(card, function()
			if not usable then
				return
			end
			selectedVehicle = config.id
			refreshStyleLabel()
			refresh()
			refreshInfoCard()
			showBike(config.id)
		end, function(hovered)
			Theme.tween(card, 0.15, { BackgroundColor3 = if hovered and usable then C.panelLight:Lerp(C.accentDark, 0.35) else C.panelLight })
		end)
	end
	refresh()
end

local function buildSettingsPanel()
	local body = contentPanel("SETTINGS", "SETTINGS")
	sectionTitle(body, 1, "GAMEPLAY")
	settingRow(body, 2, "Speed units", segmented({ "KM/H", "MPH" }, { "kmh", "mph" }, "units"))
	settingRow(body, 3, "Chase camera", toggle("chaseCamera"))
	settingRow(body, 6, "Wheelie assist", segmented({ "OFF", "LIGHT", "STD" }, { "Off", "Light", "Standard" }, "wheelieAssist"))
	settingRow(body, 4, "Show controls while riding", toggle("showControls"))
	settingRow(body, 5, "Developer overlay (F2)", toggle("debugHud"))
	sectionTitle(body, 10, "AUDIO")
	settingRow(body, 11, "Master", slider("volumeMaster"))
	settingRow(body, 12, "Vehicles", slider("volumeVehicles"))
	settingRow(body, 13, "Music", slider("volumeMusic"))
	settingRow(body, 14, "Ambience", slider("volumeAmbience"))
	settingRow(body, 15, "Interface", slider("volumeUI"))
	Theme.label("Settings are saved to your account in a later update.", F.body, 12, {
		TextColor3 = C.textDim,
		LayoutOrder = 30,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = body,
	})
end

local function buildControlsPanel()
	local body = contentPanel("CONTROLS", "CONTROLS")
	local rows = {
		{ "Throttle", "W", "RT" },
		{ "Brake (hold when stopped: reverse)", "S", "LT" },
		{ "Steer", "A / D", "Left stick" },
		{ "Front brake (stoppie)", "Space", "X" },
		{ "Lean back (wheelie)", "Shift", "Stick back" },
		{ "Lean forward", "Ctrl", "Stick forward" },
		{ "Reset bike upright", "R", "Y" },
		{ "Get on bike", "E", "X" },
		{ "Get off bike", "F", "B" },
		{ "Look around", "Hold right mouse", "Right stick" },
		{ "Menu", "M", "—" },
		{ "Developer overlay", "F2", "—" },
	}
	local header = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 0, Parent = body })
	Theme.label("ACTION", F.bodyBold, 11, { Size = UDim2.new(0.5, 0, 1, 0), TextColor3 = C.accent, Parent = header })
	Theme.label("KEYBOARD", F.bodyBold, 11, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.25, 0, 1, 0), TextColor3 = C.accent, Parent = header })
	Theme.label("GAMEPAD", F.bodyBold, 11, { Position = UDim2.fromScale(0.75, 0), Size = UDim2.new(0.25, 0, 1, 0), TextColor3 = C.accent, Parent = header })
	for i, row in rows do
		local line = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = i, Parent = body })
		Theme.label(row[1], F.body, 14, { Size = UDim2.new(0.5, 0, 1, 0), Parent = line })
		Theme.label(row[2], F.bodyBold, 14, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.25, 0, 1, 0), TextColor3 = C.text, Parent = line })
		Theme.label(row[3], F.body, 14, { Position = UDim2.fromScale(0.75, 0), Size = UDim2.new(0.25, 0, 1, 0), TextColor3 = C.textDim, Parent = line })
	end
	Theme.label("Tip: wheelies need throttle + lean back. Wheelie assist (Settings) keeps the front near 30° like a real bike's wheelie control; tap S to drop it. Turn assist off for full manual control.", F.body, 13, {
		TextColor3 = C.warning,
		TextWrapped = true,
		Size = UDim2.new(1, -8, 0, 54),
		LayoutOrder = 50,
		Parent = body,
	})
end

------------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------------

local function showPanel(name: string?)
	if activePanel == name then
		name = nil -- clicking again closes it
	end
	activePanel = name
	for panelName, panel in panels do
		panel.Visible = panelName == name
	end
	if infoCard then
		local card = gui:FindFirstChild("InfoCard") :: Frame?
		if card then
			card.Visible = name == nil or name == "GARAGE"
			card.Position = if name == "GARAGE" then UDim2.new(1, -500, 1, -40) else UDim2.new(1, -40, 1, -40)
		end
	end
	for key, b in navButtons do
		b.TextColor3 = if key == name then C.accent else C.text
	end
end

local function navButton(parent: Instance, order: number, text: string, onClick: () -> ()): TextButton
	local holder = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local bar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Parent = holder,
	}, { Theme.corner(2) })
	local button = Theme.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = F.display,
		TextSize = 48,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Parent = holder,
	})
	Theme.bindButton(button, onClick, function(hovered)
		Theme.tween(button, 0.18, { Position = UDim2.fromOffset(if hovered then 18 else 0, 0) })
		Theme.tween(bar, 0.18, { Size = UDim2.fromOffset(if hovered then 6 else 0, 30) })
		if not navButtons[text] or activePanel ~= text then
			Theme.tween(button, 0.18, { TextColor3 = if hovered then C.accent else C.text })
		end
	end)
	return button
end

local function setCameraForMenu(on: boolean)
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	local camera = Workspace.CurrentCamera
	if on then
		cameraConnection = RunService.RenderStepped:Connect(updateShowroom)
	elseif camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local session = rides.getSession()
		if not session then
			local character = Players.LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
end

function MainMenu.open()
	Settings.menuOpen = true
	gui.Enabled = true
	showBike(selectedVehicle)
	setCameraForMenu(true)
	AudioController.setMenuMode(true)
	showPanel(nil)
end

local function play()
	Theme.playUISound("UIWhoosh")
	fade.Visible = true
	fade.BackgroundTransparency = 1
	Theme.tween(fade, 0.3, { BackgroundTransparency = 0 }).Completed:Wait()
	gui.Enabled = false
	if showroomModel then
		showroomModel:Destroy()
		showroomModel = nil
	end
	setCameraForMenu(false)
	Settings.menuOpen = false
	AudioController.setMenuMode(false)

	local session = rides.getSession()
	local currentId = session and session.model:GetAttribute("VehicleId")
	local currentStyle = session and session.model:GetAttribute("StyleKey")
	if currentId ~= selectedVehicle or currentStyle ~= selectedStyle[selectedVehicle] then
		Remotes.get("VehicleAction"):FireServer("Spawn", selectedVehicle, selectedStyle[selectedVehicle])
	end
	task.wait(0.15)
	gui.Enabled = true
	MainMenu.setVisible(false)
	Theme.tween(fade, 0.5, { BackgroundTransparency = 1 }).Completed:Wait()
	fade.Visible = false
end

function MainMenu.setVisible(visible: boolean)
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child ~= fade then
			child.Visible = visible and (child.Name ~= "GARAGE" and child.Name ~= "SETTINGS" and child.Name ~= "CONTROLS")
		end
	end
	if visible then
		showPanel(nil)
	end
end

function MainMenu.start(rideSource: RideSource)
	rides = rideSource
	local player = Players.LocalPlayer
	gui = Theme.new("ScreenGui", {
		Name = "RYDEMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Theme.new("UIScale", { Parent = gui })

	-- Darken the left side so the menu text reads over the 3D scene.
	Theme.new("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(0.62, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		Theme.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.6, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- Logo
	local logo = Theme.new("Frame", { Name = "Logo", Position = UDim2.new(0, 72, 0, 64), Size = UDim2.fromOffset(520, 170), BackgroundTransparency = 1, Parent = gui })
	Theme.label("RYDE", F.display, 128, { Size = UDim2.new(1, 0, 0, 120), Parent = logo })
	Theme.new("Frame", { Position = UDim2.fromOffset(6, 122), Size = UDim2.fromOffset(150, 6), BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = logo }, { Theme.corner(3) })
	Theme.label("ELECTRIC STREET RIDING", F.heading, 20, { Position = UDim2.fromOffset(170, 114), Size = UDim2.fromOffset(340, 22), TextColor3 = C.textDim, Parent = logo })

	-- Navigation
	local nav = Theme.new("Frame", { Name = "Nav", Position = UDim2.new(0, 72, 0.5, -90), Size = UDim2.fromOffset(360, 300), BackgroundTransparency = 1, Parent = gui })
	Theme.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav })
	navButton(nav, 1, "PLAY", function()
		task.spawn(play)
	end)
	navButtons.GARAGE = navButton(nav, 2, "GARAGE", function()
		showPanel("GARAGE")
	end)
	navButtons.SETTINGS = navButton(nav, 3, "SETTINGS", function()
		showPanel("SETTINGS")
	end)
	navButtons.CONTROLS = navButton(nav, 4, "CONTROLS", function()
		showPanel("CONTROLS")
	end)

	-- Player chip (top right)
	local chip = Theme.panel({
		Name = "PlayerChip",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 40),
		Size = UDim2.fromOffset(240, 56),
		Parent = gui,
	})
	local avatar = Theme.new("ImageLabel", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		Parent = chip,
	}, { Theme.corner(20) })
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			avatar.Image = image
		end
	end)
	Theme.label(player.DisplayName, F.bodyBold, 15, { Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -66, 0, 18), Parent = chip })
	Theme.label("RIDER", F.heading, 11, { Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -66, 0, 14), TextColor3 = C.accent, Parent = chip })

	Theme.label(`DEV BUILD {GameConfig.VERSION}  ·  {string.upper(GameConfig.MILESTONE)}`, F.bodyBold, 12, {
		Name = "Version",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 72, 1, -32),
		Size = UDim2.fromOffset(600, 16),
		TextColor3 = C.textDim,
		Parent = gui,
	})

	buildInfoCard()
	buildGaragePanel()
	buildSettingsPanel()
	buildControlsPanel()

	fade = Theme.new("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	})

	MainMenu.open()
end

function MainMenu.reopen()
	MainMenu.setVisible(true)
	garageRefresh()
	MainMenu.open()
end

return MainMenu
