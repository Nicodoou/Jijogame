--!strict
local Runner = require("../Runner")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")

local TOLERANCE = 1e-12
local PEAK = 1 / 80
local LOBE_STEPS = 20
local RAMP_STEPS = 5
local RAMP_FRACTION = 0.25

local function createPart(peak: number, lobeCount: number): RoadPieceProfile.PiecePart
	return {
		peakCurvature = peak,
		lobeSteps = LOBE_STEPS,
		rampSteps = RAMP_STEPS,
		lobeCount = lobeCount,
		rampFraction = RAMP_FRACTION,
	}
end

local function createPiece(lobeCount: number, peak: number): RoadPieceProfile.RoadPiece
	return RoadPieceProfile.create("sCurve", { createPart(peak, lobeCount) })
end

-- Horquilla, recta y horquilla para el otro lado.
local function createHairpinPair(): RoadPieceProfile.RoadPiece
	local gap = createPart(0, 1)
	gap.lobeSteps = 8
	gap.rampSteps = 1
	return RoadPieceProfile.create("hairpinPair", { createPart(PEAK, 1), gap, createPart(-PEAK, 1) })
end

Runner.test("the total steps are the lobes times the steps of one lobe", function()
	Runner.expectEqual(createPiece(1, PEAK).totalSteps, LOBE_STEPS)
	Runner.expectEqual(createPiece(2, PEAK).totalSteps, 2 * LOBE_STEPS)
	Runner.expectEqual(createHairpinPair().totalSteps, 2 * LOBE_STEPS + 8)
end)

Runner.test("the curvature is zero at both ends of the piece", function()
	for lobeCount = 1, 2 do
		local piece = createPiece(lobeCount, PEAK)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, 0), 0)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, piece.totalSteps), 0)
	end
	local hairpin = createHairpinPair()
	Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(hairpin, 0), 0)
	Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(hairpin, hairpin.totalSteps), 0)
end)

Runner.test("the curvature rises linearly, stays at the peak and falls linearly", function()
	local piece = createPiece(1, PEAK)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 1), PEAK / RAMP_STEPS, TOLERANCE)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 5), PEAK, TOLERANCE)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 10), PEAK, TOLERANCE)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 15), PEAK, TOLERANCE)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 19), PEAK / RAMP_STEPS, TOLERANCE)
end)

Runner.test("the second lobe of an S curve turns the other way and passes through zero in the middle", function()
	local piece = createPiece(2, PEAK)
	Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, LOBE_STEPS), 0)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 30), -PEAK, TOLERANCE)
	Runner.expectNear(RoadPieceProfile.getCurvatureAtStep(piece, 10), PEAK, TOLERANCE)
end)

Runner.test("the curvature changes by at most one ramp slope between steps, also across parts", function()
	for _, piece in { createPiece(2, PEAK), createHairpinPair() } do
		for step = 1, piece.totalSteps do
			local change = math.abs(
				RoadPieceProfile.getCurvatureAtStep(piece, step) - RoadPieceProfile.getCurvatureAtStep(piece, step - 1)
			)
			Runner.expectEqual(change <= PEAK / RAMP_STEPS + TOLERANCE, true)
		end
	end
end)

Runner.test(
	"the hairpin pair turns one way, goes straight and turns back with the same total heading change",
	function()
		local piece = createHairpinPair()
		local heading, minimum, maximum = 0, 0, 0
		for step = 1, piece.totalSteps do
			local before = RoadPieceProfile.getCurvatureAtStep(piece, step - 1)
			heading += (before + RoadPieceProfile.getCurvatureAtStep(piece, step)) / 2
			minimum, maximum = math.min(minimum, heading), math.max(maximum, heading)
		end
		Runner.expectNear(heading, 0, TOLERANCE)
		Runner.expectEqual(maximum > 0 and minimum >= 0, true)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, LOBE_STEPS + 4), 0)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, LOBE_STEPS + 8 + 10) < 0, true)
	end
)

Runner.test("a step past the end of the piece has no curvature", function()
	Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(createPiece(1, PEAK), 500), 0)
end)

Runner.test("the steps of a part are its lobes times the steps of a lobe", function()
	Runner.expectEqual(RoadPieceProfile.getPartSteps(createPart(PEAK, 2)), 2 * LOBE_STEPS)
end)

Runner.finish()
