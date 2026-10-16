--!strict
--[[
	VehicleEffects (every client, every nearby bike)

	Particles that respond to what the bike is actually doing:
	  * Dust / dirt behind the rear tyre on loose surfaces (dirt, sand, mud,
	    grass, gravel), more with speed and much more when the tyre slides
	    or spins. Tinted per surface.
	  * Pebbles thrown up on gravel and dirt.
	  * Grey tyre smoke when the rear slides on pavement.
	  * Sparks where the bike's metal scrapes the ground (bike on its side,
	    or the chassis touching down) while moving.

	Emitter looks come from the Creator Store effects the server loads into
	ReplicatedStorage.Assets.Effects (Sparks, Dust, Pebbles). Until they
	arrive - or if they fail - simple built-in emitters are used.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VehicleMath = require(ReplicatedStorage:WaitForChild("Shared").Vehicle.VehicleMath)

export type FrameInfo = {
	speed: number, -- studs/s (forward)
	slip: number, -- tyre usage, > 1 = sliding
	grounded: boolean,
	surfaceEffect: string, -- SurfaceConfig effect family
	parked: boolean,
}

local SURFACE_TINT: { [string]: Color3 } = {
	dust = Color3.fromRGB(196, 168, 128),
	sand = Color3.fromRGB(222, 204, 156),
	mud = Color3.fromRGB(96, 74, 52),
	grass = Color3.fromRGB(120, 128, 78),
	gravel = Color3.fromRGB(160, 154, 144),
	snow = Color3.fromRGB(240, 244, 250),
	none = Color3.fromRGB(205, 205, 205), -- tyre smoke
}
local LOOSE = { dust = true, sand = true, mud = true, grass = true, gravel = true, snow = true }

local VehicleEffects = {}
VehicleEffects.__index = VehicleEffects

export type VehicleEffects = typeof(setmetatable(
	{} :: {
		chassis: BasePart,
		spec: VehicleMath.Spec,
		rearAttachment: Attachment,
		sparkAttachment: Attachment,
		dust: ParticleEmitter?,
		pebbles: ParticleEmitter?,
		sparks: ParticleEmitter?,
		usingImported: boolean,
		accum: { [string]: number },
		params: RaycastParams,
	},
	VehicleEffects
))

local function builtIn(kind: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 1
	if kind == "Sparks" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 120, 30))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new(0.25, 0)
		e.Lifetime = NumberRange.new(0.2, 0.45)
		e.Speed = NumberRange.new(12, 22)
		e.SpreadAngle = Vector2.new(40, 40)
		e.Acceleration = Vector3.new(0, -35, 0)
		e.Drag = 2
	elseif kind == "Pebbles" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Size = NumberSequence.new(0.18)
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Speed = NumberRange.new(6, 11)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Acceleration = Vector3.new(0, -35, 0)
	else
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Drag = 3
		e.Acceleration = Vector3.new(0, 2, 0)
		e.RotSpeed = NumberRange.new(-40, 40)
	end
	return e
end

local function importedTemplate(kind: string): ParticleEmitter?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local template = effects and effects:FindFirstChild(kind)
	return if template and template:IsA("ParticleEmitter") then template else nil
end

function VehicleEffects.new(chassis: BasePart, spec: VehicleMath.Spec, exclude: { Instance }): VehicleEffects
	local rear = Instance.new("Attachment")
	rear.Name = "RYDE_FX_Rear"
	rear.Position = spec.rear.hubRest - Vector3.new(0, spec.rear.radius * 0.9, -0.3)
	rear.Parent = chassis
	local spark = Instance.new("Attachment")
	spark.Name = "RYDE_FX_Spark"
	spark.Parent = chassis
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local self = setmetatable({
		chassis = chassis,
		spec = spec,
		rearAttachment = rear,
		sparkAttachment = spark,
		dust = nil :: ParticleEmitter?,
		pebbles = nil :: ParticleEmitter?,
		sparks = nil :: ParticleEmitter?,
		usingImported = false,
		accum = { dust = 0, pebbles = 0, sparks = 0 },
		params = params,
	}, VehicleEffects)
	self:refreshEmitters()
	return self
end

-- (Re)create emitters, preferring the imported Creator Store effects.
function VehicleEffects.refreshEmitters(self: VehicleEffects)
	local haveImported = importedTemplate("Dust") ~= nil or importedTemplate("Sparks") ~= nil
	if self.dust and (self.usingImported or not haveImported) then
		return
	end
	for _, e in { self.dust, self.pebbles, self.sparks } do
		if e then
			e:Destroy()
		end
	end
	local function make(kind: string, parent: Attachment): ParticleEmitter
		local template = importedTemplate(kind)
		local e = if template then template:Clone() else builtIn(kind)
		e.Enabled = false
		e.Parent = parent
		return e
	end
	self.dust = make("Dust", self.rearAttachment)
	self.pebbles = make("Pebbles", self.rearAttachment)
	self.sparks = make("Sparks", self.sparkAttachment)
	self.usingImported = haveImported
end

local function emit(self: VehicleEffects, key: string, emitter: ParticleEmitter?, rate: number, dt: number)
	if not emitter or rate <= 0 then
		self.accum[key] = 0
		return
	end
	self.accum[key] += rate * dt
	local n = math.floor(self.accum[key])
	if n > 0 then
		self.accum[key] -= n
		emitter:Emit(math.min(n, 30))
	end
end

function VehicleEffects.update(self: VehicleEffects, dt: number, info: FrameInfo)
	if not self.usingImported then
		self:refreshEmitters()
	end
	local speedFrac = math.clamp(math.abs(info.speed) / self.spec.topSpeed, 0, 1.2)
	local sliding = info.slip > 1.02

	-- Dust / smoke / pebbles from the rear tyre.
	local dustRate, pebbleRate = 0, 0
	if info.grounded and not info.parked and math.abs(info.speed) > 2 then
		local effect = info.surfaceEffect
		if LOOSE[effect] then
			dustRate = 12 + 45 * speedFrac + (if sliding then 60 else 0)
			if effect == "gravel" or effect == "dust" then
				pebbleRate = 6 + 18 * speedFrac + (if sliding then 25 else 0)
			end
		elseif sliding then
			dustRate = 35 -- tyre smoke on pavement
		end
		if self.dust then
			self.dust.Color = ColorSequence.new(SURFACE_TINT[effect] or SURFACE_TINT.dust)
		end
	end
	emit(self, "dust", self.dust, dustRate, dt)
	emit(self, "pebbles", self.pebbles, pebbleRate, dt)

	-- Sparks where metal scrapes: find the chassis box corner closest to the ground.
	local sparkRate = 0
	if math.abs(info.speed) > 5 and not info.parked then
		local cf, half = self.chassis.CFrame, self.chassis.Size / 2
		local lowest, lowestY = nil, math.huge
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = cf * Vector3.new(half.X * x, half.Y * y, half.Z * z)
					if corner.Y < lowestY then
						lowest, lowestY = corner, corner.Y
					end
				end
			end
		end
		if lowest then
			local hit = Workspace:Raycast(lowest + Vector3.new(0, 1, 0), Vector3.new(0, -1.6, 0), self.params)
			local onSide = cf.UpVector.Y < 0.45
			if hit and (hit.Position.Y > lowest.Y - 0.35 or onSide) then
				self.sparkAttachment.WorldPosition = hit.Position + Vector3.new(0, 0.1, 0)
				sparkRate = 40 + 80 * speedFrac
			end
		end
	end
	emit(self, "sparks", self.sparks, sparkRate, dt)
end

function VehicleEffects.destroy(self: VehicleEffects)
	self.rearAttachment:Destroy()
	self.sparkAttachment:Destroy()
end

return VehicleEffects
