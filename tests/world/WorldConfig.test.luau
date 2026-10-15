--!strict
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local WIDTH_SIDES = 2

Runner.test("the minimum curve radius is bigger than half the road plus the shoulder", function()
	local halfRoadWithShoulder = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.MIN_CURVE_RADIUS_STUDS > halfRoadWithShoulder, true)
end)

Runner.test("a segment is a whole number of integration steps", function()
	local steps = WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS
	Runner.expectEqual(steps, math.floor(steps))
end)

Runner.test("the road is 16 studs wide and the world starts at the origin heading to +x", function()
	Runner.expectEqual(WorldConfig.ROAD_WIDTH_STUDS, 16)
	Runner.expectEqual(WorldConfig.START_POSITION.x, 0)
	Runner.expectEqual(WorldConfig.START_POSITION.z, 0)
	Runner.expectEqual(WorldConfig.START_HEADING_DEGREES, 0)
end)

Runner.test("the live clearance is bigger than the full width of the road with both shoulders", function()
	local fullWidth = WorldConfig.ROAD_WIDTH_STUDS + WIDTH_SIDES * WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.LIVE_CLEARANCE_STUDS > fullWidth, true)
end)

Runner.test("the guide clearance leaves room for the live clearance and the tunnel on both sides", function()
	local needed = WorldConfig.LIVE_CLEARANCE_STUDS + WIDTH_SIDES * WorldConfig.LOCAL_DEVIATION_MAX_STUDS
	Runner.expectEqual(WorldConfig.GUIDE_CLEARANCE_STUDS >= needed, true)
end)

Runner.test(
	"the guide step is longer than its clearance and the neighbor distance is shorter than the lookback",
	function()
		Runner.expectEqual(WorldConfig.GUIDE_STEP_STUDS > WorldConfig.GUIDE_CLEARANCE_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEIGHBOR_ARC_STUDS < WorldConfig.LIVE_LOOKBACK_STUDS, true)
	end
)

Runner.test("a full circle of the minimum radius fits inside the neighbor distance", function()
	Runner.expectEqual(WorldConfig.LIVE_NEIGHBOR_ARC_STUDS > 2 * math.pi * WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
end)

Runner.test("the area margins fit inside the area and the start is inside it", function()
	Runner.expectEqual(WorldConfig.AREA_STEERING_MARGIN_STUDS >= WorldConfig.GUIDE_EDGE_MARGIN_STUDS, true)
	Runner.expectEqual(WorldConfig.AREA_STEERING_MARGIN_STUDS < WorldConfig.AREA_RADIUS_STUDS, true)
	local start = WorldConfig.START_POSITION
	Runner.expectEqual(math.sqrt(start.x ^ 2 + start.z ^ 2) < WorldConfig.AREA_RADIUS_STUDS, true)
end)

Runner.test("the local tunnel and the target distance fit inside one guide step", function()
	Runner.expectEqual(WorldConfig.LOCAL_DEVIATION_MAX_STUDS < WorldConfig.GUIDE_STEP_STUDS, true)
	Runner.expectEqual(WorldConfig.GUIDE_TARGET_AHEAD_STUDS < WorldConfig.GUIDE_STEP_STUDS, true)
end)

Runner.test("the start height is inside the hill band and the maximum slope is a real incline", function()
	Runner.expectEqual(WorldConfig.START_POSITION.y >= WorldConfig.HILL_MIN_HEIGHT_STUDS, true)
	Runner.expectEqual(WorldConfig.START_POSITION.y <= WorldConfig.HILL_MAX_HEIGHT_STUDS, true)
	Runner.expectEqual(WorldConfig.MAX_SLOPE_DEGREES > 0 and WorldConfig.MAX_SLOPE_DEGREES < 90, true)
end)

Runner.test("the alternative guide turns are growing angles of at most a right angle", function()
	local previous = 0
	for _, degrees in WorldConfig.GUIDE_ALTERNATIVE_TURNS_DEGREES do
		Runner.expectEqual(degrees > previous and degrees <= 90, true)
		previous = degrees
	end
end)

Runner.test("the configuration is read only", function()
	Runner.expectError(function()
		(WorldConfig :: any).ROAD_WIDTH_STUDS = 1
	end)
	Runner.expectError(function()
		(WorldConfig.LAST_RESORT_LOBE_STEPS :: any)[1] = 1
	end)
end)

Runner.test(
	"the near distance is longer than a full circle, and the near clearance covers the width of the road",
	function()
		local fullWidth = WorldConfig.ROAD_WIDTH_STUDS + WIDTH_SIDES * WorldConfig.SHOULDER_WIDTH_STUDS
		Runner.expectEqual(WorldConfig.LIVE_NEAR_ARC_STUDS > 2 * math.pi * WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_ARC_STUDS < WorldConfig.LIVE_NEIGHBOR_ARC_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_CLEARANCE_STUDS > fullWidth, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_CLEARANCE_STUDS <= WorldConfig.LIVE_CLEARANCE_STUDS, true)
	end
)

Runner.finish()
