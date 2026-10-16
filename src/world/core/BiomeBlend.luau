--!strict
-- Ayudas para quien consume los pesos de bioma: mezclar un número, y elegir material y superficie con ruido de
-- manchones (coherente en el espacio: vecinos cercanos casi siempre eligen igual). No escribe nada.

local BiomeTypes = require("./BiomeTypes")
local PatchNoise = require("./PatchNoise")
local Surface = require("../../shared/contracts/Surface")
local WorldConfig = require("./WorldConfig")

type BiomeDefinition = BiomeTypes.BiomeDefinition
type BiomeWeights = BiomeTypes.BiomeWeights
type MaterialShare = BiomeTypes.MaterialShare

local NO_WEIGHT = 0

-- Suma de pesos, cuántos biomas pesan y el último que pesa: lo que hace falta para sortear sin recorrer dos veces.
local function summarizeWeights(weights: BiomeWeights, catalog: { BiomeDefinition }): (number, number, BiomeDefinition?)
	local total, count, last = 0, 0, nil
	for _, definition in catalog do
		local weight = weights[definition.id] or NO_WEIGHT
		if weight > 0 then
			total += weight
			count += 1
			last = definition
		end
	end
	return total, count, last
end

-- Elige un bioma recorriendo el catálogo en orden: `unit` en [0, 1] cae en el tramo del peso de alguno. Si el redondeo de
-- la suma deja a `unit` fuera de todos los tramos, se queda con el último bioma que pesa.
local function pickBiomeByUnit(
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	unit: number,
	total: number,
	last: BiomeDefinition
): BiomeDefinition
	local target = unit * total
	local cumulative = 0
	local picked = last
	for _, definition in catalog do
		cumulative += weights[definition.id] or NO_WEIGHT
		if target < cumulative then
			picked = definition
			break
		end
	end
	return picked
end

-- Con un solo bioma no hace falta ruido: el resultado es el mismo en todo el mundo.
local function chooseBiome(
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	offsets: PatchNoise.PatchOffsets,
	x: number,
	z: number
): (BiomeDefinition, number)
	local total, count, last = summarizeWeights(weights, catalog)
	if last == nil then
		error("the weights do not give any biome of the catalog a positive weight", 3)
	end
	if count == 1 then
		return last, total
	end
	return pickBiomeByUnit(weights, catalog, PatchNoise.sampleUnit(offsets.biome, x, z), total, last), total
end

-- Fracción de material puente: 0 en el interior de un bioma y BIOME_BRIDGE_MAX_SHARE con los dos más pesados empatados.
local function getBridgeShare(weights: BiomeWeights, catalog: { BiomeDefinition }, total: number): number
	local first, second = 0, 0
	for _, definition in catalog do
		local weight = (weights[definition.id] or NO_WEIGHT) / total
		if weight > first then
			first, second = weight, first
		elseif weight > second then
			second = weight
		end
	end
	return WorldConfig.BIOME_BRIDGE_MAX_SHARE * (1 - (first - second))
end

local function pickShare(shares: { MaterialShare }, unit: number): string
	local cumulative = 0
	for _, share in shares do
		cumulative += share.proportion
		if unit < cumulative then
			return share.material
		end
	end
	return shares[#shares].material
end

local function pickMaterialWith(
	offsets: PatchNoise.PatchOffsets,
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	x: number,
	z: number
): string
	local biome, total = chooseBiome(weights, catalog, offsets, x, z)
	if PatchNoise.sampleUnit(offsets.bridge, x, z) < getBridgeShare(weights, catalog, total) then
		return biome.materials.transition
	end
	return pickShare(biome.materials.surface, PatchNoise.sampleUnit(offsets.material, x, z))
end

local function pickOffroadSurfaceWith(
	offsets: PatchNoise.PatchOffsets,
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	x: number,
	z: number,
	distanceFromShoulderStuds: number
): Surface.SurfaceKind
	local biome = chooseBiome(weights, catalog, offsets, x, z)
	for _, patch in biome.surfaces.patches do
		local isFarEnough = distanceFromShoulderStuds > patch.minDistanceFromShoulderStuds
		if isFarEnough and PatchNoise.sampleMud(offsets.mud, x, z, patch.noiseScalePerStud) > patch.noiseThreshold then
			return patch.surface
		end
	end
	return biome.surfaces.offroad
end

-- Mismas funciones que pickMaterial y pickOffroadSurface, con los desplazamientos del ruido ya calculados para la semilla.
export type Picker = {
	pickMaterial: (weights: BiomeWeights, x: number, z: number) -> string,
	pickOffroadSurface: (
		weights: BiomeWeights,
		x: number,
		z: number,
		distanceFromShoulderStuds: number
	) -> Surface.SurfaceKind,
}

local BiomeBlend = {}

-- Promedio de un número de las fichas (por ejemplo la amplitud de las colinas) ponderado por los pesos.
function BiomeBlend.blendNumber(
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	selector: (BiomeDefinition) -> number
): number
	local blended = 0
	for _, definition in catalog do
		local weight = weights[definition.id] or NO_WEIGHT
		if weight > 0 then
			blended += weight * selector(definition)
		end
	end
	return blended
end

-- Material de la superficie del terreno en (x, z). Cada manchón se queda con el material de un bioma, con probabilidad
-- igual a su peso; en las transiciones parte de los manchones son del material puente del bioma elegido.
function BiomeBlend.pickMaterial(
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	x: number,
	z: number,
	seed: number
): string
	return pickMaterialWith(PatchNoise.createOffsets(seed), weights, catalog, x, z)
end

-- Superficie fuera de la ruta en (x, z): la de la ficha del bioma elegido, o la de su primer manchón que corresponda.
-- `distanceFromShoulderStuds` es lo que se aleja el punto del borde de la banquina.
function BiomeBlend.pickOffroadSurface(
	weights: BiomeWeights,
	catalog: { BiomeDefinition },
	x: number,
	z: number,
	seed: number,
	distanceFromShoulderStuds: number
): Surface.SurfaceKind
	return pickOffroadSurfaceWith(PatchNoise.createOffsets(seed), weights, catalog, x, z, distanceFromShoulderStuds)
end

-- Material del subsuelo: el `deep` del bioma que más pesa (el primero del catálogo si empatan).
function BiomeBlend.pickDeepMaterial(weights: BiomeWeights, catalog: { BiomeDefinition }): string
	local heaviest: BiomeDefinition? = nil
	local heaviestWeight = NO_WEIGHT
	for _, definition in catalog do
		local weight = weights[definition.id] or NO_WEIGHT
		if weight > heaviestWeight then
			heaviest, heaviestWeight = definition, weight
		end
	end
	if heaviest == nil then
		error("the weights do not give any biome of the catalog a positive weight", 2)
	end
	return heaviest.materials.deep
end

-- Para elegir en muchos puntos con la misma semilla: los desplazamientos se calculan una vez, no en cada llamada.
function BiomeBlend.newPicker(seed: number, catalog: { BiomeDefinition }): Picker
	local offsets = PatchNoise.createOffsets(seed)
	return {
		pickMaterial = function(weights: BiomeWeights, x: number, z: number): string
			return pickMaterialWith(offsets, weights, catalog, x, z)
		end,
		pickOffroadSurface = function(
			weights: BiomeWeights,
			x: number,
			z: number,
			distanceFromShoulderStuds: number
		): Surface.SurfaceKind
			return pickOffroadSurfaceWith(offsets, weights, catalog, x, z, distanceFromShoulderStuds)
		end,
	}
end

return BiomeBlend
