--!strict
local Runner = require("../Runner")
local RoadSteerLimit = require("../../src/vehicle/core/RoadSteerLimit")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample

local MARGIN = math.rad(VehicleConfig.ROAD_STEER_MARGIN_DEGREES)
local LOOKAHEAD = VehicleConfig.ROAD_STEER_LOOKAHEAD
local WHEELBASE = VehicleConfig.WHEELS[3].offset.z - VehicleConfig.WHEELS[1].offset.z
local SPEED = 30
local BIG_STEER = 1

-- Camino recto hacia -z, o que gira `turn` radianes a la derecha (positivo) entre el punto cercano y el de adelante.
local function roadTurning(turn: number): RoadSteerLimit.RoadAhead
	return {
		near = { position = vector.zero, direction = vector.create(0, 0, -1), arcLength = 100 },
		ahead = {
			position = vector.create(0, 0, -LOOKAHEAD),
			direction = vector.create(math.sin(turn), 0, -math.cos(turn)),
			arcLength = 100 + LOOKAHEAD,
		},
	}
end

-- Auto a `x` studs a la derecha del eje, con su frente girado `heading` radianes a la derecha del camino.
local function carAt(x: number, heading: number): ChassisSample
	return {
		origin = vector.create(x, 1, 0),
		position = vector.create(x, 1, 0),
		right = vector.create(math.cos(heading), 0, math.sin(heading)),
		up = vector.create(0, 1, 0),
		forward = vector.create(math.sin(heading), 0, -math.cos(heading)),
		linearVelocity = vector.create(0, 0, -SPEED),
		angularVelocity = vector.zero,
		mass = 1000,
		gravity = 196.2,
	}
end

local CENTERED = carAt(0, 0)

local function limited(
	steer: number,
	car: ChassisSample,
	road: RoadSteerLimit.RoadAhead?,
	drift: number?,
	speed: number?
): number
	return RoadSteerLimit.limit(steer, car, speed or SPEED, drift or 0, road)
end

local function requiredFor(turn: number): number
	return math.atan(WHEELBASE * turn / LOOKAHEAD)
end

Runner.test("the required angle is atan(wheelbase * curvature) with sign", function()
	local turn = math.rad(30)
	Runner.expectNear(RoadSteerLimit.requiredAngle(roadTurning(turn)) :: number, requiredFor(turn), 1e-6)
	Runner.expectNear(RoadSteerLimit.requiredAngle(roadTurning(-turn)) :: number, -requiredFor(turn), 1e-6)
	Runner.expectNear(RoadSteerLimit.requiredAngle(roadTurning(0)) :: number, 0, 1e-9)
end)

Runner.test("the required angle is nil when the points are not usable", function()
	local backwards = roadTurning(0.3)
	backwards.ahead.arcLength = backwards.near.arcLength - 1
	Runner.expectEqual(RoadSteerLimit.requiredAngle(backwards), nil)
	local far = roadTurning(0.3)
	far.ahead.arcLength = far.near.arcLength + 1000
	Runner.expectEqual(RoadSteerLimit.requiredAngle(far), nil)
	local vertical = roadTurning(0.3)
	vertical.ahead.direction = vector.create(0, 1, 0)
	Runner.expectEqual(RoadSteerLimit.requiredAngle(vertical), nil)
end)

Runner.test("on a straight the limit is the margin on both sides", function()
	local road = roadTurning(0)
	Runner.expectNear(limited(BIG_STEER, CENTERED, road), MARGIN, 1e-9)
	Runner.expectNear(limited(-BIG_STEER, CENTERED, road), -MARGIN, 1e-9)
	Runner.expectEqual(limited(MARGIN / 2, CENTERED, road), MARGIN / 2)
	Runner.expectEqual(limited(0, CENTERED, road), 0)
end)

Runner.test("in a right curve it allows the required angle plus the margin inward", function()
	local turn = math.rad(40)
	local road = roadTurning(turn)
	Runner.expectNear(limited(BIG_STEER, CENTERED, road), requiredFor(turn) + MARGIN, 1e-6)
	Runner.expectEqual(limited(requiredFor(turn), CENTERED, road), requiredFor(turn))
end)

Runner.test("in a left curve it is the mirror image", function()
	local turn = math.rad(40)
	Runner.expectNear(limited(-BIG_STEER, CENTERED, roadTurning(-turn)), -(requiredFor(turn) + MARGIN), 1e-6)
	Runner.expectEqual(limited(BIG_STEER, CENTERED, roadTurning(-turn)), 0)
end)

Runner.test("steering away from the curve is cut to zero and never reversed", function()
	local road = roadTurning(math.rad(40))
	Runner.expectEqual(limited(-0.3, CENTERED, road), 0)
	Runner.expectEqual(limited(0.01, CENTERED, road), 0.01)
end)

Runner.test("counter steering into a clear drift is free", function()
	local road = roadTurning(0)
	local drift = math.rad(VehicleConfig.DRIFT_ANGLE_THRESHOLD_DEGREES + 5)
	Runner.expectEqual(limited(0.6, CENTERED, road, drift), 0.6)
	Runner.expectEqual(limited(-0.6, CENTERED, road, -drift), -0.6)
	Runner.expectNear(limited(-0.6, CENTERED, road, drift), -MARGIN, 1e-9)
	Runner.expectNear(limited(0.6, CENTERED, road, math.rad(2)), MARGIN, 1e-9)
end)

Runner.test("steering back to the road is free when the car points away from it", function()
	local road = roadTurning(0)
	local pointingAway = carAt(8, math.rad(20))
	Runner.expectEqual(limited(-0.6, pointingAway, road), -0.6)
	Runner.expectNear(limited(0.6, pointingAway, road), MARGIN, 1e-9)
	local pointingToward = carAt(8, math.rad(-20))
	Runner.expectNear(limited(-0.6, pointingToward, road), -MARGIN, 1e-9)
	local leftSide = carAt(-8, math.rad(-20))
	Runner.expectEqual(limited(0.6, leftSide, road), 0.6)
end)

Runner.test("close to the axis steering toward the road is still limited", function()
	local nearAxis = carAt(VehicleConfig.ROAD_STEER_RETURN_DISTANCE / 2, math.rad(10))
	Runner.expectNear(limited(-0.6, nearAxis, roadTurning(0)), -MARGIN, 1e-9)
end)

Runner.test("the limit is off in each of its off conditions", function()
	local road = roadTurning(0)
	local off = table.clone(VehicleConfig)
	off.ROAD_STEER_LIMIT_ENABLED = false
	Runner.expectEqual(RoadSteerLimit.limit(0.6, CENTERED, SPEED, 0, road, off), 0.6)
	Runner.expectEqual(limited(0.6, CENTERED, nil), 0.6)
	Runner.expectEqual(limited(0.6, CENTERED, road, 0, VehicleConfig.ROAD_STEER_MIN_SPEED - 0.1), 0.6)
	Runner.expectEqual(limited(0.6, CENTERED, road, 0, -SPEED), 0.6)
	Runner.expectNear(limited(0.6, CENTERED, road, 0, VehicleConfig.ROAD_STEER_MIN_SPEED), MARGIN, 1e-9)
	local tooFar = carAt(VehicleConfig.ROAD_STEER_MAX_DISTANCE + 1, 0)
	Runner.expectEqual(limited(0.6, tooFar, road), 0.6)
	local tooCrooked = carAt(0, math.rad(VehicleConfig.ROAD_STEER_MAX_HEADING_DEGREES + 5))
	Runner.expectEqual(limited(0.6, tooCrooked, road), 0.6)
end)

Runner.test("it never adds steering and never returns NaN", function()
	for _, turn in { -1, -0.4, 0, 0.4, 1 } do
		for _, x in { -12, -5, 0, 5, 12 } do
			for _, heading in { -0.8, -0.3, 0, 0.3, 0.8 } do
				for _, drift in { -0.4, 0, 0.4 } do
					for steer = -10, 10 do
						local input = steer / 10
						local output = limited(input, carAt(x, heading), roadTurning(turn), drift)
						Runner.expectEqual(output == output, true)
						Runner.expectEqual(math.abs(output) <= math.abs(input) + 1e-12, true)
						Runner.expectEqual(output * input >= 0, true)
					end
				end
			end
		end
	end
end)

Runner.test("invalid numbers leave the steering untouched and the result is deterministic", function()
	local road = roadTurning(0.5)
	local nan = 0 / 0
	Runner.expectEqual(limited(0.6, CENTERED, road, nan), limited(0.6, CENTERED, road, nan))
	Runner.expectEqual(limited(0.6, carAt(nan, 0), road), 0.6)
	Runner.expectEqual(limited(0.6, CENTERED, road, 0, nan), 0.6)
	local brokenRoad = roadTurning(0.5)
	brokenRoad.ahead.arcLength = nan
	Runner.expectEqual(limited(0.6, CENTERED, brokenRoad), 0.6)
	Runner.expectEqual(limited(0.6, CENTERED, road), limited(0.6, CENTERED, road))
end)

Runner.finish()
