--!strict
local Runner = require("../Runner")
local CameraConfig = require("../../src/camera/core/CameraConfig")
local ChaseCamera = require("../../src/camera/core/ChaseCamera")

type VehicleView = ChaseCamera.VehicleView
type CameraState = ChaseCamera.CameraState

local FRAME_SECONDS = 1 / 60
local TOLERANCE = 1e-9

local function headingVector(yawRadians: number): vector
	return vector.create(math.sin(yawRadians), 0, math.cos(yawRadians))
end

local function viewAt(position: vector, yawRadians: number, velocity: vector): VehicleView
	return { position = position, forward = headingVector(yawRadians), linearVelocity = velocity }
end

local function degrees(value: number): number
	return math.rad(value)
end

local function angleDifference(first: number, second: number): number
	local difference = (first - second) % (2 * math.pi)
	if difference > math.pi then
		difference -= 2 * math.pi
	end
	return difference
end

local function settle(state: CameraState, view: VehicleView, isLookingBack: boolean, seconds: number): CameraState
	local current = state
	for _ = 1, math.floor(seconds / FRAME_SECONDS) do
		current = ChaseCamera.step(current, view, isLookingBack, FRAME_SECONDS)
	end
	return current
end

local ORIGIN = vector.create(0, 0, 0)

Runner.test("a new state starts behind the car with no smoothing", function()
	local view = viewAt(vector.create(10, 3, 20), degrees(30), ORIGIN)
	local state = ChaseCamera.newState(view)
	local _, pose = ChaseCamera.step(state, view, false, FRAME_SECONDS)
	local behind = headingVector(degrees(30)) * -CameraConfig.DISTANCE_STUDS
	Runner.expectNear(pose.position.x, 10 + behind.x, 1e-6)
	Runner.expectNear(pose.position.z, 20 + behind.z, 1e-6)
	Runner.expectNear(pose.position.y, 3 + CameraConfig.HEIGHT_STUDS, 1e-6)
end)

Runner.test("the camera looks ahead of and above the car", function()
	local view = viewAt(ORIGIN, 0, ORIGIN)
	local _, pose = ChaseCamera.step(ChaseCamera.newState(view), view, false, FRAME_SECONDS)
	Runner.expectNear(pose.lookAt.z, CameraConfig.LOOK_AHEAD_STUDS, 1e-6)
	Runner.expectNear(pose.lookAt.y, CameraConfig.LOOK_HEIGHT_STUDS, 1e-6)
	Runner.expectNear(pose.position.z, -CameraConfig.DISTANCE_STUDS, 1e-6)
end)

Runner.test("a car that goes straight keeps the camera still behind it", function()
	local view = viewAt(ORIGIN, degrees(45), headingVector(degrees(45)) * 80)
	local state = settle(ChaseCamera.newState(view), view, false, 1)
	Runner.expectNear(state.yawRadians, degrees(45), 1e-9)
end)

Runner.test("when the car drifts the yaw ends up between the heading and the velocity", function()
	local driftYaw = degrees(40)
	local view = viewAt(ORIGIN, 0, headingVector(driftYaw) * 60)
	local state = settle(ChaseCamera.newState(view), view, false, 4)
	local expected = driftYaw * CameraConfig.VELOCITY_HEADING_WEIGHT
	Runner.expectNear(state.yawRadians, expected, 1e-6)
	Runner.expectEqual(state.yawRadians > 0 and state.yawRadians < driftYaw, true)
end)

Runner.test("the yaw follows the velocity to the left as well", function()
	local view = viewAt(ORIGIN, 0, headingVector(degrees(-40)) * 60)
	local state = settle(ChaseCamera.newState(view), view, false, 4)
	Runner.expectEqual(state.yawRadians < 0 and state.yawRadians > degrees(-40), true)
end)

Runner.test("below the minimum speed the camera follows the car orientation", function()
	local slow = CameraConfig.MIN_SPEED_FOR_VELOCITY_HEADING * 0.99
	local view = viewAt(ORIGIN, 0, headingVector(degrees(60)) * slow)
	local state = settle(ChaseCamera.newState(view), view, false, 3)
	Runner.expectNear(state.yawRadians, 0, 1e-9)
end)

Runner.test("just above the minimum speed the velocity already counts", function()
	local view = viewAt(ORIGIN, 0, headingVector(degrees(60)) * (CameraConfig.MIN_SPEED_FOR_VELOCITY_HEADING * 1.01))
	local state = settle(ChaseCamera.newState(view), view, false, 4)
	Runner.expectEqual(state.yawRadians > 0.1, true)
end)

Runner.test("going in reverse the camera follows the orientation", function()
	local view = viewAt(ORIGIN, 0, headingVector(degrees(150)) * 40)
	local state = settle(ChaseCamera.newState(view), view, false, 3)
	Runner.expectNear(state.yawRadians, 0, 1e-9)
end)

Runner.test("the yaw takes the short way from 179 to -179 degrees", function()
	local start = viewAt(ORIGIN, degrees(179), ORIGIN)
	local state = ChaseCamera.newState(start)
	local next = viewAt(ORIGIN, degrees(-179), ORIGIN)
	local minimumAbsolute = math.pi
	for _ = 1, 120 do
		state = ChaseCamera.step(state, next, false, FRAME_SECONDS)
		minimumAbsolute = math.min(minimumAbsolute, math.abs(state.yawRadians))
		Runner.expectEqual(math.abs(state.yawRadians) >= degrees(178.9), true)
	end
	Runner.expectEqual(minimumAbsolute >= degrees(178.9), true)
	Runner.expectNear(angleDifference(state.yawRadians, degrees(-179)), 0, 1e-3)
end)

Runner.test("mixing the velocity also takes the short way around", function()
	local view = viewAt(ORIGIN, degrees(170), headingVector(degrees(-170)) * 60)
	local state = settle(ChaseCamera.newState(view), view, false, 4)
	local expected = degrees(170) + CameraConfig.VELOCITY_HEADING_WEIGHT * degrees(20)
	Runner.expectNear(angleDifference(state.yawRadians, expected), 0, 1e-6)
end)

Runner.test("the yaw stays inside the range", function()
	local state = ChaseCamera.newState(viewAt(ORIGIN, 0, ORIGIN))
	for index = 1, 400 do
		local view = viewAt(ORIGIN, degrees(index * 7), ORIGIN)
		state = ChaseCamera.step(state, view, false, FRAME_SECONDS)
		Runner.expectEqual(math.abs(state.yawRadians) <= math.pi + TOLERANCE, true)
	end
end)

Runner.test("looking back changes the pose at once and puts the camera in front of the car", function()
	local view = viewAt(ORIGIN, 0, ORIGIN)
	local state = ChaseCamera.newState(view)
	local _, normalPose = ChaseCamera.step(state, view, false, FRAME_SECONDS)
	local nextState, backPose = ChaseCamera.step(state, view, true, FRAME_SECONDS)
	Runner.expectEqual(normalPose.position.z < 0, true)
	Runner.expectNear(backPose.position.z, CameraConfig.DISTANCE_STUDS, 1e-6)
	Runner.expectNear(backPose.lookAt.z, -CameraConfig.LOOK_AHEAD_STUDS, 1e-6)
	Runner.expectNear(nextState.yawRadians, 0, TOLERANCE)
end)

Runner.test("after looking back the camera returns to the yaw it had", function()
	local view = viewAt(ORIGIN, degrees(25), ORIGIN)
	local state = settle(ChaseCamera.newState(view), view, false, 1)
	local lookedBack = settle(state, view, true, 1)
	local _, before = ChaseCamera.step(state, view, false, FRAME_SECONDS)
	local _, after = ChaseCamera.step(lookedBack, view, false, FRAME_SECONDS)
	Runner.expectNear(after.position.x, before.position.x, 1e-9)
	Runner.expectNear(after.position.z, before.position.z, 1e-9)
end)

Runner.test("the focus follows the car position with a delay", function()
	local start = viewAt(ORIGIN, 0, ORIGIN)
	local state = ChaseCamera.newState(start)
	local moved = viewAt(vector.create(0, 10, 100), 0, ORIGIN)
	local nextState = ChaseCamera.step(state, moved, false, FRAME_SECONDS)
	local alpha = 1 - math.exp(-CameraConfig.POSITION_FOLLOW_RATE * FRAME_SECONDS)
	Runner.expectNear(nextState.focus.z, 100 * alpha, 1e-5)
	Runner.expectNear(nextState.focus.y, 10 * alpha, 1e-5)
	local settled = settle(state, moved, false, 3)
	Runner.expectNear(settled.focus.z, 100, 1e-3)
end)

Runner.test("an upside down car does not give NaN and keeps the previous yaw", function()
	local straight = viewAt(ORIGIN, degrees(70), ORIGIN)
	local state = settle(ChaseCamera.newState(straight), straight, false, 1)
	local flipped: VehicleView = {
		position = ORIGIN,
		forward = vector.create(0, 1, 0),
		linearVelocity = vector.create(30, 0, 0),
	}
	local nextState, pose = ChaseCamera.step(state, flipped, false, FRAME_SECONDS)
	Runner.expectNear(nextState.yawRadians, state.yawRadians, 1e-9)
	for _, value in { pose.position.x, pose.position.y, pose.position.z, pose.lookAt.x, pose.lookAt.z } do
		Runner.expectEqual(value == value, true)
	end
	local pointingDown: VehicleView = { position = ORIGIN, forward = vector.create(0, -1, 0), linearVelocity = ORIGIN }
	Runner.expectEqual(ChaseCamera.newState(pointingDown).yawRadians, 0)
end)

Runner.test("a dt that is not usable keeps the state and still gives a pose", function()
	local view = viewAt(vector.create(5, 0, 5), degrees(10), ORIGIN)
	local state = ChaseCamera.newState(view)
	local moved = viewAt(vector.create(50, 0, 50), degrees(90), ORIGIN)
	for _, dt in { 0, -1, 0 / 0, math.huge } do
		local nextState, pose = ChaseCamera.step(state, moved, false, dt)
		Runner.expectEqual(nextState.yawRadians, state.yawRadians)
		Runner.expectEqual(nextState.focus, state.focus)
		Runner.expectEqual(pose.position.y, state.focus.y + CameraConfig.HEIGHT_STUDS)
	end
end)

Runner.test("a huge dt is capped like MAX_STEP_SECONDS", function()
	local state = ChaseCamera.newState(viewAt(ORIGIN, 0, ORIGIN))
	local moved = viewAt(vector.create(0, 0, 100), degrees(90), ORIGIN)
	local capped = ChaseCamera.step(state, moved, false, 50)
	local reference = ChaseCamera.step(state, moved, false, CameraConfig.MAX_STEP_SECONDS)
	Runner.expectEqual(capped.yawRadians, reference.yawRadians)
	Runner.expectEqual(capped.focus, reference.focus)
end)

Runner.test("far from the origin the camera still works", function()
	local far = vector.create(-120000, 50, 3000)
	local view = viewAt(far, degrees(90), headingVector(degrees(90)) * 50)
	local state = settle(ChaseCamera.newState(view), view, false, 1)
	local _, pose = ChaseCamera.step(state, view, false, FRAME_SECONDS)
	Runner.expectNear(pose.position.x, far.x - CameraConfig.DISTANCE_STUDS, 1e-2)
end)

Runner.test("step does not modify its arguments", function()
	local view = viewAt(ORIGIN, degrees(20), headingVector(degrees(30)) * 40)
	local state = ChaseCamera.newState(view)
	table.freeze(view)
	table.freeze(state)
	local nextState, pose = ChaseCamera.step(state, view, true, FRAME_SECONDS)
	Runner.expectEqual(nextState ~= state, true)
	Runner.expectEqual(pose.position == pose.position, true)
end)

Runner.finish()
