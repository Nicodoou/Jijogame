--!strict
-- Largada plana y recta (WP-12): los primeros START_FLAT_STUDS son una recta sin pendiente a la altura de START_POSITION, y
-- después las lomas entran de a poco.
local HillProfile = require("../../src/world/core/HillProfile")
local PathHelpers = require("./PathHelpers")
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local RoadPieceSequencer = require("../../src/world/core/RoadPieceSequencer")
local Runner = require("../Runner")
local SpawnPoint = require("../../src/world/core/SpawnPoint")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEED_COUNT = 40
local STRAIGHT_KIND: RoadPieceCatalog.PieceKind = "straight"
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local START = WorldConfig.START_POSITION
local FLAT_STUDS = WorldConfig.START_FLAT_STUDS
local FADE_STUDS = WorldConfig.START_HILL_FADE_STUDS
local MAX_SLOPE_CHANGE = math.rad(WorldConfig.HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP)
local MAX_SLOPE = math.rad(WorldConfig.MAX_SLOPE_DEGREES)
local TOLERANCE = 1e-9
local SEGMENTS_AFTER_START = 8
-- Ventana temprana (la mitad del desvanecimiento) y ventana tardía (con las lomas completas) para comparar su altura.
local EARLY_END_STUDS = FLAT_STUDS + FADE_STUDS / 2
local LATE_START_STUDS = FLAT_STUDS + 4 * FADE_STUDS
local LATE_END_STUDS = LATE_START_STUDS + 3 * FADE_STUDS
local EARLY_TO_LATE_MAXIMUM_RATIO = 0.25

local function generateSamples(seed: number): { RoadPath.RoadSample }
	local samples = {}
	for _, segment in PathHelpers.generateSegments(RoadPath.new(seed), SEGMENTS_AFTER_START) do
		for offset, sample in segment.samples do
			if offset > 1 or segment.index == 0 then
				table.insert(samples, sample)
			end
		end
	end
	return samples
end

Runner.test("the first START_FLAT_STUDS are straight, flat and at the start height on every seed", function()
	for seed = 1, SEED_COUNT do
		local checked = 0
		for _, sample in generateSamples(seed) do
			if sample.arcLength <= FLAT_STUDS then
				checked += 1
				Runner.expectEqual(sample.heading, RoadFrame.getStartHeadingRadians())
				Runner.expectEqual(sample.curvature, 0)
				Runner.expectEqual(sample.slope, 0)
				Runner.expectEqual(sample.position.y, START.y)
				Runner.expectNear(sample.position.x, START.x + sample.arcLength, TOLERANCE)
				Runner.expectEqual(sample.position.z, START.z)
			end
		end
		Runner.expectEqual(checked, FLAT_STUDS / STEP_STUDS + 1)
	end
end)

Runner.test("the car spawns on the flat start: level and facing along the start heading", function()
	for seed = 1, SEED_COUNT do
		local spawn = SpawnPoint.compute(seed)
		Runner.expectEqual(spawn.position.y, START.y)
		Runner.expectEqual(spawn.direction.y, 0)
		Runner.expectNear(spawn.direction.x, math.cos(RoadFrame.getStartHeadingRadians()), TOLERANCE)
	end
end)

Runner.test("after the flat start the slope changes by at most the step limit and stays under the maximum", function()
	for seed = 1, SEED_COUNT do
		local previous: RoadPath.RoadSample? = nil
		for _, sample in generateSamples(seed) do
			if previous ~= nil then
				Runner.expectEqual(math.abs(sample.slope - previous.slope) <= MAX_SLOPE_CHANGE + TOLERANCE, true)
			end
			Runner.expectEqual(math.abs(sample.slope) <= MAX_SLOPE + TOLERANCE, true)
			previous = sample
		end
	end
end)

-- Cuánto se aparta la ruta de la altura de salida en un tramo de arcLength.
local function getLargestDeviation(samples: { RoadPath.RoadSample }, fromStuds: number, toStuds: number): number
	local largest = 0
	for _, sample in samples do
		if sample.arcLength >= fromStuds and sample.arcLength <= toStuds then
			largest = math.max(largest, math.abs(sample.position.y - START.y))
		end
	end
	return largest
end

Runner.test("the hills come in gradually: the early road is much flatter than the road with full hills", function()
	local early, late = 0, 0
	for seed = 1, SEED_COUNT do
		local samples = generateSamples(seed)
		early += getLargestDeviation(samples, FLAT_STUDS, EARLY_END_STUDS)
		late += getLargestDeviation(samples, LATE_START_STUDS, LATE_END_STUDS)
	end
	Runner.expectEqual(late > 0, true)
	Runner.expectEqual(early < EARLY_TO_LATE_MAXIMUM_RATIO * late, true)
end)

Runner.test("the first piece is the whole straight and the next one is not another straight", function()
	for seed = 1, SEED_COUNT do
		local sequencer = RoadPieceSequencer.new(seed)
		local first = sequencer.generateNextPiece()
		Runner.expectEqual(#first.samples * STEP_STUDS, FLAT_STUDS)
		Runner.expectEqual(first.retractedAfterSampleNumber, 0)
		Runner.expectEqual(sequencer.getStatistics().pieceCountByKind[STRAIGHT_KIND], 1)
		sequencer.generateNextPiece()
		Runner.expectEqual(sequencer.getStatistics().pieceCountByKind[STRAIGHT_KIND], 1)
	end
end)

Runner.test("the hill profile aims at the base height inside the flat start whatever the seed", function()
	for seed = 1, SEED_COUNT do
		local hill = HillProfile.new(seed)
		for arcLength = 0, FLAT_STUDS, STEP_STUDS do
			Runner.expectEqual(hill.nextSlope(START.y, 0, arcLength), 0)
		end
	end
end)

Runner.test("the flat start and its fade come from the settings", function()
	local settings = table.clone(HillProfile.defaultSettings)
	settings.startFlatStuds = 40
	settings.startFadeStuds = 20
	local hill = HillProfile.new(3, settings)
	local height, slope = START.y, 0
	local deviationAtFlatEnd = 0
	for step = 0, 200 do
		local arcLength = step * STEP_STUDS
		slope = hill.nextSlope(height, slope, arcLength)
		height += STEP_STUDS * math.tan(slope)
		if arcLength <= settings.startFlatStuds then
			deviationAtFlatEnd = math.max(deviationAtFlatEnd, math.abs(height - START.y))
		end
	end
	Runner.expectEqual(deviationAtFlatEnd, 0)
	Runner.expectEqual(math.abs(height - START.y) > 1, true)
end)

Runner.finish()
