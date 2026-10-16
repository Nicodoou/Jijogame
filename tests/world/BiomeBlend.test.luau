--!strict
local BiomeBlend = require("../../src/world/core/BiomeBlend")
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadQuery = require("../../src/world/core/RoadQuery")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local SurfaceClassifier = require("../../src/world/core/SurfaceClassifier")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Weights = BiomeTypes.BiomeWeights

local AREA_STUDS = 6000
local SAMPLE_COUNT = 12000
local SAMPLES_PER_SEED = 1000
local FREQUENCY_TOLERANCE = 0.03
local NEAR_STUDS = 4
local FAR_STUDS = 400
local COHERENCE_SAMPLES = 2000
local TRANSITION_SAMPLES = 2000
-- Dentro de un bioma puro, los vecinos a 4 studs eligen igual en la gran mayoría de los casos.
local MIN_PURE_NEAR_AGREEMENT = 0.85
-- En una transición hay tres campos de ruido y cuatro o más materiales: el piso es más bajo, pero muy por encima del azar.
local MIN_TRANSITION_NEAR_AGREEMENT = 0.6
local MIN_NEAR_OVER_FAR_GAP = 0.35
local PATH_SEED = 777
local GENERATED_SEGMENTS = 4
local FIRST_LOADED_SEGMENT = 1
local ROAD_SEGMENT_FOR_SCAN = 2
local CLASSIFIER_SAMPLES_PER_SEED = 50
local LATERAL_STEPS = { 0.5, 3, 11, 13, 20, 40, 75, 150, 300 }
local SHOULDER_EDGE = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
local MUD_DISTANCE = WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS
local JUST_PAST_MUD_DISTANCE = MUD_DISTANCE + 0.01

local function drawPoint(random: SeededRandom.SeededRandom): (number, number)
	return (random.nextNumber() - 0.5) * AREA_STUDS, (random.nextNumber() - 0.5) * AREA_STUDS
end

-- Frecuencia de cada material que se espera según la regla de pickMaterial, escrita a partir de los pesos de la prueba.
local function expectedMaterialShares(weights: Weights, catalog: { BiomeTypes.BiomeDefinition }): { [string]: number }
	local first, second = 0, 0
	for _, definition in catalog do
		local weight = weights[definition.id] or 0
		if weight > first then
			first, second = weight, first
		elseif weight > second then
			second = weight
		end
	end
	local bridgeShare = WorldConfig.BIOME_BRIDGE_MAX_SHARE * (1 - (first - second))
	local shares: { [string]: number } = {}
	for _, definition in catalog do
		local weight = weights[definition.id] or 0
		shares[definition.materials.transition] = (shares[definition.materials.transition] or 0) + bridgeShare * weight
		for _, share in definition.materials.surface do
			shares[share.material] = (shares[share.material] or 0) + (1 - bridgeShare) * weight * share.proportion
		end
	end
	return shares
end

local function measureMaterialFrequencies(
	weights: Weights,
	catalog: { BiomeTypes.BiomeDefinition }
): { [string]: number }
	local random = SeededRandom.new(11)
	local counts: { [string]: number } = {}
	for index = 1, SAMPLE_COUNT do
		local seed = index // SAMPLES_PER_SEED
		local x, z = drawPoint(random)
		local material = BiomeBlend.pickMaterial(weights, catalog, x, z, seed)
		counts[material] = (counts[material] or 0) + 1
	end
	for material, count in counts do
		counts[material] = count / SAMPLE_COUNT
	end
	return counts
end

local function expectFrequenciesNearExpected(weights: Weights, catalog: { BiomeTypes.BiomeDefinition })
	local expected = expectedMaterialShares(weights, catalog)
	local measured = measureMaterialFrequencies(weights, catalog)
	for material, share in expected do
		Runner.expectNear(measured[material] or 0, share, FREQUENCY_TOLERANCE)
	end
	for material in measured do
		Runner.expectEqual(expected[material] ~= nil, true)
	end
end

local function measureAgreement(
	weights: Weights,
	catalog: { BiomeTypes.BiomeDefinition },
	distanceStuds: number
): number
	local random = SeededRandom.new(5)
	local agreements = 0
	for index = 1, COHERENCE_SAMPLES do
		local seed = index // SAMPLES_PER_SEED
		local x, z = drawPoint(random)
		local here = BiomeBlend.pickMaterial(weights, catalog, x, z, seed)
		if here == BiomeBlend.pickMaterial(weights, catalog, x + distanceStuds, z, seed) then
			agreements += 1
		end
	end
	return agreements / COHERENCE_SAMPLES
end

Runner.test("blendNumber gives the weighted average of what the selector reads from each definition", function()
	local selector = function(definition: BiomeTypes.BiomeDefinition): number
		return definition.terrain.hillAmplitudeScale
	end
	local weights = { lowland = 0.25, highland = 0.75 }
	Runner.expectNear(BiomeBlend.blendNumber(weights, BiomeTestCatalog.pair, selector), 0.25 * 0.5 + 0.75 * 3, 1e-12)
end)

Runner.test("blendNumber with a pure biome gives that biome's value and works for every kind of number", function()
	local amplitude = BiomeBlend.blendNumber({ forest = 1 }, BiomeCatalog.all, function(definition)
		return definition.terrain.hillAmplitudeScale
	end)
	Runner.expectEqual(amplitude, 1)
	local roughness = BiomeBlend.blendNumber({ highland = 1 }, BiomeTestCatalog.triple, function(definition)
		return definition.terrain.hillRoughness
	end)
	Runner.expectEqual(roughness, 2)
end)

Runner.test("blendNumber ignores weights of ids that are not in the catalog and gives 0 with no weights", function()
	local selector = function(_: BiomeTypes.BiomeDefinition): number
		return 10
	end
	Runner.expectEqual(BiomeBlend.blendNumber({}, BiomeTestCatalog.pair, selector), 0)
	Runner.expectEqual(BiomeBlend.blendNumber({ ghost = 1 }, BiomeTestCatalog.pair, selector), 0)
	Runner.expectEqual(BiomeBlend.blendNumber({ lowland = 1, ghost = 5 }, BiomeTestCatalog.pair, selector), 10)
end)

Runner.test("pickMaterial gives the same material for the same weights, position and seed", function()
	local weights = { lowland = 0.5, highland = 0.5 }
	local random = SeededRandom.new(1)
	for _ = 1, 500 do
		local x, z = drawPoint(random)
		local first = BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, x, z, 3)
		Runner.expectEqual(BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, x, z, 3), first)
	end
end)

Runner.test("another seed gives another pattern", function()
	local weights = { lowland = 0.5, highland = 0.5 }
	local random = SeededRandom.new(1)
	local differences = 0
	for _ = 1, 500 do
		local x, z = drawPoint(random)
		if
			BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, x, z, 3)
			~= BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, x, z, 4)
		then
			differences += 1
		end
	end
	Runner.expectEqual(differences > 100, true)
end)

Runner.test("in a pure biome the materials follow the proportions of the definition and never the bridge", function()
	local measured = measureMaterialFrequencies({ forest = 1 }, BiomeCatalog.all)
	Runner.expectNear(measured.Grass or 0, 0.8, FREQUENCY_TOLERANCE)
	Runner.expectNear(measured.LeafyGrass or 0, 0.2, FREQUENCY_TOLERANCE)
	Runner.expectEqual(measured.Ground, nil)
end)

Runner.test("a pure biome of a catalog with several definitions gives only its own materials", function()
	local measured = measureMaterialFrequencies({ highland = 1 }, BiomeTestCatalog.triple)
	for material in measured do
		Runner.expectEqual(material == "Rock" or material == "Slate", true)
	end
end)

Runner.test("the materials respect the proportions of the weights in a 70% and 30% transition", function()
	expectFrequenciesNearExpected({ lowland = 0.7, highland = 0.3 }, BiomeTestCatalog.pair)
end)

Runner.test("the materials respect the proportions of the weights with three definitions", function()
	expectFrequenciesNearExpected({ lowland = 0.5, highland = 0.3, wetland = 0.2 }, BiomeTestCatalog.triple)
end)

Runner.test("in a transition the bridge material shows up, and it is the one of the chosen biome", function()
	local measured = measureMaterialFrequencies({ lowland = 0.5, highland = 0.5 }, BiomeTestCatalog.pair)
	local halfOfBridge = WorldConfig.BIOME_BRIDGE_MAX_SHARE / 2
	Runner.expectNear(measured.Ground or 0, halfOfBridge, FREQUENCY_TOLERANCE)
	Runner.expectNear(measured.Cobblestone or 0, halfOfBridge, FREQUENCY_TOLERANCE)
	Runner.expectEqual(measured.Limestone, nil)
end)

Runner.test("the bridge gets rarer the more one biome dominates", function()
	local even = measureMaterialFrequencies({ lowland = 0.5, highland = 0.5 }, BiomeTestCatalog.pair)
	local lopsided = measureMaterialFrequencies({ lowland = 0.9, highland = 0.1 }, BiomeTestCatalog.pair)
	local evenBridge = (even.Ground or 0) + (even.Cobblestone or 0)
	local lopsidedBridge = (lopsided.Ground or 0) + (lopsided.Cobblestone or 0)
	Runner.expectEqual(lopsidedBridge < evenBridge, true)
end)

Runner.test("weights that do not add up to 1 give the same materials as the same weights normalized", function()
	local random = SeededRandom.new(8)
	for _ = 1, 500 do
		local x, z = drawPoint(random)
		local unnormalized = BiomeBlend.pickMaterial({ lowland = 1, highland = 3 }, BiomeTestCatalog.pair, x, z, 2)
		local normalized = BiomeBlend.pickMaterial({ lowland = 0.25, highland = 0.75 }, BiomeTestCatalog.pair, x, z, 2)
		Runner.expectEqual(unnormalized, normalized)
	end
end)

Runner.test("the order of the weights in the table does not matter, only the order of the catalog", function()
	local random = SeededRandom.new(9)
	for _ = 1, 200 do
		local x, z = drawPoint(random)
		local first = BiomeBlend.pickMaterial({ lowland = 0.4, highland = 0.6 }, BiomeTestCatalog.pair, x, z, 2)
		local second = BiomeBlend.pickMaterial({ highland = 0.6, lowland = 0.4 }, BiomeTestCatalog.pair, x, z, 2)
		Runner.expectEqual(first, second)
	end
end)

Runner.test("neighbors 4 studs apart choose the same material almost always inside a biome", function()
	local near = measureAgreement({ forest = 1 }, BiomeCatalog.all, NEAR_STUDS)
	Runner.expectEqual(near >= MIN_PURE_NEAR_AGREEMENT, true)
end)

Runner.test("the choice comes in patches, not salt and pepper: much more agreement near than far", function()
	for _, weights in { { lowland = 0.9, highland = 0.1 }, { lowland = 0.5, highland = 0.5 } } do
		local near = measureAgreement(weights, BiomeTestCatalog.pair, NEAR_STUDS)
		local far = measureAgreement(weights, BiomeTestCatalog.pair, FAR_STUDS)
		Runner.expectEqual(near >= MIN_TRANSITION_NEAR_AGREEMENT, true)
		Runner.expectEqual(near - far >= MIN_NEAR_OVER_FAR_GAP, true)
	end
end)

Runner.test("materials work with huge and negative positions", function()
	local weights = { lowland = 0.5, highland = 0.5 }
	for _, coordinate in { -(2 ^ 22), -0.5, 0, 2 ^ 22 } do
		local material = BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, coordinate, -coordinate, 1)
		Runner.expectEqual(type(material), "string")
	end
end)

Runner.test("weights without any positive weight for the catalog are an error", function()
	Runner.expectError(function()
		BiomeBlend.pickMaterial({}, BiomeTestCatalog.pair, 0, 0, 1)
	end)
	Runner.expectError(function()
		BiomeBlend.pickMaterial({ ghost = 1 }, BiomeTestCatalog.pair, 0, 0, 1)
	end)
	Runner.expectError(function()
		BiomeBlend.pickOffroadSurface({ lowland = 0 }, BiomeTestCatalog.pair, 0, 0, 1, 20)
	end)
end)

Runner.test("a position that is not a number is an error", function()
	Runner.expectError(function()
		BiomeBlend.pickMaterial({ forest = 1 }, BiomeCatalog.all, 0 / 0, 0, 1)
	end)
end)

local function createWorld()
	local path = RoadPath.new(PATH_SEED)
	PathHelpers.generateSegments(path, GENERATED_SEGMENTS)
	path.releaseSegmentsBefore(FIRST_LOADED_SEGMENT)
	return path, RoadQuery.new(path)
end

Runner.test("pickOffroadSurface with forest gives the same mud and grass as SurfaceClassifier does today", function()
	local mudCount, grassCount = 0, 0
	local path, query = createWorld()
	for _, seed in { 1, -3, 1e12 } do
		local getSurfaceAt = SurfaceClassifier.createGetSurfaceAt(query, seed)
		local samples = (path.getSegment(ROAD_SEGMENT_FOR_SCAN) :: RoadPath.Segment).samples
		for index = 1, CLASSIFIER_SAMPLES_PER_SEED do
			local from, to = samples[index], samples[index + 1]
			local edge = to.position - from.position
			local length = math.sqrt(edge.x * edge.x + edge.z * edge.z)
			local right = vector.create(-edge.z / length, 0, edge.x / length)
			for _, lateral in LATERAL_STEPS do
				for _, side in { -1, 1 } do
					local position = from.position + right * (lateral + SHOULDER_EDGE) * side
					local nearest = query.findNearest(position, nil)
					local expected = getSurfaceAt(position)
					if nearest ~= nil and expected ~= "Road" and expected ~= "Shoulder" then
						local distance = math.abs(nearest.lateralOffset) - SHOULDER_EDGE
						local actual = BiomeBlend.pickOffroadSurface(
							{ forest = 1 },
							BiomeCatalog.all,
							position.x,
							position.z,
							seed,
							distance
						)
						Runner.expectEqual(actual, expected)
						if actual == "Mud" then
							mudCount += 1
						else
							grassCount += 1
						end
					end
				end
			end
		end
	end
	Runner.expectEqual(mudCount > 100, true)
	Runner.expectEqual(grassCount > 100, true)
end)

Runner.test("there is never mud up to the minimum distance from the shoulder, and it can start right after", function()
	local random = SeededRandom.new(3)
	local mudAfter = 0
	for _ = 1, 3000 do
		local x, z = drawPoint(random)
		for _, distance in { -5, 0, 1, MUD_DISTANCE } do
			Runner.expectEqual(
				BiomeBlend.pickOffroadSurface({ forest = 1 }, BiomeCatalog.all, x, z, 1, distance),
				"Grass"
			)
		end
		if
			BiomeBlend.pickOffroadSurface({ forest = 1 }, BiomeCatalog.all, x, z, 1, JUST_PAST_MUD_DISTANCE) == "Mud"
		then
			mudAfter += 1
		end
	end
	Runner.expectEqual(mudAfter > 0, true)
end)

Runner.test("pickOffroadSurface follows the definition: its surface, its patches and its minimum distance", function()
	local random = SeededRandom.new(4)
	local grassPatches = 0
	for _ = 1, 3000 do
		local x, z = drawPoint(random)
		Runner.expectEqual(
			BiomeBlend.pickOffroadSurface({ lowland = 1 }, BiomeTestCatalog.triple, x, z, 1, 100),
			"Grass"
		)
		Runner.expectEqual(BiomeBlend.pickOffroadSurface({ wetland = 1 }, BiomeTestCatalog.triple, x, z, 1, 100), "Mud")
		Runner.expectEqual(BiomeBlend.pickOffroadSurface({ highland = 1 }, BiomeTestCatalog.triple, x, z, 1, 3), "Mud")
		if BiomeBlend.pickOffroadSurface({ highland = 1 }, BiomeTestCatalog.triple, x, z, 1, 50) == "Grass" then
			grassPatches += 1
		end
	end
	Runner.expectEqual(grassPatches > 100 and grassPatches < 2900, true)
end)

Runner.test("in a transition the surface, the bridge and the materials all come from the same chosen biome", function()
	local weights = { lowland = 0.5, highland = 0.5 }
	local random = SeededRandom.new(6)
	local highlandCount = 0
	for index = 1, TRANSITION_SAMPLES do
		local x, z = drawPoint(random)
		local seed = index // SAMPLES_PER_SEED
		local surface = BiomeBlend.pickOffroadSurface(weights, BiomeTestCatalog.pair, x, z, seed, 0)
		local material = BiomeBlend.pickMaterial(weights, BiomeTestCatalog.pair, x, z, seed)
		local isHighlandMaterial = material == "Rock" or material == "Slate" or material == "Cobblestone"
		if surface == "Mud" then
			highlandCount += 1
			Runner.expectEqual(isHighlandMaterial, true)
		else
			Runner.expectEqual(isHighlandMaterial, false)
		end
	end
	Runner.expectNear(highlandCount / TRANSITION_SAMPLES, 0.5, 2 * FREQUENCY_TOLERANCE)
end)

Runner.finish()
