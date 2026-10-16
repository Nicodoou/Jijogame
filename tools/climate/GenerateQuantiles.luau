--!strict
-- Herramienta descartable (no es parte del juego): vuelve a generar src/world/core/QuantileTables.luau.
-- Mide la distribución de los mapas crudos de ClimateField y del ruido 2D de los manchones sobre muchas semillas y
-- posiciones, y imprime el módulo entero. Desde la raíz del repo:
--   luau tools/climate/GenerateQuantiles.luau > .cache/QuantileTables.luau
--   cp .cache/QuantileTables.luau src/world/core/QuantileTables.luau && stylua src/world/core/QuantileTables.luau
-- (No se redirige directo al archivo: el shell lo vaciaría antes de que ClimateField lo pueda cargar.)

local ClimateField = require("../../src/world/core/ClimateField")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local POINT_COUNT = 65
local SEED_COUNT = 500
local POINTS_PER_SEED = 400
local FIRST_SEED = 1
local POSITION_STREAM_SEED = 424242
local NOISE_PERIOD = 256
local PATCH_SAMPLE_COUNT = SEED_COUNT * POINTS_PER_SEED
local VALUE_FORMAT = "%.6f"

-- Posición uniforme dentro del círculo del área de juego.
local function drawPosition(random: SeededRandom.SeededRandom): (number, number)
	local radius = WorldConfig.AREA_RADIUS_STUDS * math.sqrt(random.nextNumber())
	local angle = 2 * math.pi * random.nextNumber()
	return radius * math.cos(angle), radius * math.sin(angle)
end

local function computeQuantiles(values: { number }): { number }
	table.sort(values)
	local quantiles = table.create(POINT_COUNT)
	for index = 1, POINT_COUNT do
		local position = (index - 1) / (POINT_COUNT - 1) * (#values - 1) + 1
		local below = math.floor(position)
		local above = math.min(below + 1, #values)
		quantiles[index] = values[below] + (values[above] - values[below]) * (position - below)
	end
	return quantiles
end

local function formatTable(name: string, quantiles: { number }): string
	local lines = { `\t{name} = table.freeze(\{` }
	for _, value in quantiles do
		table.insert(lines, `\t\t{string.format(VALUE_FORMAT, value)},`)
	end
	table.insert(lines, "\t}),")
	return table.concat(lines, "\n")
end

local function measureClimate(): ({ number }, { number }, { number })
	local positionRandom = SeededRandom.new(POSITION_STREAM_SEED)
	local relief, humidity, temperature = {}, {}, {}
	for seed = FIRST_SEED, FIRST_SEED + SEED_COUNT - 1 do
		local field = ClimateField.new(seed)
		for _ = 1, POINTS_PER_SEED do
			local x, z = drawPosition(positionRandom)
			local raw = field.sampleRaw(x, z)
			table.insert(relief, raw.relief)
			table.insert(humidity, raw.humidity)
			table.insert(temperature, raw.temperature)
		end
	end
	return relief, humidity, temperature
end

-- El ruido 2D de un manchón es estacionario: alcanza con medirlo en puntos al azar de un período.
local function measurePatchNoise(): { number }
	local random = SeededRandom.new(POSITION_STREAM_SEED + 1)
	local values = {}
	for _ = 1, PATCH_SAMPLE_COUNT do
		table.insert(values, math.noise(random.nextNumber() * NOISE_PERIOD, random.nextNumber() * NOISE_PERIOD))
	end
	return values
end

local relief, humidity, temperature = measureClimate()
print("--!strict")
print(`-- GENERADO por tools/climate/GenerateQuantiles.luau: no se edita a mano.`)
print(
	`-- {POINT_COUNT} percentiles (de 0 a 100% a pasos iguales) medidos sobre {SEED_COUNT} semillas ({FIRST_SEED} a {FIRST_SEED + SEED_COUNT - 1}) con`
)
print(
	`-- {POINTS_PER_SEED} posiciones al azar dentro del área por semilla. RELIEF, HUMIDITY y TEMPERATURE son las sumas`
)
print("-- crudas de ClimateField.sampleRaw; PATCH es math.noise 2D para los manchones de BiomeBlend.")
print("-- Si cambia algún CLIMATE_* de WorldConfig hay que volver a generarlo.")
print("")
print("return table.freeze({")
print(formatTable("RELIEF", computeQuantiles(relief)))
print(formatTable("HUMIDITY", computeQuantiles(humidity)))
print(formatTable("TEMPERATURE", computeQuantiles(temperature)))
print(formatTable("PATCH", computeQuantiles(measurePatchNoise())))
print("})")
