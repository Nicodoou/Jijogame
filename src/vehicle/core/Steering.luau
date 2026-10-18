--!strict
-- Ángulo de dirección que baja con la velocidad (CP-10). Las dos ruedas delanteras giran igual (sin Ackermann).
local Assists = require("./Assists")
local RoadSteerLimit = require("./RoadSteerLimit")
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
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

-- Ángulo pedido: el del conductor (con el límite según la curva) más las asistencias, dentro del máximo que corresponda.
function Steering.requestedAngle(
	controls: VehicleControls,
	chassis: ChassisSample,
	forwardSpeed: number,
	driftAngle: number,
	gear: number,
	road: RoadSteerLimit.RoadAhead?,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	local speed = vector.magnitude(chassis.linearVelocity)
	local isReversing = gear < 0
	local maxSteer = if isReversing
		then Steering.reverseMaxAngle(settings)
		else Steering.maxAngleWhileDrifting(speed, driftAngle, settings)
	local driverSteer = if isReversing
		then controls.steer * maxSteer
		else Steering.angle(controls.steer, speed, settings)
	local limited = RoadSteerLimit.limit(driverSteer, chassis, forwardSpeed, driftAngle, road, settings)
	local requested = limited
		+ Assists.counterSteer(driftAngle, forwardSpeed, settings)
		+ math.rad(settings.STEER_OFFSET_DEGREES)
	return math.clamp(requested, -maxSteer, maxSteer)
end

return Steering
