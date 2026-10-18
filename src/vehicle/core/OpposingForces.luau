--!strict
-- Las fuerzas longitudinales que se oponen al movimiento y no son el pedal de freno: freno motor, resistencia del aire
-- y freno de mano que sostiene (WP-17). Piden fuerza siempre positiva; el sentido y el tope por paso los pone
-- `WheelFriction`, igual que con el freno y la resistencia al rodar.
local VehicleTypes = require("./VehicleTypes")

type StepContext = VehicleTypes.StepContext
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState

local OpposingForces = {}

local REVERSE_GEAR = -1
local FIRST_GEAR = 1
-- Cada eje tiene dos ruedas y se reparte en partes iguales.
local WHEEL_SHARE_OF_AXLE = 0.5

-- En reversa el pedal que acelera es el de freno.
local function drivePedal(gear: number, controls: VehicleControls): number
	return if gear == REVERSE_GEAR then controls.brake else controls.throttle
end

local function gearRatio(gear: number, settings: VehicleSettings): number
	return if gear == REVERSE_GEAR then settings.REVERSE_RATIO else settings.GEAR_RATIOS[gear]
end

-- Freno motor de una rueda: solo en las ruedas con tracción, con marcha puesta, sin cambiar y con las RPM por encima
-- de `ENGINE_BRAKE_MIN_RPM` (abajo el embrague se abre). Escala con el pedal soltado, las RPM y la relación de la marcha.
function OpposingForces.engineBrake(
	state: VehicleState,
	controls: VehicleControls,
	mass: number,
	isFront: boolean,
	settings: VehicleSettings
): number
	if state.shiftRemainingSeconds > 0 or state.engineRpm < settings.ENGINE_BRAKE_MIN_RPM then
		return 0
	end
	local rpmFraction =
		math.clamp((state.engineRpm - settings.IDLE_RPM) / (settings.REDLINE_RPM - settings.IDLE_RPM), 0, 1)
	local gearFactor = gearRatio(state.gear, settings) / settings.GEAR_RATIOS[FIRST_GEAR]
	local axleShare = if isFront then 1 - settings.REAR_BIAS else settings.REAR_BIAS
	local released = 1 - math.clamp(drivePedal(state.gear, controls), 0, 1)
	return mass
		* settings.ENGINE_BRAKE_DECELERATION
		* rpmFraction
		* gearFactor
		* released
		* axleShare
		* WHEEL_SHARE_OF_AXLE
end

-- Resistencia del aire por unidad de carga apoyada: la fuerza total (masa · k · v²) repartida en proporción a la carga.
function OpposingForces.airDragPerLoad(
	forwardSpeed: number,
	mass: number,
	totalLoad: number,
	settings: VehicleSettings
): number
	if totalLoad <= 0 then
		return 0
	end
	return mass * settings.AIR_DRAG_PER_SPEED_SQUARED * forwardSpeed * forwardSpeed / totalLoad
end

-- Lo que el freno de mano que sostiene suma al pedido de una rueda: casi quieto y sin derrapar, frena las cuatro ruedas
-- (atrás ya frenaba con `HANDBRAKE_FORCE_PER_LOAD`, que no se cuenta dos veces). Si no sostiene, suma 0.
function OpposingForces.handbrakeHold(context: StepContext, isFront: boolean, load: number): number
	local settings = context.settings
	local isSlow = vector.magnitude(context.chassis.linearVelocity) < settings.HANDBRAKE_HOLD_SPEED
	local isStraight = math.abs(context.driftAngle) < math.rad(settings.HANDBRAKE_HOLD_MAX_DRIFT_DEGREES)
	if not (context.controls.isHandbrakeOn and isSlow and isStraight) then
		return 0
	end
	local alreadyBraking = if isFront then 0 else settings.HANDBRAKE_FORCE_PER_LOAD
	return math.max(0, settings.HANDBRAKE_HOLD_FORCE_PER_LOAD - alreadyBraking) * load
end

return OpposingForces
