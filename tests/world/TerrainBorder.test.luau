--!strict
-- Borde natural del corredor (WP-12). Para ver la loma sola, el terreno se arma con un bioma sin colinas: lo que se mide es la
-- base (la altura de la ruta, que es la ambiente) más el borde.
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local TerrainHeightField = require("../../src/world/core/TerrainHeightField")
local WorldConfig = require("../../src/world/core/WorldConfig")

local SEGMENTS = 5
local ROAD_LENGTH = SEGMENTS * SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS
local MIDDLE_X = ROAD_LENGTH / 2
local SHOULDER_EDGE = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
local ROAD_HEIGHT = WorldConfig.HILL_BASE_HEIGHT_STUDS
local BORDER_START = WorldConfig.TERRAIN_BORDER_START_STUDS
local BORDER_END = WorldConfig.TERRAIN_BORDER_END_STUDS
local BORDER_HEIGHT = WorldConfig.TERRAIN_BORDER_HEIGHT_STUDS
local FOOT_STUDS = WorldConfig.TERRAIN_BORDER_FOOT_STUDS
local MAX_FOOT_DEGREES = 20
local TOLERANCE = 1e-6
local SCAN_SPACING = 0.1
local AREA_RADIUS = 400
local MIN_BORDER_SLOPE_DEGREES = 45
-- Una pasada a esta distancia de otra queda más cerca de alguna que el inicio del borde.
local CLOSE_GAP = 100
local FAR_GAP = 2 * BORDER_END + 16

local FLAT_WEIGHTS: BiomeTypes.BiomeWeights = { flat = 1 }
local flatBiome: BiomeTypes.BiomeDefinition = {
	id = "flat",
	climate = {
		relief = { min = 0, max = 1 },
		humidity = { min = 0, max = 1 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 0, hillRoughness = 0 },
	materials = {
		surface = { { material = "Grass", proportion = 1 } },
		transition = "Ground",
		deep = "Ground",
	},
	surfaces = { offroad = "Grass", patches = {} },
	decoration = {},
}

local function createRoad(z: number, firstSegmentIndex: number): { RoadPath.Segment }
	return SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		firstSegmentIndex = firstSegmentIndex,
		startX = 0,
		startZ = z,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return ROAD_HEIGHT
		end,
	})
end

-- Un terreno plano con una pasada en z = 0 y, si se pide, otra `gap` studs al costado, a la misma altura.
local function createField(gap: number?): TerrainHeightField.TerrainHeightField
	local blocks = RoadBlocks.new()
	for _, segment in createRoad(0, 0) do
		blocks.addSegment(segment)
	end
	if gap ~= nil then
		for _, segment in createRoad(gap, SEGMENTS) do
			blocks.addSegment(segment)
		end
	end
	local field = TerrainHeightField.new(1, { flatBiome }, blocks)
	field.setArea(MIDDLE_X - AREA_RADIUS, -AREA_RADIUS, MIDDLE_X + AREA_RADIUS, AREA_RADIUS)
	return field
end

local function heightAt(field: TerrainHeightField.TerrainHeightField, z: number): number
	local height = field.sampleColumn(MIDDLE_X, z, FLAT_WEIGHTS)
	return height
end

Runner.test("up to the start of the border the terrain is exactly what it was without a border", function()
	local field = createField(nil)
	for axisDistance = SHOULDER_EDGE + 0.05, BORDER_START, 0.5 do
		Runner.expectNear(heightAt(field, axisDistance), ROAD_HEIGHT, TOLERANCE)
		Runner.expectNear(heightAt(field, -axisDistance), ROAD_HEIGHT, TOLERANCE)
	end
end)

Runner.test("from the start to the end of the border the height rises without ever going down", function()
	local field = createField(nil)
	local previous = heightAt(field, BORDER_START)
	for axisDistance = BORDER_START + SCAN_SPACING, BORDER_END, SCAN_SPACING do
		local height = heightAt(field, axisDistance)
		Runner.expectEqual(height >= previous - TOLERANCE, true)
		previous = height
	end
	Runner.expectNear(heightAt(field, BORDER_END), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
end)

Runner.test("past the end of the border it stays flat, also where no road is within reach", function()
	local field = createField(nil)
	for axisDistance = BORDER_END, AREA_RADIUS, 4 do
		Runner.expectNear(heightAt(field, axisDistance), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
		Runner.expectNear(heightAt(field, -axisDistance), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
	end
	local _, distance = field.sampleColumn(MIDDLE_X, AREA_RADIUS, FLAT_WEIGHTS)
	Runner.expectEqual(distance, math.huge)
end)

Runner.test("the foot is a shallow ditch: no steeper than 20 degrees over its first studs", function()
	local field = createField(nil)
	local previous = heightAt(field, BORDER_START)
	for axisDistance = BORDER_START + SCAN_SPACING, BORDER_START + FOOT_STUDS, SCAN_SPACING do
		local height = heightAt(field, axisDistance)
		Runner.expectEqual(height > previous, true)
		Runner.expectEqual(math.deg(math.atan((height - previous) / SCAN_SPACING)) <= MAX_FOOT_DEGREES, true)
		previous = height
	end
end)

Runner.test("the border is smooth at the crest", function()
	local field = createField(nil)
	-- A 1 stud de la cima la diferencia es de ~0,1 stud: no hay arista.
	local nearCrest = ROAD_HEIGHT + BORDER_HEIGHT - heightAt(field, BORDER_END - 1)
	Runner.expectEqual(nearCrest > 0 and nearCrest < 0.2, true)
end)

Runner.test("the steepest slope of the border is between 45 degrees and the terrain maximum", function()
	local field = createField(nil)
	local steepest = 0
	local previous = heightAt(field, BORDER_START)
	for axisDistance = BORDER_START + SCAN_SPACING, BORDER_END, SCAN_SPACING do
		local height = heightAt(field, axisDistance)
		steepest = math.max(steepest, (height - previous) / SCAN_SPACING)
		previous = height
	end
	local steepestDegrees = math.deg(math.atan(steepest))
	Runner.expectEqual(steepestDegrees >= MIN_BORDER_SLOPE_DEGREES, true)
	Runner.expectEqual(steepestDegrees <= WorldConfig.TERRAIN_MAX_SLOPE_DEGREES, true)
end)

Runner.test("with two passes at 100 studs there is no hill between them", function()
	local field = createField(CLOSE_GAP)
	for z = SHOULDER_EDGE, CLOSE_GAP - SHOULDER_EDGE, 0.5 do
		Runner.expectNear(heightAt(field, z), ROAD_HEIGHT, TOLERANCE)
	end
	-- Afuera de las dos pasadas el borde sí está.
	Runner.expectNear(heightAt(field, -BORDER_END), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
	Runner.expectNear(heightAt(field, CLOSE_GAP + BORDER_END), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
end)

Runner.test("with two passes far apart the land between them rises to the crest, as a valley on each side", function()
	local field = createField(FAR_GAP)
	Runner.expectNear(heightAt(field, FAR_GAP / 2), ROAD_HEIGHT + BORDER_HEIGHT, TOLERANCE)
	Runner.expectNear(heightAt(field, BORDER_START), ROAD_HEIGHT, TOLERANCE)
	Runner.expectNear(heightAt(field, FAR_GAP - BORDER_START), ROAD_HEIGHT, TOLERANCE)
end)

Runner.finish()
