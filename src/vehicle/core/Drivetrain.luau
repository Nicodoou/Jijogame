--!strict
-- Motor, caja automática, reparto de tracción y frenos (CP-4, CP-9 y T1). Sin inercia de rueda:
-- la fuerza longitudinal sale del motor y del freno, y el círculo de fricción del neumático la recorta.
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

-- RPM que tendría el motor en esa marcha, sin recortar al ralentí ni al corte.
local function unclampedRpm(forwardSpeed: number, gear: number, settings: VehicleSettings): number
	local wheelRevolutionsPerSecond = math.abs(forwardSpeed) / settings.WHEEL_RADIUS_STUDS / (2 * math.pi)
	return wheelRevolutionsPerSecond * SECONDS_PER_MINUTE * ratioOf(gear, settings) * settings.FINAL_DRIVE
end

function Drivetrain.engineRpm(forwardSpeed: number, gear: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	return math.min(math.max(unclampedRpm(forwardSpeed, gear, settings), settings.IDLE_RPM), settings.REDLINE_RPM)
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

local function wantsReverse(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.brake > 0 and controls.throttle == 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

local function wantsForward(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.throttle > 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

-- Aceleración hacia adelante filtrada con `1 − exp(−k·dt)`. Sin velocidad anterior (primer paso) no hay aceleración.
function Drivetrain.filteredAcceleration(
	state: VehicleState,
	forwardSpeed: number,
	dt: number,
	config: VehicleSettings?
): number
	local settings = config or VehicleConfig
	local previous = state.previousForwardSpeed
	if previous == nil then
		return state.filteredAcceleration
	end
	local alpha = 1 - math.exp(-settings.KICKDOWN_ACCEL_FILTER_RATE * dt)
	return state.filteredAcceleration + ((forwardSpeed - previous) / dt - state.filteredAcceleration) * alpha
end

-- Memoria de la caja tras un paso: tiempo desde la última subida, velocidad de este paso y aceleración filtrada.
function Drivetrain.nextMemory(
	state: VehicleState,
	newGear: number,
	forwardSpeed: number,
	dt: number,
	config: VehicleSettings?
): (number, number, number)
	local secondsSinceUpshift = if newGear > state.gear then 0 else state.secondsSinceUpshift + dt
	return secondsSinceUpshift, forwardSpeed, Drivetrain.filteredAcceleration(state, forwardSpeed, dt, config)
end

-- Aceleración (studs/s²) que daría esa marcha a esa velocidad con ese pedal.
local function thrustAcceleration(gear: number, forwardSpeed: number, pedal: number, settings: VehicleSettings): number
	return settings.FIRST_GEAR_PEAK_ACCELERATION * Drivetrain.gearForce(gear, forwardSpeed, settings) * pedal
end

-- Carga estimada por unidad de masa: lo que empuja la marcha actual menos lo que realmente acelera. Es la gravedad de
-- la pendiente, la resistencia al rodar y todo lo que se oponga.
local function estimatedLoad(
	state: VehicleState,
	forwardSpeed: number,
	pedal: number,
	acceleration: number,
	settings: VehicleSettings
): number
	return thrustAcceleration(state.gear, forwardSpeed, pedal, settings) - acceleration
end

-- Kickdown: a fondo, sin ganar velocidad y pasado el tiempo mínimo desde la última subida, baja directamente a la
-- marcha más alta que, con la carga estimada, todavía acelere `KICKDOWN_ACCEL_MARGIN` y tenga RPM ≤ `KICKDOWN_MAX_RPM`.
-- Si ninguna cumple, a la más baja que respete las RPM. Puede saltar varias marchas; las bajadas no esperan a otra bajada.
-- Devuelve la marcha de destino, o nil si no hay kickdown.
local function kickdownTarget(
	state: VehicleState,
	forwardSpeed: number,
	pedal: number,
	acceleration: number,
	dt: number,
	settings: VehicleSettings
): number?
	if state.gear <= FIRST_GEAR or state.secondsSinceUpshift + dt < settings.GEAR_HOLD_SECONDS then
		return nil
	end
	if acceleration > settings.KICKDOWN_MIN_ACCELERATION then
		return nil
	end
	local load = estimatedLoad(state, forwardSpeed, pedal, acceleration, settings)
	local lowestWithinLimit = nil
	for below = state.gear - 1, FIRST_GEAR, -1 do
		if unclampedRpm(forwardSpeed, below, settings) <= settings.KICKDOWN_MAX_RPM then
			if thrustAcceleration(below, forwardSpeed, pedal, settings) - load >= settings.KICKDOWN_ACCEL_MARGIN then
				return below
			end
			lowestWithinLimit = below
		end
	end
	return lowestWithinLimit
end

-- A fondo sube (por RPM o en el corte suave) solo si la marcha de arriba, a la velocidad que va a tener después del
-- corte (no hay empuje durante el cambio), todavía acelera `UPSHIFT_ACCEL_MARGIN` con la carga estimada.
local function shouldUpshiftAtFullThrottle(
	state: VehicleState,
	forwardSpeed: number,
	pedal: number,
	acceleration: number,
	settings: VehicleSettings
): boolean
	local load = estimatedLoad(state, forwardSpeed, pedal, acceleration, settings)
	local speedAfterShift = forwardSpeed - load * settings.SHIFT_DURATION_SECONDS
	return thrustAcceleration(state.gear + 1, speedAfterShift, pedal, settings) - load >= settings.UPSHIFT_ACCEL_MARGIN
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
	local isKickdownPedal = controls.throttle >= settings.KICKDOWN_THROTTLE
	local acceleration = Drivetrain.filteredAcceleration(state, forwardSpeed, dt, settings)
	local kickdownGear = nil
	if isKickdownPedal then
		kickdownGear = kickdownTarget(state, forwardSpeed, controls.throttle, acceleration, dt, settings)
	end
	if kickdownGear ~= nil then
		return kickdownGear, settings.SHIFT_DURATION_SECONDS
	end
	if rpm >= settings.UPSHIFT_RPM and gear < #settings.GEAR_RATIOS then
		local mayUpshift = not isKickdownPedal
			or shouldUpshiftAtFullThrottle(state, forwardSpeed, controls.throttle, acceleration, settings)
		if mayUpshift then
			return gear + 1, settings.SHIFT_DURATION_SECONDS
		end
	end
	if not isKickdownPedal and rpm <= settings.DOWNSHIFT_RPM and gear > FIRST_GEAR then
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
