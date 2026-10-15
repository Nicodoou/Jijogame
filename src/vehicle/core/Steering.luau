--!strict
-- Ángulo de dirección que baja con la velocidad (CP-10). Las dos ruedas delanteras giran igual (sin Ackermann).
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type VehicleSettings = VehicleTypes.VehicleSettings

local Steering = {}

-- Ángulo máximo en radianes para esa velocidad.
function Steering.maxAngle(speed: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local speedRange = settings.STEER_HIGH_SPEED - settings.STEER_LOW_SPEED
	local blend = math.clamp((math.abs(speed) - settings.STEER_LOW_SPEED) / speedRange, 0, 1)
	local degrees = settings.STEER_MAX_LOW_SPEED_DEGREES
		+ (settings.STEER_MAX_HIGH_SPEED_DEGREES - settings.STEER_MAX_LOW_SPEED_DEGREES) * blend
	return math.rad(degrees)
end

function Steering.angle(steerInput: number, speed: number, config: VehicleSettings?): number
	return steerInput * Steering.maxAngle(speed, config)
end

return Steering
