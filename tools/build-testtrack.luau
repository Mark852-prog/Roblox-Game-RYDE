--[[
	Generates assets/TestTrack.rbxm - the Milestone 1 vehicle test map.

	Run from the repository root:
	    lune run tools/build-testtrack

	The map is generated (not hand-built) so it is reproducible and easy to
	change: edit the numbers below and re-run. Coordinates are in studs
	(1 stud = 0.35 m). +Y is up. The ground surface is at Y = 0 and paved or
	dirt surfaces sit on top of it at Y = 0.1.

	Layout (coordinates only - Roblox has no compass). The player spawns
	facing +Z; from there -X is on their right and +X on their left.

	    z > 450   dirt trail loop, hill
	    z ~ 252   bumps & curbs lane
	    z = +200  back straight  --+
	    infield   skills pad | jump park | surface strips   (oval track)
	    z = -200  main straight --+
	    z ~ -258  spawn plaza
	    z ~ -345  crash test lane
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

local OUTPUT_PATH = "assets/TestTrack.rbxm"

local SURFACE_Y = 0.1 -- top of roads and pads
local SLAB_THICKNESS = 1

local UP = Vector3.new(0, 1, 0)

local COLORS = {
	grass = Color3.fromRGB(86, 128, 58),
	asphalt = Color3.fromRGB(52, 54, 58),
	concrete = Color3.fromRGB(160, 160, 155),
	dirt = Color3.fromRGB(122, 90, 60),
	wood = Color3.fromRGB(150, 110, 70),
	white = Color3.fromRGB(235, 235, 230),
	yellow = Color3.fromRGB(240, 200, 40),
	orange = Color3.fromRGB(255, 120, 20),
	red = Color3.fromRGB(190, 40, 40),
	signBoard = Color3.fromRGB(30, 60, 110),
	post = Color3.fromRGB(90, 90, 95),
}

local partCount = 0

----------------------------------------------------------------------------
-- Deterministic pseudo-random numbers (same map every build)
----------------------------------------------------------------------------

local seed = 12345
local function random(min: number, max: number): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return min + (seed / 2147483648) * (max - min)
end

----------------------------------------------------------------------------
-- Instance helpers
----------------------------------------------------------------------------

local function folder(name: string, parent: any): any
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

type PartOptions = {
	material: any?,
	color: any?,
	anchored: boolean?,
	collide: boolean?, -- false = decoration only (also excluded from raycasts)
	shape: any?,
	className: string?,
	surface: string?, -- optional SurfaceConfig override attribute
}

local function part(parent: any, name: string, size: any, cframe: any, options: PartOptions?): any
	local opts: PartOptions = options or {}
	local p = Instance.new(opts.className or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = if opts.anchored == nil then true else opts.anchored
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Color = opts.color or COLORS.concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.collide == false then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	if opts.surface then
		p:SetAttribute("Surface", opts.surface)
	end
	p.Parent = parent
	partCount += 1
	return p
end

-- A flat slab whose top is at `topY`, covering the rectangle x1..x2, z1..z2.
local function slab(parent: any, name: string, x1: number, z1: number, x2: number, z2: number, material: any, color: any, topY: number?): any
	local top = topY or SURFACE_Y
	local sizeX, sizeZ = math.abs(x2 - x1), math.abs(z2 - z1)
	return part(
		parent,
		name,
		Vector3.new(sizeX, SLAB_THICKNESS, sizeZ),
		CFrame.new((x1 + x2) / 2, top - SLAB_THICKNESS / 2, (z1 + z2) / 2),
		{ material = material, color = color }
	)
end

-- A thin, non-colliding painted line from point a to point b (on the surface).
local function paintLine(parent: any, a: any, b: any, width: number, color: any, y: number?): any
	local height = y or (SURFACE_Y + 0.02)
	local from = Vector3.new(a.X, height, a.Z)
	local to = Vector3.new(b.X, height, b.Z)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	return part(
		parent,
		"Paint",
		Vector3.new(width, 0.02, length),
		CFrame.lookAt(mid, to),
		{ material = Enum.Material.SmoothPlastic, color = color, collide = false }
	)
end

--[[
	A tilted slab whose TOP surface starts at `startPos` and travels `length`
	studs along the slope in horizontal direction `dir`, rising at `angleDeg`
	(negative = descending). The slab is `thickness` thick below its top
	surface, so a thick slab fills the space underneath a ramp.
	Returns the end point of the top surface.
]]
local function slope(parent: any, name: string, startPos: any, dir: any, length: number, angleDeg: number, width: number, thickness: number, material: any, color: any): any
	local angle = math.rad(angleDeg)
	local flatDir = Vector3.new(dir.X, 0, dir.Z).Unit
	local right = flatDir:Cross(UP).Unit
	local slopeDir = flatDir * math.cos(angle) + UP * math.sin(angle)
	local normal = -flatDir * math.sin(angle) + UP * math.cos(angle)
	local center = startPos + slopeDir * (length / 2) - normal * (thickness / 2)
	part(
		parent,
		name,
		Vector3.new(width, thickness, length),
		CFrame.fromMatrix(center, right, normal),
		{ material = material, color = color }
	)
	return startPos + slopeDir * length
end

-- A road-sign board on two posts with text facing direction `facing`.
local function sign(parent: any, text: string, groundPos: any, facing: any, width: number?, height: number?)
	local w = width or 16
	local h = height or 5
	local postHeight = 5
	local flatFacing = Vector3.new(facing.X, 0, facing.Z).Unit
	local right = flatFacing:Cross(UP).Unit

	local model = Instance.new("Model")
	model.Name = "Sign"
	model.Parent = parent

	local boardCenter = Vector3.new(groundPos.X, postHeight + h / 2, groundPos.Z)
	local board = part(
		model,
		"Board",
		Vector3.new(w, h, 0.4),
		CFrame.lookAt(boardCenter, boardCenter + flatFacing),
		{ material = Enum.Material.SmoothPlastic, color = COLORS.signBoard }
	)

	for _, side in { -1, 1 } do
		local postPos = Vector3.new(groundPos.X, (postHeight + h) / 2, groundPos.Z) + right * side * (w / 2 - 0.6)
		part(model, "Post", Vector3.new(0.5, postHeight + h, 0.5), CFrame.new(postPos), {
			material = Enum.Material.Metal,
			color = COLORS.post,
		})
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 1, -24)
	label.Position = UDim2.new(0, 20, 0, 12)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.white
	label.TextScaled = true
	label.TextWrapped = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	label.Text = text
	label.Parent = gui
end

-- Text painted flat on the ground (readable when riding toward `facing`'s opposite).
local function groundLabel(parent: any, text: string, center: any, readDir: any, width: number, depth: number)
	local flat = Vector3.new(readDir.X, 0, readDir.Z).Unit
	local pos = Vector3.new(center.X, SURFACE_Y + 0.03, center.Z)
	-- Top face text reads with its top edge toward the part's -Z (LookVector).
	local p = part(parent, "GroundLabel", Vector3.new(width, 0.02, depth), CFrame.lookAt(pos, pos + flat), {
		collide = false,
	})
	p.Transparency = 1

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = p

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.white
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	label.Text = text
	label.Parent = gui
end

local function cone(parent: any, position: any)
	local p = part(parent, "Cone", Vector3.new(1.2, 2.2, 1.2), CFrame.new(position.X, SURFACE_Y + 1.1, position.Z), {
		material = Enum.Material.Plastic,
		color = COLORS.orange,
		anchored = false,
	})
	p.CustomPhysicalProperties = roblox.PhysicalProperties.new(0.3, 0.6, 0.2)
	return p
end

-- A flat disc marker painted on the ground.
local function dot(parent: any, position: any, diameter: number, color: any)
	part(
		parent,
		"Marker",
		Vector3.new(0.02, diameter, diameter),
		CFrame.new(position.X, SURFACE_Y + 0.02, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		{ shape = Enum.PartType.Cylinder, color = color, collide = false }
	)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

local root = Instance.new("Folder")
root.Name = "TestTrack"

-- Ground ------------------------------------------------------------------
local groundFolder = folder("Ground", root)
part(groundFolder, "Ground", Vector3.new(2000, 10, 2000), CFrame.new(0, -5, 0), {
	material = Enum.Material.Grass,
	color = COLORS.grass,
})

-- Oval track ----------------------------------------------------------------
-- Two straights (z = -200 and z = +200, x = -400..400) joined by two
-- semicircles of radius 200 centred on (+-400, 0). Lap length ~2850 studs (1 km).
local OVAL_HALF_LENGTH = 400
local OVAL_RADIUS = 200
local ROAD_WIDTH = 36
local EDGE_LINE_OFFSET = ROAD_WIDTH / 2 - 1.5

local oval = folder("OvalTrack", root)
local ovalPaint = folder("Markings", oval)

slab(oval, "MainStraight", -OVAL_HALF_LENGTH, -OVAL_RADIUS - ROAD_WIDTH / 2, OVAL_HALF_LENGTH, -OVAL_RADIUS + ROAD_WIDTH / 2, Enum.Material.Asphalt, COLORS.asphalt)
slab(oval, "BackStraight", -OVAL_HALF_LENGTH, OVAL_RADIUS - ROAD_WIDTH / 2, OVAL_HALF_LENGTH, OVAL_RADIUS + ROAD_WIDTH / 2, Enum.Material.Asphalt, COLORS.asphalt)

for _, z in { -OVAL_RADIUS, OVAL_RADIUS } do
	for _, offset in { -EDGE_LINE_OFFSET, EDGE_LINE_OFFSET } do
		paintLine(ovalPaint, Vector3.new(-OVAL_HALF_LENGTH, 0, z + offset), Vector3.new(OVAL_HALF_LENGTH, 0, z + offset), 0.6, COLORS.white)
	end
	-- Dashed centre line
	for x = -OVAL_HALF_LENGTH + 5, OVAL_HALF_LENGTH - 15, 20 do
		paintLine(ovalPaint, Vector3.new(x, 0, z), Vector3.new(x + 10, 0, z), 0.5, COLORS.yellow)
	end
end

local CURVE_SEGMENTS = 36 -- per semicircle (5 degrees each)
for curveIndex, centerX in { OVAL_HALF_LENGTH, -OVAL_HALF_LENGTH } do
	local startAngle = if curveIndex == 1 then -90 else 90
	local step = 180 / CURVE_SEGMENTS
	for i = 0, CURVE_SEGMENTS - 1 do
		local a0 = math.rad(startAngle + i * step)
		local a1 = math.rad(startAngle + (i + 1) * step)
		local mid = (a0 + a1) / 2
		local half = (a1 - a0) / 2
		local center = Vector3.new(centerX + math.cos(mid) * OVAL_RADIUS, 0, math.sin(mid) * OVAL_RADIUS)
		local tangent = Vector3.new(-math.sin(mid), 0, math.cos(mid))
		-- Long enough to close the gap on the outside edge; neighbours overlap on
		-- the inside, so alternate segments are raised 0.002 studs to avoid flicker.
		local length = 2 * (OVAL_RADIUS + ROAD_WIDTH / 2) * math.tan(half) + 0.2
		local top = SURFACE_Y + (i % 2) * 0.002
		local pos = Vector3.new(center.X, top - SLAB_THICKNESS / 2, center.Z)
		part(oval, "Curve", Vector3.new(ROAD_WIDTH, SLAB_THICKNESS, length), CFrame.lookAt(pos, pos + tangent), {
			material = Enum.Material.Asphalt,
			color = COLORS.asphalt,
		})

		for _, offset in { -EDGE_LINE_OFFSET, EDGE_LINE_OFFSET } do
			local r = OVAL_RADIUS + offset
			local p0 = Vector3.new(centerX + math.cos(a0) * r, 0, math.sin(a0) * r)
			local p1 = Vector3.new(centerX + math.cos(a1) * r, 0, math.sin(a1) * r)
			paintLine(ovalPaint, p0, p1, 0.6, COLORS.white, SURFACE_Y + 0.025)
		end
	end
end

-- Acceleration distance boards and braking lines on the main straight.
local START_X = -360
paintLine(ovalPaint, Vector3.new(START_X, 0, -OVAL_RADIUS - EDGE_LINE_OFFSET), Vector3.new(START_X, 0, -OVAL_RADIUS + EDGE_LINE_OFFSET), 1.5, COLORS.white)
local oSigns = folder("Signs", oval)
sign(oSigns, "ACCELERATION TEST\nStart here and ride straight on.\nBoards every 100 st (35 m)", Vector3.new(START_X, 0, -OVAL_RADIUS - ROAD_WIDTH / 2 - 8), Vector3.new(-1, 0, 0), 18, 6)
for k = 1, 5 do
	local x = START_X + k * 100
	sign(oSigns, `{k * 100} st\n{k * 35} m`, Vector3.new(x, 0, -OVAL_RADIUS - ROAD_WIDTH / 2 - 6), Vector3.new(-1, 0, 0), 6, 4)
end
local BRAKE_START_X = 200
for k = 0, 7 do
	local x = BRAKE_START_X + k * 25
	paintLine(ovalPaint, Vector3.new(x, 0, -OVAL_RADIUS - EDGE_LINE_OFFSET), Vector3.new(x, 0, -OVAL_RADIUS + EDGE_LINE_OFFSET), if k == 0 then 1.2 else 0.4, if k == 0 then COLORS.red else COLORS.white)
end
sign(oSigns, "BRAKE TEST\nBrake at the red line.\nWhite lines every 25 st (8.75 m)", Vector3.new(BRAKE_START_X - 10, 0, -OVAL_RADIUS - ROAD_WIDTH / 2 - 8), Vector3.new(-1, 0, 0), 18, 6)

-- Spawn plaza ------------------------------------------------------------------
local spawnFolder = folder("SpawnPlaza", root)
slab(spawnFolder, "Plaza", -60, -290, 60, -226, Enum.Material.Concrete, COLORS.concrete)

local spawnPos = Vector3.new(0, SURFACE_Y + 0.05 - 0.5, -268)
local spawnLocation = part(spawnFolder, "SpawnLocation", Vector3.new(10, 1, 10), CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, 1)), {
	className = "SpawnLocation",
	material = Enum.Material.Concrete,
	color = Color3.fromRGB(60, 140, 200),
})
spawnLocation.Duration = 0
spawnLocation.Neutral = true

-- Reserved pad where the first bike will appear in Milestone 2.
local padPaint = folder("BikePad", spawnFolder)
local padCorners = { Vector3.new(24, 0, -280), Vector3.new(44, 0, -280), Vector3.new(44, 0, -250), Vector3.new(24, 0, -250) }
for i = 1, 4 do
	paintLine(padPaint, padCorners[i], padCorners[i % 4 + 1], 0.5, COLORS.yellow)
end
groundLabel(padPaint, "BIKE PAD\n(Milestone 2)", Vector3.new(34, 0, -265), Vector3.new(0, 0, 1), 16, 8)

sign(
	spawnFolder,
	"RYDE TEST TRACK\nAhead: oval track (1 km)\nInfield, left to right: surface strips | jump park | skills pad\nBeyond the far straight: bumps & curbs lane, dirt trail (left), hill (right)\nBehind you: crash test lane",
	Vector3.new(0, 0, -236),
	Vector3.new(0, 0, -1),
	30,
	9
)

-- Infield: skills pad -----------------------------------------------------------
local skills = folder("SkillsPad", root)
slab(skills, "Pad", -370, -160, -130, 160, Enum.Material.Asphalt, COLORS.asphalt)
local skillsMarkers = folder("Markers", skills)

for i = 0, 14 do
	cone(skillsMarkers, Vector3.new(-340, 0, -140 + i * 20))
end
sign(skills, "SLALOM\nCones every 20 st (7 m)", Vector3.new(-355, 0, -150), Vector3.new(0, 0, -1), 12, 4)

local circleCenter = Vector3.new(-230, 0, -40)
for i = 0, 11 do
	local a = math.rad(i * 30)
	dot(skillsMarkers, circleCenter + Vector3.new(math.cos(a), 0, math.sin(a)) * 20, 1.5, COLORS.white)
end
for i = 0, 23 do
	local a = math.rad(i * 15)
	dot(skillsMarkers, circleCenter + Vector3.new(math.cos(a), 0, math.sin(a)) * 40, 1.5, COLORS.yellow)
end
dot(skillsMarkers, circleCenter, 2.5, COLORS.red)
groundLabel(skills, "TURNING CIRCLES  white r=20 st (7 m)  yellow r=40 st (14 m)", circleCenter + Vector3.new(0, 0, -50), Vector3.new(0, 0, 1), 60, 5)

part(skills, "BalancePlank", Vector3.new(1.5, 0.4, 100), CFrame.new(-160, SURFACE_Y + 0.2, 90), {
	material = Enum.Material.WoodPlanks,
	color = COLORS.wood,
})
sign(skills, "BALANCE PLANK\n1.5 st wide, 0.4 st high", Vector3.new(-172, 0, 32), Vector3.new(0, 0, -1), 12, 4)

-- Infield: jump park ----------------------------------------------------------
-- Lanes run toward +Z. Each kicker starts at z = KICK_Z on the dirt surface.
local jumps = folder("JumpPark", root)
slab(jumps, "DirtBase", -110, -160, 150, 160, Enum.Material.Ground, COLORS.dirt)

local KICK_Z = -100
local FORWARD = Vector3.new(0, 0, 1)
local LANE_WIDTH = 16

local function deck(parent: any, x: number, z1: number, z2: number, height: number)
	local top = SURFACE_Y + height
	part(parent, "Deck", Vector3.new(LANE_WIDTH, height + 1, z2 - z1), CFrame.new(x, top - (height + 1) / 2, (z1 + z2) / 2), {
		material = Enum.Material.Ground,
		color = COLORS.dirt,
	})
end

-- Table-top jump: kicker -> flat deck -> landing slope.
local function tableTop(name: string, x: number, kickDeg: number, height: number, deckLength: number, landDeg: number)
	local lane = folder(name, jumps)
	local kickLength = height / math.sin(math.rad(kickDeg))
	local kickEnd = slope(lane, "Kicker", Vector3.new(x, SURFACE_Y, KICK_Z), FORWARD, kickLength, kickDeg, LANE_WIDTH, height + 2, Enum.Material.WoodPlanks, COLORS.wood)
	deck(lane, x, kickEnd.Z, kickEnd.Z + deckLength, height)
	local landLength = height / math.sin(math.rad(landDeg))
	slope(lane, "Landing", Vector3.new(x, SURFACE_Y + height, kickEnd.Z + deckLength), FORWARD, landLength, -landDeg, LANE_WIDTH, height + 2, Enum.Material.Ground, COLORS.dirt)
	return lane
end

local laneA = tableTop("LaneA_Small", -80, 15, 3, 24, 12)
sign(laneA, "SMALL TABLE\n15 deg kicker, 3 st (1 m) high", Vector3.new(-80 - 14, 0, KICK_Z - 15), Vector3.new(0, 0, -1), 11, 4)

local laneB = tableTop("LaneB_Medium", -20, 22, 5, 30, 15)
sign(laneB, "MEDIUM TABLE\n22 deg kicker, 5 st (1.75 m) high", Vector3.new(-20 - 14, 0, KICK_Z - 15), Vector3.new(0, 0, -1), 11, 4)

do -- Lane C: gap jump with a vertical face on the landing (miss it and you crash).
	local x = 40
	local lane = folder("LaneC_Gap", jumps)
	local height, kickDeg, gap, knuckle, landDeg = 6, 28, 20, 8, 20
	local kickEnd = slope(lane, "Kicker", Vector3.new(x, SURFACE_Y, KICK_Z), FORWARD, height / math.sin(math.rad(kickDeg)), kickDeg, LANE_WIDTH, height + 2, Enum.Material.WoodPlanks, COLORS.wood)
	local landingStart = kickEnd.Z + gap
	deck(lane, x, landingStart, landingStart + knuckle, height)
	slope(lane, "Landing", Vector3.new(x, SURFACE_Y + height, landingStart + knuckle), FORWARD, height / math.sin(math.rad(landDeg)), -landDeg, LANE_WIDTH, height + 2, Enum.Material.Ground, COLORS.dirt)
	sign(lane, "GAP JUMP\n28 deg kicker, 20 st (7 m) gap", Vector3.new(x - 14, 0, KICK_Z - 15), Vector3.new(0, 0, -1), 11, 4)
end

do -- Lane D: gentle climb to a platform with a sheer drop.
	local x = 110
	local lane = folder("LaneD_Drop", jumps)
	local height, climbDeg, platform = 6, 8, 30
	local climbEnd = slope(lane, "Climb", Vector3.new(x, SURFACE_Y, KICK_Z), FORWARD, height / math.sin(math.rad(climbDeg)), climbDeg, LANE_WIDTH, height + 2, Enum.Material.WoodPlanks, COLORS.wood)
	deck(lane, x, climbEnd.Z, climbEnd.Z + platform, height)
	sign(lane, "DROP-OFF\n6 st (2.1 m) drop to flat", Vector3.new(x + 14, 0, KICK_Z - 15), Vector3.new(0, 0, -1), 11, 4)
end

-- Infield: surface strips ---------------------------------------------------------
local strips = folder("SurfaceStrips", root)
local STRIP_MATERIALS = {
	{ Enum.Material.Asphalt, COLORS.asphalt, "ASPHALT" },
	{ Enum.Material.Concrete, COLORS.concrete, "CONCRETE" },
	{ Enum.Material.LeafyGrass, Color3.fromRGB(70, 120, 45), "GRASS" },
	{ Enum.Material.Ground, COLORS.dirt, "DIRT" },
	{ Enum.Material.Pebble, Color3.fromRGB(140, 135, 125), "GRAVEL" },
	{ Enum.Material.Sand, Color3.fromRGB(205, 185, 135), "SAND" },
	{ Enum.Material.Mud, Color3.fromRGB(85, 65, 45), "MUD" },
}
for i, info in STRIP_MATERIALS do
	local cx = 181 + (i - 1) * 30
	slab(strips, info[3], cx - 13, -150, cx + 13, 150, info[1], info[2])
	groundLabel(strips, info[3], Vector3.new(cx, 0, -140), Vector3.new(0, 0, 1), 20, 5)
end
sign(strips, "SURFACE STRIPS\nCompare grip and speed.\nThe HUD shows the surface you are on.", Vector3.new(159, 0, -168), Vector3.new(0, 0, -1), 14, 5)

-- North: bumps & curbs lane -------------------------------------------------------
-- Ride toward +X.
local bumps = folder("BumpsLane", root)
local LANE_Z = 252
local LANE_HALF = 12
slab(bumps, "Lane", -320, LANE_Z - LANE_HALF, 320, LANE_Z + LANE_HALF, Enum.Material.Asphalt, COLORS.asphalt)
local bumpSigns = folder("Signs", bumps)
local function laneSign(text: string, x: number)
	sign(bumpSigns, text, Vector3.new(x, 0, LANE_Z + LANE_HALF + 6), Vector3.new(-1, 0, 0), 10, 4)
end

laneSign("RUMBLE STRIP\n0.15 st bars", -300)
for x = -295, -260, 3 do
	part(bumps, "Rumble", Vector3.new(1, 0.15, LANE_HALF * 2), CFrame.new(x, SURFACE_Y + 0.075, LANE_Z), {
		material = Enum.Material.Concrete,
		color = COLORS.white,
	})
end

laneSign("SPEED BUMPS\n0.3 / 0.6 / 0.9 st high", -240)
for i, height in { 0.3, 0.6, 0.9 } do
	local radius = 3
	local x = -230 + (i - 1) * 30
	part(
		bumps,
		"SpeedBump",
		Vector3.new(LANE_HALF * 2, radius * 2, radius * 2),
		CFrame.new(x, SURFACE_Y + height - radius, LANE_Z) * CFrame.Angles(0, math.rad(90), 0),
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Asphalt, color = COLORS.yellow }
	)
end

for i, height in { 0.5, 1.0, 1.5 } do
	local x = -130 + (i - 1) * 50
	laneSign(`CURB {height} st\n({string.format("%.2f", height * 0.35)} m) up & down`, x - 12)
	part(bumps, "Curb", Vector3.new(16, height, LANE_HALF * 2), CFrame.new(x + 8, SURFACE_Y + height / 2, LANE_Z), {
		material = Enum.Material.Concrete,
		color = COLORS.concrete,
	})
end

laneSign("BROKEN PAVEMENT", 25)
for _ = 1, 40 do
	local x = random(32, 92)
	local z = random(LANE_Z - LANE_HALF + 2, LANE_Z + LANE_HALF - 2)
	local h = random(0.08, 0.25)
	part(
		bumps,
		"Patch",
		Vector3.new(random(2, 5), h, random(2, 5)),
		CFrame.new(x, SURFACE_Y + h / 2, z) * CFrame.Angles(0, math.rad(random(0, 90)), 0),
		{ material = Enum.Material.Cobblestone, color = Color3.fromRGB(95, 95, 98) }
	)
end

laneSign("WHOOPS\nRounded dirt bumps 1.5 st", 112)
slab(bumps, "WhoopsBase", 120, LANE_Z - LANE_HALF, 320, LANE_Z + LANE_HALF, Enum.Material.Ground, COLORS.dirt, SURFACE_Y + 0.004)
for i = 0, 11 do
	local radius = 8
	local height = 1.5
	part(
		bumps,
		"Whoop",
		Vector3.new(LANE_HALF * 2, radius * 2, radius * 2),
		CFrame.new(130 + i * 16, SURFACE_Y + height - radius, LANE_Z) * CFrame.Angles(0, math.rad(90), 0),
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Ground, color = COLORS.dirt }
	)
end

-- North: hill ------------------------------------------------------------------
-- Two climbs (15 and 30 degrees) up to a plateau 18 studs high, then a 25 degree descent.
local hill = folder("Hill", root)
local HILL_HEIGHT = 18
local PLATEAU_Z1 = 367
local PLATEAU_Z2 = 417
local NORTH = Vector3.new(0, 0, 1)
local HILL_THICK = HILL_HEIGHT + 6

local function climb(name: string, x1: number, x2: number, angleDeg: number)
	local run = HILL_HEIGHT / math.tan(math.rad(angleDeg))
	local length = HILL_HEIGHT / math.sin(math.rad(angleDeg))
	slope(hill, name, Vector3.new((x1 + x2) / 2, 0, PLATEAU_Z1 - run), NORTH, length, angleDeg, x2 - x1, HILL_THICK, Enum.Material.Grass, COLORS.grass)
end
climb("Climb15", -260, -160, 15)
climb("Climb30", -160, -100, 30)
part(hill, "Plateau", Vector3.new(160, HILL_HEIGHT + 1, PLATEAU_Z2 - PLATEAU_Z1), CFrame.new(-180, (HILL_HEIGHT - 1) / 2, (PLATEAU_Z1 + PLATEAU_Z2) / 2), {
	material = Enum.Material.Ground,
	color = COLORS.dirt,
})
slope(hill, "Descent25", Vector3.new(-180, HILL_HEIGHT, PLATEAU_Z2), NORTH, HILL_HEIGHT / math.sin(math.rad(25)), -25, 160, HILL_THICK, Enum.Material.Grass, COLORS.grass)
sign(hill, "HILL\nLeft: 15 deg climb   Right: 30 deg climb\nTop: 18 st (6.3 m). Far side: 25 deg descent", Vector3.new(-285, 0, 300), Vector3.new(0, 0, -1), 22, 5)

-- North: dirt trail loop ---------------------------------------------------------
local trail = folder("DirtTrail", root)
local TRAIL_WIDTH = 12
local trailPoints = {
	Vector3.new(330, 0, 252),
	Vector3.new(390, 0, 330),
	Vector3.new(350, 0, 420),
	Vector3.new(250, 0, 470),
	Vector3.new(140, 0, 440),
	Vector3.new(60, 0, 500),
	Vector3.new(-40, 0, 560),
	Vector3.new(-60, 0, 470),
	Vector3.new(0, 0, 380),
	Vector3.new(80, 0, 330),
	Vector3.new(200, 0, 300),
	Vector3.new(300, 0, 285),
}
for i, a in trailPoints do
	local b = trailPoints[i % #trailPoints + 1]
	local top = SURFACE_Y + (i % 2) * 0.003
	local mid = (a + b) / 2
	local pos = Vector3.new(mid.X, top - SLAB_THICKNESS / 2, mid.Z)
	local target = Vector3.new(b.X, pos.Y, b.Z)
	part(trail, "Segment", Vector3.new(TRAIL_WIDTH, SLAB_THICKNESS, (b - a).Magnitude), CFrame.lookAt(pos, target), {
		material = Enum.Material.Ground,
		color = COLORS.dirt,
	})
	-- Round each corner with a disc so segments join smoothly.
	part(
		trail,
		"Corner",
		Vector3.new(SLAB_THICKNESS, TRAIL_WIDTH, TRAIL_WIDTH),
		CFrame.new(a.X, SURFACE_Y + 0.006 - SLAB_THICKNESS / 2, a.Z) * CFrame.Angles(0, 0, math.rad(90)),
		{ shape = Enum.PartType.Cylinder, material = Enum.Material.Ground, color = COLORS.dirt }
	)
end
sign(trail, "DIRT TRAIL LOOP", Vector3.new(345, 0, 285), Vector3.new(-1, 0, -1), 10, 3)

-- South: crash test lane ------------------------------------------------------------
-- Ride toward -X (west) from the spawn plaza.
local crash = folder("CrashLane", root)
local CRASH_Z = -345
slab(crash, "Lane", -350, CRASH_Z - 15, 60, CRASH_Z + 15, Enum.Material.Asphalt, COLORS.asphalt)
part(crash, "Wall", Vector3.new(4, 12, 50), CFrame.new(-352, 6, CRASH_Z), {
	material = Enum.Material.Concrete,
	color = Color3.fromRGB(150, 150, 150),
})
for i = 0, 4 do -- red/white stripes on the wall face
	part(crash, "Stripe", Vector3.new(0.1, 12, 4), CFrame.new(-349.95, 6, CRASH_Z - 20 + i * 10), {
		color = COLORS.red,
		collide = false,
	})
end
part(crash, "LampPost", Vector3.new(14, 1, 1), CFrame.new(-150, 7, CRASH_Z - 8) * CFrame.Angles(0, 0, math.rad(90)), {
	shape = Enum.PartType.Cylinder,
	material = Enum.Material.Metal,
	color = COLORS.post,
})
part(crash, "CarSizedBlock", Vector3.new(6, 5, 14), CFrame.new(-280, SURFACE_Y + 2.5, CRASH_Z + 6), {
	material = Enum.Material.Metal,
	color = COLORS.red,
})
local crates = folder("LooseCrates", crash)
local crateLayers = { { -1.1, 0, 1.1 }, { -0.55, 0.55 }, { 0 } }
for layer, offsets in crateLayers do
	for _, offset in offsets do
		local crate = part(crates, "Crate", Vector3.new(2, 2, 2), CFrame.new(-220, SURFACE_Y + 1 + (layer - 1) * 2.02, CRASH_Z + offset * 2), {
			material = Enum.Material.WoodPlanks,
			color = COLORS.wood,
			anchored = false,
		})
		crate.CustomPhysicalProperties = roblox.PhysicalProperties.new(0.4, 0.5, 0.1)
	end
end
sign(crash, "CRASH TEST LANE\nRide toward the wall. Loose crates,\nlamp post, car-sized block, concrete wall", Vector3.new(55, 0, CRASH_Z - 22), Vector3.new(1, 0, 0), 18, 5)

----------------------------------------------------------------------------
-- Write
----------------------------------------------------------------------------

fs.writeFile(OUTPUT_PATH, roblox.serializeModel({ root }))
print(`Wrote {OUTPUT_PATH} ({partCount} parts)`)
