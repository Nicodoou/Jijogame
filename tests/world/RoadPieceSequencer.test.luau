--!strict
local RoadIntegrator = require("../../src/world/core/RoadIntegrator")
local RoadPieceSequencer = require("../../src/world/core/RoadPieceSequencer")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

type PieceResult = RoadPieceSequencer.PieceResult

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local SEED = 12345
local PIECES = 40
-- Semillas en las que, en las primeras piezas, la ruta usa el último recurso y retrocede.
local LAST_RESORT_SEED = 16
local BACKTRACK_SEED = 16
local BACKTRACK_PIECES = 60
local LOOSE_STUDS = 0.001
-- Un paso mide 2 studs sobre el plano, y en 3D un poco más si hay pendiente.
local MAX_STEP_DISTANCE_STUDS = STEP_STUDS / math.cos(math.rad(WorldConfig.MAX_SLOPE_DEGREES))

-- Sigue la ruta como la ve quien la usa: las muestras por número, con los retrocesos aplicados.
type Stream = {
	samples: { [number]: RoadIntegrator.RoadSample },
	lastNumber: number,
}

local function createStream(sequencer: RoadPieceSequencer.RoadPieceSequencer): Stream
	return { samples = { [0] = sequencer.getInitialSample() }, lastNumber = 0 }
end

local function applyPiece(stream: Stream, piece: PieceResult)
	for number = stream.lastNumber, piece.retractedAfterSampleNumber + 1, -1 do
		stream.samples[number] = nil
	end
	for offset, sample in piece.samples do
		stream.samples[piece.retractedAfterSampleNumber + offset] = sample
	end
	stream.lastNumber = piece.retractedAfterSampleNumber + #piece.samples
end

local function generateStream(
	seed: number,
	pieceCount: number
): (Stream, { PieceResult }, RoadPieceSequencer.RoadPieceSequencer)
	local sequencer = RoadPieceSequencer.new(seed)
	local stream = createStream(sequencer)
	local results = {}
	for index = 1, pieceCount do
		local piece = sequencer.generateNextPiece()
		applyPiece(stream, piece)
		results[index] = piece
	end
	return stream, results, sequencer
end

Runner.test("the initial sample is the start of the road, with nothing else", function()
	local sample = RoadPieceSequencer.new(SEED).getInitialSample()
	Runner.expectEqual(sample.position, WorldConfig.START_POSITION)
	Runner.expectEqual(sample.heading, math.rad(WorldConfig.START_HEADING_DEGREES))
	Runner.expectEqual(sample.curvature, 0)
	Runner.expectEqual(sample.slope, 0)
	Runner.expectEqual(sample.arcLength, 0)
end)

Runner.test("the same seed gives the same road and another seed gives another one", function()
	local first = generateStream(SEED, PIECES)
	local second = generateStream(SEED, PIECES)
	local other = generateStream(SEED + 1, PIECES)
	Runner.expectEqual(first.lastNumber, second.lastNumber)
	for number = 0, first.lastNumber do
		Runner.expectEqual(first.samples[number].position, second.samples[number].position)
		Runner.expectEqual(first.samples[number].heading, second.samples[number].heading)
	end
	local different = 0
	for number = 0, math.min(first.lastNumber, other.lastNumber) do
		different += if first.samples[number].position ~= other.samples[number].position then 1 else 0
	end
	Runner.expectEqual(different > 100, true)
end)

Runner.test("every piece continues the road without a gap, one step at a time", function()
	local stream, results = generateStream(SEED, PIECES)
	for number = 1, stream.lastNumber do
		Runner.expectEqual(stream.samples[number] ~= nil, true)
		Runner.expectEqual(stream.samples[number].arcLength, number * STEP_STUDS)
	end
	for _, piece in results do
		Runner.expectEqual(#piece.samples > 0, true)
		Runner.expectEqual(piece.samples[1].arcLength, (piece.retractedAfterSampleNumber + 1) * STEP_STUDS)
	end
end)

Runner.test("the finalized samples never go back and a piece never retracts below them", function()
	local _, results = generateStream(SEED, PIECES)
	local finalized = 0
	for _, piece in results do
		Runner.expectEqual(piece.finalizedSampleNumber >= finalized, true)
		Runner.expectEqual(piece.retractedAfterSampleNumber >= finalized, true)
		Runner.expectEqual(piece.finalizedSampleNumber <= piece.retractedAfterSampleNumber + #piece.samples, true)
		finalized = piece.finalizedSampleNumber
	end
	Runner.expectEqual(finalized > 0, true)
end)

Runner.test("the finalized samples lag behind by at most the pieces that can still be taken back", function()
	local stream, results = generateStream(SEED, PIECES)
	local lastPiece = results[#results]
	local lagStuds = (stream.lastNumber - lastPiece.finalizedSampleNumber) * STEP_STUDS
	Runner.expectEqual(lagStuds > 0, true)
	Runner.expectEqual(lagStuds <= WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS, true)
end)

Runner.test("the statistics count the pieces, by kind, and the length generated", function()
	local stream, _, sequencer = generateStream(SEED, PIECES)
	local statistics = sequencer.getStatistics()
	local byKind = 0
	for _, count in statistics.pieceCountByKind do
		byKind += count
	end
	Runner.expectEqual(statistics.pieceCount, byKind)
	Runner.expectEqual(statistics.pieceCount, PIECES - statistics.retractedPieceCount)
	Runner.expectEqual(statistics.arcLengthStuds, stream.lastNumber * STEP_STUDS)
end)

Runner.test("when no alternative fits, the last resort is used and counted", function()
	local _, _, sequencer = generateStream(LAST_RESORT_SEED, PIECES)
	Runner.expectEqual(sequencer.getStatistics().lastResortCount > 0, true)
end)

Runner.test("when even the last resort fails, the road takes back pieces and the samples are replaced", function()
	local sequencer = RoadPieceSequencer.new(BACKTRACK_SEED)
	local stream = createStream(sequencer)
	local statistics = sequencer.getStatistics()
	local retractions = 0
	local finalized = 0
	for _ = 1, BACKTRACK_PIECES do
		local previousEnd = stream.lastNumber
		local piece = sequencer.generateNextPiece()
		if piece.retractedAfterSampleNumber < previousEnd then
			retractions += 1
			Runner.expectEqual(piece.retractedAfterSampleNumber >= finalized, true)
		end
		finalized = piece.finalizedSampleNumber
		applyPiece(stream, piece)
		Runner.expectEqual(stream.samples[stream.lastNumber].arcLength, stream.lastNumber * STEP_STUDS)
	end
	Runner.expectEqual(retractions > 0, true)
	Runner.expectEqual(retractions, statistics.backtrackCount)
	Runner.expectEqual(statistics.retractedPieceCount >= statistics.backtrackCount, true)
	Runner.expectEqual(
		statistics.retractedPieceCount <= statistics.backtrackCount * WorldConfig.ROAD_BACKTRACK_MAX_PIECES,
		true
	)
end)

Runner.test("a road with retractions is the same one however it is followed", function()
	local first = generateStream(BACKTRACK_SEED, BACKTRACK_PIECES)
	local second = generateStream(BACKTRACK_SEED, BACKTRACK_PIECES)
	Runner.expectEqual(first.lastNumber, second.lastNumber)
	for number = 0, first.lastNumber do
		local a, b = first.samples[number], second.samples[number]
		Runner.expectEqual(a.position, b.position)
		Runner.expectEqual(a.heading, b.heading)
		Runner.expectEqual(a.curvature, b.curvature)
		Runner.expectEqual(a.slope, b.slope)
	end
end)

Runner.test("the road stays continuous in position even where pieces were taken back", function()
	local stream = generateStream(BACKTRACK_SEED, BACKTRACK_PIECES)
	for number = 1, stream.lastNumber do
		local distance = vector.magnitude(stream.samples[number].position - stream.samples[number - 1].position)
		Runner.expectEqual(
			distance >= STEP_STUDS - LOOSE_STUDS and distance <= MAX_STEP_DISTANCE_STUDS + LOOSE_STUDS,
			true
		)
	end
end)

Runner.test("stepping gives the same pieces and counts as asking for whole pieces, also across retractions", function()
	for _, seed in { SEED, BACKTRACK_SEED } do
		local whole = RoadPieceSequencer.new(seed)
		local stepped = RoadPieceSequencer.new(seed)
		local stepCount = 0
		for _ = 1, BACKTRACK_PIECES do
			local expected = whole.generateNextPiece()
			local stepResult = stepped.generatePieceStep()
			stepCount += 1
			while stepResult == nil do
				stepResult = stepped.generatePieceStep()
				stepCount += 1
			end
			local piece = stepResult :: PieceResult
			Runner.expectEqual(piece.retractedAfterSampleNumber, expected.retractedAfterSampleNumber)
			Runner.expectEqual(piece.finalizedSampleNumber, expected.finalizedSampleNumber)
			Runner.expectEqual(#piece.samples, #expected.samples)
			Runner.expectEqual(piece.samples[#piece.samples].position, expected.samples[#expected.samples].position)
		end
		Runner.expectEqual(stepCount > BACKTRACK_PIECES, true)
		local wholeStatistics, steppedStatistics = whole.getStatistics(), stepped.getStatistics()
		Runner.expectEqual(steppedStatistics.lastResortCount, wholeStatistics.lastResortCount)
		Runner.expectEqual(steppedStatistics.backtrackCount, wholeStatistics.backtrackCount)
		Runner.expectEqual(steppedStatistics.retractedPieceCount, wholeStatistics.retractedPieceCount)
		Runner.expectEqual(steppedStatistics.arcLengthStuds, wholeStatistics.arcLengthStuds)
	end
end)

Runner.test("the first step only draws the piece and gives nothing yet", function()
	local sequencer = RoadPieceSequencer.new(SEED)
	Runner.expectEqual(sequencer.generatePieceStep(), nil)
	Runner.expectEqual(sequencer.getStatistics().pieceCount, 0)
end)

Runner.finish()
