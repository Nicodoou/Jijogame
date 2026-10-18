--!strict
local Runner = require("../Runner")
local RoadSteerLimit = require("../../src/vehicle/core/RoadSteerLimit")
local Steering = require("../../src/vehicle/core/Steering")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample

local SPEED = 30
local CHASSIS: ChassisSample = {
	origin = vector.create(0, 1, 0),
	position = vector.create(0, 1, 0),
	right = vector.create(1, 0, 0),
	up = vector.create(0, 1, 0),
	forward = vector.create(0, 0, -1),
	linearVelocity = vector.create(0, 0, -SPEED),
	angularVelocity = vector.zero,
	mass = 1000,
	gravity = 196.2,
}
local STRAIGHT: RoadSteerLimit.RoadAhead = {
	near = { position = vector.zero, direction = vector.create(0, 0, -1), arcLength = 0 },
	ahead = { position = vector.create(0, 0, -15), direction = vector.create(0, 0, -1), arcLength = 15 },
}
local FULL_RIGHT: VehicleTypes.VehicleControls = { steer = 1, throttle = 0, brake = 0, isHandbrakeOn = false }
local MARGIN = math.rad(VehicleConfig.ROAD_STEER_MARGIN_DEGREES)

Runner.test("the requested angle matches the driver without a road", function()
	local requested = Steering.requestedAngle(FULL_RIGHT, CHASSIS, SPEED, 0, 1, nil)
	Runner.expectNear(requested, Steering.maxAngle(SPEED), 1e-9)
end)

Runner.test("the requested angle is limited by the road", function()
	local requested = Steering.requestedAngle(FULL_RIGHT, CHASSIS, SPEED, 0, 1, STRAIGHT)
	Runner.expectNear(requested, MARGIN, 1e-9)
end)

Runner.test("reversing ignores the road limit", function()
	local requested = Steering.requestedAngle(FULL_RIGHT, CHASSIS, -SPEED, 0, -1, STRAIGHT)
	Runner.expectNear(requested, math.rad(VehicleConfig.STEER_MAX_REVERSE_DEGREES), 1e-9)
end)

Runner.test("the simulator steers the front wheels with the road limit", function()
	local state = VehicleSimulator.newState()
	local _, limitedOutputs = VehicleSimulator.step(state, FULL_RIGHT, CHASSIS, {}, 1 / 60, nil, STRAIGHT)
	Runner.expectNear(limitedOutputs[1].steerAngleRadians, MARGIN, 1e-9)
	local _, freeOutputs = VehicleSimulator.step(state, FULL_RIGHT, CHASSIS, {}, 1 / 60)
	Runner.expectNear(freeOutputs[1].steerAngleRadians, Steering.maxAngle(SPEED), 1e-9)
end)

Runner.finish()
