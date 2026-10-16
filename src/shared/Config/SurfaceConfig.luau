--!strict
--[[
	SurfaceConfig

	Central table of how each ground surface affects riding.

	  grip               Tyre friction multiplier. Dry asphalt = 1.0.
	  rollingResistance  Rolling-resistance coefficient (Crr). Higher = more drag.
	  roughness          0..1. How bumpy the surface feels to the suspension
	                     (used from Milestone 3).
	  effect             Name of the particle/sound family to use later
	                     ("none", "dust", "grass", "gravel", "mud", "sand", "snow", "water").

	Surfaces are looked up by Roblox Material name, so both Parts and Terrain work.
	A Part can override its material with a string attribute named "Surface",
	e.g. a SmoothPlastic part with Surface = "Ice" behaves like ice.

	To add a surface: add a row to Surfaces below. Nothing else needs to change.
]]

export type Surface = {
	name: string,
	grip: number,
	rollingResistance: number,
	roughness: number,
	effect: string,
}

local SurfaceConfig = {}

local function surface(name: string, grip: number, rollingResistance: number, roughness: number, effect: string): Surface
	return {
		name = name,
		grip = grip,
		rollingResistance = rollingResistance,
		roughness = roughness,
		effect = effect,
	}
end

-- Keyed by Enum.Material name (or a custom name used via the "Surface" attribute).
SurfaceConfig.Surfaces = {
	-- Paved
	Asphalt = surface("Asphalt", 1.00, 0.015, 0.02, "none"),
	Concrete = surface("Concrete", 0.95, 0.015, 0.03, "none"),
	Pavement = surface("Pavement", 0.92, 0.018, 0.06, "none"),
	Brick = surface("Brick", 0.85, 0.020, 0.10, "none"),
	Cobblestone = surface("Cobblestone", 0.80, 0.025, 0.25, "none"),
	Slate = surface("Slate", 0.75, 0.020, 0.10, "none"),
	Marble = surface("Marble", 0.70, 0.015, 0.02, "none"),
	Granite = surface("Granite", 0.80, 0.018, 0.05, "none"),

	-- Built / generic part materials
	SmoothPlastic = surface("SmoothPlastic", 0.90, 0.015, 0.00, "none"),
	Plastic = surface("Plastic", 0.90, 0.015, 0.00, "none"),
	Wood = surface("Wood", 0.80, 0.020, 0.05, "none"),
	WoodPlanks = surface("WoodPlanks", 0.80, 0.020, 0.08, "none"),
	Metal = surface("Metal", 0.70, 0.015, 0.02, "none"),
	DiamondPlate = surface("DiamondPlate", 0.75, 0.015, 0.05, "none"),
	CorrodedMetal = surface("CorrodedMetal", 0.75, 0.018, 0.05, "none"),

	-- Off-road
	Ground = surface("Dirt", 0.70, 0.050, 0.30, "dust"),
	Grass = surface("Grass", 0.60, 0.060, 0.30, "grass"),
	LeafyGrass = surface("LeafyGrass", 0.55, 0.070, 0.35, "grass"),
	Pebble = surface("Gravel", 0.60, 0.080, 0.45, "gravel"),
	Rock = surface("Rock", 0.75, 0.030, 0.40, "gravel"),
	Basalt = surface("Basalt", 0.75, 0.030, 0.35, "gravel"),
	Sandstone = surface("Sandstone", 0.70, 0.030, 0.25, "dust"),
	Limestone = surface("Limestone", 0.70, 0.030, 0.25, "dust"),
	Sand = surface("Sand", 0.50, 0.150, 0.30, "sand"),
	Mud = surface("Mud", 0.40, 0.120, 0.40, "mud"),
	Salt = surface("Salt", 0.55, 0.050, 0.20, "dust"),

	-- Slippery
	Snow = surface("Snow", 0.35, 0.090, 0.20, "snow"),
	Ice = surface("Ice", 0.12, 0.010, 0.00, "none"),
	Glacier = surface("Glacier", 0.15, 0.012, 0.05, "none"),
	Water = surface("Water", 0.20, 0.300, 0.10, "water"),
}

-- Used for any material not listed above.
SurfaceConfig.Default = surface("Default", 0.85, 0.020, 0.05, "none")

-- Look up a surface by material name ("Asphalt", "Ground", ...).
function SurfaceConfig.getByName(name: string): Surface
	return SurfaceConfig.Surfaces[name] or SurfaceConfig.Default
end

--[[
	Resolve the surface for a raycast hit.
	  hitInstance  RaycastResult.Instance (may be nil)
	  material     RaycastResult.Material
]]
function SurfaceConfig.resolve(hitInstance: Instance?, material: EnumItem): Surface
	if hitInstance then
		local override = hitInstance:GetAttribute("Surface")
		if typeof(override) == "string" and SurfaceConfig.Surfaces[override] then
			return SurfaceConfig.Surfaces[override]
		end
	end
	return SurfaceConfig.getByName(material.Name)
end

return SurfaceConfig
