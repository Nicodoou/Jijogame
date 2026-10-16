--!strict
-- Colinas del terreno: dos octavas de math.noise, relativas a cero (la altura de la ruta se suma afuera). La amplitud y la
-- rugosidad de los biomas escalan la octava gruesa y la fina.

local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

export type TerrainHills = {
	-- Altura de las colinas en (x, z) con la amplitud y la rugosidad ya mezcladas por los pesos de bioma.
	getHeight: (x: number, z: number, amplitudeScale: number, roughness: number) -> number,
}

-- Período de math.noise: la entrada se envuelve para no perder precisión con coordenadas grandes.
local NOISE_PERIOD = 256
-- Un desplazamiento entero pondría los puntos del ruido sobre la grilla de la función, donde vale siempre 0.
local NON_INTEGER_OFFSET = 0.5
local INVERSE_COARSE_STUDS = 1 / WorldConfig.TERRAIN_HILL_WAVELENGTH_STUDS
local INVERSE_FINE_STUDS = 1 / WorldConfig.TERRAIN_HILL_FINE_WAVELENGTH_STUDS

local function drawOffset(random: SeededRandom.SeededRandom): number
	return math.floor(random.nextNumber() * WorldConfig.TERRAIN_HILL_NOISE_OFFSET_RANGE) + NON_INTEGER_OFFSET
end

local TerrainHillsModule = {}

function TerrainHillsModule.new(seed: number): TerrainHills
	local random = SeededRandom.new(seed + WorldConfig.TERRAIN_NOISE_SEED_SALT)
	local coarseX, coarseZ = drawOffset(random), drawOffset(random)
	local fineX, fineZ = drawOffset(random), drawOffset(random)

	local function getHeight(x: number, z: number, amplitudeScale: number, roughness: number): number
		local coarse = math.noise(
			(x * INVERSE_COARSE_STUDS + coarseX) % NOISE_PERIOD,
			(z * INVERSE_COARSE_STUDS + coarseZ) % NOISE_PERIOD
		)
		local fine =
			math.noise((x * INVERSE_FINE_STUDS + fineX) % NOISE_PERIOD, (z * INVERSE_FINE_STUDS + fineZ) % NOISE_PERIOD)
		local fineShare = WorldConfig.TERRAIN_HILL_FINE_AMPLITUDE_RATIO * roughness
		return WorldConfig.TERRAIN_HILL_AMPLITUDE_STUDS * amplitudeScale * (coarse + fineShare * fine)
	end

	return { getHeight = getHeight }
end

return TerrainHillsModule
