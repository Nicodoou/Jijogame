--!strict
-- Propiedades del simulador completo, corridas sobre el mundo de juguete a 30 FPS con las fuerzas fijas entre cuadros.
local Runner = require("../Runner")
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
local REST_MAX_DRIFT_STUDS = 0.05
local REST_MAX_SPEED = 0.05
local CRUISE_SPEED = 60
local WHEEL_COUNT = 4
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
	settleSeconds: number?
): (number, number, number)
	local runner = ToyWorld.new({ frameSeconds = frameSeconds, dropStuds = REST_DROP_STUDS, config = config })
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

Runner.test(
	"2. the car supported on its wheels does not diverge across suspension settings at 30 and 60 FPS",
	function()
		local cases = {
			{ frameSeconds = 1 / 30, frequencies = { 2, 2.5, 3, 4 }, dampings = { 0.45, 0.6, 1 } },
			{ frameSeconds = 1 / 60, frequencies = { 2, 2.5, 3, 3.5, 4 }, dampings = { 0.3, 0.6, 1 } },
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

Runner.test("4. with the handbrake and full steering at 60 studs per second the tail breaks loose", function()
	local _, timeOfTwenty =
		maxDriftWithin(ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED }), controlsWith(1, 0, 0, true), 1.5)
	Runner.expectEqual(timeOfTwenty > 0 and timeOfTwenty < 1.5, true)
	local leftTime = select(
		2,
		maxDriftWithin(ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED }), controlsWith(-1, 0, 0, true), 1.5)
	)
	Runner.expectEqual(leftTime > 0 and leftTime < 1.5, true)
end)

Runner.test("4. the same maneuver without the handbrake stays below 20 degrees of drift", function()
	local maxDrift =
		maxDriftWithin(ToyWorld.new({ initialForwardSpeed = CRUISE_SPEED }), controlsWith(1, 0, 0, false), 1.5)
	Runner.expectEqual(maxDrift < 20, true)
end)

local function brakingDistance(surface: SurfaceKind): number
	local runner = ToyWorld.new({
		initialForwardSpeed = CRUISE_SPEED,
		surfaceAt = function(_: vector): SurfaceKind?
			return surface
		end,
	})
	local startZ = runner.world.position.z
	local stopDistance = -1
	runner.run(5, constant(controlsWith(0, 0, 1)), function(world)
		if stopDistance < 0 and world.feedback.forwardSpeedStudsPerSecond < 1 then
			stopDistance = math.abs(world.position.z - startZ)
		end
	end)
	return stopDistance
end

Runner.test("6a. braking on mud takes more distance than on the road", function()
	local road = brakingDistance("Road")
	local shoulder = brakingDistance("Shoulder")
	local grass = brakingDistance("Grass")
	local mud = brakingDistance("Mud")
	Runner.expectEqual(road > 0, true)
	Runner.expectEqual(mud > road, true)
	Runner.expectEqual(road <= shoulder and shoulder <= grass and grass <= mud, true)
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
		local runner = ToyWorld.new({})
		runner.run(2, constant(controlsWith(0, 0, 1)))
		Runner.expectEqual(runner.world.feedback.gear, -1)
		Runner.expectEqual(runner.world.feedback.forwardSpeedStudsPerSecond < -5, true)
		runner.run(3, constant(controlsWith(0, 1, 0)))
		Runner.expectEqual(runner.world.feedback.gear >= 1, true)
		Runner.expectEqual(runner.world.feedback.forwardSpeedStudsPerSecond > 5, true)
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
