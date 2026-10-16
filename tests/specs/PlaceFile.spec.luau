-- Inspects build/RYDE.rbxl, the file you open in Roblox Studio.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local PLACE_PATH = "build/RYDE.rbxl"

return function(t)
	local expect = t.expect

	local game = roblox.deserializePlace(fs.readFile(PLACE_PATH))
	local workspace = game:GetService("Workspace")

	local function find(path: { string }): any
		local node = game
		for _, name in path do
			node = node and node:FindFirstChild(name)
		end
		return node
	end

	t.describe("scripts are in the right places", function()
		t.it("server entry script is a Script in ServerScriptService", function()
			local main = find({ "ServerScriptService", "Server", "Main" })
			expect(main and main.ClassName).toBe("Script")
		end)
		t.it("client entry script is a LocalScript in StarterPlayerScripts", function()
			local main = find({ "StarterPlayer", "StarterPlayerScripts", "Client", "Main" })
			expect(main and main.ClassName).toBe("LocalScript")
		end)
		t.it("shared modules are ModuleScripts in ReplicatedStorage", function()
			for _, path in {
				{ "Config", "GameConfig" },
				{ "Config", "SurfaceConfig" },
				{ "Config", "VehicleCatalog" },
				{ "Config", "Vehicles", "VoltraStorm" },
				{ "Util", "Units" },
				{ "Vehicle", "VehicleSchema" },
			} do
				local node = find({ "ReplicatedStorage", "Shared", table.unpack(path) })
				assert(node and node.ClassName == "ModuleScript", `missing {table.concat(path, ".")}`)
				assert(#node.Source > 0, `{table.concat(path, ".")} has no source`)
			end
		end)
	end)

	t.describe("world settings", function()
		t.it("gravity is 28.03", function()
			expect(workspace.Gravity).toBeNear(28.03, 0.001)
		end)
		t.it("characters use JumpHeight (4 studs), not legacy JumpPower", function()
			-- With JumpPower 50 and real gravity a character would jump ~44 studs.
			local starterPlayer = game:GetService("StarterPlayer")
			expect(starterPlayer.CharacterUseJumpPower).toBe(false)
			expect(starterPlayer.CharacterJumpHeight).toBeNear(4)
		end)
		t.it("streaming is off for the small test map", function()
			expect(workspace.StreamingEnabled).toBe(false)
		end)
	end)

	t.describe("test track", function()
		local track = workspace:FindFirstChild("TestTrack")

		t.it("exists", function()
			expect(track ~= nil).toBe(true)
		end)
		t.it("has a spawn location on the plaza", function()
			local spawn = track:FindFirstChild("SpawnLocation", true)
			expect(spawn and spawn.ClassName).toBe("SpawnLocation")
			expect(spawn.Anchored).toBe(true)
		end)
		t.it("has every test zone", function()
			for _, zone in { "Ground", "OvalTrack", "SpawnPlaza", "SkillsPad", "JumpPark", "SurfaceStrips", "BumpsLane", "Hill", "DirtTrail", "CrashLane" } do
				assert(track:FindFirstChild(zone), `missing zone {zone}`)
			end
		end)
		t.it("only cones and crates are unanchored", function()
			for _, d in track:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					assert(d.Name == "Cone" or d.Name == "Crate", `{d:GetFullName()} is unanchored`)
				end
			end
		end)
		t.it("no part exceeds Roblox's 2048-stud size limit", function()
			for _, d in track:GetDescendants() do
				if d:IsA("BasePart") then
					local s = d.Size
					assert(s.X <= 2048 and s.Y <= 2048 and s.Z <= 2048, `{d:GetFullName()} too large`)
				end
			end
		end)
		t.it("road paint does not collide or block raycasts", function()
			for _, d in track:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "Paint" or d.Name == "Marker" or d.Name == "GroundLabel") then
					assert(not d.CanCollide and not d.CanQuery, `{d:GetFullName()} should be decoration only`)
				end
			end
		end)
		t.it("main surfaces sit at Y = 0.1", function()
			local main = track.OvalTrack.MainStraight
			expect(main.CFrame.Position.Y + main.Size.Y / 2).toBeNear(0.1, 1e-4)
		end)
	end)
end
