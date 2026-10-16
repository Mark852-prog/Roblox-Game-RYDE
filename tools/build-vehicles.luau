--[[
	Generates assets/Vehicles.rbxm - one Model per vehicle, built from the
	vehicle's config so the visual geometry always matches the physics.

	    lune run tools/build-vehicles

	Model layout (what the game code relies on):

	  <VehicleId> (Model, PrimaryPart = Chassis)
	    Chassis        Invisible collision box. The ONLY part with mass; its
	                   centre is the centre of mass. Density set so the
	                   assembly weighs bike + rider.
	    LeanRoot       Pivot on the ground under the centre of mass.
	      LeanJoint    Motor6D Chassis -> LeanRoot. Each client rolls it to
	                   show the bike leaning into turns.
	    SteerRoot      Steering head. SteerJoint (Motor6D LeanRoot -> SteerRoot)
	                   rotates about the raked steering axis.
	    FrontTire / RearTire  FrontWheelJoint / RearWheelJoint (Motor6D) slide
	                   with the suspension and spin.
	    Seat           Where the rider sits (touch-sitting disabled).
	    Visual parts   Massless, non-colliding, welded to the roots above.

	Parts with a "Paint" attribute ("Primary" / "Secondary") are recoloured
	by the customisation system later.

	Only ElectricDirtBike models are generated for now; the e-bike and
	scooter get their own builders in Milestone 7.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local ModuleLoader = require("../tests/lib/ModuleLoader")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Shared = ModuleLoader.root("src/shared")
local VehicleCatalog = ModuleLoader.require(Shared.Config.VehicleCatalog)
local VehicleMath = ModuleLoader.require(Shared.Vehicle.VehicleMath)
local Units = ModuleLoader.require(Shared.Util.Units)

local OUTPUT_PATH = "assets/Vehicles.rbxm"

-- Per-vehicle paint schemes (fictional brands).
local PAINT = {
	VoltraStorm = { primary = Color3.fromRGB(40, 220, 170), secondary = Color3.fromRGB(28, 30, 34), accent = Color3.fromRGB(255, 255, 255) },
	KestrelSting = { primary = Color3.fromRGB(235, 70, 40), secondary = Color3.fromRGB(205, 205, 210), accent = Color3.fromRGB(20, 20, 22) },
}

local BLACK = Color3.fromRGB(22, 22, 24)
local RUBBER = Color3.fromRGB(28, 28, 28)
local ALU = Color3.fromRGB(170, 172, 178)
local GOLD = Color3.fromRGB(214, 160, 40)
local DISC = Color3.fromRGB(200, 200, 205)

local function hasMaterial(name: string): boolean
	for _, item in Enum.Material:GetEnumItems() do
		if item.Name == name then
			return true
		end
	end
	return false
end
local TIRE_MATERIAL = if hasMaterial("Rubber") then Enum.Material.Rubber else Enum.Material.SmoothPlastic
local SEAT_MATERIAL = if hasMaterial("Leather") then Enum.Material.Leather else Enum.Material.SmoothPlastic

local function weld(part0: any, part1: any, parent: any?)
	local w = Instance.new("Weld")
	w.Name = "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = part0.CFrame:Inverse() * part1.CFrame
	w.C1 = CFrame.new()
	w.Parent = parent or part1
	return w
end

local function motor(name: string, part0: any, part1: any, jointWorld: any)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * jointWorld
	m.C1 = part1.CFrame:Inverse() * jointWorld
	m.Parent = part1
	return m
end

local function buildDirtBike(config: any): any
	local spec = VehicleMath.derive(config)
	local paint = PAINT[config.id] or PAINT.VoltraStorm

	local model = Instance.new("Model")
	model.Name = config.id
	model:SetAttribute("VehicleId", config.id)

	-- Bike-space helper: f = studs forward of the rear axle, y = studs above
	-- the ground, x = studs to the right. Returns chassis-local position
	-- (the chassis sits at the origin, its centre = centre of mass).
	local comH, comR = spec.comHeight, spec.comFromRear
	local function B(x: number, y: number, f: number): any
		return Vector3.new(x, y - comH, -(f - comR))
	end
	local function M(meters: number): number
		return Units.metersToStuds(meters)
	end

	local function visual(name: string, size: any, cframe: any, color: any, material: any?, shape: any?, paintSlot: string?): any
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = false
		if paintSlot then
			p:SetAttribute("Paint", paintSlot)
		end
		p.Parent = model
		return p
	end

	-- A beam between two points (bike-space Vector3s already converted with B).
	local function beam(name: string, a: any, b: any, thickness: number, color: any, material: any?, xOffset: number?): any
		local off = Vector3.new(xOffset or 0, 0, 0)
		local pa, pb = a + off, b + off
		local length = (pb - pa).Magnitude
		return visual(name, Vector3.new(thickness, thickness, length), CFrame.lookAt((pa + pb) / 2, pb), color, material or Enum.Material.Metal)
	end

	-- A cylinder along a direction (axis), centred at `center`.
	local function rod(name: string, center: any, axis: any, length: number, diameter: number, color: any, material: any?): any
		local x = axis.Unit
		local helper = if math.abs(x.Y) < 0.9 then Vector3.new(0, 1, 0) else Vector3.new(1, 0, 0)
		local z = x:Cross(helper).Unit
		local y = z:Cross(x).Unit
		return visual(name, Vector3.new(length, diameter, diameter), CFrame.fromMatrix(center, x, y, z), color, material or Enum.Material.Metal, Enum.PartType.Cylinder)
	end

	-- Chassis --------------------------------------------------------------
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = spec.boxSize
	chassis.CFrame = CFrame.new()
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanQuery = false -- the wheels' ground probes must not hit the bike itself
	chassis.CanTouch = true
	chassis.Anchored = false
	chassis.RootPriority = 127
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	local volume = spec.boxSize.X * spec.boxSize.Y * spec.boxSize.Z
	local density = math.clamp(Units.kgToRmu(spec.totalMassKg) / volume, 0.0001, 100)
	chassis.CustomPhysicalProperties = roblox.PhysicalProperties.new(density, 0.4, 0.05, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = chassis
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	promptAttachment.Position = spec.seatTop + Vector3.new(0, 0.5, 0)
	promptAttachment.Parent = chassis

	-- Lean root on the ground under the centre of mass ----------------------
	local leanPivot = CFrame.new(0, -comH, 0)
	local leanRoot = visual("LeanRoot", Vector3.new(0.2, 0.2, 0.2), leanPivot, BLACK)
	leanRoot.Transparency = 1
	motor("LeanJoint", chassis, leanRoot, leanPivot)

	-- Key points (bike space) ----------------------------------------------------
	local rR, rF = spec.rear.radius, spec.front.radius
	local L = spec.wheelbase
	local rearHub = spec.rear.hubRest
	local frontHub = spec.front.hubRest
	local rake = math.rad(25)
	local axisUp = Vector3.new(0, math.cos(rake), math.sin(rake)) -- up the fork, tilted back (+Z is back)
	local forkLength = M(0.78)
	local head = frontHub + axisUp * forkLength
	local pivot = B(0, rR + M(0.12), M(0.58))
	local motorPos = B(0, rR + M(0.06), M(0.72))

	-- Steering root at the head, Y axis along the steering axis --------------------
	local steerCF = CFrame.fromMatrix(head, Vector3.new(1, 0, 0), axisUp)
	local steerRoot = visual("SteerRoot", Vector3.new(0.2, 0.2, 0.2), steerCF, BLACK)
	steerRoot.Transparency = 1
	motor("SteerJoint", leanRoot, steerRoot, steerCF)

	-- Wheels -------------------------------------------------------------------------
	local function wheel(prefix: string, hubCF: any, radius: number, jointParent: any)
		local tireWidth = M(0.13)
		local tire = visual(prefix .. "Tire", Vector3.new(tireWidth, radius * 2, radius * 2), hubCF, RUBBER, TIRE_MATERIAL, Enum.PartType.Cylinder)
		-- Knobs: a ring of small blocks makes the tyre read as off-road and shows rotation.
		for i = 0, 23 do
			local a = i * math.pi * 2 / 24
			local knob = visual("Knob", Vector3.new(tireWidth * 1.05, M(0.03), M(0.035)), hubCF * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius - M(0.008), 0), RUBBER, TIRE_MATERIAL)
			weld(tire, knob)
		end
		local rimRadius = radius * 0.74
		local rim = visual(prefix .. "Rim", Vector3.new(tireWidth * 0.8, rimRadius * 2, rimRadius * 2), hubCF, BLACK, Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(tire, rim)
		local inner = visual(prefix .. "RimInner", Vector3.new(tireWidth * 0.85, rimRadius * 1.86, rimRadius * 1.86), hubCF, Color3.fromRGB(45, 45, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(tire, inner)
		local hub = visual(prefix .. "Hub", Vector3.new(tireWidth * 1.4, radius * 0.28, radius * 0.28), hubCF, ALU, Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(tire, hub)
		for i = 0, 11 do
			local a = i * math.pi * 2 / 12
			local spoke = visual("Spoke", Vector3.new(0.04, rimRadius * 0.9, 0.04), hubCF * CFrame.Angles(a, 0, 0) * CFrame.new((i % 2 - 0.5) * tireWidth * 0.4, rimRadius * 0.5, 0), ALU, Enum.Material.Metal)
			weld(tire, spoke)
		end
		local disc = visual(prefix .. "Disc", Vector3.new(0.05, radius * 0.95, radius * 0.95), hubCF * CFrame.new(-tireWidth * 0.75, 0, 0), DISC, Enum.Material.Metal, Enum.PartType.Cylinder)
		weld(tire, disc)
		motor(prefix .. "WheelJoint", jointParent, tire, hubCF)
		return tire
	end

	wheel("Rear", CFrame.new(rearHub), rR, leanRoot)
	-- Front hub frame shares the steering orientation so suspension slides along the fork.
	local frontHubCF = CFrame.fromMatrix(frontHub, Vector3.new(1, 0, 0), axisUp)
	wheel("Front", frontHubCF, rF, steerRoot)

	-- Fork, clamps, bars (move with steering) ---------------------------------------------
	for _, side in { -1, 1 } do
		local x = side * M(0.11)
		local lowerCenter = frontHub + axisUp * (forkLength * 0.28) + Vector3.new(x, 0, 0)
		local upperCenter = frontHub + axisUp * (forkLength * 0.72) + Vector3.new(x, 0, 0)
		weld(steerRoot, rod("ForkLower", lowerCenter, axisUp, forkLength * 0.56, M(0.065), BLACK))
		weld(steerRoot, rod("ForkUpper", upperCenter, axisUp, forkLength * 0.5, M(0.05), GOLD))
	end
	local clampCF = steerCF * CFrame.new(0, M(0.02), 0)
	weld(steerRoot, visual("TripleClamp", Vector3.new(M(0.3), M(0.05), M(0.12)), clampCF, ALU, Enum.Material.Metal))
	local barCenter = head + axisUp * M(0.1) + Vector3.new(0, M(0.04), M(0.08))
	local bars = rod("Handlebar", barCenter, Vector3.new(1, 0, 0), M(0.78), M(0.03), BLACK)
	weld(steerRoot, bars)
	for _, side in { -1, 1 } do
		local grip = rod("Grip", barCenter + Vector3.new(side * M(0.33), 0, 0), Vector3.new(1, 0, 0), M(0.12), M(0.04), RUBBER, TIRE_MATERIAL)
		weld(steerRoot, grip)
		local a = Instance.new("Attachment")
		a.Name = if side < 0 then "LeftGrip" else "RightGrip"
		a.Position = Vector3.new(side * M(0.33), 0, 0)
		a.Parent = bars
	end
	-- Number plate / headlight
	local plateCF = CFrame.lookAt(head + Vector3.new(0, -M(0.05), -M(0.1)), head + Vector3.new(0, -M(0.02), -M(1)))
	weld(steerRoot, visual("NumberPlate", Vector3.new(M(0.26), M(0.24), M(0.03)), plateCF, BLACK, Enum.Material.SmoothPlastic, nil, nil))
	local lens = visual("Headlight", Vector3.new(M(0.16), M(0.07), M(0.03)), plateCF * CFrame.new(0, -M(0.02), -M(0.02)), Color3.fromRGB(255, 250, 235), Enum.Material.Neon)
	weld(steerRoot, lens)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Brightness = 3
	light.Range = 45
	light.Angle = 55
	light.Color = Color3.fromRGB(255, 245, 225)
	light.Parent = lens
	-- Front fender (on the triple clamp, turns with the bars)
	local fenderCF = CFrame.fromMatrix(frontHub + axisUp * (rF + M(0.05)) + Vector3.new(0, 0, -M(0.08)), Vector3.new(1, 0, 0), axisUp) * CFrame.Angles(math.rad(-12), 0, 0)
	weld(steerRoot, visual("FrontFender", Vector3.new(M(0.16), M(0.025), M(0.5)), fenderCF, paint.primary, Enum.Material.SmoothPlastic, nil, "Primary"))

	-- Frame and body (fixed to the lean root) ---------------------------------------------------
	local function body(part: any)
		weld(leanRoot, part)
		return part
	end
	for _, side in { -1, 1 } do
		local x = side * M(0.09)
		body(beam("FrameSpar", head + Vector3.new(0, -M(0.08), M(0.04)), pivot + Vector3.new(0, M(0.18), 0), M(0.06), paint.secondary, Enum.Material.Metal, x))
		body(beam("FrameDown", head + Vector3.new(0, -M(0.18), 0), motorPos + Vector3.new(0, M(0.05), -M(0.18)), M(0.05), paint.secondary, Enum.Material.Metal, x))
		body(beam("Swingarm", pivot, rearHub, M(0.055), ALU, Enum.Material.Metal, side * M(0.1)))
		body(beam("SubFrame", pivot + Vector3.new(0, M(0.2), 0), B(0, comH + M(0.02), M(0.05)), M(0.035), paint.secondary, Enum.Material.Metal, x))
	end
	body(beam("SwingarmBrace", pivot + Vector3.new(-M(0.1), 0, 0), pivot + Vector3.new(M(0.1), 0, 0), M(0.05), ALU))
	body(rod("Motor", motorPos, Vector3.new(1, 0, 0), M(0.2), M(0.2), Color3.fromRGB(55, 58, 64)))
	body(rod("MotorCap", motorPos + Vector3.new(-M(0.105), 0, 0), Vector3.new(1, 0, 0), M(0.02), M(0.14), paint.primary, Enum.Material.Metal))
	body(beam("DriveBelt", motorPos + Vector3.new(-M(0.12), 0, 0), rearHub + Vector3.new(-M(0.12), 0, 0), M(0.025), BLACK, Enum.Material.SmoothPlastic))

	-- Battery box between the frame spars
	local batteryCenter = (head + pivot) / 2 + Vector3.new(0, -M(0.05), 0)
	local batteryDir = (head - pivot).Unit
	body(visual("Battery", Vector3.new(M(0.2), M(0.24), (head - pivot).Magnitude * 0.62), CFrame.lookAt(batteryCenter, batteryCenter + batteryDir), Color3.fromRGB(40, 42, 46), Enum.Material.Metal))
	-- Side shrouds (painted) with a contrasting stripe
	for _, side in { -1, 1 } do
		local shroudCF = CFrame.lookAt(batteryCenter + Vector3.new(side * M(0.115), M(0.03), 0), batteryCenter + Vector3.new(side * M(0.115), M(0.03), 0) + batteryDir)
		body(visual("Shroud", Vector3.new(M(0.02), M(0.2), (head - pivot).Magnitude * 0.55), shroudCF, paint.primary, Enum.Material.SmoothPlastic, nil, "Primary"))
		body(visual("Stripe", Vector3.new(M(0.022), M(0.04), (head - pivot).Magnitude * 0.45), shroudCF * CFrame.new(0, -M(0.06), 0), paint.accent, Enum.Material.SmoothPlastic, nil, "Accent"))
	end

	-- Rear shock (gold spring)
	local shockBottom = rearHub:Lerp(pivot, 0.45) + Vector3.new(0, M(0.05), 0)
	local shockTop = pivot + Vector3.new(0, M(0.32), -M(0.05))
	body(rod("ShockSpring", (shockBottom + shockTop) / 2, shockTop - shockBottom, (shockTop - shockBottom).Magnitude * 0.7, M(0.07), GOLD))
	body(rod("ShockBody", (shockBottom + shockTop) / 2, shockTop - shockBottom, (shockTop - shockBottom).Magnitude, M(0.035), BLACK))

	-- Seat and tail
	local seatTopY = spec.seatTop.Y
	local seatFront = B(0, 0, comR + M(0.3))
	local seatBack = B(0, 0, M(0.12))
	local seatLength = math.abs(seatFront.Z - seatBack.Z)
	local seatCenter = Vector3.new(0, seatTopY - M(0.05), (seatFront.Z + seatBack.Z) / 2)
	body(visual("SeatPad", Vector3.new(M(0.22), M(0.1), seatLength), CFrame.new(seatCenter), BLACK, SEAT_MATERIAL))
	local tailCF = CFrame.new(Vector3.new(0, seatTopY - M(0.06), seatBack.Z + M(0.25))) * CFrame.Angles(math.rad(-10), 0, 0)
	body(visual("RearFender", Vector3.new(M(0.18), M(0.03), M(0.55)), tailCF, paint.primary, Enum.Material.SmoothPlastic, nil, "Primary"))
	local tail = body(visual("Taillight", Vector3.new(M(0.08), M(0.03), M(0.02)), tailCF * CFrame.new(0, -M(0.02), M(0.27)), Color3.fromRGB(255, 30, 30), Enum.Material.Neon))
	tail:SetAttribute("BrakeLight", true)

	-- Foot pegs (+ attachments for the rider's feet)
	for _, side in { -1, 1 } do
		local pegPos = B(side * M(0.17), rR + M(0.08), M(0.6))
		local peg = body(visual("FootPeg", Vector3.new(M(0.1), M(0.025), M(0.04)), CFrame.new(pegPos), ALU, Enum.Material.DiamondPlate))
		local a = Instance.new("Attachment")
		a.Name = if side < 0 then "LeftPeg" else "RightPeg"
		a.Position = Vector3.new(side * M(0.02), M(0.03), 0)
		a.Parent = peg
	end

	-- Seat the rider sits on (invisible). Top surface at the seat height.
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(M(0.25), 0.2, M(0.3))
	seat.CFrame = CFrame.new(spec.seatTop - Vector3.new(0, 0.1, 0))
	seat.Transparency = 1
	seat.Massless = true
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false -- no sitting by walking into it; the server seats riders
	seat.Anchored = false
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = model
	weld(leanRoot, seat)

	-- Place the model so the tyres rest on Y = 0 at the origin.
	local _ = L
	return model
end

local folder = Instance.new("Folder")
folder.Name = "Vehicles"
local built = {}
for _, config in VehicleCatalog.List do
	if config.category == "ElectricDirtBike" then
		local model = buildDirtBike(config)
		model.Parent = folder
		table.insert(built, config.id)
	end
end

fs.writeFile(OUTPUT_PATH, roblox.serializeModel({ folder }))
print(`Wrote {OUTPUT_PATH} ({table.concat(built, ", ")})`)
