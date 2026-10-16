--!strict
local RoadWindow = require("../../src/world/core/RoadWindow")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEGMENT_STUDS = WorldConfig.SEGMENT_LENGTH_STUDS
local AHEAD_STUDS = 1000
local MEMORY_STUDS = 2000
local ROUTE_SEGMENTS = 40
local ROAD_HEIGHT = 50
local STRIDE_STUDS = 32
local FAR_STUDS = 5000

local function createRoute()
	return SyntheticRoad.createPath(SyntheticRoad.createSegments({
		segmentCount = ROUTE_SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return ROAD_HEIGHT
		end,
	}))
end

local function createWindow(extendedSegments: number)
	local path = createRoute()
	local window = RoadWindow.new(path, AHEAD_STUDS, MEMORY_STUDS)
	for _ = 1, extendedSegments do
		window.extend()
	end
	return window, path
end

local function countBlocks(window: RoadWindow.RoadWindow): number
	return #window.blocks.gather(-FAR_STUDS, -FAR_STUDS, FAR_STUDS * 10, FAR_STUDS, 1)
end

Runner.test("extending adds consecutive segments to the route and to the blocks", function()
	local window, path = createWindow(0)
	Runner.expectEqual(window.getGeneratedEndArcLength(), 0)
	for expectedIndex = 0, 3 do
		Runner.expectEqual(window.extend().index, expectedIndex)
	end
	local firstLoaded, lastLoaded = path.getLoadedRange()
	Runner.expectEqual(firstLoaded, 0)
	Runner.expectEqual(lastLoaded, 3)
	Runner.expectEqual(window.getGeneratedEndArcLength(), 4 * SEGMENT_STUDS)
	Runner.expectEqual(
		countBlocks(window),
		4 * (SEGMENT_STUDS / WorldConfig.INTEGRATION_STEP_STUDS / WorldConfig.TERRAIN_ROAD_BLOCK_STEPS)
	)
end)

Runner.test(
	"tracking the vehicle gives its arc length on the road and keeps the last one when it is far away",
	function()
		local window = createWindow(8)
		Runner.expectEqual(window.getVehicleArcLength(), 0)
		Runner.expectNear(window.trackVehicle(vector.create(300, ROAD_HEIGHT, 5)), 300, 1e-3)
		Runner.expectNear(window.trackVehicle(vector.create(310, ROAD_HEIGHT, -20)), 310, 1e-3)
		Runner.expectNear(window.trackVehicle(vector.create(900, ROAD_HEIGHT, 4000)), 310, 1e-3)
		Runner.expectNear(window.getVehicleArcLength(), 310, 1e-3)
		Runner.expectNear(window.trackVehicle(vector.create(1500, ROAD_HEIGHT, 0)), 1500, 1e-3)
		Runner.expectNear(window.trackVehicle(vector.create(200, ROAD_HEIGHT, 0)), 200, 1e-3)
	end
)

Runner.test("the route needs extending until it reaches the distance ahead of the vehicle, then it does not", function()
	local window = createWindow(1)
	window.trackVehicle(vector.create(100, ROAD_HEIGHT, 0))
	local extensions = 0
	while window.needsExtension() do
		window.extend()
		extensions += 1
		Runner.expectEqual(extensions < 100, true)
	end
	local end_ = window.getGeneratedEndArcLength()
	Runner.expectEqual(end_ >= window.getVehicleArcLength() + AHEAD_STUDS, true)
	Runner.expectEqual(end_ < window.getVehicleArcLength() + AHEAD_STUDS + SEGMENT_STUDS, true)
end)

Runner.test("old segments are released from the route and the blocks, each by its own distance", function()
	local window, path = createWindow(ROUTE_SEGMENTS - 1)
	window.trackVehicle(vector.create(6000, ROAD_HEIGHT, 0))
	local blocksBefore = countBlocks(window)
	Runner.expectEqual(window.releaseOldSegments(), true)
	local firstLoaded = path.getLoadedRange()
	Runner.expectEqual(firstLoaded, math.floor((6000 - WorldConfig.LIVE_LOOKBACK_STUDS) / SEGMENT_STUDS))
	local blocksAfter = window.blocks.gather(-FAR_STUDS, -FAR_STUDS, FAR_STUDS * 10, FAR_STUDS, 1)
	Runner.expectEqual(#blocksAfter < blocksBefore, true)
	local blocksPerSegment = SEGMENT_STUDS / WorldConfig.INTEGRATION_STEP_STUDS / WorldConfig.TERRAIN_ROAD_BLOCK_STEPS
	Runner.expectEqual(blocksAfter[1].index, math.floor((6000 - MEMORY_STUDS) / SEGMENT_STUDS) * blocksPerSegment)
	Runner.expectEqual(window.releaseOldSegments(), false)
	window.trackVehicle(vector.create(6000 + SEGMENT_STUDS, ROAD_HEIGHT, 0))
	Runner.expectEqual(window.releaseOldSegments(), true)
end)

Runner.test("nothing is released at the start of the route", function()
	local window, path = createWindow(4)
	Runner.expectEqual(window.releaseOldSegments(), false)
	Runner.expectEqual(path.getLoadedRange(), 0)
end)

Runner.test("axis points come every stride, aligned to it, inside the arc range and the loaded route", function()
	local window = createWindow(8)
	local arcs: { number } = {}
	local xs: { number } = {}
	window.forEachAxisPoint(100, 900, STRIDE_STUDS, function(x, _, arcLength)
		table.insert(xs, x)
		table.insert(arcs, arcLength)
	end)
	Runner.expectEqual(arcs[1], 128)
	Runner.expectEqual(arcs[#arcs], 896)
	for index, arcLength in arcs do
		Runner.expectEqual(arcLength % STRIDE_STUDS, 0)
		Runner.expectNear(xs[index], arcLength, 1e-3)
		if index > 1 then
			Runner.expectEqual(arcLength - arcs[index - 1], STRIDE_STUDS)
		end
	end
end)

Runner.test("axis points stop at the last loaded point and start at the first loaded one", function()
	local window = createWindow(2)
	local last = 0
	window.forEachAxisPoint(-1000, 100000, STRIDE_STUDS, function(_, _, arcLength)
		last = arcLength
	end)
	Runner.expectEqual(last, 2 * SEGMENT_STUDS)
	local count = 0
	window.forEachAxisPoint(5000, 6000, STRIDE_STUDS, function()
		count += 1
	end)
	Runner.expectEqual(count, 0)
	local first = math.huge
	window.forEachAxisPoint(-1000, 100000, STRIDE_STUDS, function(_, _, arcLength)
		first = math.min(first, arcLength)
	end)
	Runner.expectEqual(first, 0)
end)

Runner.test("a stride shorter than a step still visits every point once", function()
	local window = createWindow(1)
	local count = 0
	window.forEachAxisPoint(0, 20, 0.1, function()
		count += 1
	end)
	Runner.expectEqual(count, 11)
end)

Runner.test("extending by steps adds the blocks only when the segment is complete", function()
	local stepsPerSegment = 4
	local segments = SyntheticRoad.createSegments({
		segmentCount = 3,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return ROAD_HEIGHT
		end,
	})
	local window = RoadWindow.new(SyntheticRoad.createPath(segments, stepsPerSegment), AHEAD_STUDS, MEMORY_STUDS)
	local blocksPerSegment = SEGMENT_STUDS / WorldConfig.INTEGRATION_STEP_STUDS / WorldConfig.TERRAIN_ROAD_BLOCK_STEPS
	for expectedIndex = 0, 2 do
		for _ = 1, stepsPerSegment - 1 do
			Runner.expectEqual(window.extendStep(), nil)
			Runner.expectEqual(countBlocks(window), expectedIndex * blocksPerSegment)
		end
		local segment = window.extendStep()
		Runner.expectEqual(segment ~= nil and segment.index, expectedIndex)
		Runner.expectEqual(countBlocks(window), (expectedIndex + 1) * blocksPerSegment)
		Runner.expectEqual(window.getGeneratedEndArcLength(), (expectedIndex + 1) * SEGMENT_STUDS)
	end
end)

Runner.finish()
