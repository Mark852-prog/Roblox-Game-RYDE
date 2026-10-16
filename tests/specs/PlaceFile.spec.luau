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
		t.it("gravity is 35 (realistic)", function()
			expect(workspace.Gravity).toBeNear(35, 0.001)
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

	t.describe("lighting", function()
		t.it("uses Future lighting with atmosphere and post-processing", function()
			local lighting = game:GetService("Lighting")
			expect(lighting.Technology.Name).toBe("Future")
			for _, name in { "Atmosphere", "Bloom", "ColorCorrection", "SunRays" } do
				assert(lighting:FindFirstChild(name), `missing Lighting.{name}`)
			end
		end)
		t.it("terrain grass decoration is on", function()
			expect(workspace.Terrain.Decoration).toBe(true)
		end)
	end)

	t.describe("world", function()
		local world = workspace:FindFirstChild("World")

		t.it("exists", function()
			expect(world ~= nil).toBe(true)
		end)
		t.it("has a spawn location on the plaza", function()
			local spawn = world:FindFirstChild("SpawnLocation", true)
			expect(spawn and spawn.ClassName).toBe("SpawnLocation")
			expect(spawn.Anchored).toBe(true)
		end)
		t.it("has every zone", function()
			for _, zone in { "Ground", "OvalTrack", "SpawnPlaza", "SkillsPad", "JumpPark", "SurfaceStrips", "BumpsLane", "Hill", "DirtTrail", "CrashLane", "Garage", "Town", "Lake", "Trees" } do
				assert(world:FindFirstChild(zone), `missing zone {zone}`)
			end
		end)
		t.it("garage has the lobby turntable, menu camera and bike slots", function()
			local garage = world.Garage
			assert(garage:FindFirstChild("Turntable"), "no Turntable")
			assert(garage:FindFirstChild("MenuCamera"), "no MenuCamera")
			local slots = garage:FindFirstChild("BikeSlots")
			local count = 0
			for _, child in slots:GetChildren() do
				if child.Name:match("^Slot") then
					count += 1
				end
			end
			expect(count >= 6).toBe(true)
		end)
		t.it("only cones and crates are unanchored", function()
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") and not d.Anchored then
					assert(d.Name == "Cone" or d.Name == "Crate", `{d:GetFullName()} is unanchored`)
				end
			end
		end)
		t.it("no part exceeds Roblox's 2048-stud size limit", function()
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") then
					local s = d.Size
					assert(s.X <= 2048 and s.Y <= 2048 and s.Z <= 2048, `{d:GetFullName()} too large`)
				end
			end
		end)
		t.it("decoration (paint, leaves, labels) does not collide or block wheel probes", function()
			local decorative = { Paint = true, Marker = true, GroundLabel = true, Leaves = true, Needles = true, Shrub = true }
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") and decorative[d.Name] then
					assert(not d.CanCollide and not d.CanQuery, `{d:GetFullName()} should be decoration only`)
				end
			end
		end)
		t.it("main surfaces sit at Y = 0.1", function()
			local main = world.OvalTrack.MainStraight
			expect(main.CFrame.Position.Y + main.Size.Y / 2).toBeNear(0.1, 1e-4)
		end)
		t.it("stays under 8000 parts", function()
			local count = 0
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
			expect(count < 8000).toBe(true)
		end)
	end)

	t.describe("vehicle assets", function()
		local vehicles = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		vehicles = vehicles and vehicles:FindFirstChild("Vehicles")
		t.it("are in ReplicatedStorage.Assets.Vehicles", function()
			expect(vehicles ~= nil).toBe(true)
			assert(vehicles:FindFirstChild("VoltraStorm"), "no VoltraStorm model")
		end)
	end)
end
