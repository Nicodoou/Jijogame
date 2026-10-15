--!strict
local Runner = require("../Runner")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local WorldConfig = require("../../src/world/core/WorldConfig")

local EXPECTED_WEIGHTS: { [RoadPieceCatalog.PieceKind]: number } = {
	straight = 1,
	gentleCurve = 3,
	sharpCurve = 6,
	sCurve = 4,
	hairpinPair = 6,
	uTurn = 6,
}
local MAX_LOBES = 2
local MIN_STEPS_PER_LOBE = 2
local HAIRPIN_MIN_TURN_DEGREES = 150
local HAIRPIN_MAX_TURN_DEGREES = 180

local function findDefinition(kind: RoadPieceCatalog.PieceKind): RoadPieceCatalog.PieceDefinition
	for _, definition in RoadPieceCatalog.definitions do
		if definition.kind == kind then
			return definition
		end
	end
	error(`missing piece {kind}`)
end

Runner.test("the catalog has the six pieces, each once, with their weights", function()
	local found = 0
	for kind: RoadPieceCatalog.PieceKind, weight: number in EXPECTED_WEIGHTS do
		Runner.expectEqual(findDefinition(kind).weight, weight)
		found += 1
	end
	Runner.expectEqual(#RoadPieceCatalog.definitions, found)
end)

Runner.test("every piece has a positive weight and ordered ranges", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.weight > 0, true)
		Runner.expectEqual(definition.minLengthStuds > 0, true)
		Runner.expectEqual(definition.minLengthStuds <= definition.maxLengthStuds, true)
		Runner.expectEqual(definition.minRadiusStuds <= definition.maxRadiusStuds, true)
	end
end)

Runner.test("no piece keeps a slope of its own: the hills give the height", function()
	for _, definition in RoadPieceCatalog.definitions do
		local fields: { [string]: unknown } = definition :: any
		Runner.expectEqual(fields.minSlopeDegrees, nil)
		Runner.expectEqual(fields.maxSlopeDegrees, nil)
	end
end)

Runner.test("no curve is tighter than the minimum radius", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.minRadiusStuds >= WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
	end
end)

Runner.test("the ramps fit twice inside each lobe", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.rampFraction > 0 and definition.rampFraction <= 0.5, true)
		Runner.expectEqual(definition.lobeCount >= 1 and definition.lobeCount <= MAX_LOBES, true)
	end
end)

Runner.test("every lobe is long enough to hold its ramps", function()
	for _, definition in RoadPieceCatalog.definitions do
		if definition.kind ~= "hairpinPair" then
			local lobeSteps = definition.minLengthStuds / definition.lobeCount / WorldConfig.INTEGRATION_STEP_STUDS
			Runner.expectEqual(lobeSteps >= MIN_STEPS_PER_LOBE, true)
		end
	end
end)

Runner.test("only the hairpin pair and the U turn have a turn, between 150 and 180 degrees", function()
	for _, definition in RoadPieceCatalog.definitions do
		if definition.kind == "hairpinPair" or definition.kind == "uTurn" then
			Runner.expectEqual(definition.minTurnDegrees, HAIRPIN_MIN_TURN_DEGREES)
			Runner.expectEqual(definition.maxTurnDegrees, HAIRPIN_MAX_TURN_DEGREES)
			Runner.expectEqual(definition.minRadiusStuds >= WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
		else
			Runner.expectEqual(definition.minTurnDegrees, nil)
			Runner.expectEqual(definition.maxTurnDegrees, nil)
		end
	end
end)

Runner.test("the hairpin pair has the radius between 60 and 84 and the U turn the one between 60 and 85", function()
	Runner.expectEqual(findDefinition("hairpinPair").maxRadiusStuds, 84)
	Runner.expectEqual(findDefinition("uTurn").maxRadiusStuds, 85)
end)

Runner.test(
	"the simple curves are the gentle, the sharp and the U turn, and the U turn needs the target far to the side",
	function()
		for _, definition in RoadPieceCatalog.definitions do
			local isExpected = definition.kind == "gentleCurve"
				or definition.kind == "sharpCurve"
				or definition.kind == "uTurn"
			Runner.expectEqual(definition.isSimpleCurve, isExpected)
			Runner.expectEqual(definition.minHeadingErrorDegrees ~= nil, definition.kind == "uTurn")
		end
	end
)

Runner.test("only the hairpin pair turns back, and the straights are short", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.turnsBack, definition.kind == "hairpinPair")
	end
	Runner.expectEqual(findDefinition("straight").maxLengthStuds <= 100, true)
end)

Runner.finish()
