local fs = require("@lune/fs")
local serde = require("@lune/serde")

local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local Units = ModuleLoader.require(Shared.Util.Units)

return function(t)
	local expect = t.expect

	t.describe("conversions", function()
		t.it("1 metre is 1/0.35 studs", function()
			expect(Units.metersToStuds(1)).toBeNear(1 / 0.35)
			expect(Units.studsToMeters(Units.metersToStuds(7.5))).toBeNear(7.5)
		end)
		t.it("km/h round-trips through studs/s", function()
			expect(Units.studsPerSecToKmh(Units.kmhToStudsPerSec(75))).toBeNear(75)
		end)
		t.it("100 km/h is ~79.4 studs/s", function()
			expect(Units.kmhToStudsPerSec(100)).toBeNear(79.365, 0.01)
		end)
		t.it("mph conversion matches km/h conversion", function()
			local studs = 50
			expect(Units.studsPerSecToMph(studs)).toBeNear(Units.studsPerSecToKmh(studs) / 1.609344, 0.001)
		end)
	end)

	t.describe("gravity", function()
		t.it("GRAVITY_STUDS is real gravity at this scale (28.03)", function()
			expect(Units.GRAVITY_STUDS).toBeNear(28.03, 0.001)
		end)
		t.it("default.project.json sets Workspace.Gravity to GRAVITY_STUDS", function()
			local project = serde.decode("json", fs.readFile("default.project.json"))
			expect(project.tree.Workspace["$properties"].Gravity).toBeNear(Units.GRAVITY_STUDS, 0.001)
		end)
	end)
end
