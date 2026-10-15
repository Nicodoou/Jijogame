--!strict
local Runner = require("../Runner")
local Steering = require("../../src/vehicle/core/Steering")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

local LOW_ANGLE = math.rad(VehicleConfig.STEER_MAX_LOW_SPEED_DEGREES)
local HIGH_ANGLE = math.rad(VehicleConfig.STEER_MAX_HIGH_SPEED_DEGREES)

Runner.test("the maximum steering angle at low speed and below is the low speed angle", function()
	Runner.expectNear(Steering.maxAngle(VehicleConfig.STEER_LOW_SPEED), LOW_ANGLE, 1e-12)
	Runner.expectNear(Steering.maxAngle(0), LOW_ANGLE, 1e-12)
end)

Runner.test("the maximum steering angle at high speed and above is the high speed angle", function()
	Runner.expectNear(Steering.maxAngle(VehicleConfig.STEER_HIGH_SPEED), HIGH_ANGLE, 1e-12)
	Runner.expectNear(Steering.maxAngle(1000), HIGH_ANGLE, 1e-12)
end)

Runner.test("the maximum steering angle goes down in a straight line between the two speeds", function()
	local middleSpeed = (VehicleConfig.STEER_LOW_SPEED + VehicleConfig.STEER_HIGH_SPEED) / 2
	Runner.expectNear(Steering.maxAngle(middleSpeed), (LOW_ANGLE + HIGH_ANGLE) / 2, 1e-12)
end)

Runner.test("the maximum steering angle never grows with the speed", function()
	local previous = Steering.maxAngle(0)
	for speed = 1, 200 do
		local current = Steering.maxAngle(speed)
		Runner.expectEqual(current <= previous + 1e-15, true)
		previous = current
	end
end)

Runner.test("the maximum steering angle at 120 studs per second is less than at 20", function()
	Runner.expectEqual(Steering.maxAngle(120) < Steering.maxAngle(20), true)
end)

Runner.test("going backwards steers like going forward", function()
	Runner.expectNear(Steering.maxAngle(-60), Steering.maxAngle(60), 1e-15)
end)

Runner.test("the steering angle is the input times the maximum", function()
	Runner.expectNear(Steering.angle(1, 0), LOW_ANGLE, 1e-12)
	Runner.expectNear(Steering.angle(-1, 0), -LOW_ANGLE, 1e-12)
	Runner.expectNear(Steering.angle(0.5, 0), LOW_ANGLE / 2, 1e-12)
	Runner.expectEqual(Steering.angle(0, 50), 0)
end)

Runner.test("while drifting the allowed angle goes above the speed limit up to the drift plus a margin", function()
	local margin = math.rad(VehicleConfig.DRIFT_STEER_MARGIN_DEGREES)
	local drift = math.rad(30)
	local allowed = Steering.maxAngleWhileDrifting(60, drift)
	Runner.expectEqual(allowed > Steering.maxAngle(60), true)
	Runner.expectNear(allowed, LOW_ANGLE, 1e-12)
	local smallDrift = math.rad(20)
	Runner.expectNear(Steering.maxAngleWhileDrifting(120, smallDrift), smallDrift + margin, 1e-12)
	Runner.expectNear(Steering.maxAngleWhileDrifting(120, -smallDrift), smallDrift + margin, 1e-12)
end)

Runner.test("going straight the allowed angle is the plain speed limit", function()
	for _, speed in { 0, 20, 60, 120, 300 } do
		Runner.expectNear(Steering.maxAngleWhileDrifting(speed, 0), Steering.maxAngle(speed), 1e-12)
	end
end)

Runner.test("the allowed angle while drifting never goes over the low speed maximum", function()
	Runner.expectNear(Steering.maxAngleWhileDrifting(120, math.rad(80)), LOW_ANGLE, 1e-12)
end)

Runner.finish()
