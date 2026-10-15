--!strict
local RoadPieceBuilder = require("../../src/world/core/RoadPieceBuilder")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type RoadPiece = RoadPieceProfile.RoadPiece

local TOLERANCE = 1e-9
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local MAX_CURVATURE = 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS
local DRAWS_PER_KIND = 300
local TURN_ANGLES_DEGREES = { 0.01, 3, 10, 45, 90, 179, 180, 270 }

-- Cambio de rumbo entre el paso `fromStep` y el `toStep` de la pieza (integral trapezoidal de la curvatura).
local function getHeadingChange(piece: RoadPiece, fromStep: number, toStep: number): number
	local change = 0
	for step = fromStep + 1, toStep do
		local before = RoadPieceProfile.getCurvatureAtStep(piece, step - 1)
		change += (before + RoadPieceProfile.getCurvatureAtStep(piece, step)) / 2 * STEP_STUDS
	end
	return change
end

local function getMaxCurvature(piece: RoadPiece): number
	local largest = 0
	for step = 0, piece.totalSteps do
		largest = math.max(largest, math.abs(RoadPieceProfile.getCurvatureAtStep(piece, step)))
	end
	return largest
end

local function drawMany(definition: RoadPieceCatalog.PieceDefinition, seed: number): { RoadPiece }
	local random = SeededRandom.new(seed)
	local pieces = {}
	for index = 1, DRAWS_PER_KIND do
		pieces[index] = RoadPieceBuilder.draw(random, definition)
	end
	return pieces
end

Runner.test(
	"every drawn piece has the kind of its definition, ends with curvature zero and is never tighter than the limit",
	function()
		for _, definition in RoadPieceCatalog.definitions do
			for _, piece in drawMany(definition, 1) do
				Runner.expectEqual(piece.kind, definition.kind)
				Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, 0), 0)
				Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, piece.totalSteps), 0)
				Runner.expectEqual(getMaxCurvature(piece) <= MAX_CURVATURE + TOLERANCE, true)
			end
		end
	end
)

Runner.test("the length of a drawn piece stays inside the range of its definition", function()
	for _, definition in RoadPieceCatalog.definitions do
		if definition.kind ~= "hairpinPair" then
			for _, piece in drawMany(definition, 2) do
				local lengthStuds = piece.totalSteps * STEP_STUDS
				Runner.expectEqual(lengthStuds >= definition.minLengthStuds - STEP_STUDS, true)
				Runner.expectEqual(lengthStuds <= definition.maxLengthStuds + STEP_STUDS, true)
			end
		end
	end
end)

Runner.test("a straight piece has no curvature and the other pieces turn to the right first", function()
	for _, definition in RoadPieceCatalog.definitions do
		for _, piece in drawMany(definition, 3) do
			local firstTurn = piece.parts[1].peakCurvature
			Runner.expectEqual(if definition.kind == "straight" then firstTurn == 0 else firstTurn > 0, true)
		end
	end
end)

Runner.test("an S curve has two lobes and the other curves have one", function()
	for _, definition in RoadPieceCatalog.definitions do
		for _, piece in drawMany(definition, 4) do
			Runner.expectEqual(piece.parts[1].lobeCount, if definition.kind == "sCurve" then 2 else 1)
		end
	end
end)

Runner.test(
	"a hairpin pair turns 120 to 180 degrees each way with a straight bit between, and ends facing as it started",
	function()
		local definition = RoadPieceCatalog.definitions[#RoadPieceCatalog.definitions]
		for _, piece in drawMany(definition, 5) do
			Runner.expectEqual(#piece.parts, 3)
			local firstEnd = RoadPieceProfile.getPartSteps(piece.parts[1])
			local secondStart = firstEnd + RoadPieceProfile.getPartSteps(piece.parts[2])
			local firstTurn = getHeadingChange(piece, 0, firstEnd)
			Runner.expectEqual(firstTurn >= math.rad(120) - TOLERANCE and firstTurn <= math.rad(180) + TOLERANCE, true)
			Runner.expectEqual(piece.parts[2].peakCurvature, 0)
			Runner.expectNear(getHeadingChange(piece, secondStart, piece.totalSteps), -firstTurn, TOLERANCE)
			Runner.expectNear(getHeadingChange(piece, 0, piece.totalSteps), 0, TOLERANCE)
		end
	end
)

Runner.test("no piece is longer than what the backtrack memory of the live road holds", function()
	local longest = 0
	for _, definition in RoadPieceCatalog.definitions do
		for _, piece in drawMany(definition, 6) do
			longest = math.max(longest, piece.totalSteps * STEP_STUDS)
		end
	end
	Runner.expectEqual(WorldConfig.ROAD_BACKTRACK_MAX_PIECES * longest <= WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS, true)
	Runner.expectEqual(longest < WorldConfig.LIVE_NEIGHBOR_ARC_STUDS, true)
end)

Runner.test("the same random stream draws the same pieces", function()
	for _, definition in RoadPieceCatalog.definitions do
		local first, second = drawMany(definition, 7), drawMany(definition, 7)
		for index = 1, DRAWS_PER_KIND do
			Runner.expectEqual(first[index].totalSteps, second[index].totalSteps)
			Runner.expectEqual(first[index].parts[1].peakCurvature, second[index].parts[1].peakCurvature)
		end
	end
end)

Runner.test("flipping a piece turns it the other way and flipping it twice gives the original", function()
	for _, definition in RoadPieceCatalog.definitions do
		for _, piece in drawMany(definition, 8) do
			local flipped = RoadPieceBuilder.flip(piece)
			Runner.expectEqual(flipped.totalSteps, piece.totalSteps)
			for step = 0, piece.totalSteps do
				Runner.expectEqual(
					RoadPieceProfile.getCurvatureAtStep(flipped, step),
					-RoadPieceProfile.getCurvatureAtStep(piece, step)
				)
			end
			local twice = RoadPieceBuilder.flip(flipped)
			Runner.expectEqual(twice.parts[1].peakCurvature, piece.parts[1].peakCurvature)
		end
	end
end)

Runner.test("flipping does not change the piece it is given", function()
	local piece = RoadPieceBuilder.createTightTurn(1, 20)
	RoadPieceBuilder.flip(piece)
	Runner.expectEqual(piece.parts[1].peakCurvature > 0, true)
end)

Runner.test("a shortened piece keeps its curvature, is shorter and still ends with curvature zero", function()
	for _, definition in RoadPieceCatalog.definitions do
		for _, piece in drawMany(definition, 9) do
			local shorter = RoadPieceBuilder.shorten(piece)
			if definition.kind == "hairpinPair" then
				Runner.expectEqual(shorter, nil)
			else
				local shortened = shorter :: RoadPiece
				Runner.expectEqual(shortened.totalSteps < piece.totalSteps, true)
				Runner.expectEqual(shortened.parts[1].peakCurvature, piece.parts[1].peakCurvature)
				Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(shortened, shortened.totalSteps), 0)
				Runner.expectEqual(getMaxCurvature(shortened) <= MAX_CURVATURE + TOLERANCE, true)
			end
		end
	end
end)

Runner.test("shortening never goes below the minimum steps of a lobe, nor below one step for a straight", function()
	local tinyCurve = RoadPieceBuilder.createTightTurn(1, 5)
	local shortenedCurve = RoadPieceBuilder.shorten(tinyCurve) :: RoadPiece
	Runner.expectEqual(shortenedCurve.parts[1].lobeSteps, WorldConfig.MIN_SHORTENED_LOBE_STEPS)
	local shortenedStraight = RoadPieceBuilder.shorten(RoadPieceBuilder.createStraight(1)) :: RoadPiece
	Runner.expectEqual(shortenedStraight.totalSteps, 1)
	local halvedStraight = RoadPieceBuilder.shorten(RoadPieceBuilder.createStraight(40)) :: RoadPiece
	Runner.expectEqual(halvedStraight.totalSteps, 20)
end)

Runner.test("a tight turn has the minimum radius and the ramps of the tight turn fraction", function()
	for _, sign in { 1, -1 } do
		local turn = RoadPieceBuilder.createTightTurn(sign, 60)
		Runner.expectEqual(turn.totalSteps, 60)
		Runner.expectNear(turn.parts[1].peakCurvature, sign * MAX_CURVATURE, TOLERANCE)
		Runner.expectEqual(turn.parts[1].rampSteps, 15)
	end
end)

Runner.test("a turn of at least an angle changes the heading by that angle or a little more, the right way", function()
	for _, degrees in TURN_ANGLES_DEGREES do
		for _, sign in { 1, -1 } do
			local wanted = sign * math.rad(degrees)
			local turn = RoadPieceBuilder.createTurnOfAtLeast(wanted)
			local change = getHeadingChange(turn, 0, turn.totalSteps)
			Runner.expectEqual(math.abs(change) >= math.abs(wanted) - TOLERANCE, true)
			Runner.expectEqual(math.abs(change) <= math.abs(wanted) + STEP_STUDS * MAX_CURVATURE, true)
			Runner.expectEqual(change * sign > 0, true)
			Runner.expectEqual(getMaxCurvature(turn) <= MAX_CURVATURE + TOLERANCE, true)
		end
	end
end)

Runner.test("a straight piece goes straight for the steps asked", function()
	local straight = RoadPieceBuilder.createStraight(WorldConfig.EMERGENCY_STRAIGHT_STEPS)
	Runner.expectEqual(straight.kind, "straight")
	Runner.expectEqual(straight.totalSteps, WorldConfig.EMERGENCY_STRAIGHT_STEPS)
	Runner.expectEqual(getMaxCurvature(straight), 0)
end)

Runner.finish()
