--!strict
-- Del clima de un punto al peso de cada bioma: w = max(0, 1 - d / R) ^ k, con d la distancia (en u) del clima a la caja
-- de la ficha. Dentro de la caja d = 0 y el peso es 1; afuera baja hasta 0 a distancia R. Los consumidores solo leen
-- estos pesos: nunca preguntan "qué bioma es".

local BiomeTypes = require("./BiomeTypes")
local WorldConfig = require("./WorldConfig")

type BiomeDefinition = BiomeTypes.BiomeDefinition
type ClimateSample = BiomeTypes.ClimateSample
type ClimateBox = BiomeTypes.ClimateBox

export type BiomeWeights = BiomeTypes.BiomeWeights

export type TransitionSettings = {
	radius: number,
	exponent: number,
	cutoff: number,
}

local defaultSettings: TransitionSettings = table.freeze({
	radius = WorldConfig.BIOME_TRANSITION_RADIUS,
	exponent = WorldConfig.BIOME_TRANSITION_EXPONENT,
	cutoff = WorldConfig.BIOME_WEIGHT_CUTOFF,
})

-- Cuánto se sale `value` del rango [min, max]: 0 si está adentro.
local function getOutsideDistance(value: number, range: BiomeTypes.ClimateRange): number
	return math.max(range.min - value, value - range.max, 0)
end

local function getDistanceToBox(climate: ClimateSample, box: ClimateBox): number
	local relief = getOutsideDistance(climate.relief, box.relief)
	local humidity = getOutsideDistance(climate.humidity, box.humidity)
	local temperature = getOutsideDistance(climate.temperature, box.temperature)
	return math.sqrt(relief * relief + humidity * humidity + temperature * temperature)
end

local function getRawWeight(distance: number, settings: TransitionSettings): number
	return math.max(0, 1 - distance / settings.radius) ^ settings.exponent
end

local BiomeWeights = {}

-- Pesos que suman 1. Los menores a `cutoff` se descartan; si ninguno llega, queda el bioma más cercano con peso 1
-- (el primero del catálogo si hay empate).
function BiomeWeights.compute(
	climate: ClimateSample,
	catalog: { BiomeDefinition },
	settings: TransitionSettings?
): BiomeWeights
	local transition = settings or defaultSettings
	if not (transition.radius > 0) then
		error("the transition radius has to be bigger than 0", 2)
	end
	local isNaN = climate.relief ~= climate.relief
		or climate.humidity ~= climate.humidity
		or climate.temperature ~= climate.temperature
	if isNaN then
		error("the climate cannot have NaN values", 2)
	end
	local weights: BiomeWeights = {}
	local keptTotal = 0
	local nearestId: string? = nil
	local nearestDistance = math.huge
	for _, definition in catalog do
		local distance = getDistanceToBox(climate, definition.climate)
		if distance < nearestDistance then
			nearestDistance = distance
			nearestId = definition.id
		end
		local weight = getRawWeight(distance, transition)
		if weight >= transition.cutoff and weight > 0 then
			weights[definition.id] = weight
			keptTotal += weight
		end
	end
	if keptTotal == 0 then
		return if nearestId == nil then weights else { [nearestId] = 1 }
	end
	for id, weight in weights do
		weights[id] = weight / keptTotal
	end
	return weights
end

return BiomeWeights
