local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local VehicleCatalog = ModuleLoader.require(Shared.Config.VehicleCatalog)
local VehicleSchema = ModuleLoader.require(Shared.Vehicle.VehicleSchema)

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

return function(t)
	local expect = t.expect

	t.describe("catalog", function()
		t.it("every vehicle config is valid", function()
			expect(VehicleCatalog.validateAll()).toBeEmpty()
		end)
		t.it("contains the four planned vehicles", function()
			for _, id in { "VoltraStorm", "KestrelSting", "MetroGlide", "ZipS1" } do
				expect(VehicleCatalog.get(id) ~= nil).toBe(true)
			end
		end)
		t.it("the starter bike is free and is the prototype", function()
			local bike = VehicleCatalog.get("VoltraStorm")
			expect(bike.price).toBe(0)
			expect(bike.status).toBe("Prototype")
		end)
		t.it("ById matches List", function()
			for _, config in VehicleCatalog.List do
				expect(VehicleCatalog.ById[config.id]).toBe(config)
			end
		end)
	end)

	t.describe("validator catches mistakes", function()
		local base = VehicleCatalog.get("VoltraStorm")

		t.it("missing field", function()
			local broken = deepCopy(base)
			broken.motor.topSpeedKmh = nil
			expect(VehicleSchema.validate(broken)).toContainMatch("motor.topSpeedKmh must be a number")
		end)
		t.it("out-of-range value (5000 kg bike)", function()
			local broken = deepCopy(base)
			broken.chassis.massKg = 5000
			expect(VehicleSchema.validate(broken)).toContainMatch("chassis.massKg = 5000 is outside")
		end)
		t.it("NaN value", function()
			local broken = deepCopy(base)
			broken.tires.lateralGrip = 0 / 0
			expect(VehicleSchema.validate(broken)).toContainMatch("tires.lateralGrip must be a number")
		end)
		t.it("centre of mass outside the wheelbase", function()
			local broken = deepCopy(base)
			broken.chassis.comFromRearM = 1.5
			expect(VehicleSchema.validate(broken)).toContainMatch("comFromRearM must be less than")
		end)
		t.it("damage thresholds in the wrong order", function()
			local broken = deepCopy(base)
			broken.damage.minorImpactKmh = 50
			expect(VehicleSchema.validate(broken)).toContainMatch("minorImpactKmh must be below")
		end)
		t.it("high-speed steering larger than low-speed steering", function()
			local broken = deepCopy(base)
			broken.steering.maxSteerDegHighSpeed = 40
			expect(VehicleSchema.validate(broken)).toContainMatch("maxSteerDegHighSpeed must not exceed")
		end)
		t.it("bad category and id", function()
			local broken = deepCopy(base)
			broken.category = "Car"
			broken.id = "9 bad id"
			local problems = VehicleSchema.validate(broken)
			expect(problems).toContainMatch("unknown category Car")
			expect(problems).toContainMatch("id must be letters/digits")
		end)
		t.it("not a table", function()
			expect(VehicleSchema.validate(42)).toContainMatch("not a table")
		end)
	end)
end
