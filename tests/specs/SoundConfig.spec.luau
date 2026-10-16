local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local SoundConfig = ModuleLoader.require(Shared.Config.SoundConfig)

return function(t)
	local expect = t.expect
	t.it("every sound has a valid id, volume and group", function()
		for key, def in SoundConfig.Sounds do
			assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0, `{key}: id`)
			assert(def.volume >= 0 and def.volume <= 10, `{key}: volume`)
			assert(SoundConfig.Groups[def.group] ~= nil, `{key}: unknown group {def.group}`)
		end
	end)
	t.it("engine, tyre and ambience sounds loop; one-shots don't", function()
		for _, key in { "MotorWhine", "TireRoad", "TireDirt", "TireSkid", "Wind", "AmbienceBirds", "LobbyMusic" } do
			expect(SoundConfig.Sounds[key].looped).toBe(true)
		end
		for _, key in { "Landing", "Impact", "UIClick" } do
			expect(SoundConfig.Sounds[key].looped).toBe(false)
		end
	end)
	t.it("builds rbxassetid URIs", function()
		expect(SoundConfig.assetUri(123)).toBe("rbxassetid://123")
	end)
end
