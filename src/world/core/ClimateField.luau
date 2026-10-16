--!strict
-- Campo de clima: relieve, humedad y temperatura en cada punto del mundo, como cuantiles u en [0, 1].
-- Cada mapa suma varias octavas de math.noise (z propio no entero, entrada envuelta con % 256 y desplazamientos sorteados
-- con la semilla). La suma cruda se convierte a u con una tabla de cuantiles medida, así u queda casi uniforme.

local BiomeTypes = require("./BiomeTypes")
local ClimateGrid = require("./ClimateGrid")
local QuantileMap = require("./QuantileMap")
local QuantileTables = require("./QuantileTables")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

export type ClimateSample = BiomeTypes.ClimateSample

export type ClimateField = {
	-- Clima normalizado (u) de una posición.
	sample: (x: number, z: number) -> ClimateSample,
	-- Sumas de octavas sin normalizar. Solo las usa la herramienta que genera QuantileTables.
	sampleRaw: (x: number, z: number) -> ClimateSample,
	-- Grilla de nodos cada `stepStuds` que cubre el cuadrado [origen, origen + sizeStuds] para interpolar los parámetros.
	sampleGrid: (originX: number, originZ: number, sizeStuds: number, stepStuds: number) -> ClimateGrid.ClimateGrid,
}

-- Período de math.noise: la entrada se envuelve para no perder precisión con coordenadas grandes.
local NOISE_PERIOD = 256
local HALF = 0.5

type NoiseOctave = { inverseWavelengthPerStud: number, amplitude: number, offsetX: number, offsetZ: number }

-- Octavas de un mapa, con amplitudes normalizadas para que la suma crudo quede en el rango de math.noise.
local function createOctaves(random: SeededRandom.SeededRandom, wavelengthStuds: number): { NoiseOctave }
	local octaves: { NoiseOctave } = {}
	local amplitudeTotal = 0
	for octave = 1, WorldConfig.CLIMATE_OCTAVES do
		local amplitude = WorldConfig.CLIMATE_OCTAVE_AMPLITUDE_FACTOR ^ (octave - 1)
		local wavelength = wavelengthStuds * WorldConfig.CLIMATE_OCTAVE_WAVELENGTH_FACTOR ^ (octave - 1)
		amplitudeTotal += amplitude
		octaves[octave] = {
			inverseWavelengthPerStud = 1 / wavelength,
			amplitude = amplitude,
			-- Un desplazamiento entero pondría las muestras sobre la grilla del ruido, donde vale siempre 0.
			offsetX = math.floor(random.nextNumber() * WorldConfig.CLIMATE_NOISE_OFFSET_RANGE) + HALF,
			offsetZ = math.floor(random.nextNumber() * WorldConfig.CLIMATE_NOISE_OFFSET_RANGE) + HALF,
		}
	end
	for _, octave in octaves do
		octave.amplitude /= amplitudeTotal
	end
	return octaves
end

local function createRawMap(
	random: SeededRandom.SeededRandom,
	wavelengthStuds: number,
	noiseZ: number
): (number, number) -> number
	local octaves = createOctaves(random, wavelengthStuds)
	return function(x: number, z: number): number
		local sum = 0
		for _, octave in octaves do
			local noiseX = (x * octave.inverseWavelengthPerStud + octave.offsetX) % NOISE_PERIOD
			local noiseY = (z * octave.inverseWavelengthPerStud + octave.offsetZ) % NOISE_PERIOD
			sum += octave.amplitude * math.noise(noiseX, noiseY, noiseZ)
		end
		return sum
	end
end

local ClimateField = {}

function ClimateField.new(seed: number): ClimateField
	local random = SeededRandom.new(seed)
	local reliefMap =
		createRawMap(random, WorldConfig.CLIMATE_RELIEF_WAVELENGTH_STUDS, WorldConfig.CLIMATE_RELIEF_NOISE_Z)
	local humidityMap =
		createRawMap(random, WorldConfig.CLIMATE_HUMIDITY_WAVELENGTH_STUDS, WorldConfig.CLIMATE_HUMIDITY_NOISE_Z)
	local temperatureMap =
		createRawMap(random, WorldConfig.CLIMATE_TEMPERATURE_WAVELENGTH_STUDS, WorldConfig.CLIMATE_TEMPERATURE_NOISE_Z)

	local function sampleRaw(x: number, z: number): ClimateSample
		local relief = reliefMap(x, z)
		return {
			relief = relief,
			humidity = humidityMap(x, z),
			temperature = temperatureMap(x, z) - WorldConfig.CLIMATE_TEMPERATURE_RELIEF_FACTOR * relief,
		}
	end

	local function sample(x: number, z: number): ClimateSample
		local raw = sampleRaw(x, z)
		return {
			relief = QuantileMap.toUnit(raw.relief, QuantileTables.RELIEF),
			humidity = QuantileMap.toUnit(raw.humidity, QuantileTables.HUMIDITY),
			temperature = QuantileMap.toUnit(raw.temperature, QuantileTables.TEMPERATURE),
		}
	end

	local function sampleGrid(
		originX: number,
		originZ: number,
		sizeStuds: number,
		stepStuds: number
	): ClimateGrid.ClimateGrid
		if not (sizeStuds > 0 and stepStuds > 0 and sizeStuds < math.huge) then
			error("the grid needs a positive finite size and step", 2)
		end
		local nodeCount = math.ceil(sizeStuds / stepStuds) + 1
		local samples: { ClimateSample } = table.create(nodeCount * nodeCount)
		for row = 0, nodeCount - 1 do
			for column = 0, nodeCount - 1 do
				samples[row * nodeCount + column + 1] = sample(originX + column * stepStuds, originZ + row * stepStuds)
			end
		end
		return ClimateGrid.new(originX, originZ, stepStuds, nodeCount, nodeCount, samples)
	end

	return { sample = sample, sampleRaw = sampleRaw, sampleGrid = sampleGrid }
end

return ClimateField
