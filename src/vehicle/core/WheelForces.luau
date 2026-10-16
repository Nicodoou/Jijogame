--!strict
-- Fuerza de cada rueda a partir de su carga, la velocidad de su punto de montaje y el reparto de tracción.
-- Lo usa VehicleSimulator en el paso 6 y 7 de su orden.
local Tire = require("./Tire")
local VehicleTypes = require("./VehicleTypes")
local WeightDistribution = require("./WeightDistribution")
local WheelFriction = require("./WheelFriction")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState
type WheelContact = VehicleTypes.WheelContact
type WheelFeedback = VehicleTypes.WheelFeedback
type WheelOutput = VehicleTypes.WheelOutput
type WheelState = VehicleTypes.WheelState

export type StepContext = VehicleTypes.StepContext

local WheelForces = {}

local NO_FORCE = vector.create(0, 0, 0)

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

local function groundedWheel(
	context: StepContext,
	index: number,
	wheel: WheelState,
	load: number,
	driveShare: number,
	driveState: VehicleState,
	scale: number
): (WheelOutput, WheelFeedback)
	local settings = context.settings
	local isFront = settings.WHEELS[index].isFront
	local steerAngle = if isFront then context.steerAngle else 0
	local forwardAxis, sideAxis = WheelFriction.wheelAxes(context.chassis, context.contactUp, steerAngle)
	local velocity = context.velocities[index]
	local longitudinalSpeed, lateralSpeed = WheelFriction.expectedSpeeds(context, velocity, forwardAxis, sideAxis)
	local slipAngle = Tire.slipAngle(lateralSpeed, longitudinalSpeed, settings)
	local brakeAndRolling =
		WheelFriction.opposingLongitudinal(context, wheel, isFront, longitudinalSpeed, load, driveState, scale)
	local grip = wheel.gripMultiplier * WheelFriction.axleGripMultiplier(context, isFront)
	local limitedLateral = WheelFriction.opposingLateral(context, slipAngle, lateralSpeed, load, grip)
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
	local scale = WheelFriction.longitudinalScale(context, wheels, loads, driveState)
	for index, wheel in wheels do
		local steerAngle = if context.settings.WHEELS[index].isFront then context.steerAngle else 0
		local output, feedback
		if wheel.isGrounded then
			output, feedback = groundedWheel(context, index, wheel, loads[index], driveShares[index], driveState, scale)
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
