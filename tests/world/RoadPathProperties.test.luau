--!strict
-- Propiedades de la ruta sobre muchas semillas: ninguna curva imposible, ningún tirón y ningún cruce.
local PathHelpers = require("./PathHelpers")
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEED_COUNT = 200
local SEGMENT_COUNT = 40
local TOLERANCE = 1e-9
-- Un vector guarda floats de 32 bits: cerca de x = -120.000 cada coordenada se redondea a 0,0078 studs.
local VECTOR_PRECISION_STUDS = 0.05
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local MAX_CURVATURE = 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS
local MAX_DEVIATION_RADIANS = math.rad(WorldConfig.MAX_HEADING_DEVIATION_DEGREES)
local MAX_SLOPE_RADIANS = math.rad(WorldConfig.MAX_SLOPE_DEGREES)
-- Cota de cuánto puede cambiar la curvatura en un paso: el pico de la curva más cerrada repartido en la rampa más corta.
local HALF_STEP_ALLOWANCE = 0.5

local function getMinimumRampSteps(): number
	local minimum = math.huge
	for _, definition in RoadPieceCatalog.definitions do
		if definition.maxRadiusStuds < math.huge then
			local lobeSteps = definition.minLengthStuds / definition.lobeCount / STEP_STUDS
			minimum = math.min(minimum, definition.rampFraction * lobeSteps - HALF_STEP_ALLOWANCE)
		end
	end
	return minimum
end

local MAX_CURVATURE_CHANGE_PER_STEP = MAX_CURVATURE / getMinimumRampSteps()
local MAX_HEIGHT_CHANGE_PER_STEP = STEP_STUDS * math.tan(MAX_SLOPE_RADIANS)

-- La pendiente cambia de forma lineal de un valor a otro dentro de la pieza más corta.
local function getMinimumPieceSteps(): number
	local minimum = math.huge
	for _, definition in RoadPieceCatalog.definitions do
		minimum = math.min(minimum, definition.minLengthStuds / STEP_STUDS)
	end
	return minimum
end

local MAX_SLOPE_CHANGE_PER_STEP = 2 * MAX_SLOPE_RADIANS / getMinimumPieceSteps()

-- Las rutas se generan una sola vez y todas las propiedades las revisan.
local cachedRoads: { { RoadPath.Segment } } = {}

local function getRoad(seed: number): { RoadPath.Segment }
	local road = cachedRoads[seed]
	if road == nil then
		road = PathHelpers.generateSegments(RoadPath.new(seed), SEGMENT_COUNT)
		cachedRoads[seed] = road
	end
	return road
end

local function forEachSample(check: (sample: RoadPath.RoadSample, previous: RoadPath.RoadSample?) -> ())
	for seed = 1, SEED_COUNT do
		local previous: RoadPath.RoadSample? = nil
		for _, segment in getRoad(seed) do
			for _, sample in segment.samples do
				check(sample, previous)
				previous = sample
			end
		end
	end
end

Runner.test("the curvature never exceeds the limit of the minimum radius", function()
	forEachSample(function(sample)
		Runner.expectEqual(math.abs(sample.curvature) <= MAX_CURVATURE + TOLERANCE, true)
	end)
end)

Runner.test("the heading stays inside the corridor around the mean heading", function()
	forEachSample(function(sample)
		local deviation = math.abs(RoadFrame.getHeadingDeviationRadians(sample.heading))
		Runner.expectEqual(deviation <= MAX_DEVIATION_RADIANS + TOLERANCE, true)
	end)
end)

Runner.test("the lateral drift stays inside the limit", function()
	forEachSample(function(sample)
		local drift = math.abs(RoadFrame.getLateralOffsetStuds(sample.position))
		Runner.expectEqual(drift <= WorldConfig.MAX_LATERAL_DRIFT_STUDS, true)
	end)
end)

Runner.test("the slope stays inside the maximum slope", function()
	forEachSample(function(sample)
		Runner.expectEqual(math.abs(sample.slope) <= MAX_SLOPE_RADIANS + TOLERANCE, true)
	end)
end)

Runner.test("every value of every sample is a finite number", function()
	forEachSample(function(sample)
		local position = sample.position
		for _, value in { position.x, position.y, position.z, sample.heading, sample.curvature, sample.slope } do
			Runner.expectEqual(value == value and math.abs(value) ~= math.huge, true)
		end
	end)
end)

Runner.test("the first sample of a segment is the last one of the previous segment", function()
	for seed = 1, SEED_COUNT do
		local road = getRoad(seed)
		for index = 2, SEGMENT_COUNT do
			local previousLast = road[index - 1].samples[#road[index - 1].samples]
			local first = road[index].samples[1]
			Runner.expectEqual(first.position, previousLast.position)
			Runner.expectEqual(first.heading, previousLast.heading)
			Runner.expectEqual(first.curvature, previousLast.curvature)
			Runner.expectEqual(first.slope, previousLast.slope)
			Runner.expectEqual(first.arcLength, previousLast.arcLength)
		end
	end
end)

Runner.test("there are no jumps in height, curvature or heading between consecutive samples", function()
	forEachSample(function(sample, previous)
		if previous == nil then
			return
		end
		Runner.expectEqual(
			math.abs(sample.position.y - previous.position.y) <= MAX_HEIGHT_CHANGE_PER_STEP + TOLERANCE,
			true
		)
		Runner.expectEqual(math.abs(sample.curvature - previous.curvature) <= MAX_CURVATURE_CHANGE_PER_STEP, true)
		Runner.expectEqual(math.abs(sample.heading - previous.heading) <= MAX_CURVATURE * STEP_STUDS + TOLERANCE, true)
		Runner.expectEqual(math.abs(sample.slope - previous.slope) <= MAX_SLOPE_CHANGE_PER_STEP + TOLERANCE, true)
	end)
end)

Runner.test("the distance between consecutive samples is one step on the ground", function()
	forEachSample(function(sample, previous)
		if previous == nil or sample.arcLength == previous.arcLength then
			return
		end
		local deltaX = sample.position.x - previous.position.x
		local deltaZ = sample.position.z - previous.position.z
		Runner.expectNear(math.sqrt(deltaX * deltaX + deltaZ * deltaZ), STEP_STUDS, VECTOR_PRECISION_STUDS)
	end)
end)

Runner.test("the road never crosses itself: x always grows", function()
	forEachSample(function(sample, previous)
		if previous ~= nil and sample.arcLength ~= previous.arcLength then
			Runner.expectEqual(sample.position.x > previous.position.x, true)
		end
	end)
end)

Runner.test("the arc length grows by exactly one step per sample", function()
	forEachSample(function(sample, previous)
		if previous ~= nil and sample.arcLength ~= previous.arcLength then
			Runner.expectEqual(sample.arcLength - previous.arcLength, STEP_STUDS)
		end
	end)
end)

Runner.test("the road keeps the limits while releasing segments as it goes", function()
	local path = RoadPath.new(31337)
	for index = 0, 399 do
		local segment = path.generateNextSegment()
		path.releaseSegmentsBefore(index)
		local last = segment.samples[#segment.samples]
		Runner.expectEqual(
			math.abs(RoadFrame.getLateralOffsetStuds(last.position)) <= WorldConfig.MAX_LATERAL_DRIFT_STUDS,
			true
		)
		Runner.expectEqual(
			math.abs(RoadFrame.getHeadingDeviationRadians(last.heading)) <= MAX_DEVIATION_RADIANS + TOLERANCE,
			true
		)
	end
end)

Runner.finish()
