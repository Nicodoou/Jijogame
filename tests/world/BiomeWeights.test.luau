--!strict
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local BiomeWeights = require("../../src/world/core/BiomeWeights")
local ClimateField = require("../../src/world/core/ClimateField")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Weights = BiomeTypes.BiomeWeights

local RANDOM_CLIMATES = 10000
local CIRCLE_POINTS = 10000
local SCAN_STEPS = 10000
local EXACT_TOLERANCE = 1e-12
local HUMIDITY_BETWEEN_LOW_BOXES = 0.25
local PURE = 1 - 1e-12

local function climateAt(relief: number, humidity: number, temperature: number): BiomeTypes.ClimateSample
	return { relief = relief, humidity = humidity, temperature = temperature }
end

local function sumOf(weights: Weights): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	return total
end

local function countKeys(weights: Weights): number
	local count = 0
	for _ in weights do
		count += 1
	end
	return count
end

-- Dos cajas que se tocan en relieve = 0,5: la transición entre ellas depende solo de R.
local function createTouchingPair(): { BiomeTypes.BiomeDefinition }
	local left = BiomeTestCatalog.copyDefinition(BiomeTestCatalog.lowland)
	local right = BiomeTestCatalog.copyDefinition(BiomeTestCatalog.highland)
	left.climate.relief = { min = 0, max = 0.5 }
	right.climate.relief = { min = 0.5, max = 1 }
	return { left, right }
end

local function drawClimate(random: SeededRandom.SeededRandom): BiomeTypes.ClimateSample
	return climateAt(random.nextNumber(), random.nextNumber(), random.nextNumber())
end

Runner.test("the weights add up to 1, are positive and have no NaN, for 1, 2 and 3 definitions", function()
	for _, catalog in { BiomeTestCatalog.single, BiomeTestCatalog.pair, BiomeTestCatalog.triple } do
		local random = SeededRandom.new(1)
		for _ = 1, RANDOM_CLIMATES do
			local weights = BiomeWeights.compute(drawClimate(random), catalog)
			Runner.expectNear(sumOf(weights), 1, EXACT_TOLERANCE)
			for _, weight in weights do
				Runner.expectEqual(weight == weight and weight > 0 and weight <= 1, true)
			end
		end
	end
end)

Runner.test("only the ids of the catalog get a weight", function()
	local random = SeededRandom.new(2)
	for _ = 1, 1000 do
		for id in BiomeWeights.compute(drawClimate(random), BiomeTestCatalog.triple) do
			Runner.expectEqual(id == "lowland" or id == "highland" or id == "wetland", true)
		end
	end
end)

Runner.test("inside a box, on its edges and corners, the biome is pure", function()
	local random = SeededRandom.new(3)
	for _, definition in BiomeTestCatalog.triple do
		local box = definition.climate
		for _ = 1, 300 do
			local inside = climateAt(
				box.relief.min + random.nextNumber() * (box.relief.max - box.relief.min),
				box.humidity.min + random.nextNumber() * (box.humidity.max - box.humidity.min),
				box.temperature.min + random.nextNumber() * (box.temperature.max - box.temperature.min)
			)
			local weights = BiomeWeights.compute(inside, BiomeTestCatalog.triple)
			Runner.expectEqual(weights[definition.id], 1)
			Runner.expectEqual(countKeys(weights), 1)
		end
		local corner = climateAt(box.relief.max, box.humidity.min, box.temperature.max)
		Runner.expectEqual(BiomeWeights.compute(corner, BiomeTestCatalog.triple)[definition.id], 1)
	end
end)

Runner.test("beyond the transition radius of every box the nearest biome gets all the weight", function()
	local far = climateAt(0.5, 0.65, 0.5)
	local weights = BiomeWeights.compute(far, BiomeTestCatalog.triple)
	Runner.expectEqual(weights.wetland, 1)
	Runner.expectEqual(countKeys(weights), 1)
end)

Runner.test("when nothing reaches and two boxes tie, the first of the catalog wins", function()
	local tiny = { radius = 0.01, exponent = 2, cutoff = 0.05 }
	local tie = climateAt(0.5, HUMIDITY_BETWEEN_LOW_BOXES, 0.5)
	Runner.expectEqual(BiomeWeights.compute(tie, BiomeTestCatalog.pair, tiny).lowland, 1)
	Runner.expectEqual(
		BiomeWeights.compute(tie, { BiomeTestCatalog.highland, BiomeTestCatalog.lowland }, tiny).highland,
		1
	)
end)

Runner.test("two boxes at the same distance share the weight evenly", function()
	local tie = climateAt(0.5, HUMIDITY_BETWEEN_LOW_BOXES, 0.5)
	local weights = BiomeWeights.compute(tie, BiomeTestCatalog.pair)
	Runner.expectNear(weights.lowland, 0.5, EXACT_TOLERANCE)
	Runner.expectNear(weights.highland, 0.5, EXACT_TOLERANCE)
end)

Runner.test("a point at distance d from a box weighs (1 - d / R) ^ k before normalizing", function()
	local pair = createTouchingPair()
	local settings = { radius = 0.15, exponent = 2, cutoff = 0.05 }
	local weights = BiomeWeights.compute(climateAt(0.5 + 0.075, 0.2, 0.5), pair, settings)
	Runner.expectNear(weights.lowland, 0.25 / 1.25, EXACT_TOLERANCE)
	Runner.expectNear(weights.highland, 1 / 1.25, EXACT_TOLERANCE)
	local linear =
		BiomeWeights.compute(climateAt(0.5 + 0.075, 0.2, 0.5), pair, { radius = 0.15, exponent = 1, cutoff = 0.05 })
	Runner.expectNear(linear.lowland, 0.5 / 1.5, EXACT_TOLERANCE)
end)

Runner.test("the distance to a box counts the three axes together", function()
	local lowBox = BiomeTestCatalog.copyDefinition(BiomeTestCatalog.lowland)
	lowBox.climate = {
		relief = { min = 0, max = 0.1 },
		humidity = { min = 0, max = 0.1 },
		temperature = { min = 0, max = 0.1 },
	}
	local here = BiomeTestCatalog.copyDefinition(BiomeTestCatalog.highland)
	here.climate = {
		relief = { min = 0.16, max = 0.16 },
		humidity = { min = 0.16, max = 0.16 },
		temperature = { min = 0.16, max = 0.16 },
	}
	local settings = { radius = 0.3, exponent = 1, cutoff = 0 }
	-- El punto se sale 0,06 de la primera caja en cada eje: la distancia es 0,06 por la raíz de 3.
	local weights = BiomeWeights.compute(climateAt(0.16, 0.16, 0.16), { lowBox, here }, settings)
	local lowBoxRawWeight = 1 - 0.06 * math.sqrt(3) / settings.radius
	Runner.expectNear(weights.lowland, lowBoxRawWeight / (1 + lowBoxRawWeight), EXACT_TOLERANCE)
	Runner.expectNear(weights.highland, 1 / (1 + lowBoxRawWeight), EXACT_TOLERANCE)
end)

Runner.test("a weight below the cutoff is dropped and the rest is normalized without it", function()
	local pair = createTouchingPair()
	local point = climateAt(0.575, 0.2, 0.5)
	local strict = BiomeWeights.compute(point, pair, { radius = 0.15, exponent = 2, cutoff = 0.3 })
	Runner.expectEqual(strict.lowland, nil)
	Runner.expectEqual(strict.highland, 1)
	local keepsAll = BiomeWeights.compute(point, pair, { radius = 0.15, exponent = 2, cutoff = 0 })
	Runner.expectEqual(keepsAll.lowland ~= nil, true)
	-- Con R = 0,25 y relieve 0,625 la distancia (0,125) es exacta y el peso vale justo 0,25: un peso igual al corte se queda.
	local exact = BiomeWeights.compute(climateAt(0.625, 0.2, 0.5), pair, { radius = 0.25, exponent = 2, cutoff = 0.25 })
	Runner.expectEqual(exact.lowland ~= nil, true)
end)

Runner.test("at exactly the radius the weight is 0 and the biome is left out", function()
	local pair = createTouchingPair()
	local settings = { radius = 0.25, exponent = 2, cutoff = 0 }
	local weights = BiomeWeights.compute(climateAt(0.75, 0.2, 0.5), pair, settings)
	Runner.expectEqual(weights.lowland, nil)
	Runner.expectEqual(weights.highland, 1)
end)

local function measureTransitionWidth(radius: number): number
	local pair = createTouchingPair()
	local settings =
		{ radius = radius, exponent = WorldConfig.BIOME_TRANSITION_EXPONENT, cutoff = WorldConfig.BIOME_WEIGHT_CUTOFF }
	local width = 0
	for step = 0, SCAN_STEPS do
		local weights = BiomeWeights.compute(climateAt(step / SCAN_STEPS, 0.2, 0.5), pair, settings)
		local biggest = math.max(weights.lowland or 0, weights.highland or 0)
		if biggest < PURE then
			width += 1 / SCAN_STEPS
		end
	end
	return width
end

Runner.test("the transition gets wider as R grows, in proportion to R", function()
	local narrow, medium, wide = measureTransitionWidth(0.05), measureTransitionWidth(0.1), measureTransitionWidth(0.2)
	Runner.expectEqual(narrow > 0 and narrow < medium and medium < wide, true)
	Runner.expectNear(medium / narrow, 2, 0.1)
	Runner.expectNear(wide / medium, 2, 0.1)
end)

Runner.test("going from one box to the next, the weight of the first only goes down", function()
	local pair = createTouchingPair()
	local previous = 1
	for step = 0, SCAN_STEPS do
		local weight = BiomeWeights.compute(climateAt(step / SCAN_STEPS, 0.2, 0.5), pair).lowland or 0
		Runner.expectEqual(weight <= previous + EXACT_TOLERANCE, true)
		previous = weight
	end
	Runner.expectEqual(previous, 0)
end)

Runner.test("the order of the catalog does not change the weights", function()
	local random = SeededRandom.new(4)
	local reversed = { BiomeTestCatalog.wetland, BiomeTestCatalog.highland, BiomeTestCatalog.lowland }
	for _ = 1, 2000 do
		local climate = drawClimate(random)
		local forward = BiomeWeights.compute(climate, BiomeTestCatalog.triple)
		local backward = BiomeWeights.compute(climate, reversed)
		for _, definition in BiomeTestCatalog.triple do
			Runner.expectNear(forward[definition.id] or 0, backward[definition.id] or 0, EXACT_TOLERANCE)
		end
	end
end)

Runner.test(
	"with only forest the weight is 1 at 10,000 points of the circle and at the corners of the climate",
	function()
		local field = ClimateField.new(42)
		for index = 0, CIRCLE_POINTS - 1 do
			local angle = 2 * math.pi * index / CIRCLE_POINTS
			local radius = WorldConfig.AREA_RADIUS_STUDS * (index % 7) / 6
			local weights =
				BiomeWeights.compute(field.sample(radius * math.cos(angle), radius * math.sin(angle)), BiomeCatalog.all)
			Runner.expectEqual(weights.forest, 1)
			Runner.expectEqual(countKeys(weights), 1)
		end
		for _, corner in { climateAt(0, 0, 0), climateAt(1, 1, 1), climateAt(0, 1, 0), climateAt(1, 0, 1) } do
			Runner.expectEqual(BiomeWeights.compute(corner, BiomeCatalog.all).forest, 1)
		end
	end
)

Runner.test("an empty catalog gives no weights", function()
	Runner.expectEqual(countKeys(BiomeWeights.compute(climateAt(0.5, 0.5, 0.5), {})), 0)
end)

Runner.test("a climate with NaN or a radius that is not positive is an error", function()
	Runner.expectError(function()
		BiomeWeights.compute(climateAt(0 / 0, 0.5, 0.5), BiomeTestCatalog.pair)
	end)
	Runner.expectError(function()
		BiomeWeights.compute(climateAt(0.5, 0 / 0, 0.5), BiomeTestCatalog.pair)
	end)
	Runner.expectError(function()
		BiomeWeights.compute(climateAt(0.5, 0.5, 0 / 0), BiomeTestCatalog.pair)
	end)
	for _, radius in { 0, -0.1, 0 / 0 } do
		Runner.expectError(function()
			BiomeWeights.compute(
				climateAt(0, 0, 0),
				BiomeTestCatalog.pair,
				{ radius = radius, exponent = 2, cutoff = 0.05 }
			)
		end)
	end
end)

Runner.test(
	"the transition of the game is gradual: neighboring points never jump from one biome to the other",
	function()
		local pair = createTouchingPair()
		local previous = BiomeWeights.compute(climateAt(0, 0.2, 0.5), pair).lowland or 0
		local biggestJump = 0
		for step = 1, SCAN_STEPS do
			local weight = BiomeWeights.compute(climateAt(step / SCAN_STEPS, 0.2, 0.5), pair).lowland or 0
			biggestJump = math.max(biggestJump, math.abs(weight - previous))
			previous = weight
		end
		-- El corte por BIOME_WEIGHT_CUTOFF es el único salto: nunca pasa de ese valor.
		Runner.expectEqual(biggestJump <= WorldConfig.BIOME_WEIGHT_CUTOFF * 2, true)
	end
)

Runner.finish()
