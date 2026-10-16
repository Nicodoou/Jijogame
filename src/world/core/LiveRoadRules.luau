--!strict
-- Las reglas de la ruta viva entre dos muestras no vecinas, sin la grilla: la distancia libre (anti-cruce) y la regla de
-- altura (WP-9). Además dice cuántas muestras seguidas de una pasada se pueden saltear sin mirarlas, porque la ruta se
-- mueve poco entre una muestra y la siguiente y entonces ninguna de esas muestras puede romper una regla.

local WorldConfig = require("./WorldConfig")

-- La posición guardada es de 32 bits (vector): entre muestras seguidas sobra esto para el redondeo.
local ROUNDING_TOLERANCE_STUDS = 0.01
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local NEIGHBOR_ARC_STUDS = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local CLEARANCE_STUDS = WorldConfig.LIVE_CLEARANCE_STUDS
local NEAR_CLEARANCE_STUDS = WorldConfig.LIVE_NEAR_CLEARANCE_STUDS
local HEIGHT_RADIUS_STUDS = WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS
-- Espacio entre los ejes de dos pasadas que ocupan la ruta y las dos banquinas: ahí el terreno no puede subir.
local ROAD_AND_SHOULDERS_STUDS = WorldConfig.ROAD_WIDTH_STUDS + 2 * WorldConfig.SHOULDER_WIDTH_STUDS
local RISE_PER_STUD =
	math.tan(math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES - WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES))
-- Lo más que se mueven dos muestras seguidas de la ruta: en el plano y en altura.
local MAX_STEP_PLAN_STUDS = STEP_STUDS + ROUNDING_TOLERANCE_STUDS
local MAX_STEP_RISE_STUDS = STEP_STUDS * math.tan(math.rad(WorldConfig.MAX_SLOPE_DEGREES)) + ROUNDING_TOLERANCE_STUDS
-- Por cada muestra que se avanza, la diferencia admitida baja a lo sumo esto y la diferencia real sube a lo sumo esto.
local HEIGHT_SLACK_PER_STEP_STUDS = RISE_PER_STUD * MAX_STEP_PLAN_STUDS + MAX_STEP_RISE_STUDS

local LiveRoadRules = {}

-- Cuántas muestras seguidas, a partir de la que sigue a la medida, cumplen seguro las dos reglas: no se acercan a menos de la
-- distancia libre y, dentro del radio, no pasan lo que el terreno salva entre las banquinas. Es negativo si la medida misma
-- rompe una regla. `arcDifference` (más de LIVE_NEAR_ARC_STUDS) decide la distancia libre que piden las dos muestras: entre
-- las cercanas alcanza la corta (LIVE_NEAR_CLEARANCE_STUDS); `rise` es el valor absoluto de la diferencia de altura.
function LiveRoadRules.getSafeSteps(distance: number, arcDifference: number, rise: number): number
	local requiredDistance = if arcDifference <= NEIGHBOR_ARC_STUDS then NEAR_CLEARANCE_STUDS else CLEARANCE_STUDS
	local safeByDistance = (distance - requiredDistance) / MAX_STEP_PLAN_STUDS
	if distance >= HEIGHT_RADIUS_STUDS then
		return math.min(safeByDistance, (distance - HEIGHT_RADIUS_STUDS) / MAX_STEP_PLAN_STUDS)
	end
	local allowedRise = RISE_PER_STUD * math.max(0, distance - ROAD_AND_SHOULDERS_STUDS)
	return math.min(safeByDistance, (allowedRise - rise) / HEIGHT_SLACK_PER_STEP_STUDS)
end

-- Si dos muestras seguidas están tan cerca como una ruta real: solo entonces se pueden saltear las que quedan en el medio.
function LiveRoadRules.isContinuousStep(planDistanceSquared: number, rise: number): boolean
	return planDistanceSquared <= MAX_STEP_PLAN_STUDS ^ 2 and rise <= MAX_STEP_RISE_STUDS
end

return LiveRoadRules
