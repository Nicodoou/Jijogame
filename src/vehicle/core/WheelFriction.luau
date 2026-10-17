--!strict
-- Las fuerzas de fricción de una rueda con su velocidad prevista al final del cuadro y el tope por paso. Lo usa
-- `WheelForces`. El tope de las fuerzas longitudinales que se oponen al movimiento se calcula acá y en ningún otro lado.
local Drivetrain = require("./Drivetrain")
local OpposingForces = require("./OpposingForces")
local Tire = require("./Tire")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample
type StepContext = VehicleTypes.StepContext
type VehicleState = VehicleTypes.VehicleState
type WheelState = VehicleTypes.WheelState

local WheelFriction = {}

local MIN_AXIS_LENGTH = 1e-4

-- Frente y costado de la rueda: el frente del chasis proyectado en el plano del contacto y girado por la dirección.
function WheelFriction.wheelAxes(chassis: ChassisSample, contactUp: vector, steerAngle: number): (vector, vector)
	local flat = chassis.forward - contactUp * vector.dot(chassis.forward, contactUp)
	local flatLength = vector.magnitude(flat)
	local baseForward = if flatLength >= MIN_AXIS_LENGTH then flat / flatLength else chassis.forward
	local baseSide = vector.cross(baseForward, contactUp)
	local cosine, sine = math.cos(steerAngle), math.sin(steerAngle)
	return baseForward * cosine + baseSide * sine, baseSide * cosine - baseForward * sine
end

-- Velocidad de la rueda en sus ejes al final del cuadro por la gravedad. Las fuerzas de fricción se calculan con
-- ella: así la fricción puede sostener el auto en una pendiente (quedarse quieto) sin invertir la velocidad.
function WheelFriction.expectedSpeeds(
	context: StepContext,
	velocity: vector,
	forwardAxis: vector,
	sideAxis: vector
): (number, number)
	local gravityPush = vector.create(0, -context.gravity * context.stepSeconds, 0)
	return vector.dot(velocity, forwardAxis) + vector.dot(gravityPush, forwardAxis),
		vector.dot(velocity, sideAxis) + vector.dot(gravityPush, sideAxis)
end

-- Lo que el tope común reparte y lo que hace falta para pedir cada rueda: el factor de escala y la resistencia del aire
-- por unidad de carga (que depende de la carga apoyada total).
export type LongitudinalPlan = { scale: number, airDragPerLoad: number }

-- Lo que piden el freno, el freno motor, el freno de mano que sostiene, la resistencia del aire y la resistencia al
-- rodar de una rueda, sin sentido ni tope (siempre positivo).
local function longitudinalRequest(
	context: StepContext,
	wheel: WheelState,
	isFront: boolean,
	load: number,
	driveState: VehicleState,
	airDragPerLoad: number
): number
	local settings = context.settings
	local brake = Drivetrain.brakeRequest(driveState, context.controls, context.mass, isFront, load, settings)
	local engineBrake = OpposingForces.engineBrake(driveState, context.controls, context.mass, isFront, settings)
	local hold = OpposingForces.handbrakeHold(context, isFront, load)
	return brake + engineBrake + hold + (wheel.rollingResistance + airDragPerLoad) * load
end

-- Única fuente del tope por paso de las fuerzas longitudinales que se oponen al movimiento (freno, freno motor, freno de
-- mano, resistencia del aire y resistencia al rodar): sumadas en todas las ruedas no pueden superar lo que para la
-- velocidad prevista del chasis en un paso (`masa · |v prevista| / dt`). El factor `scale` (de 0 a 1) escala todas, o sea
-- que el tope se reparte en proporción a lo que pide cada rueda.
function WheelFriction.longitudinalPlan(
	context: StepContext,
	wheels: { WheelState },
	loads: { number },
	driveState: VehicleState
): LongitudinalPlan
	local totalLoad = 0
	for index, wheel in wheels do
		totalLoad += if wheel.isGrounded then loads[index] else 0
	end
	local airDragPerLoad =
		OpposingForces.airDragPerLoad(context.forwardSpeed, context.mass, totalLoad, context.settings)
	local requested = 0
	for index, wheel in wheels do
		if wheel.isGrounded then
			local isFront = context.settings.WHEELS[index].isFront
			requested += longitudinalRequest(context, wheel, isFront, loads[index], driveState, airDragPerLoad)
		end
	end
	local chassisForward, chassisSide = WheelFriction.wheelAxes(context.chassis, context.contactUp, 0)
	local expectedSpeed =
		WheelFriction.expectedSpeeds(context, context.chassis.linearVelocity, chassisForward, chassisSide)
	local limit = VehicleMath.opposingForceLimit(context.mass, 1, expectedSpeed, context.stepSeconds)
	return { scale = if requested <= limit then 1 else limit / requested, airDragPerLoad = airDragPerLoad }
end

-- Lo que opone una rueda al movimiento (todo menos la tracción): va contra su velocidad prevista y se escala con el tope común.
function WheelFriction.opposingLongitudinal(
	context: StepContext,
	wheel: WheelState,
	isFront: boolean,
	longitudinalSpeed: number,
	load: number,
	driveState: VehicleState,
	plan: LongitudinalPlan
): number
	local request = longitudinalRequest(context, wheel, isFront, load, driveState, plan.airDragPerLoad)
	return -math.sign(longitudinalSpeed) * request * plan.scale
end

-- Agarre del eje: el trasero baja por su multiplicador y por el freno de mano.
function WheelFriction.axleGripMultiplier(context: StepContext, isFront: boolean): number
	if isFront then
		return context.settings.FRONT_GRIP_MULTIPLIER
	end
	return context.settings.REAR_GRIP_MULTIPLIER * context.rearGripFactor
end

function WheelFriction.opposingLateral(
	context: StepContext,
	index: number,
	slipAngle: number,
	lateralSpeed: number,
	load: number,
	grip: number
): number
	local settings = context.settings
	local limit =
		VehicleMath.opposingForceLimit(context.mass, context.loadShares[index], lateralSpeed, context.stepSeconds)
	return math.clamp(Tire.lateralForce(slipAngle, load, grip, settings), -limit, limit)
end

return WheelFriction
