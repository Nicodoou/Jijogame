--!strict
local RoadPieceAlternatives = require("../../src/world/core/RoadPieceAlternatives")
local RoadPieceBuilder = require("../../src/world/core/RoadPieceBuilder")
local RoadPiecePreview = require("../../src/world/core/RoadPiecePreview")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type RoadPiece = RoadPieceProfile.RoadPiece
type PreviewResult = RoadPiecePreview.PreviewResult

local LAST_RESORT_COUNT = #WorldConfig.LAST_RESORT_LOBE_STEPS
local RANDOM_SEED = 6

-- Un resultado cualquiera: lo único que importa es cuál intento lo devuelve.
local function createResult(piece: RoadPiece): PreviewResult
	return {
		pieceKind = piece.kind,
		samples = {},
		endState = { x = 0, y = 0, z = 0, heading = 0, curvature = 0, slope = 0, sampleIndex = 0 },
		guideArcLength = 0,
		guideSegment = 1,
	}
end

-- Rechaza todo salvo el intento número `acceptedAttempt`, y anota cada pieza que le llega.
local function createRecorder(acceptedAttempt: number): ({ RoadPiece }, RoadPieceAlternatives.TryPiece)
	local tried: { RoadPiece } = {}
	local function tryPiece(piece: RoadPiece): PreviewResult?
		table.insert(tried, piece)
		return if #tried == acceptedAttempt then createResult(piece) else nil
	end
	return tried, tryPiece
end

local function createCurve(): RoadPiece
	return RoadPieceBuilder.createTightTurn(1, 40)
end

local function expectSamePeak(piece: RoadPiece, expected: RoadPiece)
	Runner.expectEqual(piece.parts[1].peakCurvature, expected.parts[1].peakCurvature)
	Runner.expectEqual(piece.totalSteps, expected.totalSteps)
end

Runner.test("the drawn piece goes first and, if it fits, nothing else is tried and no random number is used", function()
	local tried, tryPiece = createRecorder(1)
	local random = SeededRandom.new(RANDOM_SEED)
	local piece = createCurve()
	local result, usedLastResort = RoadPieceAlternatives.findFirstAccepted(piece, 1, tryPiece, random)
	Runner.expectEqual(result ~= nil, true)
	Runner.expectEqual(usedLastResort, false)
	Runner.expectEqual(#tried, 1)
	Runner.expectEqual(tried[1], piece)
	Runner.expectEqual(random.nextNumber(), SeededRandom.new(RANDOM_SEED).nextNumber())
end)

Runner.test("then come the other side, the shorter one, a sharp curve toward the guide and a short straight", function()
	local tried, tryPiece = createRecorder(0)
	local piece = createCurve()
	local result, usedLastResort =
		RoadPieceAlternatives.findFirstAccepted(piece, -1, tryPiece, SeededRandom.new(RANDOM_SEED))
	Runner.expectEqual(result, nil)
	Runner.expectEqual(usedLastResort, true)
	Runner.expectEqual(#tried, 5 + 2 * LAST_RESORT_COUNT)
	expectSamePeak(tried[1], piece)
	expectSamePeak(tried[2], RoadPieceBuilder.flip(piece))
	expectSamePeak(tried[3], RoadPieceBuilder.shorten(piece) :: RoadPiece)
	Runner.expectEqual(tried[4].kind, "sharpCurve")
	Runner.expectEqual(tried[4].parts[1].peakCurvature < 0, true)
	Runner.expectEqual(tried[5].kind, "straight")
	Runner.expectEqual(tried[5].totalSteps, WorldConfig.EMERGENCY_STRAIGHT_STEPS)
end)

Runner.test("the last resort tries the tight turns toward the guide, longest first, and then the ones away", function()
	for _, towardSign in { 1, -1 } do
		local tried, tryPiece = createRecorder(0)
		RoadPieceAlternatives.findFirstAccepted(createCurve(), towardSign, tryPiece, SeededRandom.new(RANDOM_SEED))
		for position, lobeSteps in WorldConfig.LAST_RESORT_LOBE_STEPS do
			local toward, away = tried[5 + position], tried[5 + LAST_RESORT_COUNT + position]
			expectSamePeak(toward, RoadPieceBuilder.createTightTurn(towardSign, lobeSteps))
			expectSamePeak(away, RoadPieceBuilder.createTightTurn(-towardSign, lobeSteps))
		end
	end
end)

Runner.test("a piece accepted by the last resort says so, whichever attempt of it", function()
	for attempt = 6, 5 + 2 * LAST_RESORT_COUNT do
		local _, tryPiece = createRecorder(attempt)
		local result, usedLastResort =
			RoadPieceAlternatives.findFirstAccepted(createCurve(), 1, tryPiece, SeededRandom.new(RANDOM_SEED))
		Runner.expectEqual(result ~= nil, true)
		Runner.expectEqual(usedLastResort, true)
	end
end)

Runner.test("each of the first five attempts that fits stops the search there and is not the last resort", function()
	for attempt = 2, 5 do
		local tried, tryPiece = createRecorder(attempt)
		local result, usedLastResort =
			RoadPieceAlternatives.findFirstAccepted(createCurve(), 1, tryPiece, SeededRandom.new(RANDOM_SEED))
		Runner.expectEqual(result ~= nil, true)
		Runner.expectEqual(usedLastResort, false)
		Runner.expectEqual(#tried, attempt)
	end
end)

Runner.test(
	"a straight is not flipped, a hairpin pair is not shortened and a sharp curve is drawn when it comes",
	function()
		local straightTried, tryStraight = createRecorder(0)
		RoadPieceAlternatives.findFirstAccepted(
			RoadPieceBuilder.createStraight(40),
			1,
			tryStraight,
			SeededRandom.new(RANDOM_SEED)
		)
		Runner.expectEqual(#straightTried, 1 + 1 + 1 + 1 + 2 * LAST_RESORT_COUNT)
		expectSamePeak(straightTried[2], RoadPieceBuilder.shorten(straightTried[1]) :: RoadPiece)
		local hairpin: RoadPiece = RoadPieceProfile.create("hairpinPair", RoadPieceBuilder.createTightTurn(1, 40).parts)
		local hairpinTried, tryHairpin = createRecorder(0)
		RoadPieceAlternatives.findFirstAccepted(hairpin, 1, tryHairpin, SeededRandom.new(RANDOM_SEED))
		Runner.expectEqual(#hairpinTried, 1 + 1 + 1 + 1 + 2 * LAST_RESORT_COUNT)
		expectSamePeak(hairpinTried[2], RoadPieceBuilder.flip(hairpin))
		Runner.expectEqual(hairpinTried[3].kind, "sharpCurve")
	end
)

Runner.finish()
