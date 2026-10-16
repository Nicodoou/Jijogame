--!strict
-- Altura del terreno en (x, z) a partir de la ruta viva (RC-6: el terreno sigue a la ruta).
--   * Sobre la ruta y la banquina es plana, a la altura del eje en el punto más cercano.
--   * Fuera, la base mezcla las alturas de todos los bloques de ruta que quedan a menos de TERRAIN_ROAD_REACH_STUDS, con
--     peso 1 / distancia - 1 / alcance (la distancia contada desde el borde de la banquina). No manda el más cercano: así
--     dos pasadas cercanas a distinta altura se unen con una rampa y no con una pared. Lejos de la ruta la base se
--     desvanece hacia la altura ambiente.
--   * Sobre esa base se suman las colinas, que entran de a poco en TERRAIN_BLEND_WIDTH_STUDS.
-- Cada bloque de ruta (un arco de 64 studs) aporta su punto más cercano. Mezclar bloques y no tomar solo el punto
-- más cercano de toda la ruta evita que la altura salte cerca del centro de una curva cerrada, donde el punto más
-- cercano da la vuelta entera con un desplazamiento chico.

local BiomeBlend = require("./BiomeBlend")
local BiomeTypes = require("./BiomeTypes")
local RoadBlockNearest = require("./RoadBlockNearest")
local RoadBlocks = require("./RoadBlocks")
local TerrainHills = require("./TerrainHills")
local WorldConfig = require("./WorldConfig")

type BiomeDefinition = BiomeTypes.BiomeDefinition
type BiomeWeights = BiomeTypes.BiomeWeights

export type TerrainHeightField = {
	-- Carga los bloques de ruta que pueden influir en el cuadrado dado. Hay que llamarla antes de `sampleColumn`.
	setArea: (minX: number, minZ: number, maxX: number, maxZ: number) -> (),
	-- Distancia, medida desde el eje de la ruta, hasta la que un bloque de ruta influye en la altura de una columna.
	getInfluenceStuds: () -> number,
	-- Firma de los bloques cargados por `setArea`: cambia cuando entra o sale ruta que influye en la zona.
	getAreaSignature: () -> number,
	-- Altura del terreno en la columna y distancia entre la columna y el borde de la banquina (0 sobre la ruta y la
	-- banquina, math.huge si no hay ruta al alcance).
	sampleColumn: (x: number, z: number, weights: BiomeWeights) -> (number, number),
}

local SHOULDER_EDGE_STUDS = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
local REACH_STUDS = WorldConfig.TERRAIN_ROAD_REACH_STUDS
local INVERSE_REACH = 1 / REACH_STUDS
local AMBIENT_HEIGHT_STUDS = WorldConfig.HILL_BASE_HEIGHT_STUDS
local AMBIENT_FADE_START_STUDS = WorldConfig.TERRAIN_AMBIENT_FADE_START_STUDS
local AMBIENT_FADE_STUDS = REACH_STUDS - AMBIENT_FADE_START_STUDS
local BLEND_STUDS = WorldConfig.TERRAIN_BLEND_WIDTH_STUDS
-- Más allá de esta distancia al eje un bloque ya no pesa.
local DISTANCE_LIMIT_STUDS = SHOULDER_EDGE_STUDS + REACH_STUDS
local DISTANCE_LIMIT_SQUARED = DISTANCE_LIMIT_STUDS * DISTANCE_LIMIT_STUDS
local NO_ROAD_STUDS = math.huge
local MIN_BEYOND_SHOULDER_STUDS = 0.001
-- Desde esta distancia al eje (y hasta SMOOTH_SPAN_STUDS más) el bloque se mide contra su cuerda en vez de su arco.
local SMOOTH_START_STUDS = SHOULDER_EDGE_STUDS + WorldConfig.TERRAIN_CHORD_SMOOTH_START_STUDS
local SMOOTH_SPAN_STUDS = WorldConfig.TERRAIN_CHORD_SMOOTH_SPAN_STUDS
-- Un bloque cuya caja queda más lejos que esto del eje se mide solo contra su cuerda.
local CHORD_ONLY_DISTANCE_SQUARED = (SMOOTH_START_STUDS + SMOOTH_SPAN_STUDS) ^ 2

local function getAmplitudeScale(definition: BiomeDefinition): number
	return definition.terrain.hillAmplitudeScale
end

local function getRoughness(definition: BiomeDefinition): number
	return definition.terrain.hillRoughness
end

-- Sube de 0 a 1 con pendiente cero en los dos extremos.
local function smoothStep(fraction: number): number
	return fraction * fraction * (3 - 2 * fraction)
end

local TerrainHeightFieldModule = {}

function TerrainHeightFieldModule.new(
	seed: number,
	catalog: { BiomeDefinition },
	roadBlocks: RoadBlocks.RoadBlocks
): TerrainHeightField
	local hills = TerrainHills.new(seed)
	local areaBlocks: { RoadBlocks.RoadBlock } = {}
	local areaSignature = 0
	-- Se reutilizan en cada columna: sampleColumn no crea tablas.
	local distances: { number } = {}
	local heights: { number } = {}

	local function setArea(minX: number, minZ: number, maxX: number, maxZ: number)
		areaBlocks, areaSignature = roadBlocks.gather(minX, minZ, maxX, maxZ, DISTANCE_LIMIT_STUDS)
	end

	local function getAreaSignature(): number
		return areaSignature
	end

	local function getInfluenceStuds(): number
		return DISTANCE_LIMIT_STUDS
	end

	-- Cerca de la ruta la distancia y la altura de un bloque son las de su arco; lejos, las de su cuerda, que no tiene
	-- empates entre los extremos del bloque (ver RoadBlockNearest.findAlongChord). En el medio se mezclan.
	local function measureBlock(
		block: RoadBlocks.RoadBlock,
		x: number,
		z: number,
		boxDistanceSquared: number
	): (number, number)
		if boxDistanceSquared >= CHORD_ONLY_DISTANCE_SQUARED then
			return RoadBlockNearest.findAlongChord(block, x, z)
		end
		local arcDistance, arcHeight = RoadBlockNearest.find(block, x, z)
		-- Un bloque fuera de la banquina nunca cuenta como ruta, aunque la mezcla con la cuerda lo acerque.
		local minDistance = if arcDistance > SHOULDER_EDGE_STUDS
			then SHOULDER_EDGE_STUDS + MIN_BEYOND_SHOULDER_STUDS
			else 0
		local chordShare = smoothStep(math.clamp((arcDistance - SMOOTH_START_STUDS) / SMOOTH_SPAN_STUDS, 0, 1))
		if chordShare > 0 then
			local chordDistance, chordHeight = RoadBlockNearest.findAlongChord(block, x, z)
			arcDistance += chordShare * (chordDistance - arcDistance)
			arcHeight += chordShare * (chordHeight - arcHeight)
		end
		return math.max(arcDistance, minDistance), arcHeight
	end

	-- El punto más cercano de cada bloque que está al alcance de la columna.
	local function measureBlocks(x: number, z: number)
		for slot, block in areaBlocks do
			local gapX = math.max(block.minX - x, x - block.maxX, 0)
			local gapZ = math.max(block.minZ - z, z - block.maxZ, 0)
			local boxDistanceSquared = gapX * gapX + gapZ * gapZ
			if boxDistanceSquared < DISTANCE_LIMIT_SQUARED then
				local distance, height = measureBlock(block, x, z, boxDistanceSquared)
				distances[slot], heights[slot] = distance, height
			else
				distances[slot] = math.huge
			end
		end
	end

	-- Altura de la ruta si la columna cae sobre ella o su banquina: la del bloque más cercano, o nil.
	local function findRoadHeight(): number?
		local nearest, nearestHeight = SHOULDER_EDGE_STUDS, nil
		for slot = 1, #areaBlocks do
			if distances[slot] <= nearest then
				nearest, nearestHeight = distances[slot], heights[slot]
			end
		end
		return nearestHeight
	end

	-- Altura base fuera de la ruta y distancia al borde de la banquina del bloque más cercano.
	local function blendRoadHeights(): (number, number)
		local weightSum, weightedHeightSum = 0, 0
		local nearestBeyondShoulder = NO_ROAD_STUDS
		for slot = 1, #areaBlocks do
			local beyondShoulder = distances[slot] - SHOULDER_EDGE_STUDS
			if beyondShoulder < REACH_STUDS then
				local weight = 1 / beyondShoulder - INVERSE_REACH
				weightSum += weight
				weightedHeightSum += weight * heights[slot]
				nearestBeyondShoulder = math.min(nearestBeyondShoulder, beyondShoulder)
			end
		end
		if weightSum == 0 then
			return AMBIENT_HEIGHT_STUDS, nearestBeyondShoulder
		end
		local ambientShare =
			smoothStep(math.max((nearestBeyondShoulder - AMBIENT_FADE_START_STUDS) / AMBIENT_FADE_STUDS, 0))
		local roadsHeight = weightedHeightSum / weightSum
		return roadsHeight + ambientShare * (AMBIENT_HEIGHT_STUDS - roadsHeight), nearestBeyondShoulder
	end

	local function sampleColumn(x: number, z: number, weights: BiomeWeights): (number, number)
		measureBlocks(x, z)
		local roadHeight = findRoadHeight()
		if roadHeight ~= nil then
			return roadHeight, 0
		end
		local base, nearestBeyondShoulder = blendRoadHeights()
		local hillShare = smoothStep(math.min(nearestBeyondShoulder / BLEND_STUDS, 1))
		local amplitudeScale = BiomeBlend.blendNumber(weights, catalog, getAmplitudeScale)
		local roughness = BiomeBlend.blendNumber(weights, catalog, getRoughness)
		return base + hillShare * hills.getHeight(x, z, amplitudeScale, roughness), nearestBeyondShoulder
	end

	return {
		setArea = setArea,
		getInfluenceStuds = getInfluenceStuds,
		getAreaSignature = getAreaSignature,
		sampleColumn = sampleColumn,
	}
end

return TerrainHeightFieldModule
