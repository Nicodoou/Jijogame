--!strict
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local PathHelpers = require("./PathHelpers")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local SyntheticRoad = require("./SyntheticRoad")
local TerrainHeightField = require("../../src/world/core/TerrainHeightField")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Weights = BiomeTypes.BiomeWeights

local FOREST: Weights = { forest = 1 }
local SHOULDER_EDGE = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
local MAX_SLOPE = math.tan(math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES))
local SEGMENTS = 5
local ROAD_LENGTH = SEGMENTS * SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS
local MIDDLE_X = ROAD_LENGTH / 2
local FLAT_HEIGHT = WorldConfig.HILL_BASE_HEIGHT_STUDS
local WAVE_STEPS = 80
local WAVE_STUDS = 20
-- Un vector guarda floats de 32 bits: a mil studs del origen la posición tiene errores de unos 0,0001.
local HEIGHT_TOLERANCE = 0.01
-- Las colinas con rugosidad 1 no pasan de la amplitud por (1 + proporción de la octava fina) porque math.noise no pasa de 1.
local HILL_BOUND = WorldConfig.TERRAIN_HILL_AMPLITUDE_STUDS * (1 + WorldConfig.TERRAIN_HILL_FINE_AMPLITUDE_RATIO)
local REAL_SEEDS = { 1, 2, 3, 4 }
local REAL_SEGMENTS = 14

local function createRoad(firstSegmentIndex: number, z: number, heightAt: (number) -> number): { RoadPath.Segment }
	return SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		firstSegmentIndex = firstSegmentIndex,
		startX = 0,
		startZ = z,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = heightAt,
	})
end

local function createField(
	seed: number,
	roads: { { RoadPath.Segment } },
	catalog: { BiomeTypes.BiomeDefinition }?
): (TerrainHeightField.TerrainHeightField, RoadBlocks.RoadBlocks)
	local blocks = RoadBlocks.new()
	for _, road in roads do
		for _, segment in road do
			blocks.addSegment(segment)
		end
	end
	return TerrainHeightField.new(seed, catalog or BiomeCatalog.all, blocks), blocks
end

local function flatHeight(): number
	return FLAT_HEIGHT
end

-- Ondulada pero siempre cerca de la altura ambiente, así la mezcla con ella no distorsiona lo que se mide.
local function waveHeight(step: number): number
	return FLAT_HEIGHT + WAVE_STUDS * math.sin(step / WAVE_STEPS)
end

local function sampleHeight(
	field: TerrainHeightField.TerrainHeightField,
	x: number,
	z: number,
	weights: Weights?
): number
	local height = field.sampleColumn(x, z, weights or FOREST)
	return height
end

local function prepareAround(field: TerrainHeightField.TerrainHeightField, x: number, z: number, radius: number)
	field.setArea(x - radius, z - radius, x + radius, z + radius)
end

Runner.test("the road and the shoulder are flat across, at the height of the axis at that point", function()
	local field = createField(1, { createRoad(0, 0, waveHeight) })
	prepareAround(field, MIDDLE_X, 0, 40)
	for _, x in { MIDDLE_X, MIDDLE_X + 3.7, MIDDLE_X - 21.3 } do
		local axisHeight = sampleHeight(field, x, 0, nil)
		for lateral = -SHOULDER_EDGE, SHOULDER_EDGE, 1 do
			local height, beyondShoulder = field.sampleColumn(x, lateral, FOREST)
			Runner.expectNear(height, axisHeight, HEIGHT_TOLERANCE)
			Runner.expectEqual(beyondShoulder, 0)
		end
	end
end)

Runner.test("the distance beyond the shoulder is measured from the edge of the shoulder", function()
	local field = createField(1, { createRoad(0, 0, flatHeight) })
	prepareAround(field, MIDDLE_X, 0, 100)
	for _, beyond in { 0.5, 1, 10, 50, 120 } do
		local _, distance = field.sampleColumn(MIDDLE_X, SHOULDER_EDGE + beyond, FOREST)
		Runner.expectNear(distance, beyond, 1e-4)
		local _, otherSide = field.sampleColumn(MIDDLE_X, -SHOULDER_EDGE - beyond, FOREST)
		Runner.expectNear(otherSide, beyond, 1e-4)
	end
end)

Runner.test("the hills fade in over the blend width and never pass their bound", function()
	local field = createField(7, { createRoad(0, 0, flatHeight) })
	prepareAround(field, MIDDLE_X, 0, 200)
	local random = SeededRandom.new(2)
	local farthest = 0
	for _ = 1, 600 do
		local x = MIDDLE_X + (random.nextNumber() - 0.5) * 200
		local beyond = random.nextNumber() * 3 * WorldConfig.TERRAIN_BLEND_WIDTH_STUDS
		local height = sampleHeight(field, x, SHOULDER_EDGE + beyond, nil)
		local share = if beyond >= WorldConfig.TERRAIN_BLEND_WIDTH_STUDS
			then 1
			else beyond / WorldConfig.TERRAIN_BLEND_WIDTH_STUDS
		Runner.expectEqual(math.abs(height - FLAT_HEIGHT) <= share * HILL_BOUND + HEIGHT_TOLERANCE, true)
		farthest = math.max(farthest, math.abs(height - FLAT_HEIGHT))
	end
	Runner.expectEqual(farthest > HILL_BOUND / 4, true)
end)

local function measureHillSpread(weights: Weights, catalog: { BiomeTypes.BiomeDefinition }): number
	local field = createField(7, { createRoad(0, 0, flatHeight) }, catalog)
	prepareAround(field, MIDDLE_X, 0, 300)
	local random = SeededRandom.new(3)
	local total = 0
	local count = 800
	for _ = 1, count do
		local x = MIDDLE_X + (random.nextNumber() - 0.5) * 300
		local z = (if random.nextNumber() < 0.5 then -1 else 1) * (80 + random.nextNumber() * 100)
		local deviation = sampleHeight(field, x, z, weights) - FLAT_HEIGHT
		total += deviation * deviation
	end
	return math.sqrt(total / count)
end

Runner.test("the amplitude and the roughness of the hills come from the biome weights", function()
	local forest = measureHillSpread(FOREST, BiomeCatalog.all)
	local lowland = measureHillSpread({ lowland = 1 }, BiomeTestCatalog.pair)
	local highland = measureHillSpread({ highland = 1 }, BiomeTestCatalog.pair)
	local mixed = measureHillSpread({ lowland = 0.5, highland = 0.5 }, BiomeTestCatalog.pair)
	Runner.expectEqual(forest > 1, true)
	Runner.expectEqual(lowland < 0.7 * forest, true)
	Runner.expectEqual(highland > 2.5 * forest, true)
	Runner.expectEqual(mixed > lowland and mixed < highland, true)
end)

Runner.test("with forest alone the hills are the ones of the configuration", function()
	local field = createField(7, { createRoad(0, 0, flatHeight) })
	prepareAround(field, MIDDLE_X, 0, 300)
	local largest = 0
	local random = SeededRandom.new(4)
	for _ = 1, 3000 do
		local x = MIDDLE_X + (random.nextNumber() - 0.5) * 300
		local z = SHOULDER_EDGE + WorldConfig.TERRAIN_BLEND_WIDTH_STUDS + random.nextNumber() * 100
		largest = math.max(largest, math.abs(sampleHeight(field, x, z, nil) - FLAT_HEIGHT))
	end
	Runner.expectEqual(largest <= HILL_BOUND, true)
	Runner.expectEqual(largest > WorldConfig.TERRAIN_HILL_AMPLITUDE_STUDS / 2, true)
end)

Runner.test("neighbor columns never differ more than the maximum slope allows, across and along the road", function()
	local field = createField(11, { createRoad(0, 0, waveHeight) })
	prepareAround(field, MIDDLE_X, 0, 300)
	local spacing = 0.5
	local maximumStep = MAX_SLOPE * spacing
	for _, x in { MIDDLE_X - 50, MIDDLE_X, MIDDLE_X + 77.3 } do
		local previous = sampleHeight(field, x, -250, nil)
		for z = -250 + spacing, 250, spacing do
			local height = sampleHeight(field, x, z, nil)
			Runner.expectEqual(math.abs(height - previous) <= maximumStep, true)
			previous = height
		end
	end
	for _, z in { -90, -30, 30, 90 } do
		local previous = sampleHeight(field, MIDDLE_X - 150, z, nil)
		for x = MIDDLE_X - 150 + spacing, MIDDLE_X + 150, spacing do
			local height = sampleHeight(field, x, z, nil)
			Runner.expectEqual(math.abs(height - previous) <= maximumStep, true)
			previous = height
		end
	end
end)

Runner.test("far from every road the terrain is the ambient height plus the hills", function()
	local field = createField(7, { createRoad(0, 0, flatHeight) })
	field.setArea(MIDDLE_X, 5000, MIDDLE_X + 100, 5100)
	local height, beyondShoulder = field.sampleColumn(MIDDLE_X + 10, 5050, FOREST)
	Runner.expectEqual(beyondShoulder, math.huge)
	Runner.expectEqual(math.abs(height - FLAT_HEIGHT) <= HILL_BOUND, true)
end)

-- Dos caminos paralelos a `gap` studs entre ejes, el segundo `rise` studs más alto.
local function createPair(gap: number, rise: number): TerrainHeightField.TerrainHeightField
	local lower = createRoad(0, 0, flatHeight)
	local upper = createRoad(SEGMENTS, gap, function()
		return FLAT_HEIGHT + rise
	end)
	local field = createField(5, { lower, upper })
	prepareAround(field, MIDDLE_X, gap / 2, 150)
	return field
end

local function scanBetween(field: TerrainHeightField.TerrainHeightField, gap: number): { number }
	local heights: { number } = {}
	local spacing = 0.25
	for z = SHOULDER_EDGE, gap - SHOULDER_EDGE, spacing do
		table.insert(heights, sampleHeight(field, MIDDLE_X, z, nil))
	end
	return heights
end

Runner.test("two passes at 60 studs and different heights meet in a ramp that respects the maximum slope", function()
	local gap = 60
	-- Entre los bordes de las dos banquinas quedan 36 studs; la diferencia de altura se prueba como fracción de ese espacio
	-- (0,98 es el peor caso de 150 semillas con las pasadas a 60 studs).
	local freeStuds = gap - 2 * SHOULDER_EDGE
	for _, ratio in { 0.2, 0.5, 0.8, 0.98 } do
		local rise = ratio * freeStuds
		local field = createPair(gap, rise)
		local heights = scanBetween(field, gap)
		local spacing = 0.25
		for index = 2, #heights do
			Runner.expectEqual(math.abs(heights[index] - heights[index - 1]) <= MAX_SLOPE * spacing, true)
			Runner.expectEqual(heights[index] >= heights[index - 1] - HEIGHT_TOLERANCE, true)
		end
		Runner.expectNear(sampleHeight(field, MIDDLE_X, 0, nil), FLAT_HEIGHT, HEIGHT_TOLERANCE)
		Runner.expectNear(sampleHeight(field, MIDDLE_X, gap, nil), FLAT_HEIGHT + rise, HEIGHT_TOLERANCE)
	end
end)

Runner.test("between two passes the nearest one does not win: the height crosses halfway at the middle", function()
	local gap = 60
	local rise = 24
	local field = createPair(gap, rise)
	local middle = sampleHeight(field, MIDDLE_X, gap / 2, nil)
	Runner.expectNear(middle, FLAT_HEIGHT + rise / 2, rise / 4)
	Runner.expectEqual(sampleHeight(field, MIDDLE_X, gap / 2 - 3, nil) < middle, true)
	Runner.expectEqual(sampleHeight(field, MIDDLE_X, gap / 2 + 3, nil) > middle, true)
end)

Runner.test(
	"where the route leaves no room the bank is steep but continuous and stays between the two roads",
	function()
		local gap = 2 * SHOULDER_EDGE + 6
		local rise = 50
		local field = createPair(gap, rise)
		local heights = scanBetween(field, gap)
		local previous = heights[1]
		for _, height in heights do
			Runner.expectEqual(height >= FLAT_HEIGHT - HEIGHT_TOLERANCE, true)
			Runner.expectEqual(height <= FLAT_HEIGHT + rise + HEIGHT_TOLERANCE, true)
			Runner.expectEqual(height >= previous - HEIGHT_TOLERANCE, true)
			previous = height
		end
		Runner.expectNear(sampleHeight(field, MIDDLE_X, 0, nil), FLAT_HEIGHT, HEIGHT_TOLERANCE)
		Runner.expectNear(sampleHeight(field, MIDDLE_X, gap, nil), FLAT_HEIGHT + rise, HEIGHT_TOLERANCE)
	end
)

Runner.test("a column has the same height whichever area was prepared around it", function()
	local field = createField(9, { createRoad(0, 0, waveHeight) })
	local random = SeededRandom.new(5)
	for _ = 1, 200 do
		local x = MIDDLE_X + (random.nextNumber() - 0.5) * 300
		local z = (random.nextNumber() - 0.5) * 300
		prepareAround(field, x, z, 1)
		local small = sampleHeight(field, x, z, nil)
		field.setArea(x - 400, z - 128, x + 40, z + 250)
		local large = sampleHeight(field, x, z, nil)
		Runner.expectEqual(small, large)
	end
end)

Runner.test("the same seed gives the same terrain and another seed gives other hills", function()
	local first = createField(3, { createRoad(0, 0, flatHeight) })
	local second = createField(3, { createRoad(0, 0, flatHeight) })
	local other = createField(4, { createRoad(0, 0, flatHeight) })
	for _, field in { first, second, other } do
		prepareAround(field, MIDDLE_X, 0, 200)
	end
	local differences = 0
	for index = 1, 100 do
		local x, z = MIDDLE_X + index * 1.7, 60 + index * 0.9
		Runner.expectEqual(sampleHeight(first, x, z, nil), sampleHeight(second, x, z, nil))
		if sampleHeight(first, x, z, nil) ~= sampleHeight(other, x, z, nil) then
			differences += 1
		end
	end
	Runner.expectEqual(differences > 90, true)
end)

Runner.test("the area signature changes when the road around the area changes", function()
	local field, blocks = createField(3, { createRoad(0, 0, flatHeight) })
	prepareAround(field, 100, 0, 20)
	local before = field.getAreaSignature()
	Runner.expectEqual(before, blocks.getSignature(80, -20, 120, 20, field.getInfluenceStuds()))
	blocks.forgetBefore(1)
	prepareAround(field, 100, 0, 20)
	Runner.expectEqual(field.getAreaSignature() ~= before, true)
	Runner.expectEqual(field.getInfluenceStuds() > SHOULDER_EDGE, true)
end)

Runner.test("on real routes the road is flat across and the terrain is continuous", function()
	local random = SeededRandom.new(6)
	local columns = 0
	for _, seed in REAL_SEEDS do
		local path = RoadPath.new(seed)
		local segments = PathHelpers.generateSegments(path, REAL_SEGMENTS)
		local field = createField(seed, { segments })
		for _ = 1, 40 do
			local sample = segments[random.nextInteger(2, REAL_SEGMENTS - 1)].samples[random.nextInteger(1, 129)]
			local x, z = sample.position.x, sample.position.z
			prepareAround(field, x, z, 60)
			local axisHeight = sampleHeight(field, x, z, nil)
			Runner.expectNear(axisHeight, sample.position.y, 0.5)
			local side = vector.create(-math.sin(sample.heading), 0, math.cos(sample.heading))
			for _, lateral in { -SHOULDER_EDGE + 0.5, 0, SHOULDER_EDGE - 0.5 } do
				local height, beyond = field.sampleColumn(x + side.x * lateral, z + side.z * lateral, FOREST)
				Runner.expectEqual(beyond, 0)
				Runner.expectNear(height, sample.position.y, 0.6)
			end
			local here = sampleHeight(field, x + side.x * 40, z + side.z * 40, nil)
			local next = sampleHeight(field, x + side.x * 44, z + side.z * 44, nil)
			Runner.expectEqual(math.abs(next - here) <= MAX_SLOPE * 4, true)
			columns += 1
		end
	end
	Runner.expectEqual(columns, #REAL_SEEDS * 40)
end)

Runner.finish()
