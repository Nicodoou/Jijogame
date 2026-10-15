--!strict
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadQuery = require("../../src/world/core/RoadQuery")
local Runner = require("../Runner")
local SurfaceClassifier = require("../../src/world/core/SurfaceClassifier")
local WorldConfig = require("../../src/world/core/WorldConfig")

type SurfaceKind = "Road" | "Shoulder" | "Grass" | "Mud"

local PATH_SEED = 777
local GENERATED_SEGMENTS = 6
local FIRST_LOADED_SEGMENT = 1
-- Un vector guarda floats de 32 bits (0,0078 studs de paso cerca de x = -120.000): el hueco tiene que ser mayor que eso.
local EDGE_GAP_STUDS = 0.05
local ROAD_HALF_WIDTH = WorldConfig.ROAD_WIDTH_STUDS / 2
local SHOULDER_EDGE = ROAD_HALF_WIDTH + WorldConfig.SHOULDER_WIDTH_STUDS
local MUD_START = SHOULDER_EDGE + WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS
local SCAN_COUNT = 400
local FAR_LATERAL_STUDS = 60

local function createWorld(classifierSeed: number)
	local path = RoadPath.new(PATH_SEED)
	PathHelpers.generateSegments(path, GENERATED_SEGMENTS)
	path.releaseSegmentsBefore(FIRST_LOADED_SEGMENT)
	local getSurfaceAt = SurfaceClassifier.createGetSurfaceAt(RoadQuery.new(path), classifierSeed)
	return path, getSurfaceAt
end

-- Un punto del eje (a mitad de arista) y la dirección hacia la derecha, para medir distancias exactas al eje.
local function getAxisPoint(path: RoadPath.RoadPath, segmentIndex: number, sampleIndex: number): (vector, vector)
	local samples = (path.getSegment(segmentIndex) :: RoadPath.Segment).samples
	local from, to = samples[sampleIndex], samples[sampleIndex + 1]
	local middle = (from.position + to.position) * 0.5
	local edge = to.position - from.position
	local length = math.sqrt(edge.x * edge.x + edge.z * edge.z)
	return middle, vector.create(-edge.z / length, 0, edge.x / length)
end

local function classifyAt(
	getSurfaceAt: (vector) -> SurfaceKind?,
	lateral: number,
	sampleIndex: number,
	path: RoadPath.RoadPath
)
	local middle, right = getAxisPoint(path, 3, sampleIndex)
	return getSurfaceAt(middle + right * lateral)
end

Runner.test("the road covers up to half of the road width, on both sides", function()
	local path, getSurfaceAt = createWorld(1)
	for _, side in { -1, 1 } do
		Runner.expectEqual(classifyAt(getSurfaceAt, 0, 60, path), "Road")
		Runner.expectEqual(classifyAt(getSurfaceAt, side * (ROAD_HALF_WIDTH - EDGE_GAP_STUDS), 60, path), "Road")
	end
end)

Runner.test("the shoulder starts right after the road and ends right before the grass", function()
	local path, getSurfaceAt = createWorld(1)
	for _, side in { -1, 1 } do
		Runner.expectEqual(classifyAt(getSurfaceAt, side * (ROAD_HALF_WIDTH + EDGE_GAP_STUDS), 60, path), "Shoulder")
		Runner.expectEqual(classifyAt(getSurfaceAt, side * (SHOULDER_EDGE - EDGE_GAP_STUDS), 60, path), "Shoulder")
		local beyond = classifyAt(getSurfaceAt, side * (SHOULDER_EDGE + EDGE_GAP_STUDS), 60, path)
		Runner.expectEqual(beyond == "Grass" or beyond == "Mud", true)
	end
end)

Runner.test("there is never mud on the road, the shoulder or within the minimum distance", function()
	local path, getSurfaceAt = createWorld(1)
	for sampleIndex = 1, 120 do
		for step = 0, 20 do
			local lateral = MUD_START * step / 20 - EDGE_GAP_STUDS
			Runner.expectEqual(classifyAt(getSurfaceAt, lateral, sampleIndex, path) ~= "Mud", true)
			Runner.expectEqual(classifyAt(getSurfaceAt, -lateral, sampleIndex, path) ~= "Mud", true)
		end
	end
end)

Runner.test("between the shoulder and the mud distance the surface is grass", function()
	local path, getSurfaceAt = createWorld(1)
	local lateral = (SHOULDER_EDGE + MUD_START) / 2
	for sampleIndex = 1, 120 do
		Runner.expectEqual(classifyAt(getSurfaceAt, lateral, sampleIndex, path), "Grass")
	end
end)

Runner.test("mud shows up beyond the minimum distance, in patches that leave grass around", function()
	local path, getSurfaceAt = createWorld(1)
	local counts = { Mud = 0, Grass = 0 }
	for sampleIndex = 1, 120 do
		for _, lateral in { FAR_LATERAL_STUDS, -FAR_LATERAL_STUDS, 3 * FAR_LATERAL_STUDS } do
			local surface = classifyAt(getSurfaceAt, lateral, sampleIndex, path) :: SurfaceKind
			counts[surface] = (counts[surface] or 0) + 1
		end
	end
	Runner.expectEqual(counts.Mud > 0, true)
	Runner.expectEqual(counts.Grass > 0, true)
end)

Runner.test("the same seed gives the same mud and another seed gives another pattern", function()
	local path, firstSurface = createWorld(5)
	local _, secondSurface = createWorld(5)
	local _, otherSurface = createWorld(6)
	local differences = 0
	for sampleIndex = 1, SCAN_COUNT / 4 do
		local middle, right = getAxisPoint(path, 3, sampleIndex)
		local position = middle + right * FAR_LATERAL_STUDS
		Runner.expectEqual(firstSurface(position), secondSurface(position))
		if firstSurface(position) ~= otherSurface(position) then
			differences += 1
		end
	end
	Runner.expectEqual(differences > 0, true)
end)

Runner.test("the height does not change the surface", function()
	local path, getSurfaceAt = createWorld(1)
	for sampleIndex = 1, 120 do
		for _, lateral in { 0, ROAD_HALF_WIDTH + 1, FAR_LATERAL_STUDS } do
			local middle, right = getAxisPoint(path, 3, sampleIndex)
			local flat = getSurfaceAt(middle + right * lateral)
			Runner.expectEqual(getSurfaceAt(middle + right * lateral + vector.create(0, 5000, 0)), flat)
			Runner.expectEqual(getSurfaceAt(middle + right * lateral - vector.create(0, 5000, 0)), flat)
		end
	end
end)

Runner.test("there is no answer before the first loaded segment nor after the last one", function()
	local path, getSurfaceAt = createWorld(1)
	local firstLoaded = (path.getSegment(FIRST_LOADED_SEGMENT) :: RoadPath.Segment).samples[1].position
	local lastSegment = path.getSegment(GENERATED_SEGMENTS - 1) :: RoadPath.Segment
	local lastLoaded = lastSegment.samples[#lastSegment.samples].position
	Runner.expectEqual(getSurfaceAt(firstLoaded - vector.create(20, 0, 0)), nil)
	Runner.expectEqual(getSurfaceAt(lastLoaded + vector.create(20, 0, 0)), nil)
	Runner.expectEqual(getSurfaceAt(WorldConfig.START_POSITION), nil)
	Runner.expectEqual(getSurfaceAt(firstLoaded + vector.create(20, 0, 0)) ~= nil, true)
end)

Runner.test("there is no answer for positions that are not finite", function()
	local _, getSurfaceAt = createWorld(1)
	Runner.expectEqual(getSurfaceAt(vector.create(0 / 0, 0, 0)), nil)
	Runner.expectEqual(getSurfaceAt(vector.create(math.huge, 0, math.huge)), nil)
end)

Runner.test("the classifier follows the segments that the path releases", function()
	local path, getSurfaceAt = createWorld(1)
	local middle = getAxisPoint(path, 2, 60)
	Runner.expectEqual(getSurfaceAt(middle), "Road")
	path.releaseSegmentsBefore(3)
	Runner.expectEqual(getSurfaceAt(middle), nil)
end)

Runner.test("seeds zero, negative and fractional build a classifier", function()
	for _, seed in { 0, -3, 0.75, 1e12 } do
		local path, getSurfaceAt = createWorld(seed)
		local middle = getAxisPoint(path, 3, 10)
		Runner.expectEqual(getSurfaceAt(middle), "Road")
	end
end)

Runner.finish()
