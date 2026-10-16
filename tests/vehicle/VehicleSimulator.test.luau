--!strict
local Runner = require("../Runner")
local Suspension = require("../../src/vehicle/core/Suspension")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local Steering = require("../../src/vehicle/core/Steering")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")
local WheelForces = require("../../src/vehicle/core/WheelForces")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleControls = VehicleTypes.VehicleControls
type VehicleState = VehicleTypes.VehicleState
type WheelContact = VehicleTypes.WheelContact

local MASS = 1000
local GRAVITY = 196.2
local FRAME_SECONDS = 1 / 30
local REACH = VehicleConfig.SUSPENSION_REST_LENGTH_STUDS + VehicleConfig.WHEEL_RADIUS_STUDS
local ZERO = vector.create(0, 0, 0)
-- Velocidad lateral con la que el agarre trasero, y no el tope por paso, limita la fuerza lateral.
local SLIDE_SIDE_SPEED = 20

local function chassisWith(velocity: vector?, angularVelocity: vector?): ChassisSample
	return {
		origin = vector.create(0, 4, 0),
		position = vector.create(0, 4, 0),
		right = vector.create(1, 0, 0),
		up = vector.create(0, 1, 0),
		forward = vector.create(0, 0, -1),
		linearVelocity = velocity or ZERO,
		angularVelocity = angularVelocity or ZERO,
		mass = MASS,
		gravity = GRAVITY,
	}
end

local function controlsWith(steer: number, throttle: number, brake: number, isHandbrakeOn: boolean?): VehicleControls
	return { steer = steer, throttle = throttle, brake = brake, isHandbrakeOn = isHandbrakeOn or false }
end

-- Contactos de las cuatro ruedas con la compresión estática, sobre suelo plano.
local function restingContacts(): { WheelContact? }
	local angularFrequency = 2 * math.pi * VehicleConfig.SUSPENSION_FREQUENCY_HZ
	local staticCompression = GRAVITY / (angularFrequency * angularFrequency)
	local contacts: { WheelContact? } = {}
	for index, wheel in VehicleConfig.WHEELS do
		local point = vector.create(wheel.offset.x, -1 - (REACH - staticCompression), wheel.offset.z)
		contacts[index] = { hasHit = true, distanceStuds = REACH - staticCompression, point = point, surface = "Road" }
	end
	return contacts
end

local function stepAtRest(controls: VehicleControls, chassis: ChassisSample)
	return VehicleSimulator.step(VehicleSimulator.newState(), controls, chassis, restingContacts(), FRAME_SECONDS)
end

local function isFiniteVector(value: vector): boolean
	local total = value.x + value.y + value.z
	return total == total and math.abs(total) ~= math.huge
end

Runner.test("a new state has four road wheels, first gear and idle rpm", function()
	local state = VehicleSimulator.newState()
	Runner.expectEqual(#state.wheels, 4)
	Runner.expectEqual(state.gear, 1)
	Runner.expectEqual(state.shiftRemainingSeconds, 0)
	Runner.expectEqual(state.engineRpm, VehicleConfig.IDLE_RPM)
	for _, wheel in state.wheels do
		Runner.expectEqual(wheel.gripMultiplier, VehicleConfig.SURFACE_GRIP.Road)
		Runner.expectEqual(wheel.isGrounded, false)
	end
end)

Runner.test("the wheels are listed in the order FL, FR, RL, RR", function()
	local names = {}
	for _, wheel in VehicleConfig.WHEELS do
		table.insert(names, wheel.name)
	end
	Runner.expectEqual(table.concat(names, ","), "FL,FR,RL,RR")
	Runner.expectEqual(VehicleConfig.WHEELS[1].offset.x < 0, true)
	Runner.expectEqual(VehicleConfig.WHEELS[1].offset.z < 0, true)
end)

Runner.test("at rest the four wheels carry the weight and push straight up", function()
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), chassisWith())
	Runner.expectEqual(#outputs, 4)
	local total = ZERO
	for _, output in outputs do
		Runner.expectEqual(output.isGrounded, true)
		total += output.force
		Runner.expectNear(output.force.x, 0, 1e-6)
		Runner.expectNear(output.force.z, 0, 1e-6)
	end
	Runner.expectNear(total.y, MASS * GRAVITY, 1e-3)
end)

Runner.test("only the front wheels turn with the steering", function()
	local _, outputs = stepAtRest(controlsWith(1, 0, 0), chassisWith())
	local maxAngle = math.rad(VehicleConfig.STEER_MAX_LOW_SPEED_DEGREES)
	Runner.expectNear(outputs[1].steerAngleRadians, maxAngle, 1e-9)
	Runner.expectNear(outputs[2].steerAngleRadians, maxAngle, 1e-9)
	Runner.expectEqual(outputs[3].steerAngleRadians, 0)
	Runner.expectEqual(outputs[4].steerAngleRadians, 0)
	local _, left = stepAtRest(controlsWith(-1, 0, 0), chassisWith())
	Runner.expectNear(left[1].steerAngleRadians, -maxAngle, 1e-9)
end)

Runner.test("the throttle pushes the car along its front, which is -z, and splits by the rear bias", function()
	local _, outputs = stepAtRest(controlsWith(0, 1, 0), chassisWith())
	local total = ZERO
	for _, output in outputs do
		total += output.force
	end
	Runner.expectEqual(total.z < 0, true)
	Runner.expectNear(total.x, 0, 1e-3)
	local rearPush = outputs[3].force.z + outputs[4].force.z
	local frontPush = outputs[1].force.z + outputs[2].force.z
	Runner.expectNear(rearPush / total.z, VehicleConfig.REAR_BIAS, 1e-6)
	Runner.expectNear(frontPush / total.z, 1 - VehicleConfig.REAR_BIAS, 1e-6)
end)

Runner.test("a wheel that does not touch the ground gives no force", function()
	local contacts = restingContacts()
	contacts[2] = nil
	local state, outputs = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(0, 1, 0),
		chassisWith(),
		contacts,
		FRAME_SECONDS
	)
	Runner.expectEqual(outputs[2].isGrounded, false)
	Runner.expectEqual(outputs[2].force, ZERO)
	Runner.expectEqual(state.wheels[2].isGrounded, false)
	Runner.expectEqual(outputs[1].isGrounded, true)
end)

Runner.test("with no contact at all there are only zero forces", function()
	local _, outputs, feedback = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(1, 1, 0, true),
		chassisWith(vector.create(0, 0, -30)),
		{},
		FRAME_SECONDS
	)
	for _, output in outputs do
		Runner.expectEqual(output.force, ZERO)
		Runner.expectEqual(output.isGrounded, false)
	end
	for _, wheel in feedback.wheels do
		Runner.expectEqual(wheel.slipRatio, 0)
		Runner.expectEqual(wheel.isSliding, false)
	end
end)

Runner.test("the feedback reports speed, gear, rpm and the surface under each wheel", function()
	local contacts = restingContacts()
	local mud = table.clone(contacts[3] :: WheelContact)
	mud.surface = "Mud"
	contacts[3] = mud
	local _, _, feedback = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(0, 0, 0),
		chassisWith(vector.create(0, 0, -20)),
		contacts,
		FRAME_SECONDS
	)
	Runner.expectNear(feedback.speedStudsPerSecond, 20, 1e-9)
	Runner.expectNear(feedback.forwardSpeedStudsPerSecond, 20, 1e-9)
	Runner.expectEqual(feedback.gear, 1)
	Runner.expectEqual(feedback.isShifting, false)
	Runner.expectEqual(feedback.engineRpm > VehicleConfig.IDLE_RPM, true)
	Runner.expectEqual(#feedback.wheels, 4)
	Runner.expectEqual(feedback.wheels[1].surface, "Road")
	Runner.expectEqual(feedback.wheels[3].surface, "Mud")
end)

Runner.test("the drift angle is positive when the velocity points to the right of the front", function()
	local rightward = vector.create(20, 0, -40)
	local _, _, feedback = stepAtRest(controlsWith(0, 0, 0), chassisWith(rightward))
	Runner.expectNear(feedback.driftAngleRadians, math.atan2(20, 40), 1e-9)
	local _, _, leftFeedback = stepAtRest(controlsWith(0, 0, 0), chassisWith(vector.create(-20, 0, -40)))
	Runner.expectNear(leftFeedback.driftAngleRadians, -math.atan2(20, 40), 1e-9)
end)

Runner.test("drifting needs both the angle and the minimum speed", function()
	local threshold = math.rad(VehicleConfig.DRIFT_ANGLE_THRESHOLD_DEGREES)
	local fastAngled = vector.create(40 * math.tan(threshold * 1.2), 0, -40)
	local _, _, drifting = stepAtRest(controlsWith(0, 0, 0), chassisWith(fastAngled))
	Runner.expectEqual(drifting.isDrifting, true)
	local fastStraight = vector.create(40 * math.tan(threshold * 0.8), 0, -40)
	local _, _, notAngled = stepAtRest(controlsWith(0, 0, 0), chassisWith(fastStraight))
	Runner.expectEqual(notAngled.isDrifting, false)
	local slowSpeed = VehicleConfig.DRIFT_MIN_SPEED * 0.5
	local slowAngled = vector.create(slowSpeed * math.tan(threshold * 1.5), 0, -slowSpeed)
	local _, _, tooSlow = stepAtRest(controlsWith(0, 0, 0), chassisWith(slowAngled))
	Runner.expectEqual(tooSlow.isDrifting, false)
end)

Runner.test("in reverse the forward speed is negative and the drift angle stays small", function()
	local _, _, feedback = stepAtRest(controlsWith(0, 0, 0), chassisWith(vector.create(0, 0, 10)))
	Runner.expectNear(feedback.forwardSpeedStudsPerSecond, -10, 1e-9)
	Runner.expectEqual(math.abs(feedback.driftAngleRadians) < 1e-9, true)
end)

Runner.test("the car moving sideways is pushed back by the tires", function()
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), chassisWith(vector.create(10, 0, 0)))
	local total = ZERO
	for _, output in outputs do
		total += output.force
	end
	Runner.expectEqual(total.x < 0, true)
end)

Runner.test("the steering angle gets smaller with the speed", function()
	local _, slow = stepAtRest(controlsWith(1, 0, 0), chassisWith(vector.create(0, 0, -20)))
	local _, fast = stepAtRest(controlsWith(1, 0, 0), chassisWith(vector.create(0, 0, -120)))
	Runner.expectEqual(fast[1].steerAngleRadians < slow[1].steerAngleRadians, true)
end)

Runner.test("with the assist on, the counter steer turns the wheels toward the drift", function()
	local velocity = vector.create(15, 0, -40)
	local assisted = table.clone(VehicleConfig)
	assisted.COUNTER_STEER_STRENGTH = 0.3
	local _, outputs = VehicleSimulator.step(
		VehicleSimulator.newState(assisted),
		controlsWith(0, 0, 0),
		chassisWith(velocity),
		restingContacts(),
		FRAME_SECONDS,
		assisted
	)
	Runner.expectEqual(outputs[1].steerAngleRadians > 0, true)
end)

Runner.test("the assist is on in the default configuration", function()
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), chassisWith(vector.create(15, 0, -40)))
	Runner.expectEqual(outputs[1].steerAngleRadians > 0, true)
end)

Runner.test("the handbrake lowers the rear grip factor and the rear wheels lose lateral force", function()
	local sliding = chassisWith(vector.create(SLIDE_SIDE_SPEED, 0, -40))
	local freeState, freeOutputs = stepAtRest(controlsWith(0, 0, 0), sliding)
	local heldState, heldOutputs = stepAtRest(controlsWith(0, 0, 0, true), sliding)
	Runner.expectEqual(freeState.rearGripFactor, 1)
	local dropAlpha = 1 - math.exp(-VehicleConfig.HANDBRAKE_GRIP_DROP_RATE * FRAME_SECONDS)
	local expected = 1 + (VehicleConfig.HANDBRAKE_REAR_GRIP_MULTIPLIER - 1) * dropAlpha
	Runner.expectNear(heldState.rearGripFactor, expected, 1e-12)
	Runner.expectEqual(math.abs(heldOutputs[3].force.x) < math.abs(freeOutputs[3].force.x), true)
	Runner.expectNear(heldOutputs[1].force.x, freeOutputs[1].force.x, 1e-6)
end)

Runner.test("the rear grip factor recovers over the steps after the handbrake is released", function()
	local state = VehicleSimulator.newState()
	local chassis = chassisWith(vector.create(0, 0, -30))
	state = VehicleSimulator.step(state, controlsWith(0, 0, 0, true), chassis, restingContacts(), FRAME_SECONDS)
	local previous = state.rearGripFactor
	for _ = 1, 90 do
		state = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassis, restingContacts(), FRAME_SECONDS)
		Runner.expectEqual(state.rearGripFactor >= previous and state.rearGripFactor <= 1, true)
		previous = state.rearGripFactor
	end
	Runner.expectEqual(state.rearGripFactor > 0.95, true)
end)

Runner.test("an unusable dt keeps the rear grip factor", function()
	local state = VehicleSimulator.newState()
	state.rearGripFactor = 0.6
	local nextState = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassisWith(), restingContacts(), 0)
	Runner.expectEqual(nextState.rearGripFactor, 0.6)
end)

Runner.test("the rear axle has less grip than the front axle in a slide", function()
	local sliding = chassisWith(vector.create(12, 0, -2))
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), sliding)
	Runner.expectEqual(math.abs(outputs[3].force.x) < math.abs(outputs[1].force.x), true)
end)

Runner.test("the total steering never goes over the limit allowed for that speed and drift", function()
	local velocity = vector.create(60, 0, -40)
	local _, outputs = stepAtRest(controlsWith(1, 0, 0), chassisWith(velocity))
	local driftAngle = math.atan2(velocity.x, math.abs(velocity.z))
	local limit = Steering.maxAngleWhileDrifting(vector.magnitude(velocity), driftAngle)
	Runner.expectNear(outputs[1].steerAngleRadians, limit, 1e-9)
end)

Runner.test("in reverse gear the steering is limited to the reverse maximum", function()
	local state = VehicleSimulator.newState()
	state.gear = -1
	local _, outputs =
		VehicleSimulator.step(state, controlsWith(1, 0, 0), chassisWith(), restingContacts(), FRAME_SECONDS)
	local limit = math.rad(VehicleConfig.STEER_MAX_REVERSE_DEGREES)
	Runner.expectNear(outputs[1].steerAngleRadians, limit, 1e-9)
	Runner.expectNear(outputs[2].steerAngleRadians, limit, 1e-9)
	local _, left =
		VehicleSimulator.step(state, controlsWith(-0.5, 0, 0), chassisWith(), restingContacts(), FRAME_SECONDS)
	Runner.expectNear(left[1].steerAngleRadians, -limit / 2, 1e-9)
end)

-- Chasis con el centro de masa corrido del origen del marco, sin velocidad.
local function shiftedChassis(centerOffset: vector): ChassisSample
	local chassis = chassisWith()
	chassis.position = chassis.origin + centerOffset
	return chassis
end

Runner.test("a spin around the center of mass gives each wheel the velocity of its arm from the center", function()
	local spin = vector.create(0.3, 0.7, -0.2)
	local centerOffset = vector.create(0.1, -0.3, 0.15)
	local chassis = shiftedChassis(centerOffset)
	chassis.angularVelocity = spin
	local _, velocities = WheelForces.describeMounts(chassis, VehicleConfig)
	for index, wheel in VehicleConfig.WHEELS do
		local mountInWorld = vector.create(wheel.offset.x, wheel.offset.y, wheel.offset.z)
		local arm = mountInWorld - centerOffset
		local expected = vector.cross(spin, arm)
		Runner.expectNear(velocities[index].x, expected.x, 1e-6)
		Runner.expectNear(velocities[index].y, expected.y, 1e-6)
		Runner.expectNear(velocities[index].z, expected.z, 1e-6)
	end
end)

Runner.test("with the center of mass in the middle the arms are the mount offsets", function()
	local chassis = chassisWith()
	local offsets = WheelForces.describeMounts(chassis, VehicleConfig)
	Runner.expectNear(offsets[1].x, VehicleConfig.WHEELS[1].offset.x, 1e-9)
	Runner.expectNear(offsets[3].y, VehicleConfig.WHEELS[3].offset.y, 1e-9)
	Runner.expectNear(offsets[3].z, VehicleConfig.WHEELS[3].offset.z, 1e-9)
end)

Runner.test("a NaN origin gives the same result as the center of mass in the middle", function()
	local chassis = chassisWith()
	chassis.origin = vector.create(0 / 0, 0, 0)
	chassis.angularVelocity = vector.create(0, 1, 0)
	local _, velocities = WheelForces.describeMounts(chassis, VehicleConfig)
	local clean = chassisWith()
	clean.angularVelocity = vector.create(0, 1, 0)
	local _, cleanVelocities = WheelForces.describeMounts(clean, VehicleConfig)
	for index = 1, 4 do
		Runner.expectEqual(velocities[index], cleanVelocities[index])
	end
end)

Runner.test("with the center of mass shifted the static loads add up to the weight and the car stays level", function()
	local chassis = shiftedChassis(vector.create(0, -0.3, -0.15))
	local contacts = restingContacts()
	local state = VehicleSimulator.newState()
	local outputs = {}
	for _ = 1, 3 do
		state, outputs = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassis, contacts, FRAME_SECONDS)
	end
	local front, rear = outputs[1].force.y + outputs[2].force.y, outputs[3].force.y + outputs[4].force.y
	Runner.expectNear(front + rear, MASS * GRAVITY, 1e-3)
	Runner.expectNear(front / (front + rear), (4 + 0.15) / 8, 1e-6)
end)

Runner.test("the spin of the wheel follows the speed of the car", function()
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), chassisWith(vector.create(0, 0, -24)))
	Runner.expectNear(outputs[3].spinRadiansPerSecond, 24 / VehicleConfig.WHEEL_RADIUS_STUDS, 1e-6)
end)

Runner.test("an unusable dt leaves the state as it was and gives zero forces", function()
	local state = VehicleSimulator.newState()
	state.gear = 3
	state.engineRpm = 4000
	local chassis = chassisWith(vector.create(0, 0, -50))
	for _, dt in { 0, -1, 0 / 0, math.huge, -math.huge } do
		local nextState, outputs, feedback =
			VehicleSimulator.step(state, controlsWith(1, 1, 0), chassis, restingContacts(), dt)
		Runner.expectEqual(nextState.gear, 3)
		Runner.expectEqual(nextState.engineRpm, 4000)
		Runner.expectEqual(nextState ~= state, true)
		Runner.expectEqual(nextState.wheels[1] ~= state.wheels[1], true)
		for _, output in outputs do
			Runner.expectEqual(output.force, ZERO)
		end
		Runner.expectEqual(feedback.gear, 3)
		Runner.expectNear(feedback.speedStudsPerSecond, 50, 1e-9)
	end
end)

Runner.test("an unusable dt keeps the gearbox memory used by the kickdown", function()
	local state = VehicleSimulator.newState()
	state.secondsSinceUpshift = 0.4
	state.filteredForwardY = 0.2
	for _, dt in { 0, -1, 0 / 0, math.huge } do
		local nextState = VehicleSimulator.step(state, controlsWith(0, 1, 0), chassisWith(), restingContacts(), dt)
		Runner.expectEqual(nextState.secondsSinceUpshift, 0.4)
		Runner.expectEqual(nextState.filteredForwardY, 0.2)
	end
end)

Runner.test("a valid step updates the gearbox memory", function()
	local state = VehicleSimulator.newState()
	local chassis = chassisWith(vector.create(0, 0, -20))
	local nextState = VehicleSimulator.step(state, controlsWith(0, 0.2, 0), chassis, restingContacts(), FRAME_SECONDS)
	Runner.expectEqual(nextState.filteredForwardY ~= nil, true)
	Runner.expectEqual(nextState.secondsSinceUpshift > state.secondsSinceUpshift, true)
end)

Runner.test("the steering offset turns the front wheels by that angle", function()
	local offset = table.clone(VehicleConfig)
	offset.STEER_OFFSET_DEGREES = 3
	local _, outputs = VehicleSimulator.step(
		VehicleSimulator.newState(offset),
		controlsWith(0, 0, 0),
		chassisWith(),
		restingContacts(),
		FRAME_SECONDS,
		offset
	)
	Runner.expectNear(outputs[1].steerAngleRadians, math.rad(3), 1e-9)
	Runner.expectNear(outputs[2].steerAngleRadians, math.rad(3), 1e-9)
	Runner.expectEqual(outputs[3].steerAngleRadians, 0)
end)

Runner.test("with the defaults the wheel grip multipliers and the steering offset change nothing", function()
	Runner.expectEqual(VehicleConfig.STEER_OFFSET_DEGREES, 0)
	for index = 1, 4 do
		Runner.expectEqual(VehicleConfig.WHEEL_GRIP_MULTIPLIERS[index], 1)
	end
end)

Runner.test("a wheel grip multiplier of zero removes the lateral force of that wheel only", function()
	local slide = chassisWith(vector.create(20, 0, -40))
	local noGrip = table.clone(VehicleConfig)
	noGrip.WHEEL_GRIP_MULTIPLIERS = table.freeze({ 1, 1, 0, 1 })
	local _, free = stepAtRest(controlsWith(0, 0, 0), slide)
	local _, outputs = VehicleSimulator.step(
		VehicleSimulator.newState(noGrip),
		controlsWith(0, 0, 0),
		slide,
		restingContacts(),
		FRAME_SECONDS,
		noGrip
	)
	Runner.expectEqual(outputs[3].force.x, 0)
	Runner.expectEqual(free[3].force.x < 0, true)
	Runner.expectNear(outputs[1].force.x, free[1].force.x, 1e-6)
end)

Runner.test("a huge dt gives the same result as the maximum step", function()
	local chassis = chassisWith(vector.create(0, 0, -30))
	local _, hugeOutputs =
		VehicleSimulator.step(VehicleSimulator.newState(), controlsWith(0, 1, 0), chassis, restingContacts(), 10)
	local _, maxOutputs = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(0, 1, 0),
		chassis,
		restingContacts(),
		VehicleConfig.MAX_STEP_SECONDS
	)
	for index = 1, 4 do
		Runner.expectEqual(hugeOutputs[index].force, maxOutputs[index].force)
	end
end)

Runner.test("controls out of range behave like the clamped controls", function()
	local chassis = chassisWith(vector.create(0, 0, -30))
	local _, wild = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(7, 9, -3),
		chassis,
		restingContacts(),
		FRAME_SECONDS
	)
	local _, clamped = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(1, 1, 0),
		chassis,
		restingContacts(),
		FRAME_SECONDS
	)
	for index = 1, 4 do
		Runner.expectEqual(wild[index].force, clamped[index].force)
		Runner.expectEqual(wild[index].steerAngleRadians, clamped[index].steerAngleRadians)
	end
end)

Runner.test("NaN controls count as zero", function()
	local chassis = chassisWith()
	local nan = 0 / 0
	local _, broken = stepAtRest(controlsWith(nan, nan, nan), chassis)
	local _, idle = stepAtRest(controlsWith(0, 0, 0), chassis)
	for index = 1, 4 do
		Runner.expectEqual(broken[index].force, idle[index].force)
	end
end)

Runner.test("a mass of zero gives no forces and no NaN", function()
	local chassis = chassisWith(vector.create(5, 0, -30))
	chassis.mass = 0
	local state, outputs = stepAtRest(controlsWith(1, 1, 1, true), chassis)
	for _, output in outputs do
		Runner.expectEqual(isFiniteVector(output.force), true)
		Runner.expectEqual(vector.magnitude(output.force), 0)
	end
	Runner.expectEqual(state.engineRpm == state.engineRpm, true)
end)

Runner.test("the surface blends into the wheel state over several steps", function()
	local contacts = restingContacts()
	for index = 1, 4 do
		local contact = table.clone(contacts[index] :: WheelContact)
		contact.surface = "Mud"
		contacts[index] = contact
	end
	local state = VehicleSimulator.newState()
	local chassis = chassisWith()
	state = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassis, contacts, FRAME_SECONDS)
	local firstGrip = state.wheels[1].gripMultiplier
	Runner.expectEqual(firstGrip < 1 and firstGrip > VehicleConfig.SURFACE_GRIP.Mud, true)
	for _ = 1, 60 do
		state = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassis, contacts, FRAME_SECONDS)
	end
	Runner.expectNear(state.wheels[1].gripMultiplier, VehicleConfig.SURFACE_GRIP.Mud, 1e-6)
end)

Runner.test("a missing surface keeps the grip of the wheel", function()
	local contacts = restingContacts()
	for index = 1, 4 do
		local contact = table.clone(contacts[index] :: WheelContact)
		contact.surface = nil
		contacts[index] = contact
	end
	local state = VehicleSimulator.step(
		VehicleSimulator.newState(),
		controlsWith(0, 0, 0),
		chassisWith(),
		contacts,
		FRAME_SECONDS
	)
	Runner.expectEqual(state.wheels[1].gripMultiplier, VehicleConfig.SURFACE_GRIP.Road)
end)

Runner.test("a wheel that was bottomed out and loses its ray stays on the ground", function()
	local state = VehicleSimulator.newState()
	local deep = restingContacts()
	for index = 1, 4 do
		local contact = table.clone(deep[index] :: WheelContact)
		contact.distanceStuds = -1
		deep[index] = contact
	end
	state = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassisWith(), deep, FRAME_SECONDS)
	Runner.expectEqual(state.wheels[1].compressionStuds, VehicleConfig.SUSPENSION_MAX_COMPRESSION_STUDS)
	local nextState, outputs = VehicleSimulator.step(state, controlsWith(0, 0, 0), chassisWith(), {}, FRAME_SECONDS)
	Runner.expectEqual(nextState.wheels[1].isGrounded, true)
	Runner.expectEqual(outputs[1].force.y > 0, true)
end)

Runner.test("the load of each wheel is the suspension force", function()
	local _, outputs = stepAtRest(controlsWith(0, 0, 0), chassisWith())
	local staticLoad = Suspension.staticLoad(MASS, GRAVITY, 4)
	for _, output in outputs do
		Runner.expectNear(output.force.y, staticLoad, 1e-3)
	end
end)

Runner.test("a custom configuration with a different frequency changes the forces", function()
	local stiff = table.clone(VehicleConfig)
	stiff.SUSPENSION_FREQUENCY_HZ = 4
	local _, outputs = VehicleSimulator.step(
		VehicleSimulator.newState(stiff),
		controlsWith(0, 0, 0),
		chassisWith(),
		restingContacts(),
		FRAME_SECONDS,
		stiff
	)
	local _, normal = stepAtRest(controlsWith(0, 0, 0), chassisWith())
	Runner.expectEqual(outputs[1].force.y > normal[1].force.y, true)
end)

Runner.test("step does not modify any of its arguments", function()
	local state = VehicleSimulator.newState()
	for _, wheel in state.wheels do
		table.freeze(wheel)
	end
	table.freeze(state.wheels)
	table.freeze(state)
	local controls = controlsWith(0.5, 1, 0, true)
	table.freeze(controls)
	local chassis = chassisWith(vector.create(3, 0, -40), vector.create(0, 0.2, 0))
	table.freeze(chassis)
	local contacts = restingContacts()
	for index = 1, 4 do
		table.freeze(contacts[index] :: WheelContact)
	end
	table.freeze(contacts)
	local nextState, outputs = VehicleSimulator.step(state, controls, chassis, contacts, FRAME_SECONDS)
	Runner.expectEqual(nextState ~= state, true)
	Runner.expectEqual(#outputs, 4)
	local afterState = VehicleSimulator.step(nextState, controls, chassis, contacts, FRAME_SECONDS)
	Runner.expectEqual(afterState ~= nextState, true)
	Runner.expectEqual(state.gear, 1)
end)

Runner.test("the same inputs always give the same outputs", function()
	local chassis = chassisWith(vector.create(2, 0, -35), vector.create(0, 0.1, 0))
	local _, first = stepAtRest(controlsWith(0.3, 0.8, 0), chassis)
	local _, second = stepAtRest(controlsWith(0.3, 0.8, 0), chassis)
	for index = 1, 4 do
		Runner.expectEqual(first[index].force, second[index].force)
	end
end)

Runner.finish()
