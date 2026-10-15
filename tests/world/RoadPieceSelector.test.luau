--!strict
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local RoadPieceSelector = require("../../src/world/core/RoadPieceSelector")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Steering = RoadPieceSelector.Steering

local DRAWS = 4000
local SIGN_DRAWS = 3000
local DEVIATION = WorldConfig.LOCAL_DEVIATION_MAX_STUDS
local PROBABILITY_TOLERANCE = 0.04

local function createSteering(errorDegrees: number, lateralOffset: number): Steering
	return { headingErrorRadians = math.rad(errorDegrees), lateralOffsetStuds = lateralOffset }
end

local function countKinds(steering: Steering): { [string]: number }
	local random = SeededRandom.new(1)
	local counts: { [string]: number } = {}
	for _ = 1, DRAWS do
		local kind = RoadPieceSelector.pickDefinition(random, steering).kind
		counts[kind] = (counts[kind] or 0) + 1
	end
	return counts
end

local function measureTowardRate(steering: Steering, kind: RoadPieceCatalog.PieceKind): number
	local random = SeededRandom.new(2)
	local definition = RoadPieceSelector.getDefinition(kind)
	local toward = RoadPieceSelector.getTowardSign(steering)
	local towardCount = 0
	for _ = 1, SIGN_DRAWS do
		towardCount += if RoadPieceSelector.pickTurnSign(random, steering, definition) == toward then 1 else 0
	end
	return towardCount / SIGN_DRAWS
end

Runner.test("a definition is found by its kind and an unknown kind is an error", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(RoadPieceSelector.getDefinition(definition.kind), definition)
	end
	Runner.expectError(function()
		RoadPieceSelector.getDefinition("loop" :: any)
	end)
end)

Runner.test("the toward sign follows the side of the heading error, and zero counts as the right", function()
	Runner.expectEqual(RoadPieceSelector.getTowardSign(createSteering(10, 0)), 1)
	Runner.expectEqual(RoadPieceSelector.getTowardSign(createSteering(-10, 0)), -1)
	Runner.expectEqual(RoadPieceSelector.getTowardSign(createSteering(0, 0)), 1)
end)

Runner.test("with the target straight ahead every piece shows up, in proportion to its weight", function()
	local counts = countKinds(createSteering(0, 0))
	local totalWeight = 0
	for _, definition in RoadPieceCatalog.definitions do
		totalWeight += definition.weight
	end
	for _, definition in RoadPieceCatalog.definitions do
		local expected = DRAWS * definition.weight / totalWeight
		Runner.expectNear(counts[definition.kind] or 0, expected, expected * 0.2)
	end
end)

Runner.test("with the target far to the side only the simple curves are drawn", function()
	for _, errorDegrees in { 46, 90, 179, -46, -179 } do
		local counts = countKinds(createSteering(errorDegrees, 0))
		for kind in counts do
			Runner.expectEqual(kind == "gentleCurve" or kind == "sharpCurve", true)
		end
		Runner.expectEqual((counts.gentleCurve or 0) > 0 and (counts.sharpCurve or 0) > 0, true)
	end
end)

Runner.test("at exactly the curves only error all the kinds are still drawn", function()
	local counts = countKinds(createSteering(WorldConfig.SEQUENCER_CURVES_ONLY_ERROR_DEGREES, 0))
	Runner.expectEqual(counts.straight ~= nil and counts.sCurve ~= nil and counts.hairpinPair ~= nil, true)
end)

Runner.test("the hairpin pair is drawn only while the road is close enough to the guide", function()
	local limit = DEVIATION * WorldConfig.SEQUENCER_HAIRPIN_MAX_OFFSET_FRACTION
	Runner.expectEqual(countKinds(createSteering(0, limit - 1)).hairpinPair ~= nil, true)
	Runner.expectEqual(countKinds(createSteering(0, limit)).hairpinPair, nil)
	Runner.expectEqual(countKinds(createSteering(0, -limit - 1)).hairpinPair, nil)
	Runner.expectEqual(countKinds(createSteering(0, DEVIATION)).straight ~= nil, true)
end)

Runner.test("choosing a definition always uses exactly one random number", function()
	for _, steering in { createSteering(0, 0), createSteering(90, 0), createSteering(0, DEVIATION) } do
		local random = SeededRandom.new(3)
		local reference = SeededRandom.new(3)
		RoadPieceSelector.pickDefinition(random, steering)
		reference.nextNumber()
		Runner.expectEqual(random.nextNumber(), reference.nextNumber())
	end
end)

Runner.test("choosing a turn sign always uses exactly one random number, also for the hairpin pair", function()
	for _, kind in { "straight", "gentleCurve", "hairpinPair" } do
		local random = SeededRandom.new(4)
		local reference = SeededRandom.new(4)
		RoadPieceSelector.pickTurnSign(random, createSteering(30, 100), RoadPieceSelector.getDefinition(kind :: any))
		reference.nextNumber()
		Runner.expectEqual(random.nextNumber(), reference.nextNumber())
	end
end)

Runner.test(
	"the chance to turn toward the target is one half when it is straight ahead and grows to 0.95 at 40 degrees",
	function()
		local base = WorldConfig.SEQUENCER_TOWARD_BASE_PROBABILITY
		Runner.expectNear(measureTowardRate(createSteering(0, 0), "gentleCurve"), base, PROBABILITY_TOLERANCE)
		Runner.expectNear(
			measureTowardRate(createSteering(20, 0), "gentleCurve"),
			base + 0.5 * WorldConfig.SEQUENCER_TOWARD_PULL_GAIN,
			PROBABILITY_TOLERANCE
		)
		Runner.expectNear(
			measureTowardRate(createSteering(40, 0), "gentleCurve"),
			base + WorldConfig.SEQUENCER_TOWARD_PULL_GAIN,
			PROBABILITY_TOLERANCE
		)
		Runner.expectNear(
			measureTowardRate(createSteering(-40, 0), "gentleCurve"),
			base + WorldConfig.SEQUENCER_TOWARD_PULL_GAIN,
			PROBABILITY_TOLERANCE
		)
	end
)

Runner.test("beyond 90 degrees the turn is always toward the target", function()
	Runner.expectEqual(measureTowardRate(createSteering(91, 0), "sharpCurve"), 1)
	Runner.expectEqual(measureTowardRate(createSteering(-135, 0), "sharpCurve"), 1)
end)

Runner.test("far from the guide the turn is toward the target at least 95 percent of the time", function()
	local offCenter = DEVIATION * WorldConfig.SEQUENCER_OFF_CENTER_FRACTION + 1
	local rate = measureTowardRate(createSteering(0, offCenter), "gentleCurve")
	Runner.expectEqual(rate >= WorldConfig.SEQUENCER_OFF_CENTER_MIN_PROBABILITY - PROBABILITY_TOLERANCE, true)
	Runner.expectEqual(measureTowardRate(createSteering(0, -offCenter), "gentleCurve") >= 0.9, true)
end)

Runner.test(
	"the hairpin pair starts away from the guide: left when the road is on its right, and right otherwise",
	function()
		local hairpin = RoadPieceSelector.getDefinition("hairpinPair")
		local random = SeededRandom.new(5)
		for _ = 1, 50 do
			Runner.expectEqual(RoadPieceSelector.pickTurnSign(random, createSteering(0, 30), hairpin), -1)
			Runner.expectEqual(RoadPieceSelector.pickTurnSign(random, createSteering(0, -30), hairpin), 1)
			Runner.expectEqual(RoadPieceSelector.pickTurnSign(random, createSteering(0, 0), hairpin), 1)
		end
	end
)

Runner.finish()
