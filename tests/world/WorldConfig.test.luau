--!strict
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

Runner.test("the minimum curve radius is bigger than half the road plus the shoulder", function()
	local halfRoadWithShoulder = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.MIN_CURVE_RADIUS_STUDS > halfRoadWithShoulder, true)
end)

Runner.test("a segment is a whole number of integration steps", function()
	local steps = WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS
	Runner.expectEqual(steps, math.floor(steps))
end)

Runner.test("the mean heading is a unit vector on the ground plane", function()
	local heading = WorldConfig.MEAN_HEADING
	Runner.expectEqual(heading.y, 0)
	Runner.expectNear(heading.x * heading.x + heading.z * heading.z, 1, 1e-12)
end)

Runner.test("the heading corridor leaves the road advancing along the mean heading", function()
	Runner.expectEqual(WorldConfig.MAX_HEADING_DEVIATION_DEGREES < 90, true)
end)

Runner.test("the world starts at -120000 studs", function()
	Runner.expectEqual(WorldConfig.START_POSITION.x, -120000)
end)

Runner.test("the configuration is read only", function()
	Runner.expectError(function()
		(WorldConfig :: any).ROAD_WIDTH_STUDS = 1
	end)
end)

Runner.finish()
