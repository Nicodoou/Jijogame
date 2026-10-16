--!strict
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadQuery = require("../../src/world/core/RoadQuery")
local Runner = require("../Runner")
local SpawnPoint = require("../../src/world/core/SpawnPoint")
local SyntheticRoad = require("./SyntheticRoad")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEEDS = { 0, 1, 7, -5, 123456, 0.75, 1e12 }
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local SPAWN_ARC = WorldConfig.SPAWN_ARC_LENGTH_STUDS
local DIRECTION_TOLERANCE = 1e-6
local POSITION_TOLERANCE_STUDS = 0.01
local FORWARD_DOT_MINIMUM = 0.99
local SYNTHETIC_START_HEIGHT = 10
local SYNTHETIC_SLOPE_DEGREES = 10

Runner.test("two instances with the same seed give exactly the same spawn point", function()
	for _, seed in SEEDS do
		local first = SpawnPoint.compute(seed)
		local second = SpawnPoint.compute(seed)
		Runner.expectEqual(first.position, second.position)
		Runner.expectEqual(first.direction, second.direction)
		Runner.expectEqual(first.arcLength, second.arcLength)
	end
end)

Runner.test("the spawn point is on the road, SPAWN_ARC_LENGTH_STUDS from the start and facing forward", function()
	for _, seed in SEEDS do
		local path = RoadPath.new(seed)
		local spawn = SpawnPoint.fromPath(path)
		Runner.expectEqual(spawn.arcLength, SPAWN_ARC)
		Runner.expectNear(spawn.direction.x ^ 2 + spawn.direction.y ^ 2 + spawn.direction.z ^ 2, 1, DIRECTION_TOLERANCE)
		local nearest = RoadQuery.new(path).findNearest(spawn.position, nil)
		Runner.expectEqual(nearest ~= nil, true)
		local found = nearest :: RoadQuery.RoadQueryResult
		Runner.expectNear(found.lateralOffset, 0, POSITION_TOLERANCE_STUDS)
		Runner.expectNear(found.arcLength, SPAWN_ARC, POSITION_TOLERANCE_STUDS)
		Runner.expectNear(found.position.y, spawn.position.y, POSITION_TOLERANCE_STUDS)
		local dot = vector.dot(spawn.direction, found.direction)
		Runner.expectEqual(dot > FORWARD_DOT_MINIMUM, true)
	end
end)

Runner.test("the spawn point starts at the beginning of the route and a path gives what its seed gives", function()
	local path = RoadPath.new(9)
	local first = path.generateNextSegment().samples[1].position
	local spawn = SpawnPoint.fromPath(path)
	Runner.expectEqual(vector.magnitude(spawn.position - first) < 2 * SPAWN_ARC, true)
	local fromSeed = SpawnPoint.compute(9)
	Runner.expectEqual(spawn.position, fromSeed.position)
	Runner.expectEqual(spawn.direction, fromSeed.direction)
end)

Runner.test("an arc length between two samples is interpolated", function()
	local slope = math.tan(math.rad(SYNTHETIC_SLOPE_DEGREES))
	local segments = SyntheticRoad.createSegments({
		segmentCount = 1,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function(step: number)
			return SYNTHETIC_START_HEIGHT + step * STEP_STUDS * slope
		end,
	})
	local spawn = SpawnPoint.fromPath(SyntheticRoad.createPath(segments))
	Runner.expectNear(spawn.position.x, SPAWN_ARC, POSITION_TOLERANCE_STUDS)
	Runner.expectNear(spawn.position.y, SYNTHETIC_START_HEIGHT + SPAWN_ARC * slope, POSITION_TOLERANCE_STUDS)
	Runner.expectNear(spawn.direction.y, math.sin(math.rad(SYNTHETIC_SLOPE_DEGREES)), 1e-3)
	Runner.expectNear(spawn.direction.x, math.cos(math.rad(SYNTHETIC_SLOPE_DEGREES)), 1e-3)
end)

Runner.test("a path that already released its first segment cannot give a spawn point", function()
	local path = RoadPath.new(3)
	PathHelpers.generateSegments(path, 3)
	path.releaseSegmentsBefore(2)
	Runner.expectError(function()
		SpawnPoint.fromPath(path)
	end)
end)

Runner.finish()
