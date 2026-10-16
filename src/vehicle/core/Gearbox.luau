--!strict
-- Caja automática (CP-4): cuándo subir y bajar de marcha, con histéresis y kickdown. El motor y su curva están en
-- `Drivetrain`. El kickdown decide con la carga exacta de la cuesta (ver `docs/wp/WP-10-kickdown.md`).
local Drivetrain = require("./Drivetrain")
local VehicleConfig = require("./VehicleConfig")
local VehicleTypes = require("./VehicleTypes")

type VehicleState = VehicleTypes.VehicleState
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings

local Gearbox = {}

local REVERSE_GEAR = -1
local FIRST_GEAR = 1

local function wantsReverse(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.brake > 0 and controls.throttle == 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

local function wantsForward(controls: VehicleControls, forwardSpeed: number, settings: VehicleSettings): boolean
	return controls.throttle > 0 and math.abs(forwardSpeed) < settings.REVERSE_ENGAGE_SPEED
end

-- Inclinación del auto (componente vertical de su frente) filtrada con `1 − exp(−k·dt)`, para que el cabeceo de la
-- suspensión no mueva la carga estimada. Sin valor anterior (primer paso) o si no es finita, vale la actual (o 0).
function Gearbox.filteredSlope(state: VehicleState, forwardY: number, dt: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local current = if forwardY == forwardY and math.abs(forwardY) ~= math.huge then forwardY else 0
	local previous = state.filteredForwardY
	if previous == nil then
		return current
	end
	local alpha = 1 - math.exp(-settings.LOAD_PITCH_FILTER_RATE * dt)
	return previous + (current - previous) * alpha
end

-- Carga por unidad de masa a lo largo del auto (studs/s²): la gravedad de la pendiente (`forwardY` > 0 es cuesta
-- arriba) más la resistencia al rodar. Es exacta y sin atraso, al contrario de estimarla desde la aceleración.
function Gearbox.load(filteredForwardY: number, gravity: number, rollingResistance: number): number
	return gravity * (filteredForwardY + rollingResistance)
end

-- Memoria de la caja tras un paso: tiempo desde la última subida e inclinación filtrada.
function Gearbox.nextMemory(
	state: VehicleState,
	newGear: number,
	forwardY: number,
	dt: number,
	config: VehicleSettings?
): (number, number)
	local secondsSinceUpshift = if newGear > state.gear then 0 else state.secondsSinceUpshift + dt
	return secondsSinceUpshift, Gearbox.filteredSlope(state, forwardY, dt, config)
end

-- Aceleración (studs/s²) que daría esa marcha a esa velocidad con ese pedal.
local function thrustAcceleration(gear: number, forwardSpeed: number, pedal: number, settings: VehicleSettings): number
	return settings.FIRST_GEAR_PEAK_ACCELERATION * Drivetrain.gearForce(gear, forwardSpeed, settings) * pedal
end

-- Kickdown: a fondo, con la marcha actual sin margen para acelerar con la carga y pasado el tiempo mínimo desde la
-- última subida, baja directamente a la marcha más alta que todavía acelere `KICKDOWN_ACCEL_MARGIN` y tenga
-- RPM ≤ `KICKDOWN_MAX_RPM`. Si ninguna cumple, a la más baja que respete las RPM. Puede saltar varias marchas; las
-- bajadas no esperan a otra bajada. Devuelve la marcha de destino, o nil si no hay kickdown.
local function kickdownTarget(
	state: VehicleState,
	forwardSpeed: number,
	pedal: number,
	load: number,
	dt: number,
	settings: VehicleSettings
): number?
	if state.gear <= FIRST_GEAR or state.secondsSinceUpshift + dt < settings.GEAR_HOLD_SECONDS then
		return nil
	end
	if thrustAcceleration(state.gear, forwardSpeed, pedal, settings) - load >= settings.KICKDOWN_ACCEL_MARGIN then
		return nil
	end
	local lowestWithinLimit = nil
	for below = state.gear - 1, FIRST_GEAR, -1 do
		if Drivetrain.rawRpm(forwardSpeed, below, settings) <= settings.KICKDOWN_MAX_RPM then
			if thrustAcceleration(below, forwardSpeed, pedal, settings) - load >= settings.KICKDOWN_ACCEL_MARGIN then
				return below
			end
			lowestWithinLimit = below
		end
	end
	return lowestWithinLimit
end

-- A fondo sube (por RPM o en el corte suave) solo si la marcha de arriba, a la velocidad que va a tener después del
-- corte (no hay empuje durante el cambio), todavía acelera `UPSHIFT_ACCEL_MARGIN` con la carga.
local function shouldUpshiftAtFullThrottle(
	state: VehicleState,
	forwardSpeed: number,
	pedal: number,
	load: number,
	settings: VehicleSettings
): boolean
	local speedAfterShift = forwardSpeed - load * settings.SHIFT_DURATION_SECONDS
	return thrustAcceleration(state.gear + 1, speedAfterShift, pedal, settings) - load >= settings.UPSHIFT_ACCEL_MARGIN
end

-- Marcha de la reversa arcade: con el freno apretado y casi quieto entra en reversa, y con el acelerador vuelve a 1ra.
-- Devuelve nil si el auto está en marcha adelante y no pide reversa.
local function reverseGear(
	state: VehicleState,
	controls: VehicleControls,
	forwardSpeed: number,
	settings: VehicleSettings
): number?
	if state.gear == REVERSE_GEAR then
		return if wantsForward(controls, forwardSpeed, settings) then FIRST_GEAR else REVERSE_GEAR
	end
	if wantsReverse(controls, forwardSpeed, settings) then
		return REVERSE_GEAR
	end
	return nil
end

-- Marcha que pide el acelerador: el kickdown a fondo, la subida (a fondo, solo si la de arriba sigue acelerando) o
-- la bajada por RPM con el acelerador suave. Devuelve nil si no cambia.
local function pedalGear(
	state: VehicleState,
	rpm: number,
	forwardSpeed: number,
	controls: VehicleControls,
	dt: number,
	load: number,
	settings: VehicleSettings
): number?
	local gear = state.gear
	local isKickdownPedal = controls.throttle >= settings.KICKDOWN_THROTTLE
	if isKickdownPedal then
		local kickdownGear = kickdownTarget(state, forwardSpeed, controls.throttle, load, dt, settings)
		if kickdownGear ~= nil then
			return kickdownGear
		end
	end
	if rpm >= settings.UPSHIFT_RPM and gear < #settings.GEAR_RATIOS then
		if
			not isKickdownPedal or shouldUpshiftAtFullThrottle(state, forwardSpeed, controls.throttle, load, settings)
		then
			return gear + 1
		end
	end
	if not isKickdownPedal and rpm <= settings.DOWNSHIFT_RPM and gear > FIRST_GEAR then
		return gear - 1
	end
	return nil
end

-- Devuelve la marcha y el tiempo que le queda al cambio. Un cambio nuevo solo puede empezar cuando terminó el anterior.
-- `load` es la carga por unidad de masa (`Gearbox.load`); sin ella (0) el kickdown no ve ninguna cuesta.
function Gearbox.nextGear(
	state: VehicleState,
	rpm: number,
	forwardSpeed: number,
	controls: VehicleControls,
	dt: number,
	config: VehicleSettings?,
	load: number?
): (number, number)
	local settings = config or VehicleConfig
	local remaining = math.max(0, state.shiftRemainingSeconds - dt)
	local reverse = reverseGear(state, controls, forwardSpeed, settings)
	if reverse ~= nil then
		return reverse, remaining
	end
	if remaining > 0 then
		return state.gear, remaining
	end
	local target = pedalGear(state, rpm, forwardSpeed, controls, dt, load or 0, settings)
	if target ~= nil then
		return target, settings.SHIFT_DURATION_SECONDS
	end
	return state.gear, remaining
end

return Gearbox
