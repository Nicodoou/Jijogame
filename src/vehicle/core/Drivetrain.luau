--!strict
-- Motor, caja automática, reparto de tracción y frenos (CP-4, CP-9 y T1). Sin inercia de rueda:
-- la fuerza longitudinal sale del motor y del freno, y el círculo de fricción del neumático la recorta.
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
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
	local curve = (config or VehicleConfig).TORQUE_CURVE
	local first = curve[1]
	local last = curve[#curve]
	if rpm <= first.rpm then
		return first.fraction
	end
	for index = 2, #curve do
		local upper = curve[index]
		if rpm <= upper.rpm then
			local lower = curve[index - 1]
			local blend = (rpm - lower.rpm) / (upper.rpm - lower.rpm)
			return lower.fraction + (upper.fraction - lower.fraction) * blend
		end
	end
	return last.fraction
end

function Drivetrain.engineRpm(forwardSpeed: number, gear: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local wheelRevolutionsPerSecond = math.abs(forwardSpeed) / settings.WHEEL_RADIUS_STUDS / (2 * math.pi)
	local rpm = wheelRevolutionsPerSecond * SECONDS_PER_MINUTE * ratioOf(gear, settings) * settings.FINAL_DRIVE
	return math.min(math.max(rpm, settings.IDLE_RPM), settings.REDLINE_RPM)
end

local function wantsReverse(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.brake > 0 and controls.throttle == 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

local function wantsForward(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.throttle > 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

-- Devuelve la marcha y el tiempo que le queda al cambio. Un cambio nuevo solo puede empezar cuando terminó el anterior.
function Drivetrain.nextGear(
	state: VehicleState,
	rpm: number,
	forwardSpeed: number,
	controls: VehicleControls,
	dt: number,
	config: VehicleSettings?
): (number, number)
	local settings = config or VehicleConfig
	local remaining = math.max(0, state.shiftRemainingSeconds - dt)
	local gear = state.gear
	if gear == REVERSE_GEAR then
		return if wantsForward(controls, forwardSpeed, settings) then FIRST_GEAR else gear, remaining
	end
	if wantsReverse(controls, forwardSpeed, settings) then
		return REVERSE_GEAR, remaining
	end
	if remaining > 0 then
		return gear, remaining
	end
	if rpm >= settings.UPSHIFT_RPM and gear < #settings.GEAR_RATIOS then
		return gear + 1, settings.SHIFT_DURATION_SECONDS
	end
	if rpm <= settings.DOWNSHIFT_RPM and gear > FIRST_GEAR then
		return gear - 1, settings.SHIFT_DURATION_SECONDS
	end
	return gear, remaining
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
	local limiterFactor = math.clamp((settings.REDLINE_RPM - rpm) / settings.SOFT_LIMITER_RPM, 0, 1)
	if limiterFactor == 0 then
		return 0
	end
	local drivePedal = resolvePedals(state.gear, controls)
	local gearMultiplier = ratioOf(state.gear, settings) / settings.GEAR_RATIOS[FIRST_GEAR]
	local magnitude = mass
		* settings.FIRST_GEAR_PEAK_ACCELERATION
		* Drivetrain.torqueFraction(rpm, config)
		* gearMultiplier
		* drivePedal
		* limiterFactor
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

-- Con el pedal frenan las cuatro ruedas; con solo el freno de mano, las dos traseras. El tope por paso se reparte entre ellas.
local function brakingWheelCount(brakePedal: number, controls: VehicleControls, settings: VehicleSettings): number
	if brakePedal > 0 or not controls.isHandbrakeOn then
		return #settings.WHEELS
	end
	local rearCount = 0
	for _, wheel in settings.WHEELS do
		rearCount += if wheel.isFront then 0 else 1
	end
	return rearCount
end

-- Fuerza de frenado de una rueda. Va contra la velocidad longitudinal (prevista al final del cuadro) de esa rueda y nunca supera
-- lo que hace falta para pararla en un paso: cerca de 0 es esa fuerza, no una rampa con la velocidad. El freno de mano actúa solo atrás.
function Drivetrain.brakeForce(
	state: VehicleState,
	controls: VehicleControls,
	mass: number,
	isFront: boolean,
	longitudinalSpeed: number,
	load: number,
	dt: number,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	local _, brakePedal = resolvePedals(state.gear, controls)
	local axleShare = if isFront then settings.BRAKE_FRONT_BIAS else 1 - settings.BRAKE_FRONT_BIAS
	local maxForce = brakePedal * mass * settings.BRAKE_DECELERATION * axleShare * WHEEL_SHARE_OF_AXLE
	if controls.isHandbrakeOn and not isFront then
		maxForce += settings.HANDBRAKE_FORCE_PER_LOAD * load
	end
	local limit =
		VehicleMath.opposingForceLimit(mass, brakingWheelCount(brakePedal, controls, settings), longitudinalSpeed, dt)
	return -math.sign(longitudinalSpeed) * math.min(maxForce, limit)
end

return Drivetrain
