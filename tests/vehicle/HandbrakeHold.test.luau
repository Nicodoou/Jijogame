--!strict
-- WP-17: freno de mano que sostiene en la pendiente más empinada que el auto sube, y pendiente imposible sin freno.
local Runner = require("../Runner")
local ToyWorld = require("./ToyWorld")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls

local FRAME_SECONDS = 1 / 60
-- Pendiente más empinada que el auto sube a pleno acelerador en el ToyWorld (a 23 grados ya retrocede; medido).
local STEEPEST_CLIMB_DEGREES = 22
local IMPOSSIBLE_SLOPE_DEGREES = 30
-- El auto se apoya sobre el plano y la suspensión se asienta; se mide después.
local SETTLE_SECONDS = 3
local HOLD_SECONDS = 10
local MAX_HELD_DISPLACEMENT = 0.05
local MAX_HELD_SPEED = 0.01
local SLIDE_SECONDS = 20
local SLIDE_CHECK_SECONDS = 15
local MAX_LATE_GROWTH = 0.01
local DRIFT_DEGREES = 40
local DRIFT_SPEED = 30
-- Atrás el freno de mano suma fuerza por carga sobre lo que ya hay adelante (el círculo de fricción recorta parte).
local MIN_REAR_EXTRA = 0.1

local function controlsWith(isHandbrakeOn: boolean): VehicleControls
	return { steer = 0, throttle = 0, brake = 0, isHandbrakeOn = isHandbrakeOn }
end

-- Desplazamiento y velocidad máxima durante `HOLD_SECONDS`, después de asentarse.
local function holdOnSlope(slopeDegrees: number, isHandbrakeOn: boolean): (number, number)
	local runner = ToyWorld.new({ frameSeconds = FRAME_SECONDS, slopeDegrees = slopeDegrees, isAlignedToSlope = true })
	runner.run(SETTLE_SECONDS, function()
		return controlsWith(isHandbrakeOn)
	end)
	local start = runner.world.position
	local maxSpeed = 0
	runner.run(HOLD_SECONDS, function()
		return controlsWith(isHandbrakeOn)
	end, function(world)
		maxSpeed = math.max(maxSpeed, vector.magnitude(world.linearVelocity))
	end)
	return vector.magnitude(runner.world.position - start), maxSpeed
end

Runner.test("the hold force is enough for the steepest slope the car climbs", function()
	Runner.expectEqual(VehicleConfig.HANDBRAKE_HOLD_FORCE_PER_LOAD >= math.tan(math.rad(STEEPEST_CLIMB_DEGREES)), true)
end)

Runner.test("on the steepest slope the handbrake holds the car still without vibration", function()
	local displacement, maxSpeed = holdOnSlope(STEEPEST_CLIMB_DEGREES, true)
	Runner.expectEqual(displacement < MAX_HELD_DISPLACEMENT, true)
	Runner.expectEqual(maxSpeed < MAX_HELD_SPEED, true)
end)

Runner.test("without the handbrake the car rolls on the same slope", function()
	local displacement = holdOnSlope(STEEPEST_CLIMB_DEGREES, false)
	Runner.expectEqual(displacement > 100 * MAX_HELD_DISPLACEMENT, true)
end)

Runner.test("on a slope with no input the speed backwards is bounded by the air and the rolling", function()
	local runner =
		ToyWorld.new({ frameSeconds = FRAME_SECONDS, slopeDegrees = IMPOSSIBLE_SLOPE_DEGREES, isAlignedToSlope = true })
	local atCheck = 0
	runner.run(SLIDE_SECONDS, function()
		return controlsWith(false)
	end, function(world)
		if math.abs(world.timeSeconds - SLIDE_CHECK_SECONDS) < FRAME_SECONDS / 2 then
			atCheck = vector.magnitude(world.linearVelocity)
		end
	end)
	local final = vector.magnitude(runner.world.linearVelocity)
	Runner.expectEqual(vector.dot(runner.world.linearVelocity, runner.world.forward) < 0, true)
	Runner.expectEqual(final < atCheck * (1 + MAX_LATE_GROWTH), true)
end)

Runner.test("drifting at 30 studs/s the handbrake still brakes only the rear wheels", function()
	local runner = ToyWorld.new({ frameSeconds = FRAME_SECONDS })
	local world = runner.world
	local angle = math.rad(DRIFT_DEGREES)
	world.linearVelocity = (world.forward * math.cos(angle) + world.right * math.sin(angle)) * DRIFT_SPEED
	runner.step(controlsWith(true))
	local perLoad = {}
	for index, output in world.outputs do
		local load = vector.dot(output.force, world.up)
		perLoad[index] = math.abs(vector.dot(output.force, world.forward)) / load
	end
	Runner.expectEqual(
		perLoad[1] < VehicleConfig.HANDBRAKE_FORCE_PER_LOAD and perLoad[2] < VehicleConfig.HANDBRAKE_FORCE_PER_LOAD,
		true
	)
	Runner.expectEqual(perLoad[3] > perLoad[1] + MIN_REAR_EXTRA and perLoad[4] > perLoad[2] + MIN_REAR_EXTRA, true)
	Runner.expectEqual(perLoad[3] < VehicleConfig.HANDBRAKE_HOLD_FORCE_PER_LOAD, true)
end)

Runner.test("nothing gives NaN with the handbrake, the engine brake and the air at extreme speeds", function()
	for _, speed in { -400, -30, -2, 0, 0.5, 2.9, 3.1, 30, 400 } do
		for _, isHandbrakeOn in { false, true } do
			local runner = ToyWorld.new({ frameSeconds = FRAME_SECONDS, initialForwardSpeed = speed })
			runner.run(2, function()
				return controlsWith(isHandbrakeOn)
			end)
			local velocity = runner.world.linearVelocity
			Runner.expectEqual(velocity.x == velocity.x and velocity.y == velocity.y and velocity.z == velocity.z, true)
			Runner.expectEqual(vector.magnitude(velocity) < 1e4, true)
		end
	end
end)

Runner.finish()
