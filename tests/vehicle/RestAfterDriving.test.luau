--!strict
-- Bug 2026-10-16 (vibracion en reposo): despues de manejar y soltar todo, una perturbacion minima de giro no debe
-- crecer hasta una oscilacion de un cuadro de periodo, y el auto tiene que terminar quieto.
-- La inercia de giro del conjunto del auto (Body + lastre) tiene que ser la de la caja entera: el lastre del
-- adaptador mide lo mismo que el Body (VehicleModelBuilder) para no reducirla.
local Runner = require("../Runner")
local ToyWorld = require("./ToyWorld")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls

local THROTTLE_SECONDS = 2
local TOTAL_SECONDS = 100
local MEASURE_FROM_SECONDS = 90
local INITIAL_YAW_RATE_RADIANS = 0.0015
local MAX_REST_SPEED = 0.05
local MAX_REST_YAW_DEGREES = 0.5
-- Con la mitad de la inercia el lazo explicito de las fuerzas del neumatico es inestable por debajo de ~32 studs/s
-- (60 FPS) y ~70 studs/s (30 FPS). La fraccion minima estable medida es ~0,71 en ambos casos.
local HALF_YAW_INERTIA = 0.5

local function controlsWith(throttle: number): VehicleControls
	return { steer = 0, throttle = throttle, brake = 0, isHandbrakeOn = false }
end

-- Devuelve la velocidad y el giro (en grados por segundo) maximos al final de la corrida.
local function driveAndRelease(frameSeconds: number, yawInertiaFraction: number): (number, number)
	local runner = ToyWorld.new({ frameSeconds = frameSeconds, yawInertiaFraction = yawInertiaFraction })
	runner.world.angularVelocity = vector.create(0, INITIAL_YAW_RATE_RADIANS, 0)
	local finalSpeed, finalYawDegrees = 0, 0
	runner.run(TOTAL_SECONDS, function(world)
		return controlsWith(if world.timeSeconds < THROTTLE_SECONDS then 1 else 0)
	end, function(world)
		if world.timeSeconds > MEASURE_FROM_SECONDS then
			finalSpeed = math.max(finalSpeed, vector.magnitude(world.linearVelocity))
			finalYawDegrees = math.max(finalYawDegrees, math.abs(math.deg(world.angularVelocity.y)))
		end
	end)
	return finalSpeed, finalYawDegrees
end

Runner.test("with the full box yaw inertia the car ends at rest after driving and letting go", function()
	for _, frameSeconds in { 1 / 60, 1 / 30 } do
		local speed, yawDegrees = driveAndRelease(frameSeconds, 1)
		Runner.expectEqual(speed < MAX_REST_SPEED, true)
		Runner.expectEqual(yawDegrees < MAX_REST_YAW_DEGREES, true)
	end
end)

Runner.test("known limit: with half the yaw inertia the car does not come to rest (it keeps shaking)", function()
	for _, frameSeconds in { 1 / 60, 1 / 30 } do
		local speed, yawDegrees = driveAndRelease(frameSeconds, HALF_YAW_INERTIA)
		Runner.expectEqual(speed > MAX_REST_SPEED and yawDegrees > MAX_REST_YAW_DEGREES, true)
	end
end)

Runner.finish()
