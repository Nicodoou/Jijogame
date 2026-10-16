--!strict
-- Implementa GetSurfaceAt (contrato #17): decide la superficie de una posición con el punto más cercano del eje.
-- Sobre la ruta y la banquina manda la distancia al eje; fuera de ellas, la ficha del bioma (BiomeBlend).

local BiomeBlend = require("./BiomeBlend")
local BiomeMap = require("./BiomeMap")
local RoadQuery = require("./RoadQuery")
local Surface = require("../../shared/contracts/Surface")
local WorldConfig = require("./WorldConfig")

local ROAD_HALF_WIDTH_STUDS = WorldConfig.ROAD_WIDTH_STUDS / 2
local SHOULDER_EDGE_STUDS = ROAD_HALF_WIDTH_STUDS + WorldConfig.SHOULDER_WIDTH_STUDS

local SurfaceClassifier = {}

function SurfaceClassifier.createGetSurfaceAt(
	query: RoadQuery.RoadQuery,
	picker: BiomeBlend.Picker,
	biomeMap: BiomeMap.BiomeMap
): Surface.GetSurfaceAt
	-- Las ruedas piden puntos a pocos studs unos de otros: el resultado anterior sirve de cursor. Si no sirve (un salto),
	-- RoadQuery busca en toda la grilla.
	local lastResult: RoadQuery.RoadQueryResult? = nil

	return function(position: vector): Surface.SurfaceKind?
		local nearest = query.findNearest(position, lastResult)
		lastResult = nearest
		if nearest == nil then
			return nil
		end
		local lateralStuds = math.abs(nearest.lateralOffset)
		if lateralStuds <= ROAD_HALF_WIDTH_STUDS then
			return "Road"
		elseif lateralStuds <= SHOULDER_EDGE_STUDS then
			return "Shoulder"
		end
		local weights = biomeMap.getWeightsAt(position.x, position.z)
		return picker.pickOffroadSurface(weights, position.x, position.z, lateralStuds - SHOULDER_EDGE_STUDS)
	end
end

return SurfaceClassifier
