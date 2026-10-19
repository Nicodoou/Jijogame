--!strict
-- Motor, reparto de tracción y frenos (CP-4, CP-9 y T1); la caja automática está en `Gearbox`. Sin inercia de rueda:
-- la fuerza longitudinal sale del motor y del freno, y el círculo de fricción del neumático la recorta.
local TorqueCurve = require("./TorqueCurve")
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type VehicleState = VehicleTypes.VehicleState
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings

local Drivetrain = {}

local REVERSE_GEAR = -1
local FIRST_GEAR = 1
local SECONDS_PER_MINUTE = 60
-- Cada eje tiene dos ruedas y se reparte en partes iguales.
local WHEEL_SHARE_OF_AXLE = 0.5

local function ratioOf(gear: number, settings: VehicleSettings): number
	if gear == REVERSE_GEAR then
		return settings.REVERSE_RATIO
	end
	return settings.GEAR_RATIOS[gear]
end

-- En reversa los pedales se invierten (arcade): el freno acelera hacia atrás y el acelerador frena.
local function resolvePedals(gear: number, controls: VehicleControls): (number, number)
	if gear == REVERSE_GEAR then
		return controls.brake, controls.throttle
	end
	return controls.throttle, controls.brake
end

function Drivetrain.torqueFraction(rpm: number, config: VehicleSettings?): number
	return TorqueCurve.fractionAt((config or VehicleConfig).TORQUE_CURVE, rpm)
end

-- RPM que tendría el motor en esa marcha, sin recortar al ralentí ni al corte.
function Drivetrain.rawRpm(forwardSpeed: number, gear: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local wheelRevolutionsPerSecond = math.abs(forwardSpeed) / settings.WHEEL_RADIUS_STUDS / (2 * math.pi)
	return wheelRevolutionsPerSecond * SECONDS_PER_MINUTE * ratioOf(gear, settings) * settings.FINAL_DRIVE
end

function Drivetrain.engineRpm(forwardSpeed: number, gear: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	return math.min(math.max(Drivetrain.rawRpm(forwardSpeed, gear, settings), settings.IDLE_RPM), settings.REDLINE_RPM)
end

-- Fracción del empuje de la primera marcha a pleno pedal que da una marcha con esas RPM: la curva de torque, la
-- relación y el corte suave. Es la única fórmula del empuje por marcha: la usan `driveForce` y el kickdown.
local function thrustFraction(rpm: number, gear: number, settings: VehicleSettings): number
	local limiterFactor = math.clamp((settings.REDLINE_RPM - rpm) / settings.SOFT_LIMITER_RPM, 0, 1)
	local gearMultiplier = ratioOf(gear, settings) / settings.GEAR_RATIOS[FIRST_GEAR]
	return Drivetrain.torqueFraction(rpm, settings) * gearMultiplier * limiterFactor
end

-- Empuje relativo que daría esa marcha a esa velocidad (0 si las RPM llegan al corte).
function Drivetrain.gearForce(gear: number, forwardSpeed: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	return thrustFraction(Drivetrain.engineRpm(forwardSpeed, gear, settings), gear, settings)
end

-- Fuerza de empuje total sobre el eje del frente del auto: positiva adelante, negativa en reversa.
function Drivetrain.driveForce(
	state: VehicleState,
	controls: VehicleControls,
	rpm: number,
	mass: number,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	local drivePedal = resolvePedals(state.gear, controls)
	local magnitude = mass
		* settings.FIRST_GEAR_PEAK_ACCELERATION
		* thrustFraction(rpm, state.gear, settings)
		* drivePedal
	if state.shiftRemainingSeconds > 0 then
		magnitude *= settings.SHIFT_TORQUE_FRACTION
	end
	if state.gear == REVERSE_GEAR then
		return -magnitude * settings.REVERSE_DRIVE_FRACTION
	end
	return magnitude
end

-- Fuerza de cada rueda en el orden FL, FR, RL, RR.
function Drivetrain.split(force: number, config: VehicleSettings?): { number }
	local settings = config or VehicleConfig
	local shares = {}
	for index, wheel in settings.WHEELS do
		local axleShare = if wheel.isFront then 1 - settings.REAR_BIAS else settings.REAR_BIAS
		shares[index] = force * axleShare * WHEEL_SHARE_OF_AXLE
	end
	return shares
end

-- Fuerza que pide el freno de una rueda, siempre positiva: el pedal repartido entre los ejes y, atrás, el freno de mano.
-- Su sentido y el tope por paso los pone `WheelForces`, que reparte el tope entre todas las ruedas a la vez.
function Drivetrain.brakeRequest(
	state: VehicleState,
	controls: VehicleControls,
	mass: number,
	isFront: boolean,
	load: number,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	local _, brakePedal = resolvePedals(state.gear, controls)
	local axleShare = if isFront then settings.BRAKE_FRONT_BIAS else 1 - settings.BRAKE_FRONT_BIAS
	local request = brakePedal * mass * settings.BRAKE_DECELERATION * axleShare * WHEEL_SHARE_OF_AXLE
	if controls.isHandbrakeOn and not isFront then
		request += settings.HANDBRAKE_FORCE_PER_LOAD * load
	end
	return request
end

return Drivetrain
