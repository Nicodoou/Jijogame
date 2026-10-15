--!strict
-- Salidas de un paso que no son las fuerzas de las ruedas: el feedback y el resultado de un paso inutilizable.
local VehicleTypes = require("./VehicleTypes")
local WheelForces = require("./WheelForces")

type VehicleFeedback = VehicleTypes.VehicleFeedback
type VehicleState = VehicleTypes.VehicleState
type WheelFeedback = VehicleTypes.WheelFeedback
type WheelOutput = VehicleTypes.WheelOutput

local StepOutputs = {}

local NO_FORCE = vector.create(0, 0, 0)

function StepOutputs.buildFeedback(
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
function StepOutputs.idleStep(
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
		rearGripFactor = state.rearGripFactor,
	}
	return nextState, outputs, StepOutputs.buildFeedback(nextState, context, feedbacks)
end

return StepOutputs
