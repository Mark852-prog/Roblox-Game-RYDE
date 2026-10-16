--!strict
--[[
	WheelProbe

	Finds where a wheel touches the ground using a sphere cast the size of
	the tyre (so the wheel rolls up curb edges instead of snapping onto them).

	The cast starts one radius above the fully-compressed hub position and
	travels down by radius + travel along the bike's down axis.

	Used by BikePhysics (rider's client) and BikeVisuals (all clients).
]]

local Workspace = game:GetService("Workspace")

local VehicleMath = require(script.Parent.VehicleMath)

export type Contact = {
	grounded: boolean,
	compression: number, -- studs, 0 = fully extended, travel = fully compressed
	bottomedBy: number, -- studs beyond full compression (bump-stop), else 0
	position: Vector3, -- contact point on the ground
	normal: Vector3,
	instance: Instance?,
	material: Enum.Material,
}

local WheelProbe = {}

function WheelProbe.newParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = false
	-- Only hit what a bike collides with (the world), never riders.
	-- The group is registered by the server's VehicleService.
	pcall(function()
		params.CollisionGroup = "RYDEVehicles"
	end)
	return params
end

function WheelProbe.probe(chassisCFrame: CFrame, wheel: VehicleMath.WheelSpec, params: RaycastParams): Contact
	local up = chassisCFrame.UpVector
	local mount = chassisCFrame:PointToWorldSpace(wheel.mount)
	local origin = mount + up * wheel.radius
	local distance = wheel.radius + wheel.travel
	local result = Workspace:Spherecast(origin, wheel.radius, -up * distance, params)
	if not result then
		return {
			grounded = false,
			compression = 0,
			bottomedBy = 0,
			position = mount - up * (wheel.travel + wheel.radius),
			normal = up,
			instance = nil,
			material = Enum.Material.Air,
		}
	end
	-- How far the hub sits below its fully-compressed position.
	local hubDrop = result.Distance - wheel.radius
	return {
		grounded = true,
		compression = math.clamp(wheel.travel - hubDrop, 0, wheel.travel),
		bottomedBy = math.max(-hubDrop, 0),
		position = result.Position,
		normal = result.Normal,
		instance = result.Instance,
		material = result.Material,
	}
end

return WheelProbe
