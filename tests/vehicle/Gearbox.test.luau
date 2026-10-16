--!strict
local Runner = require("../Runner")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local Gearbox = require("../../src/vehicle/core/Gearbox")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type VehicleState = VehicleTypes.VehicleState
type VehicleControls = VehicleTypes.VehicleControls

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
		secondsSinceUpshift = VehicleConfig.GEAR_HOLD_SECONDS,
		filteredForwardY = nil,
	}
end

local function controlsWith(throttle: number, brake: number, isHandbrakeOn: boolean?): VehicleControls
	return { steer = 0, throttle = throttle, brake = brake, isHandbrakeOn = isHandbrakeOn or false }
end

local function speedFor(rpm: number, gear: number): number
	local ratio = if gear < 0 then VehicleConfig.REVERSE_RATIO else VehicleConfig.GEAR_RATIOS[gear]
	return rpm / 60 * 2 * math.pi * VehicleConfig.WHEEL_RADIUS_STUDS / (ratio * VehicleConfig.FINAL_DRIVE)
end

-- En quinta a esta velocidad las RPM están por encima de DOWNSHIFT_RPM: solo el kickdown puede bajar.
local KICKDOWN_SPEED = 70

local function speedForRpm(rpm: number, gear: number): number
	return speedFor(rpm, gear)
end

-- Cuesta de unos 15 grados: más de lo que empuja la quinta a esa velocidad y menos de lo que empuja la primera.
local STEEP_LOAD = 70
local NO_LOAD = 0
-- Cuesta que la tercera todavía sube a 55 studs/s pero la cuarta y la quinta no.
local MEDIUM_LOAD = 40

local function kick(state: VehicleState, speed: number, throttle: number, load: number, dt: number?): number
	local rpm = Drivetrain.engineRpm(speed, state.gear)
	return (Gearbox.nextGear(state, rpm, speed, controlsWith(throttle, 0), dt or FRAME_SECONDS, nil, load))
end

local function stateAfter(gear: number, secondsSinceUpshift: number): VehicleState
	local state = stateIn(gear)
	state.secondsSinceUpshift = secondsSinceUpshift
	return state
end

Runner.test("it shifts up at the upshift rpm and starts a shift", function()
	local gear, remaining =
		Gearbox.nextGear(stateIn(1), VehicleConfig.UPSHIFT_RPM, 40, controlsWith(0.5, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 2)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
end)

Runner.test("it does not shift up just below the upshift rpm", function()
	local gear, remaining =
		Gearbox.nextGear(stateIn(1), VehicleConfig.UPSHIFT_RPM - 1, 40, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 1)
	Runner.expectEqual(remaining, 0)
end)

Runner.test("it never shifts above the last gear", function()
	local gear =
		Gearbox.nextGear(stateIn(GEAR_COUNT), VehicleConfig.REDLINE_RPM, 140, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, GEAR_COUNT)
end)

Runner.test("it shifts down at the downshift rpm and starts a shift", function()
	local gear, remaining =
		Gearbox.nextGear(stateIn(3), VehicleConfig.DOWNSHIFT_RPM, 40, controlsWith(0, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 2)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
	local stays = Gearbox.nextGear(stateIn(3), VehicleConfig.DOWNSHIFT_RPM + 1, 40, controlsWith(0, 0), FRAME_SECONDS)
	Runner.expectEqual(stays, 3)
end)

Runner.test("it never shifts below first gear", function()
	local gear = Gearbox.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, 5, controlsWith(1, 0), FRAME_SECONDS)
	Runner.expectEqual(gear, 1)
end)

Runner.test("while a shift is running no other shift can start and the time goes down", function()
	local midShift = stateIn(2, 0.2)
	local gear, remaining = Gearbox.nextGear(midShift, VehicleConfig.UPSHIFT_RPM, 60, controlsWith(1, 0), 0.05)
	Runner.expectEqual(gear, 2)
	Runner.expectNear(remaining, 0.15, TOLERANCE)
	local finishedGear, finishedRemaining = Gearbox.nextGear(midShift, 4000, 60, controlsWith(1, 0), 5)
	Runner.expectEqual(finishedGear, 2)
	Runner.expectEqual(finishedRemaining, 0)
end)

Runner.test("a shift can start in the same step the previous one finishes", function()
	local gear, remaining =
		Gearbox.nextGear(stateIn(2, 0.01), VehicleConfig.UPSHIFT_RPM, 60, controlsWith(0.5, 0), 0.05)
	Runner.expectEqual(gear, 3)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
end)

Runner.test("with the brake pressed and no throttle it engages reverse when almost stopped", function()
	local gear = Gearbox.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, 0, controlsWith(0, 1), FRAME_SECONDS)
	Runner.expectEqual(gear, -1)
	local slowBackwards =
		Gearbox.nextGear(stateIn(1), VehicleConfig.IDLE_RPM, -0.5, controlsWith(0, 0.2), FRAME_SECONDS)
	Runner.expectEqual(slowBackwards, -1)
end)

Runner.test("reverse is not engaged at or above the engage speed, with throttle or without brake", function()
	local speed = VehicleConfig.REVERSE_ENGAGE_SPEED
	Runner.expectEqual(Gearbox.nextGear(stateIn(1), 1000, speed, controlsWith(0, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Gearbox.nextGear(stateIn(1), 1000, -speed, controlsWith(0, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Gearbox.nextGear(stateIn(1), 1000, 0, controlsWith(0.1, 1), FRAME_SECONDS), 1)
	Runner.expectEqual(Gearbox.nextGear(stateIn(1), 1000, 0, controlsWith(0, 0), FRAME_SECONDS), 1)
end)

Runner.test("reverse goes back to first with throttle when almost stopped", function()
	Runner.expectEqual(Gearbox.nextGear(stateIn(-1), 1000, 0, controlsWith(1, 0), FRAME_SECONDS), 1)
	Runner.expectEqual(Gearbox.nextGear(stateIn(-1), 1000, -0.9, controlsWith(0.1, 0), FRAME_SECONDS), 1)
end)

Runner.test("reverse stays while still moving or without throttle", function()
	local speed = VehicleConfig.REVERSE_ENGAGE_SPEED
	Runner.expectEqual(Gearbox.nextGear(stateIn(-1), 1000, -speed, controlsWith(1, 0), FRAME_SECONDS), -1)
	Runner.expectEqual(Gearbox.nextGear(stateIn(-1), 1000, 0, controlsWith(0, 1), FRAME_SECONDS), -1)
	Runner.expectEqual(
		Gearbox.nextGear(stateIn(-1), VehicleConfig.REDLINE_RPM, -40, controlsWith(0, 1), FRAME_SECONDS),
		-1
	)
end)

Runner.test("at full throttle on a steep slope it kicks down from fifth", function()
	local rpm = Drivetrain.engineRpm(KICKDOWN_SPEED, 5)
	local gear, remaining =
		Gearbox.nextGear(stateIn(5), rpm, KICKDOWN_SPEED, controlsWith(1, 0), FRAME_SECONDS, nil, STEEP_LOAD)
	Runner.expectEqual(gear < 5, true)
	Runner.expectEqual(remaining, VehicleConfig.SHIFT_DURATION_SECONDS)
end)

Runner.test("with no load the car can still accelerate, so there is no kickdown", function()
	Runner.expectEqual(kick(stateIn(5), KICKDOWN_SPEED, 1, NO_LOAD), 5)
end)

Runner.test("with the throttle at 0.5 there is no kickdown even on a steep slope", function()
	Runner.expectEqual(kick(stateIn(5), KICKDOWN_SPEED, 0.5, STEEP_LOAD), 5)
end)

Runner.test("the kickdown starts only from the configured throttle", function()
	Runner.expectEqual(kick(stateIn(5), KICKDOWN_SPEED, VehicleConfig.KICKDOWN_THROTTLE - 0.01, STEEP_LOAD), 5)
	Runner.expectEqual(kick(stateIn(5), KICKDOWN_SPEED, VehicleConfig.KICKDOWN_THROTTLE, STEEP_LOAD) < 5, true)
end)

Runner.test("it jumps straight to the highest gear that still accelerates with the load", function()
	local speed = 55
	local target = kick(stateIn(5), speed, 1, MEDIUM_LOAD)
	local pushes = function(gear: number): number
		return VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION * Drivetrain.gearForce(gear, speed) - MEDIUM_LOAD
	end
	Runner.expectEqual(target <= 3, true)
	Runner.expectEqual(pushes(target) >= VehicleConfig.KICKDOWN_ACCEL_MARGIN, true)
	Runner.expectEqual(pushes(target + 1) < VehicleConfig.KICKDOWN_ACCEL_MARGIN, true)
end)

Runner.test("it never kicks down to a gear above the kickdown rpm limit", function()
	local speed = speedForRpm(VehicleConfig.KICKDOWN_MAX_RPM + 100, 3)
	Runner.expectEqual(kick(stateIn(4), speed, 1, STEEP_LOAD), 4)
	local belowLimit = speedForRpm(VehicleConfig.KICKDOWN_MAX_RPM - 100, 3)
	Runner.expectEqual(kick(stateIn(4), belowLimit, 1, STEEP_LOAD), 3)
end)

Runner.test("when no gear gets the margin it takes the lowest one inside the rpm limit", function()
	local hugeLoad = 1000
	local speed = speedForRpm(VehicleConfig.KICKDOWN_MAX_RPM - 100, 2)
	Runner.expectEqual(kick(stateIn(4), speed, 1, hugeLoad), 2)
end)

Runner.test("no kickdown before the minimum time since the last upshift", function()
	local hold = VehicleConfig.GEAR_HOLD_SECONDS
	Runner.expectEqual(kick(stateAfter(5, hold - 0.1), KICKDOWN_SPEED, 1, STEEP_LOAD, 0.05), 5)
	Runner.expectEqual(kick(stateAfter(5, hold - 0.04), KICKDOWN_SPEED, 1, STEEP_LOAD, 0.05) < 5, true)
end)

Runner.test("the minimum time counts from an upshift, not from a downshift", function()
	local state = stateAfter(4, 0.1)
	local memorySeconds = Gearbox.nextMemory(state, 3, 0, FRAME_SECONDS)
	Runner.expectNear(memorySeconds, 0.1 + FRAME_SECONDS, 1e-12)
	Runner.expectEqual((Gearbox.nextMemory(state, 5, 0, FRAME_SECONDS)), 0)
	Runner.expectEqual(kick(stateAfter(4, VehicleConfig.GEAR_HOLD_SECONDS), 40, 1, STEEP_LOAD) < 4, true)
end)

Runner.test("at full throttle in second gear close to the limiter it shifts up when the load is small", function()
	local speed = speedForRpm(VehicleConfig.REDLINE_RPM - VehicleConfig.SOFT_LIMITER_RPM + 50, 2)
	Runner.expectEqual(kick(stateIn(2), speed, 1, NO_LOAD), 3)
end)

Runner.test("at full throttle it does not upshift when the gear above could not climb after the shift", function()
	local speed = speedForRpm(VehicleConfig.UPSHIFT_RPM + 100, 1)
	Runner.expectEqual(kick(stateIn(1), speed, 1, STEEP_LOAD), 1)
end)

Runner.test("the upshift looks at the speed after the cut: more load makes it stay", function()
	local speed = speedForRpm(VehicleConfig.UPSHIFT_RPM + 100, 2)
	Runner.expectEqual(kick(stateIn(2), speed, 1, 20), 3)
	Runner.expectEqual(kick(stateIn(2), speed, 1, 60), 2)
end)

Runner.test("the slope is filtered toward the measured one", function()
	local state = stateIn(3)
	state.filteredForwardY = 0.1
	local alpha = 1 - math.exp(-VehicleConfig.LOAD_PITCH_FILTER_RATE * FRAME_SECONDS)
	Runner.expectNear(Gearbox.filteredSlope(state, 0.3, FRAME_SECONDS), 0.1 + 0.2 * alpha, 1e-12)
	Runner.expectEqual(Gearbox.filteredSlope(stateIn(3), 0.25, FRAME_SECONDS), 0.25)
end)

Runner.test("a slope that is not finite counts as flat", function()
	Runner.expectEqual(Gearbox.filteredSlope(stateIn(3), 0 / 0, FRAME_SECONDS), 0)
	Runner.expectEqual(Gearbox.filteredSlope(stateIn(3), math.huge, FRAME_SECONDS), 0)
end)

Runner.test("the load is gravity along the car plus the rolling resistance", function()
	Runner.expectNear(Gearbox.load(0.2, 196.2, 0.015), 196.2 * 0.215, 1e-9)
	Runner.expectNear(Gearbox.load(-0.2, 196.2, 0.015), 196.2 * -0.185, 1e-9)
	Runner.expectEqual(Gearbox.load(0, 196.2, 0), 0)
end)

Runner.test("the gearbox memory keeps the filtered slope", function()
	local state = stateAfter(3, 2)
	state.filteredForwardY = 0.1
	local _, slope = Gearbox.nextMemory(state, 3, 0.1, FRAME_SECONDS)
	Runner.expectNear(slope, 0.1, 1e-12)
end)

Runner.test("at full throttle the old downshift rpm no longer applies (the kickdown decides)", function()
	local speed = 25
	Runner.expectEqual(Drivetrain.engineRpm(speed, 2) <= VehicleConfig.DOWNSHIFT_RPM, true)
	Runner.expectEqual(kick(stateIn(2), speed, 1, NO_LOAD), 2)
	Runner.expectEqual(kick(stateIn(2), speed, 0.5, NO_LOAD), 1)
end)

Runner.test("no kickdown during a shift, in first gear or while reversing", function()
	local shifting = stateIn(5, 0.2)
	Runner.expectEqual(kick(shifting, KICKDOWN_SPEED, 1, STEEP_LOAD, 0.05), 5)
	Runner.expectEqual(kick(stateIn(1), 10, 1, STEEP_LOAD), 1)
	local reversing = Gearbox.nextGear(stateIn(-1), 2000, -10, controlsWith(1, 0), FRAME_SECONDS, nil, STEEP_LOAD)
	Runner.expectEqual(reversing, -1)
end)

Runner.test("the last gear is never exceeded at full throttle", function()
	local topSpeed = speedForRpm(VehicleConfig.REDLINE_RPM - 100, GEAR_COUNT)
	Runner.expectEqual(kick(stateIn(GEAR_COUNT), topSpeed, 1, NO_LOAD), GEAR_COUNT)
end)

Runner.test("the gearbox functions do not modify their arguments", function()
	local state = stateIn(2, 0.1)
	table.freeze(state)
	local controls = controlsWith(1, 0)
	table.freeze(controls)
	Gearbox.nextGear(state, 6500, 60, controls, FRAME_SECONDS, nil, 10)
	Gearbox.nextMemory(state, 3, 0.1, FRAME_SECONDS)
	Gearbox.filteredSlope(state, 0.2, FRAME_SECONDS)
	Runner.expectEqual(state.gear, 2)
end)

Runner.finish()
