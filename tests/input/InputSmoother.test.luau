--!strict
local Runner = require("../Runner")
local InputConfig = require("../../src/input/core/InputConfig")
local InputSmoother = require("../../src/input/core/InputSmoother")

type RawInput = InputSmoother.RawInput
type InputState = InputSmoother.InputState

local FRAME_SECONDS = 0.025
local TOLERANCE = 1e-9

local function idleInput(): RawInput
	return {
		isSteerLeftDown = false,
		isSteerRightDown = false,
		isThrottleDown = false,
		isBrakeDown = false,
		isHandbrakeDown = false,
		isLookBackDown = false,
		gamepadSteer = 0,
		gamepadThrottle = 0,
		gamepadBrake = 0,
		lookDeltaX = 0,
		lookDeltaY = 0,
		gamepadLookX = 0,
		gamepadLookY = 0,
	}
end

local function runFor(state: InputState, raw: RawInput, seconds: number): InputState
	local current = state
	local steps = math.floor(seconds / FRAME_SECONDS + 0.5)
	for _ = 1, steps do
		current = InputSmoother.step(current, raw, FRAME_SECONDS)
	end
	return current
end

Runner.test("a new state is all zeros", function()
	local state = InputSmoother.newState()
	Runner.expectEqual(state.steer, 0)
	Runner.expectEqual(state.throttle, 0)
	Runner.expectEqual(state.brake, 0)
	Runner.expectEqual(state.isHandbrakeOn, false)
	Runner.expectEqual(state.isLookingBack, false)
end)

Runner.test("keyboard steering takes STEER_RISE_SECONDS to reach 1", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	local halfway = runFor(InputSmoother.newState(), raw, InputConfig.STEER_RISE_SECONDS / 2)
	Runner.expectNear(halfway.steer, 0.5, TOLERANCE)
	local full = runFor(InputSmoother.newState(), raw, InputConfig.STEER_RISE_SECONDS)
	Runner.expectNear(full.steer, 1, TOLERANCE)
	local beyond = runFor(InputSmoother.newState(), raw, InputConfig.STEER_RISE_SECONDS * 3)
	Runner.expectEqual(beyond.steer, 1)
end)

Runner.test("keyboard steering takes STEER_RETURN_SECONDS to come back to 0", function()
	local pressed = idleInput()
	pressed.isSteerRightDown = true
	local state = runFor(InputSmoother.newState(), pressed, InputConfig.STEER_RISE_SECONDS * 2)
	local halfway = runFor(state, idleInput(), InputConfig.STEER_RETURN_SECONDS / 2)
	Runner.expectNear(halfway.steer, 0.5, TOLERANCE)
	local released = runFor(state, idleInput(), InputConfig.STEER_RETURN_SECONDS)
	Runner.expectNear(released.steer, 0, TOLERANCE)
	Runner.expectEqual(runFor(state, idleInput(), InputConfig.STEER_RETURN_SECONDS * 3).steer, 0)
end)

Runner.test("steering to the left reaches -1", function()
	local raw = idleInput()
	raw.isSteerLeftDown = true
	local state = runFor(InputSmoother.newState(), raw, InputConfig.STEER_RISE_SECONDS * 2)
	Runner.expectEqual(state.steer, -1)
end)

Runner.test("both steering keys cancel out", function()
	local raw = idleInput()
	raw.isSteerLeftDown = true
	raw.isSteerRightDown = true
	local state = runFor(InputSmoother.newState(), raw, 1)
	Runner.expectEqual(state.steer, 0)
end)

Runner.test("switching from left to right goes through 0 first", function()
	local left = idleInput()
	left.isSteerLeftDown = true
	local state = runFor(InputSmoother.newState(), left, InputConfig.STEER_RISE_SECONDS * 2)
	local right = idleInput()
	right.isSteerRightDown = true
	local previous = state.steer
	local crossedZero = false
	local elapsed = 0
	local maxChange = FRAME_SECONDS / InputConfig.STEER_RETURN_SECONDS + TOLERANCE
	while elapsed < InputConfig.STEER_RETURN_SECONDS + InputConfig.STEER_RISE_SECONDS + 0.1 do
		state = InputSmoother.step(state, right, FRAME_SECONDS)
		elapsed += FRAME_SECONDS
		Runner.expectEqual(math.abs(state.steer - previous) <= maxChange, true)
		if state.steer >= 0 and previous < 0 then
			crossedZero = true
		end
		previous = state.steer
	end
	Runner.expectEqual(crossedZero, true)
	Runner.expectEqual(state.steer, 1)
end)

Runner.test("the time spent coming back to 0 is not lost when switching sides", function()
	local left = idleInput()
	left.isSteerLeftDown = true
	local state = runFor(InputSmoother.newState(), left, InputConfig.STEER_RISE_SECONDS / 2)
	Runner.expectNear(state.steer, -0.5, TOLERANCE)
	local right = idleInput()
	right.isSteerRightDown = true
	local stepSeconds = InputConfig.MAX_STEP_SECONDS
	local result = InputSmoother.step(state, right, stepSeconds)
	local secondsToZero = 0.5 * InputConfig.STEER_RETURN_SECONDS
	Runner.expectNear(result.steer, (stepSeconds - secondsToZero) / InputConfig.STEER_RISE_SECONDS, TOLERANCE)
end)

Runner.test("throttle and brake use their own ramps", function()
	local raw = idleInput()
	raw.isThrottleDown = true
	raw.isBrakeDown = true
	local state = runFor(InputSmoother.newState(), raw, InputConfig.BRAKE_RISE_SECONDS)
	Runner.expectNear(state.brake, 1, TOLERANCE)
	Runner.expectNear(state.throttle, InputConfig.BRAKE_RISE_SECONDS / InputConfig.THROTTLE_RISE_SECONDS, TOLERANCE)
	local released = runFor(state, idleInput(), InputConfig.BRAKE_RETURN_SECONDS)
	Runner.expectNear(released.brake, 0, TOLERANCE)
end)

Runner.test("the gamepad deadzone cuts at the zone and rescales after it", function()
	local zone = InputConfig.GAMEPAD_DEADZONE
	local raw = idleInput()
	raw.gamepadThrottle = 0
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).throttle, 0)
	raw.gamepadThrottle = zone
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).throttle, 0)
	raw.gamepadThrottle = zone * 0.99
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).throttle, 0)
	raw.gamepadThrottle = 1
	Runner.expectNear(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).throttle, 1, TOLERANCE)
	raw.gamepadThrottle = (1 + zone) / 2
	Runner.expectNear(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).throttle, 0.5, TOLERANCE)
end)

Runner.test("the gamepad steering is symmetric and applies the curve", function()
	local exponent = InputConfig.GAMEPAD_STEER_EXPONENT
	local raw = idleInput()
	raw.gamepadSteer = 1
	Runner.expectNear(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer, 1, TOLERANCE)
	raw.gamepadSteer = -1
	Runner.expectNear(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer, -1, TOLERANCE)
	raw.gamepadSteer = 0
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer, 0)
	raw.gamepadSteer = -(1 + InputConfig.GAMEPAD_DEADZONE) / 2
	local halfway = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer
	Runner.expectNear(halfway, -(0.5 ^ exponent), TOLERANCE)
end)

Runner.test("the gamepad has no ramp", function()
	local raw = idleInput()
	raw.gamepadSteer = 1
	raw.gamepadBrake = 1
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(state.steer, 1)
	Runner.expectEqual(state.brake, 1)
end)

Runner.test("the gamepad wins over the keyboard", function()
	local raw = idleInput()
	raw.isSteerLeftDown = true
	raw.isThrottleDown = true
	raw.gamepadSteer = 1
	raw.gamepadThrottle = (1 + InputConfig.GAMEPAD_DEADZONE) / 2
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectNear(state.steer, 1, TOLERANCE)
	Runner.expectNear(state.throttle, 0.5, TOLERANCE)
end)

Runner.test("when the gamepad goes back to the deadzone the keyboard continues from the last value", function()
	local raw = idleInput()
	raw.gamepadSteer = 1
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	raw.gamepadSteer = 0
	state = InputSmoother.step(state, raw, FRAME_SECONDS)
	Runner.expectNear(state.steer, 1 - FRAME_SECONDS / InputConfig.STEER_RETURN_SECONDS, TOLERANCE)
end)

Runner.test("values out of range and NaN are clamped", function()
	local raw = idleInput()
	raw.gamepadSteer = 1.3
	raw.gamepadThrottle = 5
	raw.gamepadBrake = -2
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(state.steer, 1)
	Runner.expectEqual(state.throttle, 1)
	Runner.expectEqual(state.brake, 0)
	raw.gamepadSteer = -7
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer, -1)
	raw.gamepadSteer = 0 / 0
	raw.gamepadThrottle = 0 / 0
	local broken = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(broken.steer, 0)
	Runner.expectEqual(broken.throttle, 0)
	raw.gamepadSteer = math.huge
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).steer, 1)
end)

Runner.test("the handbrake and look back pass through with no ramp", function()
	local raw = idleInput()
	raw.isHandbrakeDown = true
	raw.isLookBackDown = true
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(state.isHandbrakeOn, true)
	Runner.expectEqual(state.isLookingBack, true)
	state = InputSmoother.step(state, idleInput(), FRAME_SECONDS)
	Runner.expectEqual(state.isHandbrakeOn, false)
	Runner.expectEqual(state.isLookingBack, false)
end)

Runner.test("a dt that is not usable leaves the state unchanged", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	raw.isHandbrakeDown = true
	local state = runFor(InputSmoother.newState(), raw, 0.1)
	for _, dt in { 0, -1, 0 / 0, math.huge, -math.huge } do
		local result = InputSmoother.step(state, raw, dt)
		Runner.expectEqual(result.steer, state.steer)
		Runner.expectEqual(result.isHandbrakeOn, state.isHandbrakeOn)
		Runner.expectEqual(result == state, false)
	end
end)

Runner.test("a huge dt is capped to MAX_STEP_SECONDS", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	local result = InputSmoother.step(InputSmoother.newState(), raw, 10)
	Runner.expectNear(result.steer, InputConfig.MAX_STEP_SECONDS / InputConfig.STEER_RISE_SECONDS, TOLERANCE)
end)

Runner.test("a tiny dt still moves the value without breaking", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	local result = InputSmoother.step(InputSmoother.newState(), raw, 1e-9)
	Runner.expectEqual(result.steer > 0 and result.steer < 1e-6, true)
end)

Runner.test("step does not modify its arguments", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	local state = InputSmoother.newState()
	table.freeze(raw)
	table.freeze(state)
	local result = InputSmoother.step(state, raw, FRAME_SECONDS)
	Runner.expectEqual(result.steer > 0, true)
	Runner.expectEqual(state.steer, 0)
end)

Runner.test("the same inputs always give the same result", function()
	local raw = idleInput()
	raw.isSteerRightDown = true
	raw.isThrottleDown = true
	local first = runFor(InputSmoother.newState(), raw, 0.37)
	local second = runFor(InputSmoother.newState(), raw, 0.37)
	Runner.expectEqual(first.steer, second.steer)
	Runner.expectEqual(first.throttle, second.throttle)
end)

Runner.test("a new state does not turn the head", function()
	local state = InputSmoother.newState()
	Runner.expectEqual(state.lookYawRate, 0)
	Runner.expectEqual(state.lookPitchRate, 0)
end)

Runner.test("mouse movement becomes a turn rate in radians per second", function()
	local raw = idleInput()
	raw.lookDeltaX = 20
	raw.lookDeltaY = 10
	local result = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectNear(result.lookYawRate, 20 * InputConfig.MOUSE_LOOK_RADIANS_PER_PIXEL / FRAME_SECONDS, TOLERANCE)
	Runner.expectNear(result.lookPitchRate, -10 * InputConfig.MOUSE_LOOK_RADIANS_PER_PIXEL / FRAME_SECONDS, TOLERANCE)
end)

Runner.test("the same mouse movement over a longer frame turns slower", function()
	local raw = idleInput()
	raw.lookDeltaX = 20
	local short = InputSmoother.step(InputSmoother.newState(), raw, 0.01)
	local long = InputSmoother.step(InputSmoother.newState(), raw, 0.02)
	Runner.expectNear(short.lookYawRate, long.lookYawRate * 2, TOLERANCE)
end)

Runner.test("the right stick cuts at its deadzone and reaches the full rate", function()
	local raw = idleInput()
	raw.gamepadLookX = InputConfig.GAMEPAD_LOOK_DEADZONE
	Runner.expectEqual(InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS).lookYawRate, 0)
	raw.gamepadLookX = 1
	raw.gamepadLookY = -1
	local result = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectNear(result.lookYawRate, InputConfig.GAMEPAD_LOOK_RADIANS_PER_SECOND, TOLERANCE)
	Runner.expectNear(result.lookPitchRate, -InputConfig.GAMEPAD_LOOK_RADIANS_PER_SECOND, TOLERANCE)
end)

Runner.test("broken look values give no turn instead of NaN", function()
	local raw = idleInput()
	raw.lookDeltaX = 0 / 0
	raw.lookDeltaY = math.huge
	raw.gamepadLookX = 0 / 0
	raw.gamepadLookY = -math.huge
	local result = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(result.lookYawRate, 0)
	Runner.expectEqual(result.lookPitchRate, -InputConfig.GAMEPAD_LOOK_RADIANS_PER_SECOND)
end)

Runner.test("an invalid dt keeps the look rates", function()
	local raw = idleInput()
	raw.lookDeltaX = 20
	local state = InputSmoother.step(InputSmoother.newState(), raw, FRAME_SECONDS)
	Runner.expectEqual(InputSmoother.step(state, raw, 0 / 0).lookYawRate, state.lookYawRate)
	Runner.expectEqual(InputSmoother.step(state, raw, -1).lookYawRate, state.lookYawRate)
end)

Runner.finish()
