--!strict
local Runner = require("../Runner")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleState = VehicleTypes.VehicleState
type VehicleControls = VehicleTypes.VehicleControls

local MASS = 1000
local FRAME_SECONDS = 1 / 30
local TOLERANCE = 1e-9
local GEAR_COUNT = #VehicleConfig.GEAR_RATIOS

local function stateIn(gear: number, shiftRemaining: number?): VehicleState
	return {
		wheels = {},
		gear = gear,
		shiftRemainingSeconds = shiftRemaining or 0,
		engineRpm = VehicleConfig.IDLE_RPM,
		rearGripFactor = 1,
	}
end

local function controlsWith(throttle: number, brake: number, isHandbrakeOn: boolean?): VehicleControls
	return { steer = 0, throttle = throttle, brake = brake, isHandbrakeOn = isHandbrakeOn or false }
end

local function speedFor(rpm: number, gear: number): number
	local ratio = if gear < 0 then VehicleConfig.REVERSE_RATIO else VehicleConfig.GEAR_RATIOS[gear]
	return rpm / 60 * 2 * math.pi * VehicleConfig.WHEEL_RADIUS_STUDS / (ratio * VehicleConfig.FINAL_DRIVE)
end

Runner.test("the torque curve gives the configured value at each point", function()
	for _, point in VehicleConfig.TORQUE_CURVE do
		Runner.expectNear(Drivetrain.torqueFraction(point.rpm), point.fraction, TOLERANCE)
	end
end)

Runner.test("the torque curve interpolates in a straight line between points", function()
	Runner.expectNear(Drivetrain.torqueFraction(2000), 0.75, TOLERANCE)
	Runner.expectNear(Drivetrain.torqueFraction(3750), 0.95, TOLERANCE)
	Runner.expectNear(Drivetrain.torqueFraction(5500), 0.925, TOLERANCE)
	Runner.expectNear(Drivetrain.torqueFraction(6750), 0.775, TOLERANCE)
end)

Runner.test("the torque curve is clamped at both ends", function()
	Runner.expectEqual(Drivetrain.torqueFraction(0), 0.6)
	Runner.expectEqual(Drivetrain.torqueFraction(-500), 0.6)
	Runner.expectEqual(Drivetrain.torqueFraction(7000), 0.7)
	Runner.expectEqual(Drivetrain.torqueFraction(20000), 0.7)
end)

Runner.test("the engine idles when the car is stopped", function()
	Runner.expectEqual(Drivetrain.engineRpm(0, 1), VehicleConfig.IDLE_RPM)
	Runner.expectEqual(Drivetrain.engineRpm(0.1, 3), VehicleConfig.IDLE_RPM)
end)

Runner.test("the engine rpm follows the speed and the gear ratio", function()
	for gear = 1, GEAR_COUNT do
		Runner.expectNear(Drivetrain.engineRpm(speedFor(4000, gear), gear), 4000, 1e-6)
	end
end)

Runner.test("the engine rpm is the same going backwards and uses the reverse ratio in reverse", function()
	Runner.expectNear(Drivetrain.engineRpm(-speedFor(3000, 2), 2), 3000, 1e-6)
	Runner.expectNear(Drivetrain.engineRpm(-speedFor(3000, -1), -1), 3000, 1e-6)
end)

Runner.test("the engine rpm never goes over the redline", function()
	Runner.expectEqual(Drivetrain.engineRpm(10000, 1), VehicleConfig.REDLINE_RPM)
	Runner.expectEqual(Drivetrain.engineRpm(math.huge, 5), VehicleConfig.REDLINE_RPM)
end)

Runner.test("the top speed in the last gear is about 150 studs per second", function()
	local topSpeed = speedFor(VehicleConfig.REDLINE_RPM, GEAR_COUNT)
	Runner.expectEqual(topSpeed > 135 and topSpeed < 165, true)
end)

Runner.test("it shifts up at the upshift rpm and starts a shift", function()
	local gear, remaining =
		Drivetrain.nextGear(stateIn(1), VehicleConfig.UPSHIFT_RPM, 40, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 2)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
end)

Runner.test("it does not shift up just below the upshift rpm", function()
	local gear, remaining =
		Drivetrain.nextGear(stateIn(1), VehicleConfig.UPSHIFT_RPM - 1, 40, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 1)
	Runner.expectEqual(remaining, 0)
end)

Runner.test("it never shifts above the last gear", function()
	local gear =
		Drivetrain.nextGear(stateIn(GEAR_COUNT), VehicleConfig.REDLINE_RPM, 140, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, GEAR_COUNT)
end)

Runner.test("it shifts down at the downshift rpm and starts a shift", function()
	local gear, remaining =
		Drivetrain.nextGear(stateIn(3), VehicleConfig.DOWNSHIFT_RPM, 40, controlsWith(0, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 2)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
	local stays =
		Drivetrain.nextGear(stateIn(3), VehicleConfig.DOWNSHIFT_RPM + 1, 40, controlsWith(0, 0), FRAME_SECONDS)
	Runner.expectEqual(stays, 3)
end)

Runner.test("it never shifts below first gear", function()
	local gear = Drivetrain.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, 5, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 1)
end)

Runner.test("the gears leave a gap between the upshift and the downshift rpm", function()
	for gear = 1, GEAR_COUNT - 1 do
		local rpmAfterUpshift = VehicleConfig.UPSHIFT_RPM
			* VehicleConfig.GEAR_RATIOS[gear + 1]
			/ VehicleConfig.GEAR_RATIOS[gear]
		Runner.expectEqual(rpmAfterUpshift > VehicleConfig.DOWNSHIFT_RPM, true)
	end
end)

Runner.test("while a shift is running no other shift can start and the time goes down", function()
	local midShift = stateIn(2, 0.2)
	local gear, remaining = Drivetrain.nextGear(midShift, VehicleConfig.UPSHIFT_RPM, 60, controlsWith(1, 0), 0.05)
	Runner.expectEqual(gear, 2)
	Runner.expectNear(remaining, 0.15, TOLERANCE)
	local finishedGear, finishedRemaining = Drivetrain.nextGear(midShift, 4000, 60, controlsWith(1, 0), 5)
	Runner.expectEqual(finishedGear, 2)
	Runner.expectEqual(finishedRemaining, 0)
end)

Runner.test("a shift can start in the same step the previous one finishes", function()
	local gear, remaining =
		Drivetrain.nextGear(stateIn(2, 0.01), VehicleConfig.UPSHIFT_RPM, 60, controlsWith(1, 0), 0.05)
	Runner.expectEqual(gear, 3)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
end)

Runner.test("with the brake pressed and no throttle it engages reverse when almost stopped", function()
	local gear = Drivetrain.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, 0, controlsWith(0, 1), FRAME_SECONDS)
	Runner.expectEqual(gear, -1)
	local slowBackwards =
		Drivetrain.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, -0.5, controlsWith(0, 0.2), FRAME_SECONDS)
	Runner.expectEqual(slowBackwards, -1)
end)

Runner.test("reverse is not engaged at or above the engage speed, with throttle or without brake", function()
	local speed = VehicleConfig.REVERSE_ENGAGE_SPEED
	Runner.expectEqual(Drivetrain.nextGear(stateIn(1), 1000, speed, controlsWith(0, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Drivetrain.nextGear(stateIn(1), 1000, -speed, controlsWith(0, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Drivetrain.nextGear(stateIn(1), 1000, 0, controlsWith(0.1, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Drivetrain.nextGear(stateIn(1), 1000, 0, controlsWith(0, 0), FRAME_SECONDS), 1)
end)

Runner.test("reverse goes back to first with throttle when almost stopped", function()
	Runner.expectEqual(Drivetrain.nextGear(stateIn(-1), 1000, 0, controlsWith(1, 0), FRAME_SECONDS), 1)
	Runner.expectEqual(Drivetrain.nextGear(stateIn(-1), 1000, -0.9, controlsWith(0.1, 0), FRAME_SECONDS), 1)
end)

Runner.test("reverse stays while still moving or without throttle", function()
	local speed = VehicleConfig.REVERSE_ENGAGE_SPEED
	Runner.expectEqual(Drivetrain.nextGear(stateIn(-1), 1000, -speed, controlsWith(1, 0), FRAME_SECONDS), -1)
	Runner.expectEqual(Drivetrain.nextGear(stateIn(-1), 1000, 0, controlsWith(0, 1), FRAME_SECONDS), -1)
	Runner.expectEqual(
		Drivetrain.nextGear(stateIn(-1), VehicleConfig.REDLINE_RPM, -40, controlsWith(0, 1), FRAME_SECONDS),
		-1
	)
end)

Runner.test("the drive force at full throttle in first gear is the peak acceleration times the torque", function()
	local force = Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 4500, MASS)
	Runner.expectNear(force, MASS * VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION, 1e-6)
	local atIdle = Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 1000, MASS)
	Runner.expectNear(atIdle, MASS * VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION * 0.6, 1e-6)
end)

Runner.test("the drive force is proportional to the throttle and the mass", function()
	local full = Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 3000, MASS)
	Runner.expectNear(Drivetrain.driveForce(stateIn(1), controlsWith(0.5, 0), 3000, MASS), full / 2, 1e-6)
	Runner.expectNear(Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 3000, 2 * MASS), 2 * full, 1e-6)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(1), controlsWith(0, 0), 3000, MASS), 0)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 3000, 0), 0)
end)

Runner.test("higher gears push less in proportion to their ratio", function()
	local first = Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 4500, MASS)
	local fifth = Drivetrain.driveForce(stateIn(GEAR_COUNT), controlsWith(1, 0), 4500, MASS)
	Runner.expectNear(fifth, first * VehicleConfig.GEAR_RATIOS[GEAR_COUNT] / VehicleConfig.GEAR_RATIOS[1], 1e-6)
end)

Runner.test("the drive force is cut during a shift and at the redline", function()
	Runner.expectEqual(Drivetrain.driveForce(stateIn(2, 0.1), controlsWith(1, 0), 4500, MASS), 0)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), VehicleConfig.REDLINE_RPM, MASS), 0)
	Runner.expectEqual(
		Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), VehicleConfig.REDLINE_RPM - 1, MASS) > 0,
		true
	)
end)

Runner.test("a shift with a torque fraction keeps part of the force", function()
	local settings = table.clone(VehicleConfig)
	settings.SHIFT_TORQUE_FRACTION = 0.4
	local full = Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), 4500, MASS, settings)
	local shifting = Drivetrain.driveForce(stateIn(2, 0.1), controlsWith(1, 0), 4500, MASS, settings)
	Runner.expectNear(shifting, full * 0.4, 1e-6)
end)

Runner.test("in reverse the brake pedal pushes backwards and the throttle does not push", function()
	local backwards = Drivetrain.driveForce(stateIn(-1), controlsWith(0, 1), 3000, MASS)
	Runner.expectEqual(backwards < 0, true)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(-1), controlsWith(1, 0), 3000, MASS), 0)
end)

Runner.test("in reverse the engine pushes with a fraction of the forward force", function()
	local forward = Drivetrain.driveForce(stateIn(1), controlsWith(1, 0), 3000, MASS)
	local ratioScale = VehicleConfig.REVERSE_RATIO / VehicleConfig.GEAR_RATIOS[1]
	local backwards = Drivetrain.driveForce(stateIn(-1), controlsWith(0, 1), 3000, MASS)
	Runner.expectNear(backwards, -forward * ratioScale * VehicleConfig.REVERSE_DRIVE_FRACTION, 1e-6)
end)

Runner.test("the force fades linearly over the soft limiter band and is zero at the redline", function()
	local band = VehicleConfig.SOFT_LIMITER_RPM
	local top = VehicleConfig.REDLINE_RPM
	local below = Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), top - band, MASS)
	local expectedBelow = MASS
		* VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION
		* Drivetrain.torqueFraction(top - band)
		* VehicleConfig.GEAR_RATIOS[2]
		/ VehicleConfig.GEAR_RATIOS[1]
	Runner.expectNear(below, expectedBelow, 1e-6)
	local half = Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), top - band / 2, MASS)
	local expectedHalf = MASS
		* VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION
		* Drivetrain.torqueFraction(top - band / 2)
		* VehicleConfig.GEAR_RATIOS[2]
		/ VehicleConfig.GEAR_RATIOS[1]
		/ 2
	Runner.expectNear(half, expectedHalf, 1e-6)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), top, MASS), 0)
	Runner.expectEqual(Drivetrain.driveForce(stateIn(2), controlsWith(1, 0), top + 1000, MASS), 0)
end)

Runner.test("split gives the rear axle its share in the order FL, FR, RL, RR", function()
	local shares = Drivetrain.split(1000)
	Runner.expectEqual(#shares, 4)
	Runner.expectNear(shares[1], 1000 * (1 - VehicleConfig.REAR_BIAS) / 2, TOLERANCE)
	Runner.expectEqual(shares[1], shares[2])
	Runner.expectNear(shares[3], 1000 * VehicleConfig.REAR_BIAS / 2, TOLERANCE)
	Runner.expectEqual(shares[3], shares[4])
	Runner.expectNear(shares[1] + shares[2] + shares[3] + shares[4], 1000, TOLERANCE)
end)

Runner.test("split works at the two extremes of the rear bias", function()
	local frontOnly = table.clone(VehicleConfig)
	frontOnly.REAR_BIAS = 0
	local rearOnly = table.clone(VehicleConfig)
	rearOnly.REAR_BIAS = 1
	local front = Drivetrain.split(800, frontOnly)
	local rear = Drivetrain.split(800, rearOnly)
	Runner.expectEqual(front[1], 400)
	Runner.expectEqual(front[3], 0)
	Runner.expectEqual(rear[1], 0)
	Runner.expectEqual(rear[4], 400)
	Runner.expectEqual(Drivetrain.split(-600, rearOnly)[3] < 0, true)
end)

Runner.test("the brake request is a positive force with no direction", function()
	local state = stateIn(1)
	Runner.expectEqual(Drivetrain.brakeRequest(state, controlsWith(0, 1), MASS, true, 50000) > 0, true)
	Runner.expectEqual(Drivetrain.brakeRequest(state, controlsWith(0, 0), MASS, true, 50000), 0)
end)

Runner.test("the brake request splits between the axles with the front bias", function()
	local state = stateIn(1)
	local front = Drivetrain.brakeRequest(state, controlsWith(0, 1), MASS, true, 50000)
	local rear = Drivetrain.brakeRequest(state, controlsWith(0, 1), MASS, false, 50000)
	Runner.expectNear(front, MASS * VehicleConfig.BRAKE_DECELERATION * VehicleConfig.BRAKE_FRONT_BIAS / 2, 1e-6)
	Runner.expectNear(rear, MASS * VehicleConfig.BRAKE_DECELERATION * (1 - VehicleConfig.BRAKE_FRONT_BIAS) / 2, 1e-6)
	Runner.expectNear(2 * (front + rear), MASS * VehicleConfig.BRAKE_DECELERATION, 1e-6)
end)

Runner.test("the brake request is proportional to the pedal", function()
	local state = stateIn(1)
	local full = Drivetrain.brakeRequest(state, controlsWith(0, 1), MASS, false, 0)
	Runner.expectNear(Drivetrain.brakeRequest(state, controlsWith(0, 0.25), MASS, false, 0), full / 4, 1e-6)
end)

Runner.test("the handbrake brakes only the rear wheels, in proportion to their load", function()
	local state = stateIn(1)
	local load = 50000
	local rear = Drivetrain.brakeRequest(state, controlsWith(0, 0, true), MASS, false, load)
	local front = Drivetrain.brakeRequest(state, controlsWith(0, 0, true), MASS, true, load)
	Runner.expectNear(rear, VehicleConfig.HANDBRAKE_FORCE_PER_LOAD * load, 1e-6)
	Runner.expectEqual(front, 0)
	Runner.expectNear(Drivetrain.brakeRequest(state, controlsWith(0, 0, true), MASS, false, load / 2), rear / 2, 1e-6)
end)

Runner.test("the handbrake adds to the brake pedal at the rear", function()
	local state = stateIn(1)
	local pedalOnly = Drivetrain.brakeRequest(state, controlsWith(0, 1), MASS, false, 40000)
	local both = Drivetrain.brakeRequest(state, controlsWith(0, 1, true), MASS, false, 40000)
	Runner.expectNear(both, pedalOnly + VehicleConfig.HANDBRAKE_FORCE_PER_LOAD * 40000, 1e-6)
end)

Runner.test("in reverse the throttle is the brake", function()
	local reverse = stateIn(-1)
	Runner.expectEqual(Drivetrain.brakeRequest(reverse, controlsWith(1, 0), MASS, true, 0) > 0, true)
	Runner.expectEqual(Drivetrain.brakeRequest(reverse, controlsWith(0, 1), MASS, true, 0), 0)
end)

Runner.test("functions do not modify their arguments", function()
	local state = stateIn(2, 0.1)
	table.freeze(state)
	local controls = controlsWith(1, 0)
	table.freeze(controls)
	Drivetrain.nextGear(state, 6500, 60, controls, FRAME_SECONDS)
	Drivetrain.driveForce(state, controls, 4000, MASS)
	Drivetrain.brakeRequest(state, controls, MASS, true, 40000)
	Runner.expectEqual(state.gear, 2)
end)

Runner.finish()
