--!strict
--[[
	AssetImportService (server)

	Loads the Creator Store bikes and effects listed in ImportedAssets and
	makes them usable:

	  1. AssetService:LoadAssetAsync (needs "Allow Loading Third Party
	     Assets", set in the project file). Loaded models are sandboxed by
	     Roblox; we also delete every script, seat, physics object, sound and
	     light so nothing from the asset can run or interfere.
	  2. Fit each bike style onto our physics bike:
	       - find the bike's length axis and which end is the front
	         (part names like "handlebar"/"fork"/"headlight", else the highest
	         point, which on a dirt bike is the handlebar);
	       - find wheel parts by name (wheel/tire/rim/spoke/...) and use the
	         distance between them to scale the model to our wheelbase;
	         without wheels, scale by overall length;
	       - line it up with our wheels, then weld it on: wheel parts to our
	         spinning wheel joints, fork/bar parts to the steering joint,
	         everything else to the leaning body;
	       - hide our built-in visual parts.
	  3. Publish fitted models to ReplicatedStorage.Assets.Styles.<VehicleId>.<StyleKey>
	     (the server spawns from them; clients use them in the garage).

	Everything prints a short report to Output ("[RYDE] Import ...") so
	problems with a particular asset are easy to see. If anything fails the
	built-in model stays in use.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ImportedAssets = require(Shared.Config.ImportedAssets)
local VehicleCatalog = require(Shared.Config.VehicleCatalog)
local VehicleMath = require(Shared.Vehicle.VehicleMath)

local AssetImportService = {}

local PREFIX = "[RYDE] Import"

local REMOVE_CLASSES = {
	"LuaSourceContainer",
	"Seat",
	"VehicleSeat",
	"Humanoid",
	"Constraint",
	"JointInstance",
	"WeldConstraint",
	"NoCollisionConstraint",
	"BodyMover",
	"ProximityPrompt",
	"ClickDetector",
	"DragDetector",
	"Sound",
	"Light",
	"ParticleEmitter",
	"Fire",
	"Smoke",
	"Sparkles",
	"Trail",
	"Beam",
	"Tool",
	"Camera",
	"BillboardGui",
	"ScreenGui",
	"Explosion",
	"ForceField",
}

local WHEEL_NAMES = { "wheel", "tire", "tyre", "rim", "spoke", "hub", "rotor", "disc", "disk", "knob" }
local FRONT_NAMES = { "handle", "bar", "grip", "fork", "front", "head", "lamp", "light", "steer", "clamp", "plate", "number", "mirror", "throttle", "lever", "dash", "display", "stanchion" }
local REAR_NAMES = { "rear", "back", "swing", "tail", "chain", "sprocket", "shock", "exhaust", "license" }
local STEER_NAMES = { "handle", "bar", "grip", "fork", "clamp", "lamp", "light", "plate", "number", "mirror", "throttle", "lever", "dash", "display", "stanchion", "steer" }

local ready = false
local styleFolder: Folder
local effectsFolder: Folder

local function nameMatches(name: string, list: { string }): boolean
	local lower = string.lower(name)
	for _, word in list do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local function fullName(part: Instance): string
	-- Parent names count too ("FrontWheel" model containing "Part" children).
	local names = {}
	local node: Instance? = part
	for _ = 1, 4 do
		if not node or node:IsA("DataModel") then
			break
		end
		table.insert(names, node.Name)
		node = node.Parent
	end
	return table.concat(names, " ")
end

local function load(assetId: number): Model?
	local ok, result = pcall(function()
		return AssetService:LoadAssetAsync(assetId)
	end)
	if not ok or not result then
		warn(`{PREFIX} asset {assetId} failed to load: {result}`)
		return nil
	end
	return result :: Model
end

local function sanitize(model: Instance): number
	local removed = 0
	for _, d in model:GetDescendants() do
		for _, className in REMOVE_CLASSES do
			if d:IsA(className) then
				d:Destroy()
				removed += 1
				break
			end
		end
	end
	return removed
end

local function partsOf(model: Instance): { BasePart }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- World-axis bounding box of a set of parts.
local function bounds(parts: { BasePart }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local cf, half = p.CFrame, p.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local c = cf * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					lo = lo:Min(c)
					hi = hi:Max(c)
				end
			end
		end
	end
	return lo, hi
end

type Fit = {
	model: Model,
	report: string,
}

local function fitStyle(vehicleTemplate: Model, styleModel: Model, spec: VehicleMath.Spec, styleName: string): Fit?
	local parts = partsOf(styleModel)
	if #parts == 0 then
		return nil
	end
	local lo, hi = bounds(parts)
	local size = hi - lo
	local centre = (lo + hi) / 2

	-- Length axis: the longer horizontal extent.
	local axis = if size.X >= size.Z then Vector3.xAxis else Vector3.zAxis
	local length = if axis == Vector3.xAxis then size.X else size.Z
	local function along(p: Vector3): number
		return (p - centre):Dot(axis)
	end

	-- Which end is the front?
	local frontScore, method = 0, "names"
	for _, p in parts do
		local n = fullName(p)
		if nameMatches(n, FRONT_NAMES) and not nameMatches(n, REAR_NAMES) then
			frontScore += math.sign(along(p.Position))
		elseif nameMatches(n, REAR_NAMES) then
			frontScore -= math.sign(along(p.Position))
		end
	end
	if frontScore == 0 then
		method = "highest point"
		local top, topPart = -math.huge, nil
		for _, p in parts do
			local _, phi = bounds({ p })
			if phi.Y > top then
				top, topPart = phi.Y, p
			end
		end
		frontScore = if topPart then math.sign(along(topPart.Position)) else 1
	end
	local forward = axis * (if frontScore >= 0 then 1 else -1)

	-- Wheels.
	local frontWheel, rearWheel = {}, {}
	for _, p in parts do
		if nameMatches(fullName(p), WHEEL_NAMES) then
			if (p.Position - centre):Dot(forward) >= 0 then
				table.insert(frontWheel, p)
			else
				table.insert(rearWheel, p)
			end
		end
	end
	local wheelsFound = #frontWheel > 0 and #rearWheel > 0
	local frontCentre, rearCentre
	if wheelsFound then
		local flo, fhi = bounds(frontWheel)
		local rlo, rhi = bounds(rearWheel)
		frontCentre, rearCentre = (flo + fhi) / 2, (rlo + rhi) / 2
		local measured = (frontCentre - rearCentre):Dot(forward)
		if measured < length * 0.3 then
			wheelsFound = false -- implausible (e.g. both groups at one end)
		end
	end

	-- Scale.
	local scale
	if wheelsFound then
		scale = spec.wheelbase / (frontCentre - rearCentre):Dot(forward)
	else
		scale = (spec.wheelbase + spec.front.radius + spec.rear.radius + 0.3) / length
	end
	if scale < 0.05 or scale > 20 then
		return nil
	end

	-- Frame of the imported bike: origin at the reference point, -Z = forward, +Y = up.
	local refPoint
	if wheelsFound then
		refPoint = rearCentre
	else
		refPoint = Vector3.new(centre.X, lo.Y, centre.Z) - forward * (length / 2)
	end
	local sourceFrame = CFrame.lookAt(refPoint, refPoint + forward)

	-- Where that reference point goes on our bike (chassis local space).
	local targetLocal
	if wheelsFound then
		targetLocal = CFrame.new(spec.rear.hubRest)
	else
		-- Bottom-back corner of the bike: ground level, behind the rear wheel.
		targetLocal = CFrame.new(0, -spec.comHeight, spec.comFromRear + spec.rear.radius + 0.15)
	end

	local model = vehicleTemplate:Clone()
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	local leanRoot = model:FindFirstChild("LeanRoot") :: BasePart
	local steerRoot = model:FindFirstChild("SteerRoot") :: BasePart
	local frontTire = model:FindFirstChild("FrontTire") :: BasePart
	local rearTire = model:FindFirstChild("RearTire") :: BasePart
	local chassisCF = chassis.CFrame

	-- Hide the built-in visuals (keep joints and the parts that carry them).
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= chassis then
			d.Transparency = 1
		elseif d:IsA("SpotLight") then
			d.Enabled = false
		end
	end

	-- Transform: source frame -> target, with uniform scale about the reference point.
	local function place(cf: CFrame): CFrame
		local rel = sourceFrame:ToObjectSpace(cf)
		rel = CFrame.new(rel.Position * scale) * rel.Rotation
		return chassisCF * targetLocal * rel
	end

	local function weld(part0: BasePart, part1: BasePart)
		local w = Instance.new("Weld")
		w.Part0 = part0
		w.Part1 = part1
		w.C0 = part0.CFrame:Inverse() * part1.CFrame
		w.C1 = CFrame.new()
		w.Parent = part1
	end

	-- Re-centre the wheel joints on the imported wheels so they spin about the right point.
	local function recentreWheel(tire: BasePart, jointName: string, wheelCentreSource: Vector3)
		local joint = tire:FindFirstChild(jointName) :: Motor6D?
		if not joint or not joint.Part0 then
			return
		end
		local centreWorld = place(CFrame.new(wheelCentreSource)).Position
		local frame = CFrame.fromMatrix(centreWorld, (joint.Part0 :: BasePart).CFrame.RightVector, (joint.Part0 :: BasePart).CFrame.UpVector)
		tire.CFrame = frame
		joint.C0 = (joint.Part0 :: BasePart).CFrame:Inverse() * frame
		joint.C1 = CFrame.new()
	end
	if wheelsFound then
		recentreWheel(rearTire, "RearWheelJoint", rearCentre)
		recentreWheel(frontTire, "FrontWheelJoint", frontCentre)
	end

	local imported = Instance.new("Model")
	imported.Name = "Style"
	imported:SetAttribute("StyleName", styleName)
	local frontWheelSet, rearWheelSet = {}, {}
	for _, p in frontWheel do
		frontWheelSet[p] = true
	end
	for _, p in rearWheel do
		rearWheelSet[p] = true
	end
	local names: { [BasePart]: string } = {}
	for _, p in parts do
		names[p] = fullName(p) -- before re-parenting (parent names carry hints like "FrontWheel")
	end
	local steered = 0
	for _, p in parts do
		local newCF = place(p.CFrame)
		p.Size *= scale
		p.CFrame = newCF
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = imported
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			-- File meshes are sized by Scale alone; basic shapes scale with the part.
			if mesh.MeshType == Enum.MeshType.FileMesh then
				mesh.Scale *= scale
			end
			mesh.Offset *= scale
		end
		if wheelsFound and frontWheelSet[p] then
			weld(frontTire, p)
		elseif wheelsFound and rearWheelSet[p] then
			weld(rearTire, p)
		elseif nameMatches(names[p], STEER_NAMES) and (p.Position - chassis.Position):Dot(chassis.CFrame.LookVector) > 0 then
			weld(steerRoot, p)
			steered += 1
		else
			weld(leanRoot, p)
		end
	end
	imported.Parent = model

	local report = string.format(
		"%s: %d parts, front by %s, wheels %s (front %d / rear %d), steering parts %d, scale %.2f",
		styleName,
		#parts,
		method,
		if wheelsFound then "found" else "NOT found (wheels won't spin)",
		#frontWheel,
		#rearWheel,
		steered,
		scale
	)
	model:SetAttribute("StyleReport", report)
	return { model = model, report = report }
end

local function firstEmitter(model: Instance): ParticleEmitter?
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			return d
		end
	end
	return nil
end

local function importEffects()
	for effectName, ids in ImportedAssets.Effects do
		for _, id in ids do
			local model = load(id)
			local emitter = model and firstEmitter(model)
			if emitter then
				local copy = emitter:Clone()
				copy.Name = effectName
				copy.Enabled = false
				copy.Parent = effectsFolder
				print(`{PREFIX} effect {effectName} from asset {id}`)
				break
			end
		end
	end
end

local function importStyles()
	local vehicles = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	-- Load each style once.
	local loaded: { [string]: Model } = {}
	for _, style in ImportedAssets.BikeStyles do
		local model = load(style.assetId)
		if model then
			local removed = sanitize(model)
			loaded[style.key] = model
			print(`{PREFIX} loaded {style.name} ({style.assetId}), removed {removed} unsafe/unneeded objects`)
		end
	end
	-- Fit every style onto every dirt bike.
	for _, config in VehicleCatalog.List do
		local template = vehicles:FindFirstChild(config.id)
		if config.category == "ElectricDirtBike" and template then
			local spec = VehicleMath.derive(config)
			local folder = Instance.new("Folder")
			folder.Name = config.id
			for _, style in ImportedAssets.BikeStyles do
				local source = loaded[style.key]
				if source then
					local ok, fit = pcall(fitStyle, template :: Model, source:Clone(), spec, style.name)
					if ok and fit then
						fit.model.Name = style.key
						fit.model.Parent = folder
						print(`{PREFIX} {config.id} <- {fit.report}`)
					else
						warn(`{PREFIX} could not fit {style.name} onto {config.id}: {fit}`)
					end
				end
			end
			folder.Parent = styleFolder
		end
	end
end

-- Fitted model for a vehicle + style key, or nil (caller falls back to the built-in model).
function AssetImportService.getStyledTemplate(vehicleId: string, styleKey: string?): Model?
	local deadline = os.clock() + 8
	while not ready and os.clock() < deadline do
		task.wait(0.2)
	end
	local folder = styleFolder:FindFirstChild(vehicleId)
	if not folder then
		return nil
	end
	local key = styleKey or ImportedAssets.DefaultStyle[vehicleId]
	local model = key and folder:FindFirstChild(key)
	if not model then
		model = folder:FindFirstChildOfClass("Model")
	end
	return model :: Model?
end

function AssetImportService.start()
	local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
	styleFolder = Instance.new("Folder")
	styleFolder.Name = "Styles"
	styleFolder.Parent = assets
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	effectsFolder.Parent = assets
	task.spawn(function()
		local started = os.clock()
		local ok, err = pcall(function()
			importEffects()
			importStyles()
		end)
		if not ok then
			warn(`{PREFIX} failed: {err}`)
		end
		ready = true
		print(string.format("%s finished in %.1f s", PREFIX, os.clock() - started))
	end)
end

return AssetImportService
