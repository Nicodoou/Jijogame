--!strict
local Runner = require("../Runner")
local CameraConfig = require("../../src/camera/core/CameraConfig")
local CameraYawLag = require("../../src/camera/core/CameraYawLag")

local DT = 1 / 60
local MAX_LAG = math.rad(CameraConfig.CAMERA_YAW_MAX_LAG_DEGREES)

local function forwardAt(yaw: number): vector
	return vector.create(math.sin(yaw), 0, -math.cos(yaw))
end

local function config(overrides: { [string]: number }): typeof(CameraConfig)
	local copy: { [string]: any } = table.clone(CameraConfig :: any)
	for key, value in overrides do
		copy[key] = value
	end
	return copy :: any
end

-- El auto gira a `rate` rad/s durante `seconds` y después se queda quieto `restSeconds`. Mira el offset en cada cuadro.
local function turn(
	settings: typeof(CameraConfig),
	rate: number,
	seconds: number,
	restSeconds: number,
	dt: number,
	observe: (number) -> ()
)
	local lag = CameraYawLag.new()
	local yaw = 0
	for index = 1, math.floor((seconds + restSeconds) / dt) do
		if index * dt <= seconds then
			yaw += rate * dt
		end
		lag = CameraYawLag.step(lag, forwardAt(yaw), dt, false, settings)
		observe(lag.offset)
	end
end

Runner.test("a turn-rate step is absorbed gradually and the lag settles near 2 * rate / frequency", function()
	local settings = config({ CAMERA_YAW_MAX_LAG_DEGREES = 90 })
	local rate = 0.5
	local first, last = nil, 0
	turn(settings, rate, 3, 0, DT, function(offset)
		first = first or offset
		last = offset
	end)
	Runner.expectEqual(math.abs(first :: number) < 0.01, true)
	Runner.expectNear(last, -2 * rate / settings.CAMERA_YAW_SMOOTHING, 0.01)
end)

Runner.test("after the turn the camera catches up without overshooting", function()
	local settings = config({ CAMERA_YAW_MAX_LAG_DEGREES = 90 })
	local worstOvershoot, final = 0, 1
	turn(settings, 0.5, 1, 4, DT, function(offset)
		worstOvershoot = math.max(worstOvershoot, offset)
		final = offset
	end)
	Runner.expectEqual(worstOvershoot < 1e-3, true)
	Runner.expectNear(final, 0, 1e-3)
end)

Runner.test("a spin never lags more than the cap, at 60 and 30 fps", function()
	for _, dt in { 1 / 60, 1 / 30 } do
		local worst = 0
		turn(config({}), 12, 3, 1, dt, function(offset)
			worst = math.max(worst, math.abs(offset))
			Runner.expectEqual(offset == offset, true)
		end)
		Runner.expectEqual(worst <= MAX_LAG + 1e-9, true)
		Runner.expectEqual(worst > MAX_LAG * 0.99, true)
	end
end)

Runner.test("without smoothing, or when looking back, the camera sticks to the car", function()
	local none = config({ CAMERA_YAW_SMOOTHING = 0 })
	turn(none, 2, 1, 0, DT, function(offset)
		Runner.expectEqual(offset, 0)
	end)
	local lag = CameraYawLag.new()
	lag = CameraYawLag.step(lag, forwardAt(0), DT, false, config({}))
	lag = CameraYawLag.step(lag, forwardAt(0.1), DT, false, config({}))
	Runner.expectEqual(lag.offset < 0, true)
	lag = CameraYawLag.step(lag, forwardAt(0.2), DT, true, config({}))
	Runner.expectEqual(lag.offset, 0)
	Runner.expectEqual(lag.rate, 0)
end)

Runner.test("a very high frequency is stable and nearly the same as no smoothing", function()
	turn(config({ CAMERA_YAW_SMOOTHING = 1e6 }), 2, 1, 0, DT, function(offset)
		Runner.expectEqual(math.abs(offset) < 1e-3, true)
	end)
end)

Runner.test("vertical, invalid or wrapped-around directions do not break it", function()
	local settings = config({})
	local lag = CameraYawLag.step(CameraYawLag.new(), forwardAt(3.1), DT, false, settings)
	lag = CameraYawLag.step(lag, forwardAt(-3.1), DT, false, settings)
	Runner.expectEqual(math.abs(lag.offset) < 0.1, true)
	lag = CameraYawLag.step(lag, vector.create(0, 1, 0), DT, false, settings)
	lag = CameraYawLag.step(lag, vector.create(0 / 0, 0, 0 / 0), DT, false, settings)
	Runner.expectEqual(lag.offset == lag.offset, true)
	Runner.expectEqual(lag.carYaw ~= nil, true)
end)

Runner.finish()
