-- Inspects build/PhysicsLab.rbxl, the physics test place.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

return function(t)
	local expect = t.expect
	local game = roblox.deserializePlace(fs.readFile("build/PhysicsLab.rbxl"))
	local workspace = game:GetService("Workspace")
	local lab = workspace:FindFirstChild("PhysicsLab")

	t.it("is marked as the lab and has the lab map (not the game world)", function()
		expect(workspace:GetAttribute("RYDE_Lab")).toBe(true)
		expect(lab ~= nil).toBe(true)
		expect(workspace:FindFirstChild("World")).toBe(nil)
	end)
	t.it("uses the same gravity and game code as the main place", function()
		expect(workspace.Gravity).toBeNear(35, 0.001)
		local main = game:GetService("ServerScriptService"):FindFirstChild("Server")
		assert(main and main:FindFirstChild("Main"), "server code missing")
		local client = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client")
		assert(client and client:FindFirstChild("Lab") and client.Lab:FindFirstChild("LabController"), "LabController missing")
	end)
	t.it("has every start marker the autopilot uses", function()
		for _, name in { "Start_Straight", "Start_Kerb", "Start_Pad" } do
			assert(lab:FindFirstChild(name), `missing {name}`)
		end
	end)
	t.it("has bike slots and a spawn", function()
		assert(lab:FindFirstChild("BikeSlots"), "no BikeSlots")
		assert(lab:FindFirstChild("SpawnLocation"), "no SpawnLocation")
	end)
	t.it("the test field is flat asphalt with its top at Y = 0", function()
		local field = lab.Field
		expect(field.Material.Name).toBe("Asphalt")
		expect(field.CFrame.Position.Y + field.Size.Y / 2).toBeNear(0, 1e-4)
	end)
	t.it("the kerb is 15 cm (0.55 studs) high", function()
		expect(lab.Kerb.Size.Y).toBeNear(0.55, 1e-4)
	end)
end
