--[[
	Generates assets/PhysicsLab.rbxm - the controlled physics test place.

	    lune run tools/build-physicslab

	Deliberately plain: one flat asphalt field (top at Y = 0) so measurements
	aren't affected by the map. +X is "forward" for every scenario.

	  Main straight   z = 0      x -1150 .. 1150   (acceleration, braking, wheelies, steering)
	  Kerb lane       z = 120    0.55-stud (15 cm) kerb up/down at x = 0
	  Marks           every 50 studs, numbered in metres
	  Start markers   invisible parts named Start_<Name>; the autopilot places the bike there
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local UDim2 = roblox.UDim2
local Font = roblox.Font

local OUTPUT_PATH = "assets/PhysicsLab.rbxm"
local M_PER_STUD = 0.28

local root = Instance.new("Folder")
root.Name = "PhysicsLab"

local function part(name: string, size: any, cframe: any, color: any, material: any?, decoration: boolean?): any
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if decoration then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	p.Parent = root
	return p
end

local function marker(name: string, position: any, facing: any)
	local p = part(name, Vector3.new(2, 0.2, 2), CFrame.lookAt(position, position + facing), Color3.fromRGB(40, 230, 175), nil, true)
	p.Transparency = 1
	return p
end

-- Ground: asphalt field (Asphalt grip = 1.0 in SurfaceConfig)
part("Field", Vector3.new(2400, 4, 400), CFrame.new(0, -2, 60), Color3.fromRGB(52, 54, 58), Enum.Material.Asphalt)

-- Distance marks across the main straight every 50 studs
for x = -1100, 1100, 50 do
	part("Mark", Vector3.new(0.6, 0.02, 40), CFrame.new(x, 0.011, 0), Color3.fromRGB(235, 235, 230), nil, true)
	local board = part("MarkLabel", Vector3.new(6, 0.02, 3), CFrame.lookAt(Vector3.new(x, 0.02, -24), Vector3.new(x + 1, 0.02, -24)), Color3.new(0, 0, 0), nil, true)
	board.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(235, 235, 230)
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	label.Text = string.format("%d m", math.floor((x + 1100) * M_PER_STUD + 0.5))
	label.Parent = gui
end
-- Lane edges
for _, z in { -20, 20 } do
	part("Edge", Vector3.new(2300, 0.02, 0.5), CFrame.new(0, 0.012, z), Color3.fromRGB(240, 200, 40), nil, true)
end

-- Kerb lane: 0.55 studs (15 cm) up, 30 studs long, then down
part("Kerb", Vector3.new(30, 0.55, 30), CFrame.new(15, 0.275, 120), Color3.fromRGB(170, 170, 165), Enum.Material.Concrete)
part("KerbLaneEdge", Vector3.new(400, 0.02, 0.5), CFrame.new(0, 0.012, 100), Color3.fromRGB(240, 200, 40), nil, true)
part("KerbLaneEdge", Vector3.new(400, 0.02, 0.5), CFrame.new(0, 0.012, 140), Color3.fromRGB(240, 200, 40), nil, true)

-- Start markers used by the autopilot (bike faces +X)
local FORWARD = Vector3.new(1, 0, 0)
marker("Start_Straight", Vector3.new(-1100, 0, 0), FORWARD)
marker("Start_Kerb", Vector3.new(-60, 0, 120), FORWARD)
marker("Start_Pad", Vector3.new(-1000, 0, 70), FORWARD)

-- Bike spawn slots + spawn location
local slots = Instance.new("Folder")
slots.Name = "BikeSlots"
slots.Parent = root
for i = 0, 5 do
	local slot = part(string.format("Slot%02d", i + 1), Vector3.new(4, 0.05, 9), CFrame.lookAt(Vector3.new(-1080, 0.1, -60 - i * 10), Vector3.new(-1079, 0.1, -60 - i * 10)), Color3.new(1, 1, 1), nil, true)
	slot.Transparency = 1
	slot.Parent = slots
end
local spawn = Instance.new("SpawnLocation")
spawn.Name = "SpawnLocation"
spawn.Size = Vector3.new(10, 1, 10)
spawn.CFrame = CFrame.new(-1110, -0.45, -60)
spawn.Anchored = true
spawn.Duration = 0
spawn.Neutral = true
spawn.Color = Color3.fromRGB(60, 140, 200)
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.Parent = root

fs.writeFile(OUTPUT_PATH, roblox.serializeModel({ root }))
print(`Wrote {OUTPUT_PATH}`)
