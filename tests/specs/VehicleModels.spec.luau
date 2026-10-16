-- Structure of the generated bike models (assets/Vehicles.rbxm) that the game code relies on.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local VehicleCatalog = ModuleLoader.require(Shared.Config.VehicleCatalog)
local VehicleMath = ModuleLoader.require(Shared.Vehicle.VehicleMath)
local Units = ModuleLoader.require(Shared.Util.Units)

return function(t)
	local expect = t.expect
	local folder = roblox.deserializeModel(fs.readFile("assets/Vehicles.rbxm"))[1]

	for _, model in folder:GetChildren() do
		t.describe(model.Name, function()
			local config = VehicleCatalog.get(model.Name)
			local spec = VehicleMath.derive(config)
			local chassis = model:FindFirstChild("Chassis")

			t.it("has a config and Chassis as PrimaryPart", function()
				expect(config ~= nil).toBe(true)
				expect(model.PrimaryPart).toBe(chassis)
			end)
			t.it("Chassis is the only part with mass", function()
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and d ~= chassis then
						assert(d.Massless, `{d.Name} is not massless`)
						assert(not d.CanCollide, `{d.Name} collides`)
						assert(not d.CanQuery, `{d.Name} blocks raycasts`)
					end
				end
			end)
			t.it("Chassis weighs bike + rider", function()
				local s = chassis.Size
				local massKg = chassis.CustomPhysicalProperties.Density * s.X * s.Y * s.Z * Units.KG_PER_RMU
				expect(massKg).toBeNear(spec.totalMassKg, 0.5)
			end)
			t.it("Chassis is excluded from wheel probes and has max root priority", function()
				expect(chassis.CanQuery).toBe(false)
				expect(chassis.RootPriority).toBe(127)
			end)
			t.it("has the animation joints", function()
				for _, pair in { { "LeanRoot", "LeanJoint" }, { "SteerRoot", "SteerJoint" }, { "FrontTire", "FrontWheelJoint" }, { "RearTire", "RearWheelJoint" } } do
					local part = model:FindFirstChild(pair[1])
					local joint = part and part:FindFirstChild(pair[2])
					assert(joint and joint.ClassName == "Motor6D", `missing {pair[1]}.{pair[2]}`)
				end
			end)
			t.it("seat can't be sat in by touching it", function()
				local seat = model:FindFirstChild("Seat")
				expect(seat.ClassName).toBe("Seat")
				expect(seat.CanTouch).toBe(false)
			end)
			t.it("has grip and peg attachments for the rider IK", function()
				for _, name in { "LeftGrip", "RightGrip", "LeftPeg", "RightPeg" } do
					assert(model:FindFirstChild(name, true), `missing {name}`)
				end
			end)
			t.it("has a prompt attachment", function()
				assert(chassis:FindFirstChild("PromptAttachment"), "missing PromptAttachment")
			end)
		end)
	end
end
