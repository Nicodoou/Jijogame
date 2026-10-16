--!strict
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeMap = require("../../src/world/core/BiomeMap")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local AREA_ORIGIN_X = -300
local AREA_ORIGIN_Z = 1200
local AREA_STUDS = 128
local POINT_COUNT = 400
-- La grilla interpola los parámetros del clima entre nodos y los pesos salen de ahí: con el catálogo de dos fichas puede
-- diferir poco del cálculo exacto, y mucho menos que el ancho de una transición.
local MAX_WEIGHT_DIFFERENCE = 0.08

local function sumWeights(weights: { [string]: number }): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	return total
end

Runner.test("with forest alone the weights are one everywhere, exact or interpolated", function()
	local biomeMap = BiomeMap.new(5, BiomeCatalog.all)
	biomeMap.prepareArea(AREA_ORIGIN_X, AREA_ORIGIN_Z, AREA_STUDS)
	local random = SeededRandom.new(1)
	for _ = 1, POINT_COUNT do
		local x = AREA_ORIGIN_X + random.nextNumber() * AREA_STUDS
		local z = AREA_ORIGIN_Z + random.nextNumber() * AREA_STUDS
		Runner.expectEqual(biomeMap.getWeightsAt(x, z).forest, 1)
		Runner.expectEqual(biomeMap.getWeightsInArea(x, z).forest, 1)
	end
end)

Runner.test("the weights of a catalog with several biomes add up to one", function()
	local biomeMap = BiomeMap.new(5, BiomeTestCatalog.triple)
	biomeMap.prepareArea(AREA_ORIGIN_X, AREA_ORIGIN_Z, AREA_STUDS)
	local random = SeededRandom.new(2)
	for _ = 1, POINT_COUNT do
		local x = AREA_ORIGIN_X + random.nextNumber() * AREA_STUDS
		local z = AREA_ORIGIN_Z + random.nextNumber() * AREA_STUDS
		Runner.expectNear(sumWeights(biomeMap.getWeightsAt(x, z)), 1, 1e-9)
		Runner.expectNear(sumWeights(biomeMap.getWeightsInArea(x, z)), 1, 1e-9)
	end
end)

Runner.test("the interpolated weights stay close to the exact ones", function()
	local biomeMap = BiomeMap.new(9, BiomeTestCatalog.pair)
	biomeMap.prepareArea(AREA_ORIGIN_X, AREA_ORIGIN_Z, AREA_STUDS)
	local random = SeededRandom.new(3)
	local worst = 0
	for _ = 1, POINT_COUNT do
		local x = AREA_ORIGIN_X + random.nextNumber() * AREA_STUDS
		local z = AREA_ORIGIN_Z + random.nextNumber() * AREA_STUDS
		local exact = biomeMap.getWeightsAt(x, z)
		local interpolated = biomeMap.getWeightsInArea(x, z)
		for _, definition in BiomeTestCatalog.pair do
			local difference = math.abs((exact[definition.id] or 0) - (interpolated[definition.id] or 0))
			worst = math.max(worst, difference)
		end
	end
	Runner.expectEqual(worst < MAX_WEIGHT_DIFFERENCE, true)
end)

Runner.test("the same seed gives the same weights and a prepared area does not change the exact ones", function()
	local first = BiomeMap.new(11, BiomeTestCatalog.pair)
	local second = BiomeMap.new(11, BiomeTestCatalog.pair)
	second.prepareArea(0, 0, WorldConfig.CHUNK_SIZE_STUDS)
	for index = 1, 50 do
		local x, z = index * 37.5, -index * 11.25
		Runner.expectEqual(first.getWeightsAt(x, z).lowland, second.getWeightsAt(x, z).lowland)
	end
end)

Runner.test("asking for interpolated weights before preparing an area is an error", function()
	local biomeMap = BiomeMap.new(5, BiomeCatalog.all)
	Runner.expectError(function()
		biomeMap.getWeightsInArea(0, 0)
	end)
end)

Runner.finish()
