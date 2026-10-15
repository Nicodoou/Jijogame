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

-- Al derrapar se puede contravolantear más allá del máximo por velocidad: hasta el ángulo de deriva más un margen,
-- sin pasar del máximo de baja velocidad. En recta (deriva 0) vale lo mismo que `maxAngle`.
function Steering.maxAngleWhileDrifting(speed: number, driftAngle: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local driftLimit = math.abs(driftAngle) + math.rad(settings.DRIFT_STEER_MARGIN_DEGREES)
	local lowSpeedLimit = math.rad(settings.STEER_MAX_LOW_SPEED_DEGREES)
	return math.max(Steering.maxAngle(speed, config), math.min(driftLimit, lowSpeedLimit))
end

-- En marcha atrás la dirección tiene su propio máximo, fijo.
function Steering.reverseMaxAngle(config: VehicleSettings?): number
	return math.rad((config or VehicleConfig).STEER_MAX_REVERSE_DEGREES)
end

function Steering.angle(steerInput: number, speed: number, config: VehicleSettings?): number
	return steerInput * Steering.maxAngle(speed, config)
end

return Steering
