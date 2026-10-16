--!strict
-- Las revisiones de la ruta también se prueban con rutas armadas a mano: si no vieran un defecto, no servirían.
local RoadPath = require("../../src/world/core/RoadPath")
local RoadSampleChecks = require("./RoadSampleChecks")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Sample = RoadPath.RoadSample

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = WorldConfig.SEGMENT_LENGTH_STUDS // STEP_STUDS
local ROAD_SAMPLES = 10
local FLAT_HEIGHT = 50

local function createSample(index: number): Sample
	return {
		position = vector.create(index * STEP_STUDS, FLAT_HEIGHT, 0),
		heading = 0,
		curvature = 0,
		slope = 0,
		arcLength = index * STEP_STUDS,
	}
end

local function createRoad(): { Sample }
	local road = {}
	for index = 0, ROAD_SAMPLES do
		road[index + 1] = createSample(index)
	end
	return road
end

-- Cuenta las violaciones de una ruta recta a la que se le cambió una muestra.
local function countWith(change: (sample: Sample) -> ()): RoadSampleChecks.Violations
	local road = createRoad()
	change(road[5])
	return RoadSampleChecks.countViolations(road)
end

Runner.test("a flat straight road has no violations", function()
	local violations = RoadSampleChecks.countViolations(createRoad())
	for _, count in violations :: any do
		Runner.expectEqual(count, 0)
	end
end)

Runner.test("a curvature beyond the minimum radius is counted, and so is a jump of curvature", function()
	local violations = countWith(function(sample)
		sample.curvature = 2 / WorldConfig.MIN_CURVE_RADIUS_STUDS
	end)
	Runner.expectEqual(violations.curvature, 1)
	Runner.expectEqual(violations.curvatureJump, 2)
end)

Runner.test("a slope beyond the maximum is counted, and so is a jump of slope", function()
	local violations = countWith(function(sample)
		sample.slope = math.rad(WorldConfig.MAX_SLOPE_DEGREES) + 0.1
	end)
	Runner.expectEqual(violations.slope, 1)
	Runner.expectEqual(violations.slopeChange, 2)
end)

Runner.test("a sample above or below the band of heights is counted", function()
	Runner.expectEqual(
		countWith(function(sample)
			sample.position = vector.create(sample.position.x, WorldConfig.HILL_MAX_HEIGHT_STUDS + 1, 0)
		end).height,
		1
	)
	Runner.expectEqual(
		countWith(function(sample)
			sample.position = vector.create(sample.position.x, WorldConfig.HILL_MIN_HEIGHT_STUDS - 1, 0)
		end).height,
		1
	)
end)

Runner.test("a sample outside the area is counted, in x and in z", function()
	local beyond = WorldConfig.AREA_RADIUS_STUDS + 1
	Runner.expectEqual(
		countWith(function(sample)
			sample.position = vector.create(beyond, FLAT_HEIGHT, 0)
		end).area,
		1
	)
	Runner.expectEqual(
		countWith(function(sample)
			sample.position = vector.create(0, FLAT_HEIGHT, -beyond)
		end).area,
		1
	)
end)

Runner.test("a gap or a repeated sample breaks the one step rule", function()
	local gap = countWith(function(sample)
		sample.position = vector.create(sample.position.x + 5, FLAT_HEIGHT, 0)
	end)
	Runner.expectEqual(gap.step, 2)
	local wrongArc = countWith(function(sample)
		sample.arcLength += 1
	end)
	Runner.expectEqual(wrongArc.step, 2)
end)

Runner.test("values that are not finite are counted", function()
	local violations = countWith(function(sample)
		sample.heading = 0 / 0
		sample.curvature = math.huge
	end)
	Runner.expectEqual(violations.notFinite, 2)
end)

local function createSegments(count: number): { RoadPath.Segment }
	local segments = {}
	for index = 1, count do
		local samples = {}
		for offset = 0, STEPS_PER_SEGMENT do
			samples[offset + 1] = createSample((index - 1) * STEPS_PER_SEGMENT + offset)
		end
		segments[index] = { index = index - 1, samples = samples }
	end
	return segments
end

Runner.test("segments that share their end sample have no continuity violations", function()
	Runner.expectEqual(RoadSampleChecks.countContinuityViolations(createSegments(4)), 0)
	Runner.expectEqual(RoadSampleChecks.countContinuityViolations(createSegments(1)), 0)
end)

Runner.test("a segment that starts in another place, heading, curvature, slope or arc is counted", function()
	local changes: { (sample: Sample) -> () } = {
		function(sample)
			sample.position = vector.create(0, 0, 0)
		end,
		function(sample)
			sample.heading = 1
		end,
		function(sample)
			sample.curvature = 0.01
		end,
		function(sample)
			sample.slope = 0.1
		end,
		function(sample)
			sample.arcLength = 1
		end,
	}
	for _, change in changes do
		local segments = createSegments(3)
		change(segments[2].samples[1])
		Runner.expectEqual(RoadSampleChecks.countContinuityViolations(segments), 1)
	end
end)

Runner.test("flattening drops the sample that two segments share", function()
	local road = RoadSampleChecks.flatten(createSegments(3))
	Runner.expectEqual(#road, 3 * STEPS_PER_SEGMENT + 1)
	for index, sample in road do
		Runner.expectEqual(sample.arcLength, (index - 1) * STEP_STUDS)
	end
	Runner.expectEqual(#RoadSampleChecks.flatten({}), 0)
end)

Runner.finish()
