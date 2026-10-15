--!strict
-- Contravolante suave (CP-1). Con COUNTER_STEER_STRENGTH en 0 queda apagado.
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type VehicleSettings = VehicleTypes.VehicleSettings

local Assists = {}

-- Ángulo en radianes que se suma a la dirección. Un ángulo de deriva positivo (la velocidad apunta a la
-- derecha del frente) pide girar a la derecha. Solo con el auto yendo hacia adelante.
function Assists.counterSteer(driftAngle: number, forwardSpeed: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	if not (forwardSpeed > settings.COUNTER_STEER_MIN_SPEED) then
		return 0
	end
	local limit = math.rad(settings.COUNTER_STEER_MAX_DEGREES)
	return math.clamp(settings.COUNTER_STEER_STRENGTH * driftAngle, -limit, limit)
end

return Assists
