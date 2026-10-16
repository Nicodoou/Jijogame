--!strict
-- Bug 2026-10-16-deslizamiento-pendiente: sobre una pendiente el auto se arrastra hasta caerse aunque el agarre
-- alcance para sostenerlo. Estas pruebas FALLAN hasta que se corrija la causa (docs/bugs/2026-10-16-deslizamiento-pendiente.md).
local Runner = require("../Runner")
local ToyWorld = require("./ToyWorld")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls

local HOLD_SECONDS = 6
local MAX_HELD_SPEED = 0.05
local SLOPES_DEGREES = { 5, 10, 15 }
-- El freno de mano solo frena las ruedas traseras, con HANDBRAKE_FORCE_PER_LOAD por unidad de carga: sostiene hasta
-- tan(pendiente) = HANDBRAKE_FORCE_PER_LOAD / 2 (dos de las cuatro ruedas, cada una con la mitad de la carga que le toca).
local HANDBRAKE_HOLD_SLOPES_DEGREES = { 3, 5 }
local SIDE_YAWS_DEGREES = { 90, 270 }
local LENGTHWISE_YAWS_DEGREES = { 0, 180 }
local FRAME_RATES = { 30, 60 }

local NO_INPUT: VehicleControls = { steer = 0, throttle = 0, brake = 0, isHandbrakeOn = false }
local HANDBRAKE: VehicleControls = { steer = 0, throttle = 0, brake = 0, isHandbrakeOn = true }

local function speedAfterHolding(
	slopeDegrees: number,
	yawDegrees: number,
	controls: VehicleControls,
	fps: number
): number
	local runner = ToyWorld.new({
		frameSeconds = 1 / fps,
		slopeDegrees = slopeDegrees,
		initialYawDegrees = yawDegrees,
		isAlignedToSlope = true,
	})
	runner.run(HOLD_SECONDS, function()
		return controls
	end)
	return vector.magnitude(runner.world.linearVelocity)
end

Runner.test("the grip is enough to hold the slope the tires and the handbrake are tested on", function()
	local steepest = math.rad(SLOPES_DEGREES[#SLOPES_DEGREES])
	Runner.expectEqual(
		VehicleConfig.TIRE_FRICTION * VehicleConfig.SURFACE_GRIP.Road * math.cos(steepest) >= math.sin(steepest),
		true
	)
	local handbrakeLimit = math.atan(VehicleConfig.HANDBRAKE_FORCE_PER_LOAD / 2)
	for _, slope in HANDBRAKE_HOLD_SLOPES_DEGREES do
		Runner.expectEqual(math.rad(slope) < handbrakeLimit, true)
	end
end)

Runner.test("sideways on a slope the car stays still with no input", function()
	for _, fps in FRAME_RATES do
		for _, slope in SLOPES_DEGREES do
			for _, yaw in SIDE_YAWS_DEGREES do
				local speed = speedAfterHolding(slope, yaw, NO_INPUT, fps)
				if not (speed < MAX_HELD_SPEED) then
					error(`{slope} grados de costado (yaw {yaw}) a {fps} FPS: arrastra a {speed} studs/s`, 0)
				end
			end
		end
	end
end)

Runner.test("sideways on a slope the car stays still with the handbrake", function()
	for _, fps in FRAME_RATES do
		for _, slope in SLOPES_DEGREES do
			for _, yaw in SIDE_YAWS_DEGREES do
				local speed = speedAfterHolding(slope, yaw, HANDBRAKE, fps)
				if not (speed < MAX_HELD_SPEED) then
					error(`{slope} grados de costado (yaw {yaw}) a {fps} FPS: arrastra a {speed} studs/s`, 0)
				end
			end
		end
	end
end)

Runner.test("facing the slope or backwards the handbrake holds the car within its own limit", function()
	for _, fps in FRAME_RATES do
		for _, slope in HANDBRAKE_HOLD_SLOPES_DEGREES do
			for _, yaw in LENGTHWISE_YAWS_DEGREES do
				local speed = speedAfterHolding(slope, yaw, HANDBRAKE, fps)
				if not (speed < MAX_HELD_SPEED) then
					error(`{slope} grados, yaw {yaw}, freno de mano a {fps} FPS: arrastra a {speed} studs/s`, 0)
				end
			end
		end
	end
end)

Runner.finish()
