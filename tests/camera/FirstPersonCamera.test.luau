--!strict
local Runner = require("../Runner")
local CameraConfig = require("../../src/camera/core/CameraConfig")
local FirstPersonCamera = require("../../src/camera/core/FirstPersonCamera")

type VehicleView = FirstPersonCamera.VehicleView
type LookRates = FirstPersonCamera.LookRates
type CameraState = FirstPersonCamera.CameraState
type CameraPose = FirstPersonCamera.CameraPose

local FRAME_SECONDS = 1 / 60
local TOLERANCE = 1e-9
-- `vector` guarda floats de 32 bits: con posiciones de decenas de studs el error ronda 1e-6.
local VECTOR_TOLERANCE = 1e-5
local ONE_G = 196.2
local HEAD = vector.create(10, 3, -20)
local RIGHT = vector.create(1, 0, 0)
local UP = vector.create(0, 1, 0)
local FORWARD = vector.create(0, 0, -1)
local NO_LOOK: LookRates = { yawRate = 0, pitchRate = 0 }

-- Estas pruebas miden la cámara sin los ajustes del experimento: horizonte libre, multiplicadores en 1, sin girar el yaw.
local CLASSIC: { [string]: any } = table.clone(CameraConfig :: any)
local classicOverrides: { [string]: number } =
	{ HORIZON_LOCK = 0, HEAD_SWAY = 1, HEAD_TILT = 1, HEAD_VIBRATION = 1, LOOK_INTO_VELOCITY = 0 }
for key, value in classicOverrides do
	CLASSIC[key] = value
end

local function classicStep(
	state: CameraState,
	view: VehicleView,
	look: LookRates,
	isLookingBack: boolean,
	dt: number
): (CameraState, CameraPose)
	return FirstPersonCamera.step(state, view, look, isLookingBack, dt, CLASSIC :: any)
end

local function viewMoving(velocity: vector): VehicleView
	return { right = RIGHT, up = UP, forward = FORWARD, headPosition = HEAD, linearVelocity = velocity }
end

local STILL = viewMoving(vector.zero)

local function frames(seconds: number): number
	return math.floor(seconds / FRAME_SECONDS + 0.5)
end

-- Corre la cámara cuadro a cuadro; `viewAt` da la vista en cada instante y `observe` mira cada pose.
local function simulate(
	seconds: number,
	viewAt: (number) -> VehicleView,
	look: LookRates,
	observe: (CameraPose, number) -> (),
	startState: CameraState?
): CameraState
	local state = startState or FirstPersonCamera.newState()
	for index = 1, frames(seconds) do
		local time = index * FRAME_SECONDS
		local pose
		state, pose = classicStep(state, viewAt(time), look, false, FRAME_SECONDS)
		observe(pose, time)
	end
	return state
end

local function ignore(_pose: CameraPose, _time: number) end

local function angleBetween(first: vector, second: vector): number
	return math.acos(math.clamp(vector.dot(first, second), -1, 1))
end

local function offsetAlong(pose: CameraPose, axis: vector): number
	return vector.dot(pose.position - HEAD, axis)
end

local function isFinitePose(pose: CameraPose): boolean
	for _, value in { pose.position, pose.right, pose.up, pose.forward } do
		local total = value.x + value.y + value.z
		if total ~= total or math.abs(total) == math.huge then
			return false
		end
	end
	return true
end

local function deepFreeze(state: CameraState)
	for _, spring in { state.swayRight, state.swayForward, state.tiltRoll, state.tiltPitch } do
		table.freeze(spring)
	end
	table.freeze(state)
end

Runner.test("a car at rest leaves the head still and looking forward", function()
	local lastPose
	simulate(
		2,
		function()
			return STILL
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end
	)
	Runner.expectEqual(lastPose.position, HEAD)
	Runner.expectEqual(lastPose.forward, FORWARD)
	Runner.expectEqual(lastPose.up, UP)
	Runner.expectEqual(lastPose.right, RIGHT)
end)

Runner.test("the head follows the position it is given", function()
	local moved = {
		right = RIGHT,
		up = UP,
		forward = FORWARD,
		headPosition = vector.create(-5, 8, 40),
		linearVelocity = vector.zero,
	}
	local _, pose = classicStep(FirstPersonCamera.newState(), moved, NO_LOOK, false, FRAME_SECONDS)
	Runner.expectEqual(pose.position, vector.create(-5, 8, 40))
end)

Runner.test("a positive yaw rate looks right and a positive pitch rate looks up", function()
	local state = FirstPersonCamera.newState()
	local _, pose = classicStep(state, STILL, { yawRate = 1, pitchRate = 0 }, false, FRAME_SECONDS)
	Runner.expectEqual(vector.dot(pose.forward, RIGHT) > 0, true)
	_, pose = classicStep(state, STILL, { yawRate = 0, pitchRate = 1 }, false, FRAME_SECONDS)
	Runner.expectEqual(vector.dot(pose.forward, UP) > 0, true)
end)

Runner.test("the look yaw stops at its limit on both sides", function()
	for _, sign in { 1, -1 } do
		local lastPose
		simulate(5, function()
			return STILL
		end, { yawRate = 3 * sign, pitchRate = 0 }, function(pose)
			lastPose = pose
		end)
		Runner.expectNear(angleBetween(lastPose.forward, FORWARD), math.rad(CameraConfig.LOOK_MAX_YAW_DEGREES), 1e-6)
		Runner.expectEqual(vector.dot(lastPose.forward, RIGHT) * sign > 0, true)
	end
end)

Runner.test("the look pitch stops at its limit up and down", function()
	for _, sign in { 1, -1 } do
		local lastPose
		simulate(5, function()
			return STILL
		end, { yawRate = 0, pitchRate = 3 * sign }, function(pose)
			lastPose = pose
		end)
		Runner.expectNear(angleBetween(lastPose.forward, FORWARD), math.rad(CameraConfig.LOOK_MAX_PITCH_DEGREES), 1e-6)
		Runner.expectEqual(vector.dot(lastPose.forward, UP) * sign > 0, true)
	end
end)

Runner.test("the head is back to 95 percent in one second when the look input stops", function()
	local looked = simulate(5, function()
		return STILL
	end, { yawRate = 3, pitchRate = 3 }, ignore)
	local lastPose
	simulate(
		1,
		function()
			return STILL
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end,
		looked
	)
	local limit = math.rad(CameraConfig.LOOK_MAX_YAW_DEGREES)
	Runner.expectEqual(math.abs(looked.lookYawRadians) >= limit - 1e-9, true)
	Runner.expectEqual(angleBetween(lastPose.forward, FORWARD) <= 0.05 * limit, true)
	Runner.expectEqual(math.abs(vector.dot(lastPose.right, FORWARD)) <= 0.05 * limit, true)
end)

Runner.test("looking back turns 180 degrees at once and looking forward again is also at once", function()
	local state = FirstPersonCamera.newState()
	local back, pose = classicStep(state, STILL, NO_LOOK, true, FRAME_SECONDS)
	Runner.expectNear(vector.dot(pose.forward, FORWARD), -1, TOLERANCE)
	Runner.expectNear(vector.dot(pose.right, RIGHT), -1, TOLERANCE)
	Runner.expectNear(vector.dot(pose.up, UP), 1, TOLERANCE)
	local _, facingForward = classicStep(back, STILL, NO_LOOK, false, FRAME_SECONDS)
	Runner.expectNear(vector.dot(facingForward.forward, FORWARD), 1, TOLERANCE)
end)

Runner.test("looking back keeps the look limit relative to the back", function()
	local state = FirstPersonCamera.newState()
	for _ = 1, frames(5) do
		state = classicStep(state, STILL, { yawRate = 3, pitchRate = 0 }, true, FRAME_SECONDS)
	end
	Runner.expectNear(state.lookYawRadians, math.rad(CameraConfig.LOOK_MAX_YAW_DEGREES), 1e-9)
end)

Runner.test("braking at 1 g moves the head forward, never past the sway limit", function()
	local startSpeed = 400
	local furthest = 0
	local lastPose
	simulate(
		1,
		function(time)
			return viewMoving(FORWARD * (startSpeed - ONE_G * time))
		end,
		NO_LOOK,
		function(pose)
			furthest = math.max(furthest, offsetAlong(pose, FORWARD))
			lastPose = pose
		end
	)
	Runner.expectEqual(offsetAlong(lastPose, FORWARD) > 0.1 * CameraConfig.HEAD_SWAY_PER_ACCELERATION * ONE_G, true)
	Runner.expectEqual(furthest <= CameraConfig.HEAD_SWAY_MAX_STUDS + VECTOR_TOLERANCE, true)
end)

Runner.test("an enormous deceleration still respects the sway and tilt limits", function()
	local furthest, tilt = 0, 0
	simulate(
		1,
		function(time)
			return viewMoving(FORWARD * (1e6 - 1e6 * time * time))
		end,
		NO_LOOK,
		function(pose)
			furthest = math.max(furthest, math.abs(offsetAlong(pose, FORWARD)))
			tilt = math.max(tilt, math.abs(vector.dot(pose.forward, UP)))
		end
	)
	Runner.expectEqual(furthest <= CameraConfig.HEAD_SWAY_MAX_STUDS + VECTOR_TOLERANCE, true)
	Runner.expectEqual(tilt <= math.sin(math.rad(CameraConfig.HEAD_TILT_MAX_DEGREES)) + VECTOR_TOLERANCE, true)
end)

Runner.test("after braking the head returns without crossing zero more than twice", function()
	local braked = simulate(0.5, function(time)
		return viewMoving(FORWARD * (400 - ONE_G * time))
	end, NO_LOOK, ignore)
	local cruiseVelocity = viewMoving(FORWARD * (400 - ONE_G * 0.5))
	local crossings, previousSign, lastOffset = 0, 0, 0
	simulate(
		3,
		function()
			return cruiseVelocity
		end,
		NO_LOOK,
		function(pose)
			lastOffset = offsetAlong(pose, FORWARD)
			local sign = if lastOffset > 1e-6 then 1 elseif lastOffset < -1e-6 then -1 else 0
			if sign ~= 0 and previousSign ~= 0 and sign ~= previousSign then
				crossings += 1
			end
			previousSign = if sign ~= 0 then sign else previousSign
		end,
		braked
	)
	Runner.expectEqual(crossings <= 2, true)
	Runner.expectNear(lastOffset, 0, 1e-4)
end)

Runner.test("accelerating moves the head back and tilts it up", function()
	local lastPose
	simulate(
		0.5,
		function(time)
			return viewMoving(FORWARD * (ONE_G * time))
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end
	)
	Runner.expectEqual(offsetAlong(lastPose, FORWARD) < 0, true)
	Runner.expectEqual(vector.dot(lastPose.forward, UP) > 0, true)
end)

Runner.test("braking tilts the head down", function()
	local lastPose
	simulate(
		0.5,
		function(time)
			return viewMoving(FORWARD * (400 - ONE_G * time))
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end
	)
	Runner.expectEqual(vector.dot(lastPose.forward, UP) < 0, true)
end)

Runner.test("in a right turn the head leans out to the left", function()
	local lastPose
	simulate(
		0.5,
		function(time)
			return viewMoving(FORWARD * 50 + RIGHT * (ONE_G * time))
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end
	)
	Runner.expectEqual(offsetAlong(lastPose, RIGHT) < 0, true)
	Runner.expectEqual(vector.dot(lastPose.up, RIGHT) < 0, true)
end)

Runner.test("in a left turn the head leans out to the right", function()
	local lastPose
	simulate(
		0.5,
		function(time)
			return viewMoving(FORWARD * 50 - RIGHT * (ONE_G * time))
		end,
		NO_LOOK,
		function(pose)
			lastPose = pose
		end
	)
	Runner.expectEqual(offsetAlong(lastPose, RIGHT) > 0, true)
	Runner.expectEqual(vector.dot(lastPose.up, RIGHT) > 0, true)
end)

Runner.test("a constant velocity moves the head only by the vibration", function()
	local sideways, forwards = 0, 0
	simulate(
		3,
		function()
			return viewMoving(FORWARD * 60)
		end,
		NO_LOOK,
		function(pose)
			sideways = math.max(sideways, math.abs(offsetAlong(pose, RIGHT)))
			forwards = math.max(forwards, math.abs(offsetAlong(pose, FORWARD)))
		end
	)
	Runner.expectEqual(sideways, 0)
	Runner.expectEqual(forwards, 0)
end)

Runner.test("the vibration is zero at rest and bounded at any speed", function()
	local maxAtRest, maxFast = 0, 0
	simulate(
		2,
		function()
			return STILL
		end,
		NO_LOOK,
		function(pose)
			maxAtRest = math.max(maxAtRest, math.abs(offsetAlong(pose, UP)))
		end
	)
	simulate(
		5,
		function()
			return viewMoving(FORWARD * 5000)
		end,
		NO_LOOK,
		function(pose)
			maxFast = math.max(maxFast, math.abs(offsetAlong(pose, UP)))
		end
	)
	Runner.expectEqual(maxAtRest, 0)
	Runner.expectEqual(maxFast > 0, true)
	Runner.expectEqual(maxFast <= CameraConfig.HEAD_VIBRATION_AMPLITUDE_STUDS + VECTOR_TOLERANCE, true)
end)

Runner.test("the vibration grows with the speed", function()
	local function peakAt(speed: number): number
		local peak = 0
		simulate(
			5,
			function()
				return viewMoving(FORWARD * speed)
			end,
			NO_LOOK,
			function(pose)
				peak = math.max(peak, math.abs(offsetAlong(pose, UP)))
			end
		)
		return peak
	end
	Runner.expectEqual(peakAt(10) < peakAt(50), true)
end)

Runner.test("the vibration depends on the distance travelled, not on the frame rate", function()
	local function offsetAfterDistance(frameSeconds: number): number
		local state = FirstPersonCamera.newState()
		local view = viewMoving(FORWARD * 80)
		local pose
		for _ = 1, math.floor(1 / frameSeconds + 0.5) do
			state, pose = classicStep(state, view, NO_LOOK, false, frameSeconds)
		end
		return offsetAlong(pose, UP)
	end
	Runner.expectNear(offsetAfterDistance(1 / 60), offsetAfterDistance(1 / 30), 1e-9)
end)

Runner.test("an invalid dt leaves the state as it was", function()
	local state = simulate(0.3, function(time)
		return viewMoving(FORWARD * (100 - 50 * time))
	end, { yawRate = 1, pitchRate = 1 }, ignore)
	for _, dt in { 0, -1, 0 / 0, math.huge, -math.huge } do
		local nextState, pose = classicStep(state, STILL, { yawRate = 5, pitchRate = 5 }, false, dt)
		Runner.expectEqual(nextState, state)
		Runner.expectEqual(isFinitePose(pose), true)
	end
end)

Runner.test("a very long frame counts as the longest allowed step", function()
	local view = viewMoving(FORWARD * 20)
	local look = { yawRate = 1, pitchRate = 0 }
	local longStep = classicStep(FirstPersonCamera.newState(), view, look, false, 30)
	local maxStep = classicStep(FirstPersonCamera.newState(), view, look, false, CameraConfig.MAX_STEP_SECONDS)
	Runner.expectEqual(longStep.lookYawRadians, maxStep.lookYawRadians)
	Runner.expectEqual(longStep.travelledStuds, maxStep.travelledStuds)
end)

Runner.test("NaN and infinite velocity or look rates never produce NaN", function()
	local broken = { 0 / 0, math.huge, -math.huge }
	local state = FirstPersonCamera.newState()
	for _, value in broken do
		local view = viewMoving(vector.create(value, 1, value))
		local look = { yawRate = value, pitchRate = value }
		local pose
		state, pose = classicStep(state, view, look, false, FRAME_SECONDS)
		Runner.expectEqual(isFinitePose(pose), true)
	end
	local _, pose = classicStep(state, viewMoving(FORWARD * 10), NO_LOOK, false, FRAME_SECONDS)
	Runner.expectEqual(isFinitePose(pose), true)
end)

Runner.test("an overturned car gives a finite pose that follows the car frame", function()
	local upsideDown = {
		right = -RIGHT,
		up = -UP,
		forward = FORWARD,
		headPosition = HEAD,
		linearVelocity = vector.create(3, -40, 2),
	}
	local state = FirstPersonCamera.newState()
	local pose
	for _ = 1, 120 do
		state, pose = classicStep(state, upsideDown, { yawRate = 1, pitchRate = 1 }, false, FRAME_SECONDS)
		Runner.expectEqual(isFinitePose(pose), true)
	end
	Runner.expectEqual(vector.dot(pose.up, -UP) > 0.8, true)
end)

Runner.test("the arguments are not modified", function()
	local state = FirstPersonCamera.newState()
	deepFreeze(state)
	local view = viewMoving(FORWARD * 30)
	table.freeze(view)
	local look = { yawRate = 1, pitchRate = 1 }
	table.freeze(look)
	local nextState = classicStep(state, view, look, true, FRAME_SECONDS)
	Runner.expectEqual(state.lookYawRadians, 0)
	Runner.expectEqual(nextState.lookYawRadians > 0, true)
	Runner.expectEqual(state.previousVelocity, nil)
end)

Runner.test("the same inputs always give the same pose", function()
	local function run(): CameraPose
		local lastPose
		simulate(2, function(time)
			return viewMoving(FORWARD * (80 - 30 * time) + RIGHT * (20 * math.sin(time * 3)))
		end, { yawRate = 0.5, pitchRate = -0.2 }, function(pose)
			lastPose = pose
		end)
		return lastPose
	end
	local first, second = run(), run()
	Runner.expectEqual(first.position, second.position)
	Runner.expectEqual(first.forward, second.forward)
end)

Runner.test("the orientation stays orthonormal after any mix of look and tilt", function()
	local worst = 0
	simulate(5, function(time)
		return viewMoving(FORWARD * (60 + 40 * math.sin(time)) + RIGHT * (80 * math.cos(time * 2)))
	end, { yawRate = 1.3, pitchRate = -0.7 }, function(pose)
		worst = math.max(
			worst,
			math.abs(vector.dot(pose.right, pose.up)),
			math.abs(vector.dot(pose.right, pose.forward)),
			math.abs(vector.dot(pose.up, pose.forward)),
			math.abs(vector.magnitude(pose.forward) - 1)
		)
	end)
	Runner.expectNear(worst, 0, VECTOR_TOLERANCE)
end)

Runner.finish()
