--!strict
-- Propiedades del simulador completo, corridas sobre el mundo de juguete a 30 FPS con las fuerzas fijas entre cuadros.
local Runner = require("../Runner")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local Steering = require("../../src/vehicle/core/Steering")
local ToyWorld = require("./ToyWorld")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type ToyWorldInstance = ToyWorld.ToyWorld
type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings
type SurfaceKind = VehicleTypes.SurfaceKind
type WheelContact = VehicleTypes.WheelContact

local FRAME_SECONDS = 1 / 30
local SETTLE_SECONDS = 2
-- Con otras frecuencias y amortiguaciones la oscilación tarda más en apagarse que con los valores iniciales.
local GRID_SETTLE_SECONDS = 6
local REST_SECONDS = 10
local REST_DROP_STUDS = 0.5
local REST_PUSH_STUDS_PER_SECOND = 0.3
local REST_SPIN_RADIANS_PER_SECOND = 0.01
local REST_MAX_DRIFT_STUDS = 0.05
local REST_MAX_SPEED = 0.05
local CRUISE_SPEED = 60
-- Más rápido que STEER_LOW_SPEED, donde el máximo por velocidad ya bajó del de baja velocidad.
local DRIFT_CHECK_SPEED = 100
local HANDBRAKE_SECONDS = 0.3
local HANDBRAKE_TURN_SECONDS = 2.5
local HANDBRAKE_DRIFT_DEGREES = 15
local SPIN_DRIFT_DEGREES = 90
local ACCELERATION_SECONDS = 3
local REAR_BIAS_STEER = 0.7
local CORNER_SECONDS = 1
local CORNER_THROTTLE = 0.2
local EXIT_SECONDS = 2
local MIN_REAR_BIAS_DRIFT_GAIN_DEGREES = 10
local WHEEL_COUNT = 4
local SHIFT_FORWARD_STUDS = 0.15
local SHIFT_DOWN_STUDS = 0.3
local SHIFT_SIDE_STUDS = 0.1
local MAX_REST_TILT_DEGREES = 1
local REST_LOAD_TOLERANCE = 0.05
local REVERSE_SECONDS = 6
local REVERSE_MAX_SPEED = 32
local REVERSE_MOVING_SPEED = 5
local REVERSE_GRIP_FRACTION = 0.8
local LIMITER_SWEEP_STEP_RPM = 10
local LIMITER_SWEEP_EXTRA_RPM = 500
local MAX_FORCE_DROP_FRACTION = 0.2
local LIMITER_RUN_SECONDS = 40
local GRAVITY = 196.2
local MASS = 1000

local function controlsWith(steer: number, throttle: number, brake: number, isHandbrakeOn: boolean?): VehicleControls
	return { steer = steer, throttle = throttle, brake = brake, isHandbrakeOn = isHandbrakeOn or false }
end

local IDLE = controlsWith(0, 0, 0)

local function constant(controls: VehicleControls): (ToyWorldInstance) -> VehicleControls
	return function()
		return controls
	end
end

local function horizontalDistance(first: vector, second: vector): number
	local delta = first - second
	return math.sqrt(delta.x * delta.x + delta.z * delta.z)
end

local function isFiniteVector(value: vector): boolean
	local total = value.x + value.y + value.z
	return total == total and math.abs(total) ~= math.huge
end

local function frontLoad(world: ToyWorldInstance): number
	return world.outputs[1].force.y + world.outputs[2].force.y
end

local function rearLoad(world: ToyWorldInstance): number
	return world.outputs[3].force.y + world.outputs[4].force.y
end

local function leftLoad(world: ToyWorldInstance): number
	return world.outputs[1].force.y + world.outputs[3].force.y
end

local function rightLoad(world: ToyWorldInstance): number
	return world.outputs[2].force.y + world.outputs[4].force.y
end

-- Promedia una medida del mundo en una ventana de tiempo, para no depender de un solo cuadro.
local function averageBetween(
	runner: ToyWorld.Runner,
	controls: VehicleControls,
	fromSeconds: number,
	toSeconds: number,
	measure: (ToyWorldInstance) -> number
): number
	local total, count = 0, 0
	runner.run(toSeconds, constant(controls), function(world)
		if world.timeSeconds >= fromSeconds then
			total += measure(world)
			count += 1
		end
	end)
	return total / count
end

local function runRestScenario(
	frameSeconds: number,
	config: VehicleSettings?,
	settleSeconds: number?,
	isPerturbed: boolean?
): (number, number, number)
	local runner = ToyWorld.new({ frameSeconds = frameSeconds, dropStuds = REST_DROP_STUDS, config = config })
	if isPerturbed then
		runner.world.linearVelocity = vector.create(REST_PUSH_STUDS_PER_SECOND, 0, 0)
		runner.world.angularVelocity = vector.create(0, REST_SPIN_RADIANS_PER_SECOND, 0)
	end
	local settledPosition = runner.world.position
	local maxDrift, maxSpeed = 0, 0
	runner.run(REST_SECONDS, constant(IDLE), function(world)
		if world.timeSeconds < (settleSeconds or SETTLE_SECONDS) then
			settledPosition = world.position
			return
		end
		maxDrift = math.max(maxDrift, horizontalDistance(world.position, settledPosition))
		maxSpeed = math.max(maxSpeed, vector.magnitude(world.linearVelocity))
	end)
	return maxDrift, maxSpeed, runner.world.position.y
end

Runner.test("1. at rest on flat ground the car settles in under 2 seconds and does not move", function()
	for _, frameSeconds in { 1 / 30, 1 / 60 } do
		local maxDrift, maxSpeed, height = runRestScenario(frameSeconds)
		Runner.expectEqual(maxDrift < REST_MAX_DRIFT_STUDS, true)
		Runner.expectEqual(maxSpeed < REST_MAX_SPEED, true)
		local angularFrequency = 2 * math.pi * VehicleConfig.SUSPENSION_FREQUENCY_HZ
		local staticCompression = GRAVITY / (angularFrequency * angularFrequency)
		local expectedHeight = 1
			+ VehicleConfig.SUSPENSION_REST_LENGTH_STUDS
			+ VehicleConfig.WHEEL_RADIUS_STUDS
			- staticCompression
		Runner.expectNear(height, expectedHeight, 0.01)
	end
end)

Runner.test("1. at rest after a sideways push and a small spin the car settles and does not move", function()
	for _, frameSeconds in { 1 / 30, 1 / 60 } do
		local maxDrift, maxSpeed, height = runRestScenario(frameSeconds, nil, nil, true)
		Runner.expectEqual(maxDrift < REST_MAX_DRIFT_STUDS, true)
		Runner.expectEqual(maxSpeed < REST_MAX_SPEED, true)
		Runner.expectEqual(height > 1, true)
	end
end)

local function runShiftedRest(frameSeconds: number, centerOffset: vector): (number, number, number, number, number)
	local runner = ToyWorld.new({
		frameSeconds = frameSeconds,
		dropStuds = REST_DROP_STUDS,
		centerOfMassOffset = centerOffset,
	})
	local settledPosition = runner.world.position
	local maxDrift, maxSpeed, maxTilt = 0, 0, 0
	runner.run(REST_SECONDS, constant(IDLE), function(world)
		if world.timeSeconds < SETTLE_SECONDS then
			settledPosition = world.position
			return
		end
		maxDrift = math.max(maxDrift, horizontalDistance(world.position, settledPosition))
		maxSpeed = math.max(maxSpeed, vector.magnitude(world.linearVelocity))
		maxTilt = math.max(maxTilt, math.deg(math.asin(math.max(math.abs(world.forward.y), math.abs(world.right.y)))))
	end)
	local front, rear = frontLoad(runner.world), rearLoad(runner.world)
	return maxDrift, maxSpeed, maxTilt, front / (front + rear), leftLoad(runner.world) / (front + rear)
end

Runner.test(
	"17. at rest with the center of mass shifted the car settles level and loads each axle as expected",
	function()
		local wheelbase = VehicleConfig.WHEELS[3].offset.z - VehicleConfig.WHEELS[1].offset.z
		local halfTrack = VehicleConfig.WHEELS[2].offset.x
		local cases = {
			vector.create(0, -SHIFT_DOWN_STUDS, -SHIFT_FORWARD_STUDS),
			vector.create(0, -SHIFT_DOWN_STUDS, SHIFT_FORWARD_STUDS),
			vector.create(SHIFT_SIDE_STUDS, -SHIFT_DOWN_STUDS, -SHIFT_FORWARD_STUDS),
		}
		for _, frameSeconds in { 1 / 30, 1 / 60 } do
			for _, centerOffset in cases do
				local drift, speed, tilt, frontShare, leftShare = runShiftedRest(frameSeconds, centerOffset)
				Runner.expectEqual(drift < REST_MAX_DRIFT_STUDS, true)
				Runner.expectEqual(speed < REST_MAX_SPEED, true)
				Runner.expectEqual(tilt < MAX_REST_TILT_DEGREES, true)
				local expectedFront = (wheelbase / 2 - centerOffset.z) / wheelbase
				local expectedLeft = (halfTrack - centerOffset.x) / (2 * halfTrack)
				Runner.expectNear(frontShare / expectedFront, 1, REST_LOAD_TOLERANCE)
				Runner.expectNear(leftShare / expectedLeft, 1, REST_LOAD_TOLERANCE)
			end
		end
	end
)

Runner.test("17. the front wheels carry more than the rear ones when the center of mass is forward", function()
	local _, _, _, frontShare = runShiftedRest(1 / 30, vector.create(0, -SHIFT_DOWN_STUDS, -SHIFT_FORWARD_STUDS))
	Runner.expectEqual(frontShare > 0.5, true)
end)

Runner.test(
	"2. the car supported on its wheels does not diverge across suspension settings at 30 and 60 FPS",
	function()
		local cases = {
			{ frameSeconds = 1 / 30, frequencies = { 2, 2.5, 3, 3.5, 4 }, dampings = { 0.45, 0.6, 1 } },
			{ frameSeconds = 1 / 60, frequencies = { 2, 2.5, 3, 3.5, 4 }, dampings = { 0.3, 0.45, 0.6, 1 } },
		}
		for _, case in cases do
			for _, frequency in case.frequencies do
				for _, damping in case.dampings do
					local settings = table.clone(VehicleConfig)
					settings.SUSPENSION_FREQUENCY_HZ = frequency
					settings.SUSPENSION_DAMPING_RATIO = damping
					local maxDrift, maxSpeed, height = runRestScenario(case.frameSeconds, settings, GRID_SETTLE_SECONDS)
					Runner.expectEqual(maxDrift < REST_MAX_DRIFT_STUDS, true)
					Runner.expectEqual(maxSpeed < REST_MAX_SPEED, true)
					Runner.expectEqual(height > 1, true)
				end
			end
		end
	end
)

Runner.test("3a. braking hard puts more load on the front wheels than on the rear ones", function()
	local runner = ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED })
	local front = averageBetween(runner, controlsWith(0, 0, 1), 0.1, 0.25, frontLoad)
	local runnerForRear = ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED })
	local rear = averageBetween(runnerForRear, controlsWith(0, 0, 1), 0.1, 0.25, rearLoad)
	Runner.expectEqual(front > rear, true)
	Runner.expectEqual(front > MASS * GRAVITY / 2, true)
end)

Runner.test("3b. accelerating puts more load on the rear wheels than on the front ones", function()
	local front = averageBetween(ToyWorld.new({}), controlsWith(0, 1, 0), 0.3, 0.7, frontLoad)
	local rear = averageBetween(ToyWorld.new({}), controlsWith(0, 1, 0), 0.3, 0.7, rearLoad)
	Runner.expectEqual(rear > front, true)
	Runner.expectEqual(rear > MASS * GRAVITY / 2, true)
end)

Runner.test("3c. in a corner the wheels on the outside carry more load", function()
	local rightTurn = ToyWorld.new({ initialForwardSpeed = 40 })
	local outsideOfRightTurn = averageBetween(rightTurn, controlsWith(0.5, 0.3, 0), 1, 1.5, leftLoad)
	local insideOfRightTurn =
		averageBetween(ToyWorld.new({ initialForwardSpeed = 40 }), controlsWith(0.5, 0.3, 0), 1, 1.5, rightLoad)
	Runner.expectEqual(outsideOfRightTurn > insideOfRightTurn, true)
	local outsideOfLeftTurn =
		averageBetween(ToyWorld.new({ initialForwardSpeed = 40 }), controlsWith(-0.5, 0.3, 0), 1, 1.5, rightLoad)
	local insideOfLeftTurn =
		averageBetween(ToyWorld.new({ initialForwardSpeed = 40 }), controlsWith(-0.5, 0.3, 0), 1, 1.5, leftLoad)
	Runner.expectEqual(outsideOfLeftTurn > insideOfLeftTurn, true)
end)

local function maxDriftWithin(runner: ToyWorld.Runner, controls: VehicleControls, seconds: number): (number, number)
	local maxDrift, timeOfTwenty = 0, -1
	runner.run(seconds, constant(controls), function(world)
		local drift = math.abs(math.deg(world.feedback.driftAngleRadians))
		maxDrift = math.max(maxDrift, drift)
		if drift > 20 and timeOfTwenty < 0 then
			timeOfTwenty = world.timeSeconds
		end
	end)
	return maxDrift, timeOfTwenty
end

local function runHandbrakeTurn(frameSeconds: number, steer: number, isHandbrakeUsed: boolean): (number, number, number)
	local runner = ToyWorld.new({ frameSeconds = frameSeconds, initialForwardSpeed = CRUISE_SPEED })
	local controlsAt = function(world: ToyWorldInstance): VehicleControls
		return controlsWith(steer, 0, 0, isHandbrakeUsed and world.timeSeconds < HANDBRAKE_SECONDS)
	end
	local maxDrift, timeOfThreshold, factorAfterRelease = 0, -1, 1
	runner.run(HANDBRAKE_TURN_SECONDS, controlsAt, function(world)
		local drift = math.abs(math.deg(world.feedback.driftAngleRadians))
		maxDrift = math.max(maxDrift, drift)
		if drift > HANDBRAKE_DRIFT_DEGREES and timeOfThreshold < 0 then
			timeOfThreshold = world.timeSeconds
		end
		factorAfterRelease = world.vehicleState.rearGripFactor
	end)
	return maxDrift, timeOfThreshold, factorAfterRelease
end

Runner.test(
	"4. a short handbrake at 60 studs per second with full steering breaks the tail loose without a spin",
	function()
		for _, frameSeconds in { 1 / 30, 1 / 60 } do
			for _, steer in { 1, -1 } do
				local maxDrift, timeOfThreshold = runHandbrakeTurn(frameSeconds, steer, true)
				Runner.expectEqual(timeOfThreshold > 0 and timeOfThreshold < HANDBRAKE_TURN_SECONDS, true)
				Runner.expectEqual(maxDrift < SPIN_DRIFT_DEGREES, true)
			end
		end
	end
)

Runner.test("4. the same maneuver without the handbrake stays below the drift threshold at first", function()
	for _, frameSeconds in { 1 / 30, 1 / 60 } do
		local runner = ToyWorld.new({ frameSeconds = frameSeconds, initialForwardSpeed = CRUISE_SPEED })
		local maxDrift = maxDriftWithin(runner, controlsWith(1, 0, 0, false), HANDBRAKE_SECONDS + 1)
		Runner.expectEqual(maxDrift < HANDBRAKE_DRIFT_DEGREES, true)
	end
end)

Runner.test("13. after releasing the handbrake the rear grip comes back above 95% in under 1.5 seconds", function()
	local runner = ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED })
	local controlsAt = function(world: ToyWorldInstance): VehicleControls
		return controlsWith(0, 0, 0, world.timeSeconds < HANDBRAKE_SECONDS)
	end
	local recoveredAt = -1
	runner.run(HANDBRAKE_SECONDS + 2, controlsAt, function(world)
		local factor = world.vehicleState.rearGripFactor
		Runner.expectEqual(factor <= 1, true)
		Runner.expectEqual(factor >= VehicleConfig.HANDBRAKE_REAR_GRIP_MULTIPLIER, true)
		if world.timeSeconds < HANDBRAKE_SECONDS then
			Runner.expectEqual(factor < 1, true)
		elseif recoveredAt < 0 and factor > 0.95 then
			recoveredAt = world.timeSeconds - HANDBRAKE_SECONDS
		end
	end)
	Runner.expectEqual(recoveredAt > 0 and recoveredAt < 1.5, true)
end)

Runner.test(
	"14. while the car drifts the allowed steering angle is above the one for its speed, and not when going straight",
	function()
		local runner = ToyWorld.new({ initialForwardSpeed = DRIFT_CHECK_SPEED })
		local checked = false
		runner.run(HANDBRAKE_TURN_SECONDS, function(world: ToyWorldInstance): VehicleControls
			return controlsWith(1, 0, 0, world.timeSeconds < HANDBRAKE_SECONDS)
		end, function(world)
			local drift = world.feedback.driftAngleRadians
			local speed = world.feedback.speedStudsPerSecond
			if math.abs(drift) > math.rad(30) and speed > VehicleConfig.STEER_LOW_SPEED then
				checked = true
				Runner.expectEqual(Steering.maxAngleWhileDrifting(speed, drift) > Steering.maxAngle(speed), true)
			end
		end)
		Runner.expectEqual(checked, true)
		for _, speed in { VehicleConfig.STEER_LOW_SPEED, CRUISE_SPEED, VehicleConfig.STEER_HIGH_SPEED } do
			Runner.expectEqual(Steering.maxAngleWhileDrifting(speed, 0), Steering.maxAngle(speed))
		end
	end
)

local function distanceAtFullThrottle(surface: SurfaceKind): number
	local runner = ToyWorld.new({
		surfaceAt = function(_: vector): SurfaceKind?
			return surface
		end,
	})
	local startZ = runner.world.position.z
	runner.run(ACCELERATION_SECONDS, constant(controlsWith(0, 1, 0)))
	return math.abs(runner.world.position.z - startZ)
end

Runner.test("6a. accelerating on mud covers less distance than on the road", function()
	local road = distanceAtFullThrottle("Road")
	local shoulder = distanceAtFullThrottle("Shoulder")
	local grass = distanceAtFullThrottle("Grass")
	local mud = distanceAtFullThrottle("Mud")
	Runner.expectEqual(mud < road, true)
	Runner.expectEqual(road >= shoulder and shoulder >= grass and grass >= mud, true)
end)

Runner.test("6b. the grip does not jump in a single step when crossing the edge of a surface", function()
	local runner = ToyWorld.new({
		initialForwardSpeed = 40,
		surfaceAt = function(point: vector): SurfaceKind?
			return if point.z > -20 then "Road" else "Mud"
		end,
	})
	local lastGrip = 1
	local largestChange = 0
	runner.run(2.5, constant(controlsWith(0, 0.3, 0)), function(world)
		local grip = world.vehicleState.wheels[1].gripMultiplier
		largestChange = math.max(largestChange, math.abs(grip - lastGrip))
		lastGrip = grip
	end)
	local fullJump = VehicleConfig.SURFACE_GRIP.Road - VehicleConfig.SURFACE_GRIP.Mud
	Runner.expectEqual(largestChange > 0, true)
	Runner.expectEqual(largestChange < fullJump / 2, true)
	Runner.expectNear(lastGrip, VehicleConfig.SURFACE_GRIP.Mud, 0.05)
end)

Runner.test(
	"7. at full throttle from a stop it goes through every gear in order and reaches about 150 studs per second",
	function()
		local runner = ToyWorld.new({})
		local gears = { 1 }
		local shiftTimes = {}
		runner.run(40, constant(controlsWith(0, 1, 0)), function(world)
			if world.feedback.gear ~= gears[#gears] then
				table.insert(gears, world.feedback.gear)
				table.insert(shiftTimes, world.timeSeconds)
			end
		end)
		Runner.expectEqual(table.concat(gears, ","), "1,2,3,4,5")
		for index = 2, #shiftTimes do
			Runner.expectEqual(
				shiftTimes[index] - shiftTimes[index - 1] >= VehicleConfig.SHIFT_DURATION_SECONDS - 1e-9,
				true
			)
		end
		local topSpeed = runner.world.feedback.forwardSpeedStudsPerSecond
		Runner.expectNear(topSpeed, 150, 15)
	end
)

Runner.test("8. the maximum steering angle at 120 studs per second is less than at 20", function()
	local function frontAngleAt(speed: number): number
		local runner = ToyWorld.new({ initialForwardSpeed = speed })
		runner.step(controlsWith(1, 0, 0))
		return runner.world.outputs[1].steerAngleRadians
	end
	local slow = frontAngleAt(20)
	local fast = frontAngleAt(120)
	Runner.expectEqual(fast < slow, true)
	Runner.expectEqual(fast > 0, true)
end)

Runner.test(
	"9. stopped with the brake held the car reverses, and with the throttle it goes back to first gear",
	function()
		for _, frameSeconds in { 1 / 30, 1 / 60 } do
			local runner = ToyWorld.new({ frameSeconds = frameSeconds })
			runner.run(2, constant(controlsWith(0, 0, 1)))
			Runner.expectEqual(runner.world.feedback.gear, -1)
			Runner.expectEqual(runner.world.feedback.forwardSpeedStudsPerSecond < -5, true)
			runner.run(3, constant(controlsWith(0, 1, 0)))
			Runner.expectEqual(runner.world.feedback.gear >= 1, true)
			Runner.expectEqual(runner.world.feedback.forwardSpeedStudsPerSecond > 5, true)
		end
	end
)

local function maxDriftOnExit(rearBias: number, surface: SurfaceKind, steer: number, speed: number): (number, number)
	local settings = table.clone(VehicleConfig)
	settings.REAR_BIAS = rearBias
	local runner = ToyWorld.new({
		config = settings,
		initialForwardSpeed = speed,
		surfaceAt = function(_: vector): SurfaceKind?
			return surface
		end,
	})
	local maxDrift, highestGear = 0, 0
	local controlsAt = function(world: ToyWorldInstance): VehicleControls
		return controlsWith(steer, if world.timeSeconds < CORNER_SECONDS then CORNER_THROTTLE else 1, 0)
	end
	runner.run(CORNER_SECONDS + EXIT_SECONDS, controlsAt, function(world)
		if world.timeSeconds > CORNER_SECONDS and world.feedback.gear <= 2 then
			maxDrift = math.max(maxDrift, math.abs(math.deg(world.feedback.driftAngleRadians)))
			highestGear = math.max(highestGear, world.feedback.gear)
		end
	end)
	return maxDrift, highestGear
end

Runner.test(
	"5. coming out of a corner at full throttle in first or second gear, a rear bias of 1 drifts more than 0.5",
	function()
		for _, speed in { 20, 30 } do
			local rearDrive, gear = maxDriftOnExit(1, "Road", REAR_BIAS_STEER, speed)
			local balanced = maxDriftOnExit(0.5, "Road", REAR_BIAS_STEER, speed)
			Runner.expectEqual(gear >= 1 and gear <= 2, true)
			Runner.expectEqual(rearDrive > balanced + MIN_REAR_BIAS_DRIFT_GAIN_DEGREES, true)
		end
	end
)

Runner.test(
	"15. in reverse with the brake and the steering to the floor the car stays slow, limited in steering and gripping",
	function()
		for _, frameSeconds in { 1 / 30, 1 / 60 } do
			local runner = ToyWorld.new({ frameSeconds = frameSeconds })
			local maxSpeed, maxSteer, gripFrames, movingFrames = 0, 0, 0, 0
			local previousGear = 1
			runner.run(REVERSE_SECONDS, constant(controlsWith(1, 0, 1)), function(world)
				maxSpeed = math.max(maxSpeed, world.feedback.speedStudsPerSecond)
				if previousGear == -1 and world.feedback.gear == -1 then
					maxSteer = math.max(maxSteer, math.abs(world.outputs[1].steerAngleRadians))
					if world.feedback.speedStudsPerSecond > REVERSE_MOVING_SPEED then
						movingFrames += 1
						local rear = world.feedback.wheels
						gripFrames += if math.max(rear[3].slipRatio, rear[4].slipRatio) <= 1 then 1 else 0
					end
				end
				previousGear = world.feedback.gear
			end)
			Runner.expectEqual(runner.world.feedback.gear, -1)
			Runner.expectEqual(maxSpeed <= REVERSE_MAX_SPEED, true)
			Runner.expectEqual(maxSteer <= math.rad(VehicleConfig.STEER_MAX_REVERSE_DEGREES) + 1e-9, true)
			Runner.expectEqual(maxSteer > 0, true)
			Runner.expectEqual(movingFrames > 0 and gripFrames / movingFrames >= REVERSE_GRIP_FRACTION, true)
		end
	end
)

Runner.test("16. near the rev limiter the engine force falls continuously in every gear", function()
	local mass = MASS
	for gear = 1, #VehicleConfig.GEAR_RATIOS do
		local state: VehicleTypes.VehicleState = VehicleSimulator.newState()
		state.gear = gear
		local peak = mass
			* VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION
			* VehicleConfig.GEAR_RATIOS[gear]
			/ VehicleConfig.GEAR_RATIOS[1]
		local previous = Drivetrain.driveForce(state, controlsWith(0, 1, 0), VehicleConfig.IDLE_RPM, mass)
		for rpm = VehicleConfig.IDLE_RPM, VehicleConfig.REDLINE_RPM + LIMITER_SWEEP_EXTRA_RPM, LIMITER_SWEEP_STEP_RPM do
			local force = Drivetrain.driveForce(state, controlsWith(0, 1, 0), rpm, mass)
			Runner.expectEqual(previous - force <= peak * MAX_FORCE_DROP_FRACTION, true)
			previous = force
		end
		Runner.expectEqual(previous, 0)
	end
end)

Runner.test(
	"16. at full throttle in the simulation the engine force never falls by more than 20% between frames",
	function()
		local runner = ToyWorld.new({})
		local controls = controlsWith(0, 1, 0)
		local previousForce, previousGear, previousShifting = 0, 1, false
		runner.run(LIMITER_RUN_SECONDS, constant(controls), function(world)
			local feedback = world.feedback
			local state = world.vehicleState
			local force = Drivetrain.driveForce(state, controls, feedback.engineRpm, MASS)
			local peak = MASS
				* VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION
				* VehicleConfig.GEAR_RATIOS[feedback.gear]
				/ VehicleConfig.GEAR_RATIOS[1]
			if feedback.gear == previousGear and not feedback.isShifting and not previousShifting then
				Runner.expectEqual(previousForce - force <= peak * MAX_FORCE_DROP_FRACTION, true)
			end
			previousForce, previousGear, previousShifting = force, feedback.gear, feedback.isShifting
		end)
		Runner.expectNear(runner.world.feedback.forwardSpeedStudsPerSecond, 150, 15)
	end
)

local function deterministicNumbers(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
end

local function contactAt(distance: number, surface: SurfaceKind?): WheelContact
	return { hasHit = true, distanceStuds = distance, point = vector.create(0, -1, 0), surface = surface }
end

local function forceCap(mass: number, gravity: number): number
	local staticLoad = mass * gravity / WHEEL_COUNT
	local maxLoad = VehicleConfig.SUSPENSION_MAX_FORCE_PER_STATIC_LOAD * staticLoad
	return maxLoad * math.sqrt(1 + VehicleConfig.TIRE_FRICTION * VehicleConfig.TIRE_FRICTION) * (1 + 1e-9)
end

local function checkStepIsSane(
	state: VehicleTypes.VehicleState,
	outputs: { VehicleTypes.WheelOutput },
	mass: number,
	gravity: number
)
	for _, wheel in state.wheels do
		Runner.expectEqual(wheel.compressionStuds == wheel.compressionStuds, true)
		Runner.expectEqual(wheel.gripMultiplier == wheel.gripMultiplier, true)
	end
	Runner.expectEqual(state.engineRpm == state.engineRpm, true)
	for _, output in outputs do
		Runner.expectEqual(isFiniteVector(output.force), true)
		Runner.expectEqual(vector.magnitude(output.force) <= forceCap(mass, gravity), true)
		Runner.expectEqual(output.spinRadiansPerSecond == output.spinRadiansPerSecond, true)
		Runner.expectEqual(output.steerAngleRadians == output.steerAngleRadians, true)
	end
end

Runner.test("10. nothing gives NaN or infinity and the forces stay inside the cap for extreme inputs", function()
	local random = deterministicNumbers(7)
	local nan = 0 / 0
	local dts = { 0, -1, nan, math.huge, 1e-6, 10, FRAME_SECONDS }
	local masses = { 0, MASS, 1e6 }
	local distances = { -5, -0.001, 0, 1, 2.5, 3.7, 50, nan }
	for _, dt in dts do
		for _, mass in masses do
			for trial = 1, 12 do
				local velocity = vector.create((random() - 0.5) * 300, (random() - 0.5) * 40, (random() - 0.5) * 300)
				local chassis: VehicleTypes.ChassisSample = {
					origin = vector.create(0, 4, 0),
					position = vector.create(0, 4, 0),
					right = vector.create(1, 0, 0),
					up = vector.create(0, 1, 0),
					forward = vector.create(0, 0, -1),
					linearVelocity = velocity,
					angularVelocity = vector.create(random() - 0.5, random() - 0.5, random() - 0.5) * 10,
					mass = mass,
					gravity = GRAVITY,
				}
				local contacts: { WheelContact? } = {}
				for index = 1, WHEEL_COUNT do
					if trial % 4 ~= 0 then
						contacts[index] = contactAt(distances[(trial + index) % #distances + 1], "Mud")
					end
				end
				local controls =
					controlsWith((random() - 0.5) * 10, (random() - 0.5) * 6, (random() - 0.5) * 6, trial % 2 == 0)
				local state = VehicleSimulator.newState()
				for _ = 1, 3 do
					local outputs
					state, outputs = VehicleSimulator.step(state, controls, chassis, contacts, dt)
					checkStepIsSane(state, outputs, mass, GRAVITY)
				end
			end
		end
	end
end)

Runner.test("10. a long run with hard inputs and a drop stays finite", function()
	local runner = ToyWorld.new({ initialForwardSpeed = 40, dropStuds = 5 })
	local controlsAt = function(world: ToyWorldInstance): VehicleControls
		local phase = math.floor(world.timeSeconds) % 3
		return controlsWith(
			if phase == 0 then 1 else -0.5,
			if phase == 1 then 1 else 0,
			if phase == 2 then 1 else 0,
			phase == 2
		)
	end
	runner.run(12, controlsAt, function(world)
		Runner.expectEqual(isFiniteVector(world.position), true)
		Runner.expectEqual(isFiniteVector(world.linearVelocity), true)
	end)
end)

Runner.test("extreme rear bias and slide friction ratio stay finite and bounded while driving", function()
	local variants: { { [string]: number } } = {
		{ SUSPENSION_FREQUENCY_HZ = 4, SUSPENSION_DAMPING_RATIO = 0.45 },
		{ REAR_BIAS = 0 },
		{ REAR_BIAS = 1 },
		{ TIRE_SLIDE_FRICTION_RATIO = 0.5 },
	}
	for _, variant in variants do
		local settings: any = table.clone(VehicleConfig)
		for key, value in variant do
			settings[key] = value
		end
		local runner = ToyWorld.new({ config = settings, initialForwardSpeed = 30 })
		local controlsAt = function(world: ToyWorldInstance): VehicleControls
			local phase = math.floor(world.timeSeconds * 2) % 4
			return controlsWith(
				if phase < 2 then 1 else -1,
				if phase ~= 1 then 1 else 0,
				if phase == 1 then 1 else 0,
				phase == 3
			)
		end
		runner.run(10, controlsAt, function(world)
			Runner.expectEqual(isFiniteVector(world.position), true)
			Runner.expectEqual(vector.magnitude(world.linearVelocity) < 400, true)
			Runner.expectEqual(vector.magnitude(world.angularVelocity) < 100, true)
		end)
	end
end)

Runner.finish()
