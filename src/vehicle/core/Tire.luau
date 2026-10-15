--!strict
-- Neumático (CP-1 y CP-3): fuerza lateral lineal con tope y círculo de fricción con la fuerza longitudinal.
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type VehicleSettings = VehicleTypes.VehicleSettings

local Tire = {}

-- La fuerza termina de caer cuando el ángulo llega a este múltiplo del ángulo del pico.
local FALL_END_PEAK_MULTIPLE = 2

-- A baja velocidad el denominador no baja de la regularización: el neumático amortigua en vez de temblar.
function Tire.slipAngle(lateralSpeed: number, longitudinalSpeed: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local reference = math.max(math.abs(longitudinalSpeed), settings.LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND)
	return math.atan2(lateralSpeed, reference)
end

-- Lineal hasta el ángulo del pico; después baja hasta SLIDE_FRICTION_RATIO · tope al doble de ese ángulo.
function Tire.lateralForce(slipAngle: number, load: number, grip: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local peakForce = settings.TIRE_FRICTION * grip * load
	local peakAngle = settings.TIRE_FRICTION * grip / settings.TIRE_CORNERING_STIFFNESS_PER_RADIAN
	local magnitude = math.abs(slipAngle)
	local force
	if magnitude <= peakAngle then
		force = settings.TIRE_CORNERING_STIFFNESS_PER_RADIAN * load * magnitude
	elseif magnitude < FALL_END_PEAK_MULTIPLE * peakAngle then
		local fallFraction = (magnitude - peakAngle) / peakAngle
		force = peakForce * (1 - (1 - settings.TIRE_SLIDE_FRICTION_RATIO) * fallFraction)
	else
		force = peakForce * settings.TIRE_SLIDE_FRICTION_RATIO
	end
	return -math.sign(slipAngle) * force
end

-- Devuelve la fuerza longitudinal y la lateral ya recortadas al círculo, el cociente entre lo pedido y lo
-- disponible (0 si no hay carga) y si el neumático está deslizando (pidió más de lo que agarra).
function Tire.combine(
	longitudinal: number,
	lateral: number,
	load: number,
	grip: number,
	config: VehicleSettings?
): (number, number, number, boolean)
	local settings = config or VehicleConfig
	local available = settings.TIRE_FRICTION * grip * load
	if not (available > 0) then
		return 0, 0, 0, false
	end
	local requested = math.sqrt(longitudinal * longitudinal + lateral * lateral)
	local slipRatio = requested / available
	if slipRatio <= 1 then
		return longitudinal, lateral, slipRatio, false
	end
	return longitudinal / slipRatio, lateral / slipRatio, slipRatio, true
end

return Tire
