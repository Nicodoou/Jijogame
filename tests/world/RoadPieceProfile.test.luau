--!strict
local Runner = require("../Runner")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")
local WorldConfig = require("../../src/world/core/WorldConfig")

local TOLERANCE = 1e-12
local PEAK = 1 / 80
local LOBE_STEPS = 20
local RAMP_STEPS = 5

local function createPiece(lobeCount: number, peak: number): RoadPieceProfile.RoadPiece
	return {
		kind = "sCurve",
		lobeCount = lobeCount,
		lobeSteps = LOBE_STEPS,
		rampSteps = RAMP_STEPS,
		peakCurvature = peak,
		endSlopeRadians = 0,
	}
end

Runner.test("the total steps are the lobes times the steps of one lobe", function()
	Runner.expectEqual(RoadPieceProfile.getTotalSteps(createPiece(1, PEAK)), LOBE_STEPS)
	Runner.expectEqual(RoadPieceProfile.getTotalSteps(createPiece(2, PEAK)), 2 * LOBE_STEPS)
end)

Runner.test("the curvature is zero at both ends of the piece", function()
	for lobeCount = 1, 2 do
		local piece = createPiece(lobeCount, PEAK)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, 0), 0)
		Runner.expectEqual(RoadPieceProfile.getCurvatureAtStep(piece, RoadPieceProfile.getTotalSteps(piece)), 0)
	end
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

Runner.test("the curvature changes by at most one ramp slope between steps", function()
	local piece = createPiece(2, PEAK)
	for step = 1, RoadPieceProfile.getTotalSteps(piece) do
		local change = math.abs(
			RoadPieceProfile.getCurvatureAtStep(piece, step) - RoadPieceProfile.getCurvatureAtStep(piece, step - 1)
		)
		Runner.expectEqual(change <= PEAK / RAMP_STEPS + TOLERANCE, true)
	end
end)

Runner.test("the heading change of a lobe matches the integral of the curvature", function()
	local piece = createPiece(1, PEAK)
	local integral = 0
	for step = 1, RoadPieceProfile.getTotalSteps(piece) do
		local before = RoadPieceProfile.getCurvatureAtStep(piece, step - 1)
		local after = RoadPieceProfile.getCurvatureAtStep(piece, step)
		integral += (before + after) / 2 * WorldConfig.INTEGRATION_STEP_STUDS
	end
	Runner.expectNear(RoadPieceProfile.getFirstLobeHeadingChange(piece), integral, TOLERANCE)
end)

Runner.test("a right curve and a left curve change the heading in opposite directions", function()
	Runner.expectEqual(RoadPieceProfile.getFirstLobeHeadingChange(createPiece(1, PEAK)) > 0, true)
	Runner.expectEqual(RoadPieceProfile.getFirstLobeHeadingChange(createPiece(1, -PEAK)) < 0, true)
end)

Runner.finish()
