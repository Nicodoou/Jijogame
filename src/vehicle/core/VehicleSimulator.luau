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
local StepOutputs = require("./StepOutputs")
local Suspension = require("./Suspension")
local Tire = require("./Tire")
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")
local WeightDistribution = require("./WeightDistribution")
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
	settings: VehicleSettings,
	stepSeconds: number,
	rearGripFactor: number,
	gear: number
): WheelForces.StepContext
	local forwardSpeed = vector.dot(chassis.linearVelocity, chassis.forward)
	local driftAngle = Tire.slipAngle(vector.dot(chassis.linearVelocity, chassis.right), forwardSpeed, settings)
	local speed = vector.magnitude(chassis.linearVelocity)
	local isReversing = gear < 0
	local maxSteer = if isReversing
		then Steering.reverseMaxAngle(settings)
		else Steering.maxAngleWhileDrifting(speed, driftAngle, settings)
	local baseSteer = if isReversing then controls.steer * maxSteer else Steering.angle(controls.steer, speed, settings)
	local requestedSteer = baseSteer + Assists.counterSteer(driftAngle, forwardSpeed, settings)
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
		loadShares = WeightDistribution.wheelShares(chassis, settings),
		velocities = velocities,
		stepSeconds = stepSeconds,
		rearGripFactor = rearGripFactor,
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
		wheels[index], loads[index] = Suspension.step(
			gripped,
			contact,
			compressionSpeed,
			context.mass,
			context.gravity,
			dt,
			context.settings,
			context.loadShares[index]
		)
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
	local secondsSinceUpshift, previousSpeed, acceleration =
		Drivetrain.nextMemory(state, gear, context.forwardSpeed, dt, settings)
	local driveState: VehicleState = {
		wheels = state.wheels,
		gear = gear,
		shiftRemainingSeconds = shiftRemaining,
		engineRpm = rpm,
		rearGripFactor = state.rearGripFactor,
		secondsSinceUpshift = secondsSinceUpshift,
		previousForwardSpeed = previousSpeed,
		filteredAcceleration = acceleration,
	}
	local force = Drivetrain.driveForce(driveState, context.controls, rpm, context.mass, settings)
	return driveState, Drivetrain.split(force, settings)
end

function VehicleSimulator.newState(config: VehicleSettings?): VehicleState
	local settings = config or VehicleConfig
	local wheels = {}
	for index = 1, #settings.WHEELS do
		wheels[index] = SurfaceGrip.newWheelState(settings)
	end
	return {
		wheels = wheels,
		gear = 1,
		shiftRemainingSeconds = 0,
		engineRpm = settings.IDLE_RPM,
		rearGripFactor = 1,
		secondsSinceUpshift = settings.GEAR_HOLD_SECONDS,
		previousForwardSpeed = nil,
		filteredAcceleration = 0,
	}
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
	local isUsable = VehicleMath.isUsableStep(dt)
	local stepSeconds = if isUsable then math.min(dt, settings.MAX_STEP_SECONDS) else 0
	local safeControls = sanitizeControls(controls)
	local rearGripFactor = if isUsable
		then SurfaceGrip.nextRearGripFactor(state.rearGripFactor, safeControls.isHandbrakeOn, stepSeconds, settings)
		else state.rearGripFactor
	local context = buildContext(safeControls, chassis, contacts, settings, stepSeconds, rearGripFactor, state.gear)
	if not isUsable then
		return StepOutputs.idleStep(state, context)
	end
	local wheels, loads = updateWheels(state, contacts, context, stepSeconds)
	local driveState, driveShares = advanceDrivetrain(state, context, stepSeconds)
	local outputs, feedbacks = WheelForces.simulateWheels(context, wheels, loads, contacts, driveState, driveShares)
	local nextState: VehicleState = table.clone(driveState)
	nextState.wheels = wheels
	nextState.rearGripFactor = rearGripFactor
	return nextState, outputs, StepOutputs.buildFeedback(nextState, context, feedbacks)
end

return VehicleSimulator
