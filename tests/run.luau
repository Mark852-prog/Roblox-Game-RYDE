--[[
	Runs all automated tests.

	    lune run tests/run

	Run from the repository root. Build the place first (tools/build.sh) so
	the place-file checks inspect the latest build.
]]

local process = require("@lune/process")

local TestRunner = require("./lib/TestRunner")

local results = TestRunner.run({
	["1 Syntax"] = require("./specs/Syntax.spec"),
	["2 Units"] = require("./specs/Units.spec"),
	["3 SurfaceConfig"] = require("./specs/SurfaceConfig.spec"),
	["4 VehicleConfigs"] = require("./specs/VehicleConfigs.spec"),
	["5 PlaceFile"] = require("./specs/PlaceFile.spec"),
})

print(`\n{results.passed} passed, {results.failed} failed`)
if results.failed > 0 then
	print("\nFailures:")
	for _, failure in results.failures do
		print(`  - {failure}`)
	end
	process.exit(1)
end
