--!strict
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadGuide = require("../../src/world/core/RoadGuide")
local RoadIntegrator = require("../../src/world/core/RoadIntegrator")
local RoadPieceChooser = require("../../src/world/core/RoadPieceChooser")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local GUIDE_SEED = 3
local RANDOM_SEED = 8
local CHOICES = 40

local function createStart(): RoadIntegrator.IntegratorState
	return RoadIntegrator.createState(WorldConfig.START_POSITION, RoadFrame.getStartHeadingRadians())
end

Runner.test("the same guide, random numbers and state give the same choice", function()
	local first = RoadPieceChooser.choose(
		RoadGuide.new(SeededRandom.new(GUIDE_SEED)),
		SeededRandom.new(RANDOM_SEED),
		createStart(),
		1,
		0,
		nil
	)
	local second = RoadPieceChooser.choose(
		RoadGuide.new(SeededRandom.new(GUIDE_SEED)),
		SeededRandom.new(RANDOM_SEED),
		createStart(),
		1,
		0,
		nil
	)
	Runner.expectEqual(first.piece.kind, second.piece.kind)
	Runner.expectEqual(first.piece.totalSteps, second.piece.totalSteps)
	Runner.expectEqual(first.towardSign, second.towardSign)
	Runner.expectEqual(first.guideArcLength, second.guideArcLength)
end)

Runner.test("the choice says which side the guide is on and where the road sits on it", function()
	local guide = RoadGuide.new(SeededRandom.new(GUIDE_SEED))
	local random = SeededRandom.new(RANDOM_SEED)
	for _ = 1, CHOICES do
		local choice = RoadPieceChooser.choose(guide, random, createStart(), 1, 0, "gentleCurve")
		Runner.expectEqual(math.abs(choice.towardSign), 1)
		Runner.expectEqual(choice.piece.totalSteps > 0, true)
		Runner.expectEqual(choice.guideSegment, 1)
		Runner.expectNear(choice.guideArcLength, 0, 1e-6)
	end
end)

Runner.test("the guide is generated ahead of the road before choosing", function()
	local guide = RoadGuide.new(SeededRandom.new(GUIDE_SEED))
	RoadPieceChooser.choose(guide, SeededRandom.new(RANDOM_SEED), createStart(), 1, 0, nil)
	local x, z = guide.getPointAt(WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
	Runner.expectEqual(x == x and z == z, true)
	local start = WorldConfig.START_POSITION
	Runner.expectEqual(x ~= start.x or z ~= start.z, true)
end)

Runner.finish()
