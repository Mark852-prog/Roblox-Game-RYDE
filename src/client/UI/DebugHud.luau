--!strict
--[[
	DebugHud

	A small developer overlay in the top-left corner showing:
	  - game version and whether the server started correctly
	  - frames per second
	  - your speed (km/h, mph, studs/s)
	  - the surface under you and its grip value from SurfaceConfig
	  - your position (useful when reporting problems)

	Press F2 to show or hide it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local SurfaceConfig = require(Shared.Config.SurfaceConfig)
local Units = require(Shared.Util.Units)

local TOGGLE_KEY = Enum.KeyCode.F2
local UPDATE_INTERVAL = 0.1 -- seconds between text refreshes
local SURFACE_RAY_LENGTH = 4.5 -- studs below the character's root (~3 when standing)

local DebugHud = {}

local function createGui(): (ScreenGui, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RYDEDebugHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 100

	local label = Instance.new("TextLabel")
	label.Name = "Info"
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(12, 12)
	label.Size = UDim2.fromOffset(400, 160)
	label.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	label.BackgroundTransparency = 0.35
	label.BorderSizePixel = 0
	label.Font = Enum.Font.RobotoMono
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(235, 240, 245)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = false
	label.Text = "RYDE"
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = label

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	return gui, label
end

local function getSurfaceUnder(character: Model, rootPart: BasePart): (string, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(rootPart.Position, Vector3.new(0, -SURFACE_RAY_LENGTH, 0), params)
	if not result then
		return "(airborne)", 0
	end
	local surface = SurfaceConfig.resolve(result.Instance, result.Material)
	return `{surface.name} [{result.Material.Name}]`, surface.grip
end

local function serverStatus(): string
	local version = Workspace:GetAttribute("RYDEServerVersion")
	if version == nil then
		return "waiting..."
	end
	if Workspace:GetAttribute("RYDEServerHealthy") == true then
		return `OK (v{version})`
	end
	return `PROBLEMS - check Output (v{version})`
end

function DebugHud.start(visible: boolean)
	local player = Players.LocalPlayer
	local gui, label = createGui()
	gui.Enabled = visible
	gui.Parent = player:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			gui.Enabled = not gui.Enabled
		end
	end)

	local frames = 0
	local elapsed = 0
	local fps = 0

	RunService.Heartbeat:Connect(function(dt: number)
		frames += 1
		elapsed += dt
		if elapsed < UPDATE_INTERVAL or not gui.Enabled then
			return
		end
		fps = frames / elapsed
		frames = 0
		elapsed = 0

		local lines = {
			`RYDE dev build {GameConfig.VERSION}`,
			`Server: {serverStatus()}`,
			`FPS: {math.floor(fps + 0.5)}`,
		}

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if character and rootPart and rootPart:IsA("BasePart") then
			local velocity = rootPart.AssemblyLinearVelocity
			local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local surfaceName, grip = getSurfaceUnder(character, rootPart)
			local position = rootPart.Position

			table.insert(
				lines,
				string.format(
					"Speed: %5.1f km/h  %5.1f mph  (%.1f st/s)",
					Units.studsPerSecToKmh(flatSpeed),
					Units.studsPerSecToMph(flatSpeed),
					flatSpeed
				)
			)
			table.insert(lines, `Surface: {surfaceName}`)
			table.insert(lines, string.format("Grip: %.2f", grip))
			table.insert(lines, string.format("Pos: %.0f, %.0f, %.0f", position.X, position.Y, position.Z))
		else
			table.insert(lines, "Character: not spawned")
		end

		table.insert(lines, "F2: hide/show")
		label.Text = table.concat(lines, "\n")
	end)
end

return DebugHud
