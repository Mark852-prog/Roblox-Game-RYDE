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
	["5 VehicleMath"] = require("./specs/VehicleMath.spec"),
	["6 VehicleModels"] = require("./specs/VehicleModels.spec"),
	["7 SoundConfig"] = require("./specs/SoundConfig.spec"),
	["8 PlaceFile"] = require("./specs/PlaceFile.spec"),
	["9 LabPlace"] = require("./specs/LabPlace.spec"),
})

print(`\n{results.passed} passed, {results.failed} failed`)
if results.failed > 0 then
	print("\nFailures:")
	for _, failure in results.failures do
		print(`  - {failure}`)
	end
	process.exit(1)
end
