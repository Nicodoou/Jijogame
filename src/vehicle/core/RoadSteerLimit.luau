--!strict
-- Límite de dirección según la curva (experimento). Recibe el camino como datos: un punto cerca del auto y otro
-- adelante. Solo recorta dirección que pasa del ángulo que pide el tramo más un margen; nunca agrega dirección.
-- Todos los ángulos son en radianes y positivos hacia la derecha.
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleSettings = VehicleTypes.VehicleSettings

export type RoadSample = {
	position: vector,
	direction: vector,
	arcLength: number,
}

export type RoadAhead = {
	near: RoadSample,
	ahead: RoadSample,
}

-- Puntos descartados seguidos tras los cuales se acepta el nuevo (el auto reapareció o saltó de tramo).
local MAX_REJECTED_POINTS = 30
-- El punto de adelante puede quedar hasta este múltiplo de la anticipación sobre el eje.
local MAX_AHEAD_ARC_FACTOR = 3
local EPSILON = 1e-6

local RoadSteerLimit = {}

-- Dirección horizontal unitaria, o nil si es vertical, nula o inválida.
local function flatten(direction: vector): vector?
	local flat = vector.create(direction.x, 0, direction.z)
	local length = vector.magnitude(flat)
	if not (length > EPSILON) then
		return nil
	end
	return flat / length
end

local function rightOf(direction: vector): vector
	return vector.create(-direction.z, 0, direction.x)
end

-- Ángulo con signo de `to` respecto de `from` (unitarios horizontales): positivo si `to` queda a la derecha.
local function signedAngle(from: vector, to: vector): number
	return math.atan2(vector.dot(to, rightOf(from)), vector.dot(to, from))
end

local function wheelbase(settings: VehicleSettings): number
	return math.abs(settings.WHEELS[3].offset.z - settings.WHEELS[1].offset.z)
end

-- Ángulo de dirección que pide el tramo entre los dos puntos: atan(distancia entre ejes · curvatura).
function RoadSteerLimit.requiredAngle(road: RoadAhead, config: VehicleSettings?): number?
	local settings = config or VehicleConfig
	local nearDirection, aheadDirection = flatten(road.near.direction), flatten(road.ahead.direction)
	local arc = road.ahead.arcLength - road.near.arcLength
	local maxArc = settings.ROAD_STEER_LOOKAHEAD * MAX_AHEAD_ARC_FACTOR
	if nearDirection == nil or aheadDirection == nil or not (arc > EPSILON and arc <= maxArc) then
		return nil
	end
	return math.atan(wheelbase(settings) * signedAngle(nearDirection, aheadDirection) / arc)
end

-- Dirección que no se recorta: contravolante (a favor de una deriva clara) y volver al camino apuntando afuera.
local function isExempt(steer: number, offset: number, heading: number, driftAngle: number, settings: VehicleSettings)
	local isDrifting = math.abs(driftAngle) > math.rad(settings.DRIFT_ANGLE_THRESHOLD_DEGREES)
	if isDrifting and math.sign(steer) == math.sign(driftAngle) then
		return true
	end
	local isOffRoad = math.abs(offset) > settings.ROAD_STEER_RETURN_DISTANCE
	return isOffRoad and offset * heading > 0 and math.sign(steer) == -math.sign(offset)
end

-- El límite solo actúa cerca del eje del camino y con el auto más o menos alineado con él.
local function isInScope(offset: number, heading: number, settings: VehicleSettings): boolean
	return math.abs(offset) <= settings.ROAD_STEER_MAX_DISTANCE
		and math.abs(heading) <= math.rad(settings.ROAD_STEER_MAX_HEADING_DEGREES)
end

-- Devuelve la dirección pedida, recortada si corresponde. El rango permitido siempre incluye el 0, así que
-- recortar solo acerca la dirección al 0 (o la deja en el borde) y nunca la aumenta.
function RoadSteerLimit.limit(
	steer: number,
	chassis: ChassisSample,
	forwardSpeed: number,
	driftAngle: number,
	road: RoadAhead?,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	if road == nil or not settings.ROAD_STEER_LIMIT_ENABLED or not (forwardSpeed >= settings.ROAD_STEER_MIN_SPEED) then
		return steer
	end
	local required = RoadSteerLimit.requiredAngle(road, settings)
	local roadDirection, carDirection = flatten(road.near.direction), flatten(chassis.forward)
	if required == nil or roadDirection == nil or carDirection == nil then
		return steer
	end
	local offset = vector.dot(chassis.position - road.near.position, rightOf(roadDirection))
	local heading = signedAngle(roadDirection, carDirection)
	if not isInScope(offset, heading, settings) or isExempt(steer, offset, heading, driftAngle, settings) then
		return steer
	end
	local margin = math.rad(settings.ROAD_STEER_MARGIN_DEGREES)
	return math.clamp(steer, math.min(required - margin, 0), math.max(required + margin, 0))
end

-- Decide si se acepta el punto del camino según su arcLength. Devuelve si se acepta, el último arcLength aceptado y
-- la cuenta de descartes seguidos. Un salto mayor que ROAD_STEER_MAX_ARC_JUMP se descarta (U cerradas).
function RoadSteerLimit.track(
	lastArc: number?,
	rejectedCount: number,
	arc: number,
	config: VehicleSettings?
): (boolean, number?, number)
	local settings = config or VehicleConfig
	local isContinuous = lastArc == nil or math.abs(arc - lastArc) <= settings.ROAD_STEER_MAX_ARC_JUMP
	if isContinuous or rejectedCount >= MAX_REJECTED_POINTS then
		return arc == arc, if arc == arc then arc else lastArc, 0
	end
	return false, lastArc, rejectedCount + 1
end

return RoadSteerLimit
