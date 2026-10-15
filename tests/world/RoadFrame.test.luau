--!strict
local Runner = require("../Runner")
local RoadFrame = require("../../src/world/core/RoadFrame")
local WorldConfig = require("../../src/world/core/WorldConfig")

local TOLERANCE = 1e-9

Runner.test("the mean heading points to +x", function()
	Runner.expectEqual(RoadFrame.getMeanHeadingRadians(), 0)
end)

Runner.test("there are 128 steps in a segment", function()
	Runner.expectEqual(RoadFrame.getStepsPerSegment(), 128)
end)

Runner.test("the heading deviation of the mean heading is zero", function()
	Runner.expectEqual(RoadFrame.getHeadingDeviationRadians(0), 0)
end)

Runner.test("the heading deviation wraps full turns", function()
	Runner.expectNear(RoadFrame.getHeadingDeviationRadians(2 * math.pi + 0.3), 0.3, TOLERANCE)
	Runner.expectNear(RoadFrame.getHeadingDeviationRadians(-2 * math.pi - 0.3), -0.3, TOLERANCE)
end)

Runner.test("the heading deviation is positive to the right and negative to the left", function()
	Runner.expectNear(RoadFrame.getHeadingDeviationRadians(0.5), 0.5, TOLERANCE)
	Runner.expectNear(RoadFrame.getHeadingDeviationRadians(-0.5), -0.5, TOLERANCE)
end)

Runner.test("the lateral offset of the start is zero", function()
	Runner.expectEqual(RoadFrame.getLateralOffsetStuds(WorldConfig.START_POSITION), 0)
end)

Runner.test("the lateral offset ignores movement along the mean heading and height", function()
	local moved = WorldConfig.START_POSITION + vector.create(5000, 300, 0)
	Runner.expectEqual(RoadFrame.getLateralOffsetStuds(moved), 0)
end)

Runner.test("the lateral offset is positive toward +z, the right of the mean heading", function()
	local right = WorldConfig.START_POSITION + vector.create(0, 0, 40)
	Runner.expectNear(RoadFrame.getLateralOffsetStuds(right), 40, TOLERANCE)
	local left = WorldConfig.START_POSITION + vector.create(0, 0, -25)
	Runner.expectNear(RoadFrame.getLateralOffsetStuds(left), -25, TOLERANCE)
end)

Runner.finish()
