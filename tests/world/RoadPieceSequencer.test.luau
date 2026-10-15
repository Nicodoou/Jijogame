--!strict
local Runner = require("../Runner")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")
local RoadPieceSequencer = require("../../src/world/core/RoadPieceSequencer")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEED_COUNT = 200
local PIECES_PER_SEED = 60
local MAX_DEVIATION_RADIANS = math.rad(WorldConfig.MAX_HEADING_DEVIATION_DEGREES)
local MAX_CURVATURE = 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS
local FORCED_DRIFT_STUDS = WorldConfig.MAX_LATERAL_DRIFT_STUDS * WorldConfig.STEERING_FORCED_DRIFT_FRACTION
local TOLERANCE = 1e-9
-- Se sortea el contexto sobre todo el rango permitido, incluidos los extremos.
local EXTREME_FRACTIONS = { -1, -0.999, -0.5, 0, 0.5, 0.999, 1 }

local function chooseWithContext(random: SeededRandom.SeededRandom, headingDeviation: number, lateralOffset: number)
	return RoadPieceSequencer.chooseNextPiece(random, {
		headingDeviationRadians = headingDeviation,
		lateralOffsetStuds = lateralOffset,
	})
end

local function getWorstDeviation(piece: RoadPieceProfile.RoadPiece, headingDeviation: number): number
	return math.max(
		math.abs(headingDeviation),
		math.abs(headingDeviation + RoadPieceProfile.getFirstLobeHeadingChange(piece))
	)
end

Runner.test("a piece never exceeds the curvature limit nor leaves the heading corridor", function()
	for seed = 1, SEED_COUNT do
		local random = SeededRandom.new(seed)
		for _ = 1, PIECES_PER_SEED do
			local headingDeviation = (random.nextNumber() * 2 - 1) * MAX_DEVIATION_RADIANS
			local lateralOffset = (random.nextNumber() * 2 - 1) * WorldConfig.MAX_LATERAL_DRIFT_STUDS
			local piece = chooseWithContext(random, headingDeviation, lateralOffset)
			Runner.expectEqual(math.abs(piece.peakCurvature) <= MAX_CURVATURE + TOLERANCE, true)
			Runner.expectEqual(getWorstDeviation(piece, headingDeviation) <= MAX_DEVIATION_RADIANS, true)
			Runner.expectEqual(math.abs(piece.endSlopeRadians) <= math.rad(WorldConfig.MAX_SLOPE_DEGREES), true)
		end
	end
end)

Runner.test("a piece holds the corridor at the extremes of heading and drift", function()
	for _, headingFraction in EXTREME_FRACTIONS do
		for _, lateralFraction in EXTREME_FRACTIONS do
			local random = SeededRandom.new(1)
			for _ = 1, PIECES_PER_SEED do
				local headingDeviation = headingFraction * MAX_DEVIATION_RADIANS
				local lateralOffset = lateralFraction * WorldConfig.MAX_LATERAL_DRIFT_STUDS
				local piece = chooseWithContext(random, headingDeviation, lateralOffset)
				Runner.expectEqual(getWorstDeviation(piece, headingDeviation) <= MAX_DEVIATION_RADIANS, true)
			end
		end
	end
end)

Runner.test("beyond the forced drift the piece is a curve that turns toward the mean", function()
	for _, side in { -1, 1 } do
		for seed = 1, SEED_COUNT do
			local random = SeededRandom.new(seed)
			local piece = chooseWithContext(random, 0, side * (FORCED_DRIFT_STUDS + 1))
			Runner.expectEqual(piece.lobeCount, 1)
			Runner.expectEqual(piece.peakCurvature * side < 0, true)
		end
	end
end)

Runner.test("with the road at the drift limit and heading away, the piece turns back as sharp as allowed", function()
	local random = SeededRandom.new(5)
	local headingDeviation = MAX_DEVIATION_RADIANS * 0.9
	local piece = chooseWithContext(random, headingDeviation, WorldConfig.MAX_LATERAL_DRIFT_STUDS - 10)
	Runner.expectEqual(piece.lobeCount, 1)
	Runner.expectEqual(piece.peakCurvature < 0, true)
	Runner.expectEqual(getWorstDeviation(piece, headingDeviation) <= MAX_DEVIATION_RADIANS, true)
end)

Runner.test("near the mean drift the sense of the curve follows the heading error", function()
	local rightTurns = 0
	local totalTurns = 0
	for seed = 1, SEED_COUNT do
		local piece = chooseWithContext(SeededRandom.new(seed), -MAX_DEVIATION_RADIANS * 0.8, 0)
		if piece.peakCurvature ~= 0 then
			totalTurns += 1
			rightTurns += if piece.peakCurvature > 0 then 1 else 0
		end
	end
	Runner.expectEqual(rightTurns > totalTurns * 0.7, true)
end)

Runner.test("with a centered road both senses are drawn", function()
	local rightTurns = 0
	local leftTurns = 0
	for seed = 1, SEED_COUNT do
		local piece = chooseWithContext(SeededRandom.new(seed), 0, 0)
		rightTurns += if piece.peakCurvature > 0 then 1 else 0
		leftTurns += if piece.peakCurvature < 0 then 1 else 0
	end
	Runner.expectEqual(rightTurns > 0 and leftTurns > 0, true)
end)

Runner.test("all four kinds of piece show up over many draws", function()
	local random = SeededRandom.new(77)
	local seen = {}
	for _ = 1, 400 do
		seen[chooseWithContext(random, 0, 0).kind] = true
	end
	for _, kind in { "straight", "gentleCurve", "sharpCurve", "sCurve" } do
		Runner.expectEqual(seen[kind], true)
	end
end)

Runner.test("the same random state and context give the same piece", function()
	local first = chooseWithContext(SeededRandom.new(9), 0.2, 100)
	local second = chooseWithContext(SeededRandom.new(9), 0.2, 100)
	Runner.expectEqual(first.kind, second.kind)
	Runner.expectEqual(first.lobeSteps, second.lobeSteps)
	Runner.expectEqual(first.peakCurvature, second.peakCurvature)
	Runner.expectEqual(first.endSlopeRadians, second.endSlopeRadians)
end)

Runner.test("a straight piece has no curvature", function()
	local random = SeededRandom.new(3)
	local foundStraight = false
	for _ = 1, 100 do
		local piece = chooseWithContext(random, 0, 0)
		if piece.kind == "straight" then
			foundStraight = true
			Runner.expectEqual(piece.peakCurvature, 0)
		end
	end
	Runner.expectEqual(foundStraight, true)
end)

Runner.finish()
