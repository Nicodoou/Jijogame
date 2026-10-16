--!strict
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local DETERMINISM_SEGMENTS = 20
local STEPS_PER_SEGMENT = WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS
local REFERENCE_SEED = 12345
-- Semilla en la que la ruta retrocede dentro de los primeros 70 tramos (ver RoadPieceSequencer.test.luau).
local STEP_BACKTRACK_SEED = 54
local STEP_SEGMENTS = 70

local function hashFirstSegments(path: RoadPath.RoadPath, releaseEvery: number?): number
	local segments = {}
	for index = 1, DETERMINISM_SEGMENTS do
		segments[index] = path.generateNextSegment()
		if releaseEvery ~= nil and index % releaseEvery == 0 then
			path.releaseSegmentsBefore(index - 1)
		end
	end
	return PathHelpers.hashSegments(segments)
end

Runner.test("the same seed gives the same first 20 segments", function()
	local first = hashFirstSegments(RoadPath.new(REFERENCE_SEED), nil)
	local second = hashFirstSegments(RoadPath.new(REFERENCE_SEED), nil)
	Runner.expectEqual(first, second)
end)

Runner.test("another seed gives another road", function()
	local first = hashFirstSegments(RoadPath.new(REFERENCE_SEED), nil)
	Runner.expectEqual(first ~= hashFirstSegments(RoadPath.new(REFERENCE_SEED + 1), nil), true)
	Runner.expectEqual(first ~= hashFirstSegments(RoadPath.new(0), nil), true)
end)

Runner.test("releasing segments in the middle does not change the road", function()
	local reference = hashFirstSegments(RoadPath.new(REFERENCE_SEED), nil)
	Runner.expectEqual(hashFirstSegments(RoadPath.new(REFERENCE_SEED), 1), reference)
	Runner.expectEqual(hashFirstSegments(RoadPath.new(REFERENCE_SEED), 7), reference)
end)

Runner.test("releasing every segment and generating on gives the same segment as never releasing", function()
	local untouched = RoadPath.new(REFERENCE_SEED)
	local released = RoadPath.new(REFERENCE_SEED)
	PathHelpers.generateSegments(untouched, 10)
	PathHelpers.generateSegments(released, 10)
	released.releaseSegmentsBefore(1000)
	local expectedSegment = untouched.generateNextSegment()
	local actualSegment = released.generateNextSegment()
	Runner.expectEqual(actualSegment.index, 10)
	Runner.expectEqual(PathHelpers.hashSegments({ actualSegment }), PathHelpers.hashSegments({ expectedSegment }))
end)

Runner.test("a segment generated after releasing earlier ones equals that of a fresh path", function()
	local path = RoadPath.new(REFERENCE_SEED)
	local segments = PathHelpers.generateSegments(path, 5)
	path.releaseSegmentsBefore(4)
	local fresh = PathHelpers.generateSegments(RoadPath.new(REFERENCE_SEED), 5)
	Runner.expectEqual(PathHelpers.hashSegments({ segments[5] }), PathHelpers.hashSegments({ fresh[5] }))
end)

Runner.test("seeds zero, negative, huge and fractional all build a road", function()
	for _, seed in { 0, -1, -7.5, 0.25, 1e15, -1e15, 1e300 } do
		local segments = PathHelpers.generateSegments(RoadPath.new(seed), 3)
		for _, segment in segments do
			for _, sample in segment.samples do
				Runner.expectEqual(sample.position == sample.position, true)
			end
		end
	end
end)

Runner.test("a seed that is not finite is rejected", function()
	Runner.expectError(function()
		RoadPath.new(0 / 0)
	end)
	Runner.expectError(function()
		RoadPath.new(math.huge)
	end)
end)

Runner.test("the road starts at the configured start position, heading to +x", function()
	local first = RoadPath.new(1).generateNextSegment().samples[1]
	Runner.expectEqual(first.position, WorldConfig.START_POSITION)
	Runner.expectEqual(first.heading, math.rad(WorldConfig.START_HEADING_DEGREES))
	Runner.expectEqual(first.curvature, 0)
	Runner.expectEqual(first.slope, 0)
	Runner.expectEqual(first.arcLength, 0)
end)

Runner.test("each segment has one sample per step plus the shared one and numbers its arc length", function()
	local segments = PathHelpers.generateSegments(RoadPath.new(2), 3)
	for index, segment in segments do
		Runner.expectEqual(segment.index, index - 1)
		Runner.expectEqual(#segment.samples, STEPS_PER_SEGMENT + 1)
		Runner.expectEqual(segment.samples[1].arcLength, (index - 1) * WorldConfig.SEGMENT_LENGTH_STUDS)
		Runner.expectEqual(segment.samples[STEPS_PER_SEGMENT + 1].arcLength, index * WorldConfig.SEGMENT_LENGTH_STUDS)
	end
end)

Runner.test("the loaded range starts empty and follows generation and release", function()
	local path = RoadPath.new(3)
	local first, last = path.getLoadedRange()
	Runner.expectEqual(last < first, true)
	PathHelpers.generateSegments(path, 5)
	first, last = path.getLoadedRange()
	Runner.expectEqual(first, 0)
	Runner.expectEqual(last, 4)
	path.releaseSegmentsBefore(3)
	first, last = path.getLoadedRange()
	Runner.expectEqual(first, 3)
	Runner.expectEqual(last, 4)
end)

Runner.test("getSegment returns nil before, after and for released segments", function()
	local path = RoadPath.new(4)
	Runner.expectEqual(path.getSegment(0), nil)
	PathHelpers.generateSegments(path, 4)
	path.releaseSegmentsBefore(2)
	Runner.expectEqual(path.getSegment(1), nil)
	Runner.expectEqual(path.getSegment(-1), nil)
	Runner.expectEqual(path.getSegment(4), nil)
	Runner.expectEqual((path.getSegment(2) :: RoadPath.Segment).index, 2)
	Runner.expectEqual((path.getSegment(3) :: RoadPath.Segment).index, 3)
end)

Runner.test("releasing before the first loaded index or a negative index does nothing", function()
	local path = RoadPath.new(5)
	PathHelpers.generateSegments(path, 3)
	path.releaseSegmentsBefore(-5)
	path.releaseSegmentsBefore(0)
	local first, last = path.getLoadedRange()
	Runner.expectEqual(first, 0)
	Runner.expectEqual(last, 2)
	path.releaseSegmentsBefore(2)
	path.releaseSegmentsBefore(1)
	first, last = path.getLoadedRange()
	Runner.expectEqual(first, 2)
	Runner.expectEqual(last, 2)
end)

Runner.test("releasing everything leaves the range empty and generation continues", function()
	local path = RoadPath.new(6)
	PathHelpers.generateSegments(path, 3)
	path.releaseSegmentsBefore(math.huge)
	local first, last = path.getLoadedRange()
	Runner.expectEqual(last < first, true)
	local following = path.generateNextSegment()
	Runner.expectEqual(following.index, 3)
	first, last = path.getLoadedRange()
	Runner.expectEqual(first, 3)
	Runner.expectEqual(last, 3)
end)

Runner.test("releasing with an index that is not an integer is rejected", function()
	local path = RoadPath.new(7)
	PathHelpers.generateSegments(path, 2)
	Runner.expectError(function()
		path.releaseSegmentsBefore(1.5)
	end)
	Runner.expectError(function()
		path.releaseSegmentsBefore(0 / 0)
	end)
end)

Runner.test("generating step by step gives exactly the same segments as generateNextSegment", function()
	for _, seed in { REFERENCE_SEED, STEP_BACKTRACK_SEED, 0, -7.5 } do
		local reference = PathHelpers.generateSegments(RoadPath.new(seed), STEP_SEGMENTS)
		local stepped = PathHelpers.generateSegmentsByStep(RoadPath.new(seed), STEP_SEGMENTS)
		Runner.expectEqual(PathHelpers.hashSegments(stepped), PathHelpers.hashSegments(reference))
		for index, segment in stepped do
			Runner.expectEqual(segment.index, index - 1)
		end
	end
end)

Runner.test("a step does a little work and returns nil until it has a whole segment", function()
	local path = RoadPath.new(REFERENCE_SEED)
	Runner.expectEqual(path.generateStep(), nil)
	local first, last = path.getLoadedRange()
	Runner.expectEqual(last < first, true)
	local _, mostCalls = PathHelpers.generateSegmentsByStep(RoadPath.new(REFERENCE_SEED), STEP_SEGMENTS)
	Runner.expectEqual(mostCalls > 1, true)
end)

Runner.test("steps and whole segments can be mixed, and releasing in the middle changes nothing", function()
	local reference = hashFirstSegments(RoadPath.new(REFERENCE_SEED), nil)
	local path = RoadPath.new(REFERENCE_SEED)
	local segments = {}
	for index = 1, DETERMINISM_SEGMENTS do
		local segment = if index % 2 == 0
			then path.generateNextSegment()
			else PathHelpers.generateSegmentsByStep(path, 1)[1]
		segments[index] = segment
		path.releaseSegmentsBefore(index - 1)
	end
	Runner.expectEqual(PathHelpers.hashSegments(segments), reference)
end)

Runner.test("after a segment is published the next steps start the following one", function()
	local path = RoadPath.new(REFERENCE_SEED)
	local firstBatch = PathHelpers.generateSegmentsByStep(path, 2)
	Runner.expectEqual(firstBatch[2].index, 1)
	local first, last = path.getLoadedRange()
	Runner.expectEqual(first, 0)
	Runner.expectEqual(last, 1)
	Runner.expectEqual((path.getSegment(1) :: RoadPath.Segment).index, 1)
end)

Runner.finish()
