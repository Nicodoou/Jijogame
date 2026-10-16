--!strict
-- Las fuerzas de fricción de una rueda con su velocidad prevista al final del cuadro y el tope por paso. Lo usa
-- `WheelForces`. El tope de las fuerzas longitudinales que se oponen al movimiento se calcula acá y en ningún otro lado.
local Drivetrain = require("./Drivetrain")
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

-- Lo que piden el freno y la resistencia al rodar de una rueda, sin sentido ni tope (siempre positivo).
local function longitudinalRequest(
	context: StepContext,
	wheel: WheelState,
	isFront: boolean,
	load: number,
	driveState: VehicleState
): number
	local brake = Drivetrain.brakeRequest(driveState, context.controls, context.mass, isFront, load, context.settings)
	return brake + wheel.rollingResistance * load
end

-- Única fuente del tope por paso de las fuerzas longitudinales que se oponen al movimiento (freno, freno de mano y
-- resistencia al rodar): sumadas en todas las ruedas no pueden superar lo que para la velocidad prevista del chasis
-- en un paso (`masa · |v prevista| / dt`). Devuelve el factor (de 0 a 1) por el que se escalan todas, o sea que el
-- tope se reparte en proporción a lo que pide cada rueda.
function WheelFriction.longitudinalScale(
	context: StepContext,
	wheels: { WheelState },
	loads: { number },
	driveState: VehicleState
): number
	local requested = 0
	for index, wheel in wheels do
		if wheel.isGrounded then
			local isFront = context.settings.WHEELS[index].isFront
			requested += longitudinalRequest(context, wheel, isFront, loads[index], driveState)
		end
	end
	local chassisForward, chassisSide = WheelFriction.wheelAxes(context.chassis, context.contactUp, 0)
	local expectedSpeed =
		WheelFriction.expectedSpeeds(context, context.chassis.linearVelocity, chassisForward, chassisSide)
	local limit = VehicleMath.opposingForceLimit(context.mass, 1, expectedSpeed, context.stepSeconds)
	if requested <= limit then
		return 1
	end
	return limit / requested
end

-- Freno y resistencia al rodar de una rueda: van contra su velocidad prevista y se escalan con el tope común.
function WheelFriction.opposingLongitudinal(
	context: StepContext,
	wheel: WheelState,
	isFront: boolean,
	longitudinalSpeed: number,
	load: number,
	driveState: VehicleState,
	scale: number
): number
	return -math.sign(longitudinalSpeed) * longitudinalRequest(context, wheel, isFront, load, driveState) * scale
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
	slipAngle: number,
	lateralSpeed: number,
	load: number,
	grip: number
): number
	local settings = context.settings
	local limit = VehicleMath.opposingForceLimit(context.mass, #settings.WHEELS, lateralSpeed, context.stepSeconds)
	return math.clamp(Tire.lateralForce(slipAngle, load, grip, settings), -limit, limit)
end

return WheelFriction
