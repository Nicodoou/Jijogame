--!strict
-- WP-17: freno motor y resistencia del aire. Se miden con un solo cuadro (la fuerza longitudinal de las ruedas) para
-- que la caja no cambie de marcha en el medio, y con la velocidad máxima en 5ta en plano.
local Runner = require("../Runner")
local ToyWorld = require("./ToyWorld")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local OpposingForces = require("../../src/vehicle/core/OpposingForces")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings

local MASS = 1000
local FRAME_SECONDS = 1 / 60
local MAX_SPEED_SECONDS = 80
local MAX_TOP_SPEED_DROP = 0.1
local TOLERANCE = 1e-9

local NO_ENGINE_BRAKE = table.clone(VehicleConfig)
NO_ENGINE_BRAKE.ENGINE_BRAKE_DECELERATION = 0
local NO_AIR = table.clone(VehicleConfig)
NO_AIR.AIR_DRAG_PER_SPEED_SQUARED = 0

local function controlsWith(throttle: number): VehicleControls
	return { steer = 0, throttle = throttle, brake = 0, isHandbrakeOn = false }
end

-- Desaceleración (studs/s²) del primer cuadro, en plano, a esa velocidad y en esa marcha.
local function decelerationIn(gear: number, speed: number, throttle: number, config: VehicleSettings): number
	local runner = ToyWorld.new({ config = config, frameSeconds = FRAME_SECONDS, initialForwardSpeed = speed })
	runner.world.vehicleState.gear = gear
	runner.world.vehicleState.secondsSinceUpshift = 0
	runner.step(controlsWith(throttle))
	if runner.world.vehicleState.gear ~= gear then
		error(`la caja cambió de marcha en la prueba ({gear} a {runner.world.vehicleState.gear})`, 0)
	end
	local total = 0
	for _, output in runner.world.outputs do
		total += vector.dot(output.force, runner.world.forward)
	end
	return -total / MASS
end

local function topSpeed(config: VehicleSettings): number
	local runner = ToyWorld.new({ config = config, frameSeconds = FRAME_SECONDS })
	local best = 0
	runner.run(MAX_SPEED_SECONDS, function()
		return controlsWith(1)
	end, function(world)
		best = math.max(best, vector.magnitude(world.linearVelocity))
	end)
	return best
end

local function engineBrakeAt(speed: number, gear: number, throttle: number, rpmOverride: number?): number
	local state = VehicleSimulator.newState()
	state.gear = gear
	state.engineRpm = rpmOverride or Drivetrain.engineRpm(speed, gear)
	return OpposingForces.engineBrake(state, controlsWith(throttle), MASS, true, VehicleConfig)
end

Runner.test("releasing the throttle at 60 studs/s in 3rd decelerates more than without engine brake", function()
	local withBrake = decelerationIn(3, 60, 0, VehicleConfig)
	local without = decelerationIn(3, 60, 0, NO_ENGINE_BRAKE)
	Runner.expectEqual(withBrake > without + 1, true)
end)

Runner.test("the engine brake is stronger in 2nd than in 4th at the same speed", function()
	local second = decelerationIn(2, 55, 0, VehicleConfig) - decelerationIn(2, 55, 0, NO_ENGINE_BRAKE)
	local fourth = decelerationIn(4, 55, 0, VehicleConfig) - decelerationIn(4, 55, 0, NO_ENGINE_BRAKE)
	Runner.expectEqual(second > fourth and fourth > 0, true)
end)

Runner.test("the engine brake is 0 below the minimum rpm, with full throttle and during a shift", function()
	Runner.expectEqual(engineBrakeAt(0, 1, 0, VehicleConfig.ENGINE_BRAKE_MIN_RPM - 1), 0)
	Runner.expectEqual(engineBrakeAt(60, 3, 1), 0)
	Runner.expectEqual(engineBrakeAt(60, 3, 0) > 0, true)
	local state = VehicleSimulator.newState()
	state.gear, state.engineRpm, state.shiftRemainingSeconds = 3, 5000, 0.1
	Runner.expectEqual(OpposingForces.engineBrake(state, controlsWith(0), MASS, true, VehicleConfig), 0)
end)

Runner.test("the engine brake scales with the released pedal and never pushes forward", function()
	Runner.expectNear(engineBrakeAt(60, 3, 0.5) * 2, engineBrakeAt(60, 3, 0), TOLERANCE)
	for gear = 1, #VehicleConfig.GEAR_RATIOS do
		for speed = 0, 200, 10 do
			for _, throttle in { 0, 0.3, 1 } do
				Runner.expectEqual(engineBrakeAt(speed, gear, throttle) >= 0, true)
			end
		end
	end
end)

Runner.test("the four wheels add up to mass times the configured deceleration at the redline in 1st", function()
	local state = VehicleSimulator.newState()
	state.gear, state.engineRpm = 1, VehicleConfig.REDLINE_RPM
	local total = 0
	for _, wheel in VehicleConfig.WHEELS do
		total += OpposingForces.engineBrake(state, controlsWith(0), MASS, wheel.isFront, VehicleConfig)
	end
	Runner.expectNear(total, MASS * VehicleConfig.ENGINE_BRAKE_DECELERATION, 1e-6)
end)

Runner.test("the top speed in 5th drops at most 10% with the air resistance", function()
	local withAir = topSpeed(VehicleConfig)
	local without = topSpeed(NO_AIR)
	Runner.expectEqual(withAir >= without * (1 - MAX_TOP_SPEED_DROP), true)
	Runner.expectEqual(withAir < without, true)
end)

Runner.test("the air resistance is 0 at rest and grows with the square of the speed", function()
	Runner.expectEqual(OpposingForces.airDragPerLoad(0, MASS, 1000, VehicleConfig), 0)
	local base = OpposingForces.airDragPerLoad(20, MASS, 1000, VehicleConfig)
	Runner.expectNear(OpposingForces.airDragPerLoad(40, MASS, 1000, VehicleConfig), base * 4, TOLERANCE)
	Runner.expectNear(OpposingForces.airDragPerLoad(-40, MASS, 1000, VehicleConfig), base * 4, TOLERANCE)
	Runner.expectEqual(OpposingForces.airDragPerLoad(40, MASS, 0, VehicleConfig), 0)
end)

Runner.test("in the air no wheel force acts", function()
	local runner = ToyWorld.new({ frameSeconds = FRAME_SECONDS, dropStuds = 30, initialForwardSpeed = 100 })
	runner.step(controlsWith(0))
	for _, output in runner.world.outputs do
		Runner.expectEqual(vector.magnitude(output.force), 0)
	end
end)

Runner.finish()
