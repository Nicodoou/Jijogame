--!strict
-- Fuerza de cada rueda a partir de su carga, la velocidad de su punto de montaje y el reparto de tracción.
-- Lo usa VehicleSimulator en el paso 6 y 7 de su orden.
local Drivetrain = require("./Drivetrain")
local Tire = require("./Tire")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")
local WeightDistribution = require("./WeightDistribution")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState
type WheelContact = VehicleTypes.WheelContact
type WheelFeedback = VehicleTypes.WheelFeedback
type WheelOutput = VehicleTypes.WheelOutput
type WheelState = VehicleTypes.WheelState

export type StepContext = {
	settings: VehicleSettings,
	controls: VehicleControls,
	chassis: ChassisSample,
	mass: number,
	gravity: number,
	forwardSpeed: number,
	driftAngle: number,
	steerAngle: number,
	contactUp: vector,
	offsets: { vector },
	loadShares: { number },
	velocities: { vector },
	stepSeconds: number,
	rearGripFactor: number,
}

local WheelForces = {}

local NO_FORCE = vector.create(0, 0, 0)
local MIN_AXIS_LENGTH = 1e-4

-- El marco del chasis es el de Roblox: -z es adelante, así que un offset z positivo queda atrás.
local function mountOffset(chassis: ChassisSample, localOffset: vector): vector
	return chassis.right * localOffset.x + chassis.up * localOffset.y - chassis.forward * localOffset.z
end

-- Brazo de cada rueda desde el centro de masa y velocidad de su punto de montaje.
function WheelForces.describeMounts(chassis: ChassisSample, settings: VehicleSettings): ({ vector }, { vector })
	local offsets, velocities = {}, {}
	local originArm = WeightDistribution.frameOrigin(chassis) - chassis.position
	for index, wheel in settings.WHEELS do
		offsets[index] = originArm + mountOffset(chassis, wheel.offset)
		velocities[index] = chassis.linearVelocity + vector.cross(chassis.angularVelocity, offsets[index])
	end
	return offsets, velocities
end

-- Frente y costado de la rueda: el frente del chasis proyectado en el plano del contacto y girado por la dirección.
local function wheelAxes(chassis: ChassisSample, contactUp: vector, steerAngle: number): (vector, vector)
	local flat = chassis.forward - contactUp * vector.dot(chassis.forward, contactUp)
	local flatLength = vector.magnitude(flat)
	local baseForward = if flatLength >= MIN_AXIS_LENGTH then flat / flatLength else chassis.forward
	local baseSide = vector.cross(baseForward, contactUp)
	local cosine, sine = math.cos(steerAngle), math.sin(steerAngle)
	return baseForward * cosine + baseSide * sine, baseSide * cosine - baseForward * sine
end

local function airborneWheel(context: StepContext, wheel: WheelState, steerAngle: number): (WheelOutput, WheelFeedback)
	local output: WheelOutput = {
		force = NO_FORCE,
		isGrounded = false,
		steerAngleRadians = steerAngle,
		compressionStuds = wheel.compressionStuds,
		spinRadiansPerSecond = context.forwardSpeed / context.settings.WHEEL_RADIUS_STUDS,
	}
	return output, { slipRatio = 0, slipAngleRadians = 0, isSliding = false, surface = nil }
end

-- Velocidad de la rueda en sus ejes al final del cuadro por la gravedad. Las fuerzas de fricción se calculan con
-- ella: así la fricción puede sostener el auto en una pendiente (quedarse quieto) sin invertir la velocidad.
local function expectedSpeeds(
	context: StepContext,
	velocity: vector,
	forwardAxis: vector,
	sideAxis: vector
): (number, number)
	local gravityPush = vector.create(0, -context.gravity * context.stepSeconds, 0)
	return vector.dot(velocity, forwardAxis) + vector.dot(gravityPush, forwardAxis),
		vector.dot(velocity, sideAxis) + vector.dot(gravityPush, sideAxis)
end

-- Freno y resistencia al rodar de una rueda, con el tope por paso compartido: juntos no pueden frenar
-- más de lo que la rueda lleva de velocidad.
local function opposingLongitudinal(
	context: StepContext,
	wheel: WheelState,
	isFront: boolean,
	longitudinalSpeed: number,
	load: number,
	driveState: VehicleState
): number
	local settings = context.settings
	local brake = Drivetrain.brakeForce(
		driveState,
		context.controls,
		context.mass,
		isFront,
		longitudinalSpeed,
		load,
		context.stepSeconds,
		settings
	)
	local limit = VehicleMath.opposingForceLimit(context.mass, #settings.WHEELS, longitudinalSpeed, context.stepSeconds)
	local rolling = math.min(wheel.rollingResistance * load, math.max(0, limit - math.abs(brake)))
	return brake - math.sign(longitudinalSpeed) * rolling
end

-- Agarre del eje: el trasero baja por su multiplicador y por el freno de mano.
local function axleGripMultiplier(context: StepContext, isFront: boolean): number
	if isFront then
		return context.settings.FRONT_GRIP_MULTIPLIER
	end
	return context.settings.REAR_GRIP_MULTIPLIER * context.rearGripFactor
end

local function opposingLateral(
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

local function groundedWheel(
	context: StepContext,
	index: number,
	wheel: WheelState,
	load: number,
	driveShare: number,
	driveState: VehicleState
): (WheelOutput, WheelFeedback)
	local settings = context.settings
	local isFront = settings.WHEELS[index].isFront
	local steerAngle = if isFront then context.steerAngle else 0
	local forwardAxis, sideAxis = wheelAxes(context.chassis, context.contactUp, steerAngle)
	local velocity = context.velocities[index]
	local longitudinalSpeed, lateralSpeed = expectedSpeeds(context, velocity, forwardAxis, sideAxis)
	local slipAngle = Tire.slipAngle(lateralSpeed, longitudinalSpeed, settings)
	local brakeAndRolling = opposingLongitudinal(context, wheel, isFront, longitudinalSpeed, load, driveState)
	local grip = wheel.gripMultiplier * axleGripMultiplier(context, isFront)
	local limitedLateral = opposingLateral(context, slipAngle, lateralSpeed, load, grip)
	local longitudinal, lateral, slipRatio, isSliding = Tire.combine(
		driveShare + brakeAndRolling,
		limitedLateral,
		load,
		grip,
		Tire.linearLateralForce(slipAngle, load, settings),
		settings
	)
	local output: WheelOutput = {
		force = context.contactUp * load + forwardAxis * longitudinal + sideAxis * lateral,
		isGrounded = true,
		steerAngleRadians = steerAngle,
		compressionStuds = wheel.compressionStuds,
		spinRadiansPerSecond = vector.dot(velocity, forwardAxis) / settings.WHEEL_RADIUS_STUDS,
	}
	return output, { slipRatio = slipRatio, slipAngleRadians = slipAngle, isSliding = isSliding, surface = nil }
end

function WheelForces.simulateWheels(
	context: StepContext,
	wheels: { WheelState },
	loads: { number },
	contacts: { WheelContact? },
	driveState: VehicleState,
	driveShares: { number }
): ({ WheelOutput }, { WheelFeedback })
	local outputs, feedbacks = {}, {}
	for index, wheel in wheels do
		local steerAngle = if context.settings.WHEELS[index].isFront then context.steerAngle else 0
		local output, feedback
		if wheel.isGrounded then
			output, feedback = groundedWheel(context, index, wheel, loads[index], driveShares[index], driveState)
		else
			output, feedback = airborneWheel(context, wheel, steerAngle)
		end
		local contact = contacts[index]
		feedback.surface = if contact ~= nil and contact.hasHit then contact.surface else nil
		outputs[index], feedbacks[index] = output, feedback
	end
	return outputs, feedbacks
end

return WheelForces
