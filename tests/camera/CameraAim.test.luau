--!strict
local Runner = require("../Runner")
local CameraAim = require("../../src/camera/core/CameraAim")
local CameraConfig = require("../../src/camera/core/CameraConfig")
local FirstPersonCamera = require("../../src/camera/core/FirstPersonCamera")

local FORWARD = vector.create(0, 0, -1)
local RIGHT = vector.create(1, 0, 0)
local UP = vector.create(0, 1, 0)
local FRAME_SECONDS = 1 / 60
local NO_LOOK: FirstPersonCamera.LookRates = { yawRate = 0, pitchRate = 0 }

local function viewWith(velocity: vector, curveTarget: vector?): CameraAim.AimView
	return { forward = FORWARD, headPosition = vector.zero, linearVelocity = velocity, curveTarget = curveTarget }
end

local function config(overrides: { [string]: number }): typeof(CameraConfig)
	local copy: { [string]: any } = table.clone(CameraConfig :: any)
	for key, value in overrides do
		copy[key] = value
	end
	return copy :: any
end

Runner.test("the level frame keeps only the yaw when the lock is 1", function()
	local pitched = { right = RIGHT, up = vector.create(0, 0.8, 0.6), forward = vector.create(0, 0.6, -0.8) }
	local level = CameraAim.levelFrame(pitched, 1)
	Runner.expectNear(level.up.y, 1, 1e-6)
	Runner.expectNear(level.forward.y, 0, 1e-6)
	Runner.expectNear(level.forward.z, -1, 1e-6)
	Runner.expectNear(vector.dot(level.right, level.forward), 0, 1e-6)
end)

Runner.test("the level frame is unchanged at 0 and in between it mixes", function()
	local rolled = { right = vector.create(0.8, -0.6, 0), up = vector.create(0.6, 0.8, 0), forward = FORWARD }
	Runner.expectEqual(CameraAim.levelFrame(rolled, 0), rolled)
	local half = CameraAim.levelFrame(rolled, 0.5)
	Runner.expectEqual(half.up.y > rolled.up.y and half.up.y < 1, true)
end)

Runner.test("the level frame survives a vertical or inverted chassis", function()
	local vertical = { right = RIGHT, up = FORWARD, forward = UP }
	Runner.expectEqual(CameraAim.levelFrame(vertical, 1), vertical)
	local upsideDown = { right = -RIGHT, up = -UP, forward = FORWARD }
	Runner.expectEqual(CameraAim.levelFrame(upsideDown, 0.5), upsideDown)
end)

Runner.test("the camera yaw turns toward the velocity with a cap", function()
	local settings = config({ LOOK_INTO_VELOCITY = 0.5, LOOK_INTO_VELOCITY_MAX_DEGREES = 25 })
	local expected = 0.5 * math.atan2(10, 30)
	Runner.expectNear(CameraAim.targetYaw(viewWith(vector.create(10, 0, -30)), settings), expected, 1e-6)
	Runner.expectNear(CameraAim.targetYaw(viewWith(vector.create(-10, 0, -30)), settings), -expected, 1e-6)
	local sideways = config({ LOOK_INTO_VELOCITY = 1, LOOK_INTO_VELOCITY_MAX_DEGREES = 25 })
	Runner.expectNear(CameraAim.targetYaw(viewWith(vector.create(60, 0, -20)), sideways), math.rad(25), 1e-6)
end)

Runner.test("the camera yaw ignores slow, reversing and invalid velocities", function()
	local settings = config({ LOOK_INTO_VELOCITY = 1 })
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.create(1, 0, -3)), settings), 0)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.create(10, 0, 30)), settings), 0)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.create(0 / 0, 0, -30)), settings), 0)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.zero), settings), 0)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.create(10, 0, -30)), config({ LOOK_INTO_VELOCITY = 0 })), 0)
end)

Runner.test("the camera yaw can look toward the curve point", function()
	local settings = config({ LOOK_INTO_VELOCITY = 0, LOOK_INTO_CURVE = 1 })
	local sharp = viewWith(vector.create(0, 0, -30), vector.create(10, 0, -10))
	Runner.expectNear(CameraAim.targetYaw(sharp, settings), math.rad(25), 1e-6)
	local gentle = viewWith(vector.zero, vector.create(2, 0, -10))
	Runner.expectNear(CameraAim.targetYaw(gentle, settings), math.atan2(2, 10), 1e-6)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.zero, nil), settings), 0)
	Runner.expectEqual(CameraAim.targetYaw(viewWith(vector.zero, vector.create(0, 5, 0)), settings), 0)
end)

Runner.test("follow converges and does not depend on the frame rate", function()
	local settings = config({})
	local at60, at30 = 0, 0
	for _ = 1, 60 do
		at60 = CameraAim.follow(at60, 1, 1 / 60, settings)
	end
	for _ = 1, 30 do
		at30 = CameraAim.follow(at30, 1, 1 / 30, settings)
	end
	Runner.expectNear(at60, at30, 1e-9)
	Runner.expectEqual(at60 > 0.99, true)
end)

Runner.test("the horizon lock keeps the camera level on a pitched and rolled chassis", function()
	local view: FirstPersonCamera.VehicleView = {
		right = vector.create(0.8, -0.6, 0),
		up = vector.create(0.6, 0.8, 0),
		forward = FORWARD,
		headPosition = vector.zero,
		linearVelocity = vector.zero,
	}
	local _, locked = FirstPersonCamera.step(FirstPersonCamera.newState(), view, NO_LOOK, false, FRAME_SECONDS)
	Runner.expectNear(locked.up.y, 1, 1e-5)
	local unlocked = config({ HORIZON_LOCK = 0 })
	local _, free = FirstPersonCamera.step(FirstPersonCamera.newState(), view, NO_LOOK, false, FRAME_SECONDS, unlocked)
	Runner.expectNear(free.up.y, 0.8, 1e-5)
end)

Runner.test("sliding turns the camera toward the velocity and a zero factor does not", function()
	local view: FirstPersonCamera.VehicleView = {
		right = RIGHT,
		up = UP,
		forward = FORWARD,
		headPosition = vector.zero,
		linearVelocity = vector.create(15, 0, -30),
	}
	local function lastForwardX(settings: typeof(CameraConfig)): number
		local state = FirstPersonCamera.newState()
		local pose
		for _ = 1, 120 do
			state, pose = FirstPersonCamera.step(state, view, NO_LOOK, false, FRAME_SECONDS, settings)
		end
		return pose.forward.x
	end
	Runner.expectEqual(lastForwardX(config({})) > 0.05, true)
	Runner.expectNear(lastForwardX(config({ LOOK_INTO_VELOCITY = 0 })), 0, 1e-6)
end)

Runner.finish()
