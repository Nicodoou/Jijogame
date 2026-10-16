--!strict
-- Ruido de manchones con semilla para BiomeBlend. Todos los campos salen de una misma corrida del generador, en orden
-- fijo, y el primero (el del barro) es el mismo que ya usaba SurfaceClassifier: así los manchones de hoy no cambian.

local QuantileMap = require("./QuantileMap")
local QuantileTables = require("./QuantileTables")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

export type Offset = { x: number, z: number }

export type PatchOffsets = {
	mud: Offset,
	biome: Offset,
	material: Offset,
	bridge: Offset,
}

-- Período de math.noise: la entrada se envuelve para no perder precisión con coordenadas grandes.
local NOISE_PERIOD = 256
-- Un desplazamiento entero pondría los puntos del ruido sobre la grilla de la función, donde vale siempre 0.
local NON_INTEGER_OFFSET = 0.5
local INVERSE_PATCH_STUDS = 1 / WorldConfig.BIOME_MATERIAL_PATCH_STUDS

local function drawOffset(random: SeededRandom.SeededRandom, range: number): Offset
	local x = math.floor(random.nextNumber() * range) + NON_INTEGER_OFFSET
	local z = math.floor(random.nextNumber() * range) + NON_INTEGER_OFFSET
	return { x = x, z = z }
end

local PatchNoise = {}

function PatchNoise.createOffsets(seed: number): PatchOffsets
	local random = SeededRandom.new(seed)
	local mud = drawOffset(random, WorldConfig.MUD_NOISE_OFFSET_RANGE)
	return {
		mud = mud,
		biome = drawOffset(random, WorldConfig.BIOME_PATCH_NOISE_OFFSET_RANGE),
		material = drawOffset(random, WorldConfig.BIOME_PATCH_NOISE_OFFSET_RANGE),
		bridge = drawOffset(random, WorldConfig.BIOME_PATCH_NOISE_OFFSET_RANGE),
	}
end

-- Valor del ruido de barro, sin normalizar: la misma cuenta que hacía SurfaceClassifier.
function PatchNoise.sampleMud(offset: Offset, x: number, z: number, scalePerStud: number): number
	return math.noise(x * scalePerStud + offset.x, z * scalePerStud + offset.z)
end

-- Número en [0, 1] casi uniforme que cambia despacio: cada BIOME_MATERIAL_PATCH_STUDS studs cambia de manchón.
function PatchNoise.sampleUnit(offset: Offset, x: number, z: number): number
	local noiseX = (x * INVERSE_PATCH_STUDS + offset.x) % NOISE_PERIOD
	local noiseZ = (z * INVERSE_PATCH_STUDS + offset.z) % NOISE_PERIOD
	return QuantileMap.toUnit(math.noise(noiseX, noiseZ), QuantileTables.PATCH)
end

return PatchNoise
