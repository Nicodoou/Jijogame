--!strict
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadQuery = require("../../src/world/core/RoadQuery")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type RoadQueryResult = RoadQuery.RoadQueryResult

local POSITION_COUNT = 1000
local TOLERANCE = 0.01
-- El punto devuelto es un vector de floats de 32 bits: a 8.000 studs del origen se redondea a 0,001 studs por coordenada.
local VECTOR_PRECISION_STUDS = 0.03
local PATH_SEED = 2024
local GENERATED_SEGMENTS = 8
local FIRST_LOADED_SEGMENT = 2
local WINDOW_SAMPLES = WorldConfig.ROAD_QUERY_CURSOR_WINDOW_SAMPLES
-- Una consulta con ventana mira como mucho las muestras de la ventana más la del extremo.
local MAX_WINDOW_EXAMINED = 2 * WINDOW_SAMPLES + 2
local MAX_DISTANCE = WorldConfig.ROAD_QUERY_MAX_DISTANCE_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
-- Solo cerca del eje el punto más cercano es único; más lejos pueden empatar dos puntos de una curva.
local UNIQUE_LATERAL_STUDS = 40

local function createLoadedPath(): RoadPath.RoadPath
	local path = RoadPath.new(PATH_SEED)
	PathHelpers.generateSegments(path, GENERATED_SEGMENTS)
	path.releaseSegmentsBefore(FIRST_LOADED_SEGMENT)
	return path
end

local function collectSamples(path: RoadPath.RoadPath): { RoadPath.RoadSample }
	local samples = {}
	local first, last = path.getLoadedRange()
	for index = first, last do
		local segment = path.getSegment(index) :: RoadPath.Segment
		for offset, sample in segment.samples do
			if index == first or offset > 1 then
				table.insert(samples, sample)
			end
		end
	end
	return samples
end

-- Búsqueda por fuerza bruta sobre todas las aristas, escrita aparte de RoadQuery a propósito.
local function findNearestByBruteForce(samples: { RoadPath.RoadSample }, query: vector): (number?, number?, number?)
	local bestDistance, bestLateral, bestArcLength = math.huge, nil, nil
	local bestEdge, bestRaw = 0, 0
	for index = 1, #samples - 1 do
		local a, b = samples[index].position, samples[index + 1].position
		local edgeX, edgeZ = b.x - a.x, b.z - a.z
		local raw = ((query.x - a.x) * edgeX + (query.z - a.z) * edgeZ) / (edgeX * edgeX + edgeZ * edgeZ)
		local fraction = math.clamp(raw, 0, 1)
		local deltaX, deltaZ = a.x + edgeX * fraction - query.x, a.z + edgeZ * fraction - query.z
		local distance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
		if distance < bestDistance then
			bestDistance, bestEdge, bestRaw = distance, index, raw
			bestLateral = distance * (if deltaX * edgeZ - deltaZ * edgeX >= 0 then 1 else -1)
			bestArcLength = samples[index].arcLength + fraction * STEP_STUDS
		end
	end
	local isBeforeStart = bestEdge == 1 and bestRaw < 0
	local isAfterEnd = bestEdge == #samples - 1 and bestRaw > 1
	if bestDistance > MAX_DISTANCE or isBeforeStart or isAfterEnd then
		return nil, nil, nil
	end
	return bestDistance, bestLateral, bestArcLength
end

local function createRandomPosition(random: SeededRandom.SeededRandom, samples: { RoadPath.RoadSample }): vector
	local sample = samples[random.nextInteger(1, #samples)]
	local position = sample.position
	local right = vector.create(-math.sin(sample.heading), 0, math.cos(sample.heading))
	local kind = random.nextInteger(1, 6)
	local height = (random.nextNumber() - 0.5) * 2000
	if kind == 1 then
		return vector.create(position.x, height, position.z)
	elseif kind == 2 then
		return position + right * (WorldConfig.ROAD_WIDTH_STUDS / 2) * (if random.nextNumber() < 0.5 then 1 else -1)
	elseif kind == 3 then
		return position + right * (random.nextNumber() - 0.5) * 80
	elseif kind == 4 then
		return position + right * (random.nextNumber() - 0.5) * 2 * (MAX_DISTANCE * 0.95)
	elseif kind == 5 then
		return position + right * (random.nextNumber() - 0.5) * 2 * (MAX_DISTANCE * 3)
	end
	return position + vector.create((random.nextNumber() - 0.5) * 4000, 0, (random.nextNumber() - 0.5) * 4000)
end

Runner.test("the nearest point matches the brute force search in 1000 positions", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	local random = SeededRandom.new(99)
	local foundCount, missingCount = 0, 0
	for _ = 1, POSITION_COUNT do
		local position = createRandomPosition(random, samples)
		local distance, lateral, arcLength = findNearestByBruteForce(samples, position)
		local result = query.findNearest(position, nil)
		if distance == nil then
			missingCount += 1
			Runner.expectEqual(result, nil)
		else
			foundCount += 1
			local found = result :: RoadQueryResult
			Runner.expectNear(math.abs(found.lateralOffset), distance, TOLERANCE)
			local groundDistance = math.sqrt((found.position.x - position.x) ^ 2 + (found.position.z - position.z) ^ 2)
			Runner.expectNear(groundDistance, distance, VECTOR_PRECISION_STUDS)
			if distance < UNIQUE_LATERAL_STUDS then
				Runner.expectNear(found.lateralOffset, lateral :: number, TOLERANCE)
				Runner.expectNear(found.arcLength, arcLength :: number, TOLERANCE)
			end
		end
	end
	Runner.expectEqual(foundCount > POSITION_COUNT / 2, true)
	Runner.expectEqual(missingCount > 0, true)
end)

Runner.test("a position on the axis has zero lateral offset and returns itself", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local sample = (path.getSegment(FIRST_LOADED_SEGMENT + 1) :: RoadPath.Segment).samples[40]
	local result = query.findNearest(sample.position, nil) :: RoadQueryResult
	Runner.expectNear(result.lateralOffset, 0, TOLERANCE)
	Runner.expectNear(result.arcLength, sample.arcLength, TOLERANCE)
	Runner.expectEqual(result.segmentIndex, FIRST_LOADED_SEGMENT + 1)
	Runner.expectNear(vector.magnitude(result.position - sample.position), 0, TOLERANCE)
end)

Runner.test("the direction is a unit vector that follows the heading", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local sample = (path.getSegment(FIRST_LOADED_SEGMENT + 2) :: RoadPath.Segment).samples[60]
	local result = query.findNearest(sample.position, nil) :: RoadQueryResult
	Runner.expectNear(vector.magnitude(result.direction), 1, 1e-6)
	Runner.expectNear(result.direction.x, math.cos(sample.heading), 0.05)
	Runner.expectNear(result.direction.z, math.sin(sample.heading), 0.05)
end)

Runner.test("the sign of the lateral offset is positive to the right of the direction of travel", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local sample = (path.getSegment(FIRST_LOADED_SEGMENT + 1) :: RoadPath.Segment).samples[50]
	local right = vector.create(-math.sin(sample.heading), 0, math.cos(sample.heading))
	Runner.expectNear(
		(query.findNearest(sample.position + right * 7, nil) :: RoadQueryResult).lateralOffset,
		7,
		TOLERANCE
	)
	Runner.expectNear(
		(query.findNearest(sample.position - right * 7, nil) :: RoadQueryResult).lateralOffset,
		-7,
		TOLERANCE
	)
end)

Runner.test("positions before the first loaded segment and after the last one have no answer", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	local first, last = samples[1], samples[#samples]
	local before = first.position - vector.create(math.cos(first.heading), 0, math.sin(first.heading)) * 30
	local after = last.position + vector.create(math.cos(last.heading), 0, math.sin(last.heading)) * 30
	Runner.expectEqual(query.findNearest(before, nil), nil)
	Runner.expectEqual(query.findNearest(after, nil), nil)
end)

Runner.test("the first and the last loaded points still answer", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	Runner.expectEqual(query.findNearest(samples[1].position, nil) ~= nil, true)
	Runner.expectEqual(query.findNearest(samples[#samples].position, nil) ~= nil, true)
end)

Runner.test("an empty path has no answer", function()
	local query = RoadQuery.new(RoadPath.new(PATH_SEED))
	Runner.expectEqual(query.findNearest(WorldConfig.START_POSITION, nil), nil)
end)

Runner.test("positions that are not finite have no answer and do not hang", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local sample = (path.getSegment(FIRST_LOADED_SEGMENT + 1) :: RoadPath.Segment).samples[10]
	local position = sample.position
	local nan, infinity = 0 / 0, math.huge
	Runner.expectEqual(query.findNearest(vector.create(nan, 0, position.z), nil), nil)
	Runner.expectEqual(query.findNearest(vector.create(position.x, 0, nan), nil), nil)
	Runner.expectEqual(query.findNearest(vector.create(infinity, 0, position.z), nil), nil)
	Runner.expectEqual(query.findNearest(vector.create(position.x, 0, -infinity), nil), nil)
	Runner.expectEqual(query.findNearest(vector.create(1e300, 0, 1e300), nil), nil)
	Runner.expectEqual(query.findNearest(position, nil) ~= nil, true)
end)

Runner.test("the query follows the segments that the path generates and releases", function()
	local path = RoadPath.new(PATH_SEED)
	local query = RoadQuery.new(path)
	local firstSegment = path.generateNextSegment()
	local middle = firstSegment.samples[64].position
	Runner.expectEqual(query.findNearest(middle, nil) ~= nil, true)
	local secondSegment = path.generateNextSegment()
	local later = secondSegment.samples[64].position
	Runner.expectEqual(query.findNearest(later, nil) ~= nil, true)
	path.releaseSegmentsBefore(1)
	Runner.expectEqual(query.findNearest(middle, nil), nil)
	Runner.expectEqual(query.findNearest(later, nil) ~= nil, true)
	path.releaseSegmentsBefore(10)
	Runner.expectEqual(query.findNearest(later, nil), nil)
	local thirdSegment = path.generateNextSegment()
	Runner.expectEqual(query.findNearest(thirdSegment.samples[64].position, nil) ~= nil, true)
	Runner.expectEqual(query.findNearest(later, nil), nil)
end)

Runner.test("with a cursor the result matches the brute force while driving along the road", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	local random = SeededRandom.new(5)
	local cursor: RoadQueryResult? = nil
	for index = 1, #samples - 1 do
		local sample = samples[index]
		local right = vector.create(-math.sin(sample.heading), 0, math.cos(sample.heading))
		local position = sample.position + right * (random.nextNumber() - 0.5) * 30
		local distance, _, arcLength = findNearestByBruteForce(samples, position)
		local result = query.findNearest(position, cursor)
		if distance == nil then
			Runner.expectEqual(result, nil)
		else
			local found = result :: RoadQueryResult
			Runner.expectNear(math.abs(found.lateralOffset), distance, TOLERANCE)
			Runner.expectNear(found.arcLength, arcLength :: number, TOLERANCE)
			if cursor ~= nil then
				Runner.expectEqual(query.getExaminedSampleCount() <= MAX_WINDOW_EXAMINED, true)
			end
		end
		cursor = result
	end
end)

Runner.test("with a cursor the samples examined do not grow with the number of loaded segments", function()
	local examinedBySegments = {}
	for _, segmentCount in { 4, 40 } do
		local path = RoadPath.new(PATH_SEED)
		PathHelpers.generateSegments(path, segmentCount)
		local query = RoadQuery.new(path)
		local middle = (path.getSegment(2) :: RoadPath.Segment).samples[64]
		local first = query.findNearest(middle.position, nil) :: RoadQueryResult
		query.findNearest(middle.position, first)
		table.insert(examinedBySegments, query.getExaminedSampleCount())
	end
	Runner.expectEqual(examinedBySegments[1], examinedBySegments[2])
	Runner.expectEqual(examinedBySegments[2] <= MAX_WINDOW_EXAMINED, true)
end)

Runner.test("a stale cursor far from the position falls back to the general search", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	local staleCursor = query.findNearest(samples[10].position, nil) :: RoadQueryResult
	local target = samples[#samples - 20].position
	local result = query.findNearest(target, staleCursor) :: RoadQueryResult
	Runner.expectNear(result.lateralOffset, 0, TOLERANCE)
	Runner.expectNear(result.arcLength, samples[#samples - 20].arcLength, TOLERANCE)
end)

Runner.test("a cursor from released segments falls back to the general search", function()
	local path = RoadPath.new(PATH_SEED)
	PathHelpers.generateSegments(path, 6)
	local query = RoadQuery.new(path)
	local oldPosition = (path.getSegment(0) :: RoadPath.Segment).samples[20].position
	local oldCursor = query.findNearest(oldPosition, nil) :: RoadQueryResult
	path.releaseSegmentsBefore(4)
	local target = (path.getSegment(5) :: RoadPath.Segment).samples[30].position
	local result = query.findNearest(target, oldCursor) :: RoadQueryResult
	Runner.expectNear(result.lateralOffset, 0, TOLERANCE)
end)

Runner.test("a far position near the window edge is checked by the general search", function()
	local path = createLoadedPath()
	local query = RoadQuery.new(path)
	local samples = collectSamples(path)
	local cursor = query.findNearest(samples[100].position, nil) :: RoadQueryResult
	local sample = samples[100]
	local right = vector.create(-math.sin(sample.heading), 0, math.cos(sample.heading))
	local position = sample.position + right * 400
	local distance = findNearestByBruteForce(samples, position)
	local result = query.findNearest(position, cursor) :: RoadQueryResult
	Runner.expectNear(math.abs(result.lateralOffset), distance :: number, TOLERANCE)
end)

Runner.finish()
