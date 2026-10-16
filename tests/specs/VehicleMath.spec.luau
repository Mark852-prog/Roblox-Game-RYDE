-- Behaviour the handling is designed around, checked from the real config numbers.
local ModuleLoader = require("../lib/ModuleLoader")
local Shared = ModuleLoader.root("src/shared")
local VehicleCatalog = ModuleLoader.require(Shared.Config.VehicleCatalog)
local VehicleMath = ModuleLoader.require(Shared.Vehicle.VehicleMath)
local Units = ModuleLoader.require(Shared.Util.Units)

local function maxLaunchAccel(spec): number
	-- m/s^2 at very low speed, full throttle
	return spec.config.motor.maxDriveForceN / spec.totalMassKg
end

-- Simple 1-D straight-line simulation on asphalt (studs, seconds).
local function simulate(spec, seconds: number): (number, number?)
	local v, t, dt = 0, 0, 1 / 120
	local timeTo50 = nil
	local target50 = Units.kmhToStudsPerSec(50)
	local rolling = 0.015 * spec.gravity
	while t < seconds do
		local a = VehicleMath.motorAccel(spec, v, 1) - VehicleMath.dragAccel(spec, v) - rolling
		v = math.max(v + a * dt, 0)
		t += dt
		if not timeTo50 and v >= target50 then
			timeTo50 = t
		end
	end
	return v, timeTo50
end

return function(t)
	local expect = t.expect
	local specs = {}
	for _, config in VehicleCatalog.List do
		specs[config.id] = VehicleMath.derive(config)
	end

	t.describe("geometry", function()
		t.it("static sag is a sensible fraction of travel (20-60%)", function()
			for id, spec in specs do
				for _, w in { spec.front, spec.rear } do
					local frac = w.sag / w.travel
					assert(frac > 0.2 and frac <= 0.6, `{id}: sag {frac}`)
				end
			end
		end)
		t.it("weight split adds up to 100%", function()
			for _, spec in specs do
				expect(spec.front.loadShare + spec.rear.loadShare).toBeNear(1)
			end
		end)
		t.it("wheels touch the ground at rest (hub height = radius)", function()
			for _, spec in specs do
				expect(spec.rear.hubRest.Y + spec.comHeight).toBeNear(spec.rear.radius)
				expect(spec.front.hubRest.Y + spec.comHeight).toBeNear(spec.front.radius)
			end
		end)
		t.it("collision box clears the ground at rest", function()
			for id, spec in specs do
				local bottom = spec.comHeight - spec.boxSize.Y / 2
				assert(bottom > 0.5, `{id}: box bottom {bottom}`)
			end
		end)
	end)

	t.describe("acceleration and top speed", function()
		t.it("each vehicle settles near its top speed (90-100%)", function()
			for id, spec in specs do
				local v = simulate(spec, 60)
				local frac = v / spec.topSpeed
				assert(frac > 0.9 and frac <= 1.0, `{id}: reaches {frac * 100}% of top speed`)
			end
		end)
		t.it("Voltra Storm: 0-50 km/h in under 4 s", function()
			local _, t50 = simulate(specs.VoltraStorm, 10)
			assert(t50 and t50 < 4, `took {t50}`)
		end)
		t.it("Kestrel Sting out-accelerates the Voltra Storm", function()
			local _, a = simulate(specs.VoltraStorm, 10)
			local _, b = simulate(specs.KestrelSting, 10)
			expect(b).toBeLessThan(a)
		end)
		t.it("the e-bike is much slower off the line than the dirt bikes", function()
			local _, ebike = simulate(specs.MetroGlide, 20)
			local _, dirt = simulate(specs.VoltraStorm, 10)
			assert(ebike == nil or ebike > dirt * 2, "e-bike too quick")
		end)
	end)

	t.describe("wheelies", function()
		t.it("Voltra Storm needs the rider to lean back to lift the front", function()
			local spec = specs.VoltraStorm
			expect(maxLaunchAccel(spec)).toBeLessThan(VehicleMath.wheelieThreshold(spec, 0))
			expect(maxLaunchAccel(spec)).toBeGreaterThan(VehicleMath.wheelieThreshold(spec, 1))
		end)
		t.it("Kestrel Sting lifts the front even without leaning (more aggressive)", function()
			local spec = specs.KestrelSting
			expect(maxLaunchAccel(spec)).toBeGreaterThan(VehicleMath.wheelieThreshold(spec, 0))
		end)
		t.it("leaning forward keeps the front of every vehicle down", function()
			for id, spec in specs do
				assert(maxLaunchAccel(spec) < VehicleMath.wheelieThreshold(spec, -1) or id == "KestrelSting", `{id} wheelies leaning forward`)
			end
		end)
		t.it("the e-bike and scooter can't power-wheelie", function()
			for _, id in { "MetroGlide", "ZipS1" } do
				expect(maxLaunchAccel(specs[id])).toBeLessThan(VehicleMath.wheelieThreshold(specs[id], 1))
			end
		end)
	end)

	t.describe("braking and stoppies", function()
		t.it("the normal brake (S) never tips a vehicle onto its front wheel", function()
			-- As the bike decelerates, weight moves forward and the rear tyre can
			-- transmit less force (grip = load on asphalt, mu = 1). Iterate to the
			-- steady deceleration and compare with the stoppie threshold.
			for id, spec in specs do
				local c = spec.config
				local m, h, L = spec.totalMassKg, c.chassis.comHeightM, c.chassis.wheelbaseM
				local lf = L - c.chassis.comFromRearM
				local front = c.brakes.frontMaxForceN * VehicleMath.NORMAL_BRAKE_FRONT_SHARE
				local a = 0
				for _ = 1, 50 do
					local rearLoad = math.max(m * (9.81 * lf - a * h) / L, 0)
					local rear = math.min(c.brakes.rearMaxForceN, rearLoad * c.tires.longitudinalGrip)
					a = (front + rear) / m
				end
				assert(a < VehicleMath.stoppieThreshold(spec, 0), `{id}: {a} m/s^2 would endo`)
			end
		end)
		t.it("the normal brake stops the dirt bikes from 50 km/h in 12-16 m", function()
			for _, id in { "VoltraStorm", "KestrelSting" } do
				local spec = specs[id]
				local c = spec.config
				local m, h, L = spec.totalMassKg, c.chassis.comHeightM, c.chassis.wheelbaseM
				local lf = L - c.chassis.comFromRearM
				local front = c.brakes.frontMaxForceN * VehicleMath.NORMAL_BRAKE_FRONT_SHARE
				local a = 0
				for _ = 1, 50 do
					local rear = math.min(c.brakes.rearMaxForceN, math.max(m * (9.81 * lf - a * h) / L, 0) * c.tires.longitudinalGrip)
					a = (front + rear) / m
				end
				local v = 50 / 3.6
				local distance = v * v / (2 * a)
				assert(distance > 12 and distance < 16, `{id}: {distance} m`)
			end
		end)
		t.it("full front brake on the dirt bikes is enough for a stoppie", function()
			for _, id in { "VoltraStorm", "KestrelSting" } do
				local spec = specs[id]
				local decel = spec.config.brakes.frontMaxForceN / spec.totalMassKg
				expect(decel).toBeGreaterThan(VehicleMath.stoppieThreshold(spec, 0))
			end
		end)
	end)

	t.describe("steering and lean", function()
		t.it("steering lock shrinks as speed rises", function()
			local spec = specs.VoltraStorm
			local slow = VehicleMath.maxSteer(spec, 0, 1)
			local fast = VehicleMath.maxSteer(spec, spec.topSpeed, 1)
			expect(slow).toBeNear(math.rad(spec.config.steering.maxSteerDegLowSpeed), 1e-6)
			expect(fast).toBeLessThan(slow / 4)
		end)
		t.it("steering is limited by grip (less lock on ice)", function()
			local spec = specs.VoltraStorm
			local speed = Units.kmhToStudsPerSec(30)
			expect(VehicleMath.maxSteer(spec, speed, 0.12)).toBeLessThan(VehicleMath.maxSteer(spec, speed, 1))
		end)
		t.it("lean angle follows tan(lean) = v*w/g and is clamped", function()
			local spec = specs.VoltraStorm
			expect(VehicleMath.leanAngle(spec, 20, 0.5)).toBeNear(math.atan(20 * 0.5 / spec.gravity), 1e-6)
			expect(VehicleMath.leanAngle(spec, 200, 5)).toBeNear(math.rad(spec.config.steering.maxLeanDeg), 1e-6)
			expect(VehicleMath.leanAngle(spec, 20, -0.5)).toBeLessThan(0)
		end)
	end)
end
