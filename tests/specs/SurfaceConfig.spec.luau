local roblox = require("@lune/roblox")

local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local SurfaceConfig = ModuleLoader.require(Shared.Config.SurfaceConfig)

return function(t)
	local expect = t.expect

	t.describe("table contents", function()
		t.it("asphalt is the grip reference (1.0)", function()
			expect(SurfaceConfig.getByName("Asphalt").grip).toBe(1)
		end)
		t.it("every surface has sane values", function()
			for key, surface in SurfaceConfig.Surfaces do
				assert(type(surface.name) == "string", `{key}: name`)
				assert(surface.grip > 0 and surface.grip <= 1.5, `{key}: grip {surface.grip}`)
				assert(surface.rollingResistance >= 0 and surface.rollingResistance < 1, `{key}: rollingResistance`)
				assert(surface.roughness >= 0 and surface.roughness <= 1, `{key}: roughness`)
				assert(type(surface.effect) == "string", `{key}: effect`)
			end
		end)
		t.it("every key is a real Roblox material name", function()
			local valid = {}
			for _, item in roblox.Enum.Material:GetEnumItems() do
				valid[item.Name] = true
			end
			for key in SurfaceConfig.Surfaces do
				assert(valid[key], `'{key}' is not an Enum.Material name`)
			end
		end)
		t.it("off-road surfaces grip less than asphalt", function()
			for _, name in { "Grass", "Ground", "Sand", "Mud", "Pebble", "Ice" } do
				expect(SurfaceConfig.getByName(name).grip).toBeLessThan(1)
			end
		end)
	end)

	t.describe("resolve", function()
		t.it("uses the material when there is no override", function()
			local p = roblox.Instance.new("Part")
			expect(SurfaceConfig.resolve(p, roblox.Enum.Material.Mud).name).toBe("Mud")
		end)
		t.it("unknown materials fall back to Default", function()
			expect(SurfaceConfig.resolve(nil, roblox.Enum.Material.Neon).name).toBe("Default")
		end)
		t.it("a 'Surface' attribute overrides the material", function()
			local p = roblox.Instance.new("Part")
			p:SetAttribute("Surface", "Ice")
			expect(SurfaceConfig.resolve(p, roblox.Enum.Material.SmoothPlastic).name).toBe("Ice")
		end)
		t.it("an invalid 'Surface' attribute is ignored", function()
			local p = roblox.Instance.new("Part")
			p:SetAttribute("Surface", "NotARealSurface")
			expect(SurfaceConfig.resolve(p, roblox.Enum.Material.Asphalt).name).toBe("Asphalt")
		end)
	end)
end
