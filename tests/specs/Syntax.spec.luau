-- Every game script must compile as Luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ModuleLoader = require("../lib/ModuleLoader")

return function(t)
	t.describe("all files in src/ compile", function()
		for _, path in ModuleLoader.listFiles("src") do
			t.it(path, function()
				local ok, err = pcall(luau.compile, fs.readFile(path))
				if not ok then
					error(err)
				end
			end)
		end
	end)
end
