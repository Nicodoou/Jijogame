--!strict
local Runner = require("../Runner")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local WorldConfig = require("../../src/world/core/WorldConfig")

local EXPECTED_KINDS = { "straight", "gentleCurve", "sharpCurve", "sCurve" }
local MAX_LOBES = 2
local MIN_STEPS_PER_LOBE = 2

Runner.test("the catalog has the four pieces of the design", function()
	local found = {}
	for _, definition in RoadPieceCatalog.definitions do
		found[definition.kind] = true
	end
	for _, kind in EXPECTED_KINDS do
		Runner.expectEqual(found[kind], true)
	end
	Runner.expectEqual(#RoadPieceCatalog.definitions, #EXPECTED_KINDS)
end)

Runner.test("every piece has a positive weight and ordered ranges", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.weight > 0, true)
		Runner.expectEqual(definition.minLengthStuds > 0, true)
		Runner.expectEqual(definition.minLengthStuds <= definition.maxLengthStuds, true)
		Runner.expectEqual(definition.minRadiusStuds <= definition.maxRadiusStuds, true)
		Runner.expectEqual(definition.minSlopeDegrees <= definition.maxSlopeDegrees, true)
	end
end)

Runner.test("every piece keeps its slope inside the maximum slope", function()
	for _, definition in RoadPieceCatalog.definitions do
		Runner.expectEqual(definition.minSlopeDegrees >= -WorldConfig.MAX_SLOPE_DEGREES, true)
		Runner.expectEqual(definition.maxSlopeDegrees <= WorldConfig.MAX_SLOPE_DEGREES, true)
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
		local lobeSteps = definition.minLengthStuds / definition.lobeCount / WorldConfig.INTEGRATION_STEP_STUDS
		Runner.expectEqual(lobeSteps >= MIN_STEPS_PER_LOBE, true)
	end
end)

Runner.finish()
