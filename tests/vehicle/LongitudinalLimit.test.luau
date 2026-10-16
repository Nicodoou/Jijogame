--!strict
-- El tope por paso de las fuerzas longitudinales que se oponen al movimiento (freno, freno de mano y resistencia al
-- rodar) vale para la suma de las cuatro ruedas: no pueden superar `masa · |v prevista| / dt` del chasis.
local Runner = require("../Runner")
local ToyWorld = require("./ToyWorld")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls

local MASS = 1000
local RELATIVE_TOLERANCE = 1e-5
local SLOPES_DEGREES = { 0, 10 }
local YAWS_DEGREES = { 0, 180 }
local FRAME_RATES = { 30, 60 }
local SPEEDS = { 0.02, 0.1, 0.5, 1, 4, 30, -0.3, -2 }
local BINDING_SPEED = 0.1
-- Con el pedal apretado y menos de esta velocidad entra la reversa, donde el freno pasa a ser empuje.
local REVERSE_ENGAGE_SPEED = 1
local BINDING_FRACTION = 0.999

local function controlsWith(brake: number, isHandbrakeOn: boolean): VehicleControls
	return { steer = 0, throttle = 0, brake = brake, isHandbrakeOn = isHandbrakeOn }
end

local CONTROLS: { VehicleControls } = {
	controlsWith(0, false),
	controlsWith(0, true),
	controlsWith(1, false),
	controlsWith(1, true),
	controlsWith(0.3, true),
}

-- Suma de las fuerzas de las cuatro ruedas a lo largo del frente del chasis tras un cuadro, y el tope que le toca.
local function opposingTotalAndLimit(
	fps: number,
	slopeDegrees: number,
	yawDegrees: number,
	speed: number,
	controls: VehicleControls
): (number, number)
	local runner = ToyWorld.new({
		frameSeconds = 1 / fps,
		slopeDegrees = slopeDegrees,
		initialYawDegrees = yawDegrees,
		isAlignedToSlope = true,
	})
	local world = runner.world
	local forward = world.forward
	world.linearVelocity = forward * speed
	local dt = world.frameSeconds
	local expectedSpeed = speed + vector.dot(vector.create(0, -world.gravity * dt, 0), forward)
	runner.step(controls)
	local total = 0
	for _, output in world.outputs do
		total += vector.dot(output.force, forward)
	end
	return total, MASS * math.abs(expectedSpeed) / dt
end

Runner.test("brake, handbrake and rolling resistance together never pass the one-step stop of the whole car", function()
	for _, fps in FRAME_RATES do
		for _, slope in SLOPES_DEGREES do
			for _, yaw in YAWS_DEGREES do
				for _, speed in SPEEDS do
					for _, controls in CONTROLS do
						if controls.brake > 0 and math.abs(speed) < REVERSE_ENGAGE_SPEED then
							continue
						end
						local total, limit = opposingTotalAndLimit(fps, slope, yaw, speed, controls)
						if not (math.abs(total) <= limit * (1 + RELATIVE_TOLERANCE) + 1e-6) then
							error(
								`{fps} FPS, {slope} grados, yaw {yaw}, v {speed}, freno {controls.brake}, freno de mano `
									.. `{controls.isHandbrakeOn}: la suma {total} pasa el tope {limit}`,
								0
							)
						end
					end
				end
			end
		end
	end
end)

Runner.test("on flat ground, when the handbrake asks for more than the limit the total is exactly the limit", function()
	for _, fps in FRAME_RATES do
		for _, yaw in YAWS_DEGREES do
			local total, limit = opposingTotalAndLimit(fps, 0, yaw, BINDING_SPEED, controlsWith(0, true))
			Runner.expectEqual(limit > 0, true)
			Runner.expectNear(math.abs(total) / limit, 1, 1 - BINDING_FRACTION)
		end
	end
end)

Runner.test("the opposing force pushes against the motion of the car", function()
	for _, speed in { 0.5, -0.5 } do
		local total = opposingTotalAndLimit(30, 0, 0, speed, controlsWith(0, true))
		Runner.expectEqual(total * speed < 0, true)
	end
end)

Runner.test("with no brake at speed the rolling resistance is far below the limit", function()
	local total, limit = opposingTotalAndLimit(30, 0, 0, 30, controlsWith(0, false))
	Runner.expectEqual(math.abs(total) < limit, true)
	Runner.expectEqual(math.abs(total) > 0, true)
end)

Runner.finish()
