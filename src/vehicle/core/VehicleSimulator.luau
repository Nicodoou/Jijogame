--!strict
-- Un paso del auto: compone los otros módulos, sin física propia. Orden fijo:
--   1. recortar dt y las entradas;
--   2. ángulo de deriva y dirección más contravolante;
--   3. "arriba" del contacto (va antes de la suspensión porque la velocidad de compresión se proyecta sobre él);
--   4. por rueda: superficie y agarre, y después suspensión y carga (la carga es la fuerza de la suspensión);
--   5. caja y motor;
--   6. por rueda (WheelForces): ejes en el plano del contacto, deslizamiento, fuerza longitudinal (motor + freno +
--      resistencia al rodar), fuerza lateral y círculo de fricción;
--   7. fuerza total = suspensión · arriba + longitudinal · frente + lateral · costado (en el aire, 0);
--   8. feedback.
local Assists = require("./Assists")
local ContactPlane = require("./ContactPlane")
local Drivetrain = require("./Drivetrain")
local Steering = require("./Steering")
local SurfaceGrip = require("./SurfaceGrip")
local Suspension = require("./Suspension")
local Tire = require("./Tire")
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")
local WheelForces = require("./WheelForces")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState
type VehicleFeedback = VehicleTypes.VehicleFeedback
type WheelContact = VehicleTypes.WheelContact
type WheelFeedback = VehicleTypes.WheelFeedback
type WheelOutput = VehicleTypes.WheelOutput
type WheelState = VehicleTypes.WheelState
type SurfaceKind = VehicleTypes.SurfaceKind

local VehicleSimulator = {}

local NO_FORCE = vector.create(0, 0, 0)

local function sanitizeControls(controls: VehicleControls): VehicleControls
	return {
		steer = math.clamp(VehicleMath.finiteOr(controls.steer, 0), -1, 1),
		throttle = math.clamp(VehicleMath.finiteOr(controls.throttle, 0), 0, 1),
		brake = math.clamp(VehicleMath.finiteOr(controls.brake, 0), 0, 1),
		isHandbrakeOn = controls.isHandbrakeOn,
	}
end

local function buildContext(
	controls: VehicleControls,
	chassis: ChassisSample,
	contacts: { WheelContact? },
	settings: VehicleSettings
): WheelForces.StepContext
	local forwardSpeed = vector.dot(chassis.linearVelocity, chassis.forward)
	local driftAngle = Tire.slipAngle(vector.dot(chassis.linearVelocity, chassis.right), forwardSpeed, settings)
	local speed = vector.magnitude(chassis.linearVelocity)
	local maxSteer = Steering.maxAngle(speed, settings)
	local requestedSteer = Steering.angle(controls.steer, speed, settings)
		+ Assists.counterSteer(driftAngle, forwardSpeed, settings)
	local offsets, velocities = WheelForces.describeMounts(chassis, settings)
	return {
		settings = settings,
		controls = controls,
		chassis = chassis,
		mass = math.max(0, VehicleMath.finiteOr(chassis.mass, 0)),
		gravity = math.max(0, VehicleMath.finiteOr(chassis.gravity, 0)),
		forwardSpeed = forwardSpeed,
		driftAngle = driftAngle,
		steerAngle = math.clamp(requestedSteer, -maxSteer, maxSteer),
		contactUp = ContactPlane.upDirection(ContactPlane.hitPoints(contacts, settings), chassis.up, settings),
		offsets = offsets,
		velocities = velocities,
	}
end

local function updateWheels(
	state: VehicleState,
	contacts: { WheelContact? },
	context: WheelForces.StepContext,
	dt: number
): ({ WheelState }, { number })
	local wheels, loads = {}, {}
	for index = 1, #context.settings.WHEELS do
		local contact = contacts[index]
		local surface: SurfaceKind? = if contact ~= nil and contact.hasHit then contact.surface else nil
		local gripped = SurfaceGrip.step(state.wheels[index], surface, dt, context.settings)
		local compressionSpeed = -vector.dot(context.velocities[index], context.contactUp)
		wheels[index], loads[index] =
			Suspension.step(gripped, contact, compressionSpeed, context.mass, context.gravity, dt, context.settings)
	end
	return wheels, loads
end

local function advanceDrivetrain(
	state: VehicleState,
	context: WheelForces.StepContext,
	dt: number
): (VehicleState, { number })
	local settings = context.settings
	local rpmBefore = Drivetrain.engineRpm(context.forwardSpeed, state.gear, settings)
	local gear, shiftRemaining =
		Drivetrain.nextGear(state, rpmBefore, context.forwardSpeed, context.controls, dt, settings)
	local rpm = Drivetrain.engineRpm(context.forwardSpeed, gear, settings)
	local driveState: VehicleState =
		{ wheels = state.wheels, gear = gear, shiftRemainingSeconds = shiftRemaining, engineRpm = rpm }
	local force = Drivetrain.driveForce(driveState, context.controls, rpm, context.mass, settings)
	return driveState, Drivetrain.split(force, settings)
end

local function buildFeedback(
	state: VehicleState,
	context: WheelForces.StepContext,
	wheels: { WheelFeedback }
): VehicleFeedback
	local settings = context.settings
	local speed = vector.magnitude(context.chassis.linearVelocity)
	local driftLimit = math.rad(settings.DRIFT_ANGLE_THRESHOLD_DEGREES)
	return {
		speedStudsPerSecond = speed,
		forwardSpeedStudsPerSecond = context.forwardSpeed,
		engineRpm = state.engineRpm,
		gear = state.gear,
		isShifting = state.shiftRemainingSeconds > 0,
		driftAngleRadians = context.driftAngle,
		isDrifting = math.abs(context.driftAngle) > driftLimit and speed > settings.DRIFT_MIN_SPEED,
		wheels = wheels,
	}
end

-- Con un dt inutilizable el estado queda igual y las fuerzas en cero.
local function idleStep(
	state: VehicleState,
	context: WheelForces.StepContext
): (VehicleState, { WheelOutput }, VehicleFeedback)
	local outputs, feedbacks, wheels = {}, {}, {}
	for index, wheel in state.wheels do
		wheels[index] = table.clone(wheel)
		outputs[index] = {
			force = NO_FORCE,
			isGrounded = wheel.isGrounded,
			steerAngleRadians = 0,
			compressionStuds = wheel.compressionStuds,
			spinRadiansPerSecond = 0,
		}
		feedbacks[index] = { slipRatio = 0, slipAngleRadians = 0, isSliding = false, surface = nil }
	end
	local nextState: VehicleState = {
		wheels = wheels,
		gear = state.gear,
		shiftRemainingSeconds = state.shiftRemainingSeconds,
		engineRpm = state.engineRpm,
	}
	return nextState, outputs, buildFeedback(nextState, context, feedbacks)
end

function VehicleSimulator.newState(config: VehicleSettings?): VehicleState
	local settings = config or VehicleConfig
	local wheels = {}
	for index = 1, #settings.WHEELS do
		wheels[index] = SurfaceGrip.newWheelState(settings)
	end
	return { wheels = wheels, gear = 1, shiftRemainingSeconds = 0, engineRpm = settings.IDLE_RPM }
end

function VehicleSimulator.step(
	state: VehicleState,
	controls: VehicleControls,
	chassis: ChassisSample,
	contacts: { WheelContact? },
	dt: number,
	config: VehicleSettings?
): (VehicleState, { WheelOutput }, VehicleFeedback)
	local settings = config or VehicleConfig
	local context = buildContext(sanitizeControls(controls), chassis, contacts, settings)
	if not VehicleMath.isUsableStep(dt) then
		return idleStep(state, context)
	end
	local stepSeconds = math.min(dt, settings.MAX_STEP_SECONDS)
	local wheels, loads = updateWheels(state, contacts, context, stepSeconds)
	local driveState, driveShares = advanceDrivetrain(state, context, stepSeconds)
	local outputs, feedbacks = WheelForces.simulateWheels(context, wheels, loads, contacts, driveState, driveShares)
	local nextState: VehicleState = {
		wheels = wheels,
		gear = driveState.gear,
		shiftRemainingSeconds = driveState.shiftRemainingSeconds,
		engineRpm = driveState.engineRpm,
	}
	return nextState, outputs, buildFeedback(nextState, context, feedbacks)
end

return VehicleSimulator
