--!strict
local Runner = require("../Runner")
local RoadFrame = require("../../src/world/core/RoadFrame")

local TOLERANCE = 1e-9
local FULL_TURN = 2 * math.pi

Runner.test("the start heading points to +x", function()
	Runner.expectEqual(RoadFrame.getStartHeadingRadians(), 0)
end)

Runner.test("there are 128 steps in a segment", function()
	Runner.expectEqual(RoadFrame.getStepsPerSegment(), 128)
end)

Runner.test("an angle inside the range does not change", function()
	for _, angle in { 0, 0.3, -0.3, 3, -3 } do
		Runner.expectNear(RoadFrame.wrapAngleRadians(angle), angle, TOLERANCE)
	end
end)

Runner.test("full turns are removed from the angle, in both directions", function()
	Runner.expectNear(RoadFrame.wrapAngleRadians(FULL_TURN + 0.3), 0.3, TOLERANCE)
	Runner.expectNear(RoadFrame.wrapAngleRadians(-FULL_TURN - 0.3), -0.3, TOLERANCE)
	Runner.expectNear(RoadFrame.wrapAngleRadians(100 * FULL_TURN + 1), 1, 1e-7)
	Runner.expectNear(RoadFrame.wrapAngleRadians(-100 * FULL_TURN - 1), -1, 1e-7)
end)

Runner.test("the range is closed at minus pi and open at pi", function()
	Runner.expectNear(RoadFrame.wrapAngleRadians(math.pi), -math.pi, TOLERANCE)
	Runner.expectNear(RoadFrame.wrapAngleRadians(-math.pi), -math.pi, TOLERANCE)
	Runner.expectEqual(RoadFrame.wrapAngleRadians(math.pi - 1e-6) > 0, true)
	Runner.expectEqual(RoadFrame.wrapAngleRadians(math.pi + 1e-6) < 0, true)
end)

Runner.finish()
