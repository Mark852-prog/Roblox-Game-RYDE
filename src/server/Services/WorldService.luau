--!strict
--[[
	WorldService (server)

	Builds the Terrain when the server starts: grass ground, a lake with a
	sandy beach, rolling hills, a free-ride dirt park and a ring of
	mountains that bounds the map. Terrain replicates to every player
	automatically.

	Why at runtime? Terrain is stored as voxels that our build tools can't
	write into the place file, and generating it from code keeps it
	reproducible and easy to change. It takes a moment at server start.
	(In Studio's edit mode you won't see it - press Play.)

	Everything is deterministic (fixed random seed), so every server builds
	the same world. Terrain is kept clear of roads and test zones.
]]

local Workspace = game:GetService("Workspace")

local WorldService = {}

local GROUND_TOP = 0
local GROUND_DEPTH = 12
local MAP = { x1 = -1100, x2 = 1100, z1 = -900, z2 = 1000 }
local LAKE = { x = -650, z = 450, radius = 140, beach = 178 }
local DIRT_PARK = { x1 = 460, x2 = 940, z1 = 610, z2 = 890 }

local function fillGround(terrain: Terrain)
	-- In tiles, to keep each call a reasonable size.
	local tile = 400
	for x = MAP.x1, MAP.x2 - 1, tile do
		for z = MAP.z1, MAP.z2 - 1, tile do
			local sx = math.min(tile, MAP.x2 - x)
			local sz = math.min(tile, MAP.z2 - z)
			terrain:FillBlock(
				CFrame.new(x + sx / 2, GROUND_TOP - GROUND_DEPTH / 2, z + sz / 2),
				Vector3.new(sx, GROUND_DEPTH, sz),
				Enum.Material.Grass
			)
		end
	end
end

local function lake(terrain: Terrain)
	local center = Vector3.new(LAKE.x, 0, LAKE.z)
	local up = CFrame.Angles(0, 0, 0)
	-- Sandy beach ring at ground level.
	terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -2, 0)) * up, 4, LAKE.beach, Enum.Material.Sand)
	-- Bowl: three stepped cuts that the voxel smoothing turns into a slope.
	local steps = { { radius = LAKE.radius, depth = 4 }, { radius = LAKE.radius - 25, depth = 8 }, { radius = LAKE.radius - 55, depth = 12 } }
	for _, step in steps do
		terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -step.depth / 2 + 0.5, 0)), step.depth + 1, step.radius, Enum.Material.Air)
	end
	-- Sand lake bed below the cut.
	terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -14, 0)), 4, LAKE.radius + 4, Enum.Material.Sand)
	-- Fill the hollow with water up to 4 studs below the ground.
	local region = Region3.new(center - Vector3.new(LAKE.radius + 4, 12, LAKE.radius + 4), center + Vector3.new(LAKE.radius + 4, -4, LAKE.radius + 4)):ExpandToGrid(4)
	terrain:ReplaceMaterial(region, 4, Enum.Material.Air, Enum.Material.Water)
end

local function mountains(terrain: Terrain, rng: Random)
	-- A ring of big hills just outside the playable area.
	local function ridge(fromPoint: Vector3, toPoint: Vector3, count: number)
		for i = 0, count do
			local p = fromPoint:Lerp(toPoint, i / count)
			local radius = rng:NextNumber(85, 125)
			local material = if rng:NextNumber() < 0.3 then Enum.Material.Rock else Enum.Material.Grass
			local jitter = Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40))
			terrain:FillBall(p + jitter + Vector3.new(0, -radius * 0.42, 0), radius, material)
		end
	end
	ridge(Vector3.new(MAP.x1 - 60, 0, MAP.z1), Vector3.new(MAP.x1 - 60, 0, MAP.z2), 12)
	ridge(Vector3.new(MAP.x2 + 60, 0, MAP.z1), Vector3.new(MAP.x2 + 60, 0, MAP.z2), 12)
	ridge(Vector3.new(MAP.x1, 0, MAP.z2 + 60), Vector3.new(MAP.x2, 0, MAP.z2 + 60), 14)
	ridge(Vector3.new(MAP.x1, 0, MAP.z1 - 60), Vector3.new(MAP.x2, 0, MAP.z1 - 60), 14)
end

local function rollingHills(terrain: Terrain, rng: Random)
	-- Gentle grassy hills in open countryside (positions chosen away from roads and zones).
	local spots = {
		Vector3.new(-900, 0, -600),
		Vector3.new(-800, 0, -250),
		Vector3.new(-950, 0, 150),
		Vector3.new(-350, 0, 780),
		Vector3.new(80, 0, 820),
		Vector3.new(-700, 0, 800),
		Vector3.new(850, 0, -700),
		Vector3.new(450, 0, -700),
		Vector3.new(-600, 0, -720),
	}
	for _, spot in spots do
		for _ = 1, 3 do
			local radius = rng:NextNumber(45, 80)
			local offset = Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-50, 50))
			terrain:FillBall(spot + offset + Vector3.new(0, -radius * 0.78, 0), radius, Enum.Material.Grass)
		end
	end
end

local function dirtPark(terrain: Terrain, rng: Random)
	-- Free-ride area: dirt ground with rollers and mounds to jump.
	local center = Vector3.new((DIRT_PARK.x1 + DIRT_PARK.x2) / 2, 0, (DIRT_PARK.z1 + DIRT_PARK.z2) / 2)
	terrain:FillBlock(CFrame.new(center + Vector3.new(0, -1.5, 0)), Vector3.new(DIRT_PARK.x2 - DIRT_PARK.x1, 3, DIRT_PARK.z2 - DIRT_PARK.z1), Enum.Material.Ground)
	for _ = 1, 26 do
		local radius = rng:NextNumber(10, 26)
		local p = Vector3.new(rng:NextNumber(DIRT_PARK.x1 + 30, DIRT_PARK.x2 - 30), 0, rng:NextNumber(DIRT_PARK.z1 + 30, DIRT_PARK.z2 - 30))
		terrain:FillBall(p + Vector3.new(0, -radius * rng:NextNumber(0.55, 0.75), 0), radius, Enum.Material.Ground)
	end
	-- A row of rollers along the park's south edge.
	for i = 0, 9 do
		terrain:FillBall(Vector3.new(DIRT_PARK.x1 + 40 + i * 22, -7, DIRT_PARK.z1 + 20), 9, Enum.Material.Ground)
	end
end

local function colours(terrain: Terrain)
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 150, 62))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(132, 98, 66))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(222, 204, 150))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(120, 116, 112))
	terrain.WaterColor = Color3.fromRGB(28, 110, 130)
	terrain.WaterTransparency = 0.45
	terrain.WaterWaveSize = 0.25
	terrain.WaterReflectance = 0.6
end

function WorldService.start()
	local terrain = Workspace.Terrain
	local started = os.clock()
	local rng = Random.new(2024)
	colours(terrain)
	fillGround(terrain)
	mountains(terrain, rng)
	rollingHills(terrain, rng)
	dirtPark(terrain, rng)
	lake(terrain)
	print(string.format("[RYDE] Terrain generated in %.2f s", os.clock() - started))
end

return WorldService
