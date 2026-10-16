--!strict
-- Pesos de bioma de cada punto del mundo: une el clima (ClimateField) con los pesos (BiomeWeights). Para muchos puntos
-- de una misma zona (un chunk) se arma antes una grilla de clima y se interpolan los parámetros, no los pesos.

local BiomeTypes = require("./BiomeTypes")
local BiomeWeights = require("./BiomeWeights")
local ClimateField = require("./ClimateField")
local ClimateGrid = require("./ClimateGrid")
local WorldConfig = require("./WorldConfig")

type BiomeDefinition = BiomeTypes.BiomeDefinition
type BiomeWeightsMap = BiomeTypes.BiomeWeights

export type BiomeMap = {
	-- Pesos con el clima calculado en el punto exacto (para consultas sueltas).
	getWeightsAt: (x: number, z: number) -> BiomeWeightsMap,
	-- Arma la grilla de clima del cuadrado [origen, origen + sizeStuds] para `getWeightsInArea`.
	prepareArea: (originX: number, originZ: number, sizeStuds: number) -> (),
	-- Pesos con el clima interpolado de la grilla preparada. Fuera del cuadrado vale lo del borde.
	getWeightsInArea: (x: number, z: number) -> BiomeWeightsMap,
}

local BiomeMapModule = {}

function BiomeMapModule.new(seed: number, catalog: { BiomeDefinition }): BiomeMap
	local climate = ClimateField.new(seed)
	local grid: ClimateGrid.ClimateGrid? = nil

	local function getWeightsAt(x: number, z: number): BiomeWeightsMap
		return BiomeWeights.compute(climate.sample(x, z), catalog, nil)
	end

	local function prepareArea(originX: number, originZ: number, sizeStuds: number)
		grid = climate.sampleGrid(originX, originZ, sizeStuds, WorldConfig.CLIMATE_GRID_STEP_STUDS)
	end

	local function getWeightsInArea(x: number, z: number): BiomeWeightsMap
		local prepared = grid
		if prepared == nil then
			error("prepareArea has to be called before getWeightsInArea", 2)
		end
		return BiomeWeights.compute(prepared.sampleAt(x, z), catalog, nil)
	end

	return { getWeightsAt = getWeightsAt, prepareArea = prepareArea, getWeightsInArea = getWeightsInArea }
end

return BiomeMapModule
