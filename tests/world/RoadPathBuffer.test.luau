--!strict
-- El buffer de RoadPath: las piezas se generan por delante y un tramo se publica recién cuando ya no puede cambiar.
local HillProfile = require("../../src/world/core/HillProfile")
local PathHelpers = require("./PathHelpers")
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadIntegrator = require("../../src/world/core/RoadIntegrator")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadPieceSequencer = require("../../src/world/core/RoadPieceSequencer")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
-- En esta semilla la ruta retrocede dentro de los primeros 70 tramos (ver RoadPieceSequencer.test.luau).
local BACKTRACK_SEED = 16
local BACKTRACK_SEGMENTS = 70
local OTHER_SEED = 7

type Sample = RoadPath.RoadSample

local function expectSameSample(actual: Sample, expected: Sample)
	Runner.expectEqual(actual.position, expected.position)
	Runner.expectEqual(actual.heading, expected.heading)
	Runner.expectEqual(actual.curvature, expected.curvature)
	Runner.expectEqual(actual.slope, expected.slope)
	Runner.expectEqual(actual.arcLength, expected.arcLength)
end

-- La ruta que arma el secuenciador solo, con los retrocesos aplicados, hasta la última muestra definitiva.
local function followSequencer(seed: number, sampleCount: number): { [number]: Sample }
	local sequencer = RoadPieceSequencer.new(seed)
	local samples: { [number]: Sample } = { [0] = sequencer.getInitialSample() }
	local lastNumber, finalizedNumber = 0, 0
	while finalizedNumber < sampleCount do
		local piece = sequencer.generateNextPiece()
		for number = lastNumber, piece.retractedAfterSampleNumber + 1, -1 do
			samples[number] = nil
		end
		for offset, sample in piece.samples do
			samples[piece.retractedAfterSampleNumber + offset] = sample
		end
		lastNumber = piece.retractedAfterSampleNumber + #piece.samples
		finalizedNumber = piece.finalizedSampleNumber
	end
	return samples
end

Runner.test("the published segments are what the sequencer gives, also across a retraction", function()
	local segments = PathHelpers.generateSegments(RoadPath.new(BACKTRACK_SEED), BACKTRACK_SEGMENTS)
	local expected = followSequencer(BACKTRACK_SEED, BACKTRACK_SEGMENTS * STEPS_PER_SEGMENT)
	for index, segment in segments do
		for offset, sample in segment.samples do
			expectSameSample(sample, expected[(index - 1) * STEPS_PER_SEGMENT + offset - 1])
		end
	end
end)

Runner.test("replaying the published curvatures with RoadIntegrator gives the same samples bit by bit", function()
	for _, seed in { BACKTRACK_SEED, OTHER_SEED } do
		local seedRandom = SeededRandom.new(seed)
		seedRandom.nextNumber()
		local hill = HillProfile.new(seedRandom.nextNumber())
		local state = RoadIntegrator.createState(WorldConfig.START_POSITION, RoadFrame.getStartHeadingRadians())
		for _, segment in PathHelpers.generateSegments(RoadPath.new(seed), 12) do
			for offset = 2, #segment.samples do
				local sample = segment.samples[offset]
				RoadIntegrator.step(state, sample.curvature, hill)
				expectSameSample(sample, RoadIntegrator.toSample(state))
			end
		end
	end
end)

Runner.test("the generated length is ahead of the published one by at most what can still be taken back", function()
	local path, getStatistics = RoadPath.newWithStatistics(OTHER_SEED)
	for segmentCount = 1, 40 do
		path.generateNextSegment()
		local lagStuds = getStatistics().arcLengthStuds - segmentCount * WorldConfig.SEGMENT_LENGTH_STUDS
		Runner.expectEqual(lagStuds >= 0 and lagStuds <= WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS, true)
	end
end)

Runner.test("releasing every segment while pieces are waiting to be published does not break the road", function()
	local never = RoadPath.new(BACKTRACK_SEED)
	local released = RoadPath.new(BACKTRACK_SEED)
	local previousLast: Sample? = nil
	for _ = 1, BACKTRACK_SEGMENTS do
		local segment = released.generateNextSegment()
		if previousLast ~= nil then
			expectSameSample(segment.samples[1], previousLast)
		end
		previousLast = segment.samples[#segment.samples]
		released.releaseSegmentsBefore(math.huge)
		local expected = never.generateNextSegment()
		Runner.expectEqual(PathHelpers.hashSegments({ segment }), PathHelpers.hashSegments({ expected }))
	end
end)

Runner.test("the published segments keep their samples when later pieces are taken back", function()
	local path = RoadPath.new(BACKTRACK_SEED)
	local segments = PathHelpers.generateSegments(path, BACKTRACK_SEGMENTS)
	local hashes = {}
	for index, segment in segments do
		hashes[index] = PathHelpers.hashSegments({ segment })
	end
	PathHelpers.generateSegments(path, BACKTRACK_SEGMENTS)
	for index, segment in segments do
		Runner.expectEqual(PathHelpers.hashSegments({ segment }), hashes[index])
		Runner.expectEqual(PathHelpers.hashSegments({ path.getSegment(index - 1) :: RoadPath.Segment }), hashes[index])
	end
end)

Runner.test("the statistics come with the path and count the pieces generated", function()
	local path, getStatistics = RoadPath.newWithStatistics(OTHER_SEED)
	Runner.expectEqual(getStatistics().pieceCount, 0)
	path.generateNextSegment()
	Runner.expectEqual(getStatistics().pieceCount > 0, true)
	Runner.expectEqual(getStatistics().arcLengthStuds >= STEPS_PER_SEGMENT * STEP_STUDS, true)
end)

Runner.test("new and newWithStatistics build the same road", function()
	local plain = PathHelpers.generateSegments(RoadPath.new(OTHER_SEED), 10)
	local counted = PathHelpers.generateSegments((RoadPath.newWithStatistics(OTHER_SEED)), 10)
	Runner.expectEqual(PathHelpers.hashSegments(plain), PathHelpers.hashSegments(counted))
end)

Runner.finish()
