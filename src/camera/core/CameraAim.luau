--!strict
-- Apuntado de la cámara: nivela el horizonte (quita el roll y el pitch del chasis) y calcula cuánto gira el yaw hacia
-- la velocidad del auto (derrape) o hacia el punto del camino que viene.
local CameraFrame = require("./CameraFrame")

type Config = typeof(require("./CameraConfig"))

export type AimView = {
	forward: vector,
	headPosition: vector,
	linearVelocity: vector,
	curveTarget: vector?,
}

local EPSILON = 1e-4
local WORLD_UP = vector.create(0, 1, 0)

local CameraAim = {}

-- Dirección horizontal unitaria, o nil si es vertical, nula o inválida.
local function flatten(direction: vector): vector?
	local flat = vector.create(direction.x, 0, direction.z)
	local length = vector.magnitude(flat)
	if not (length > EPSILON and length < math.huge) then
		return nil
	end
	return flat / length
end

-- Ángulo horizontal de `to` respecto de `from`, positivo hacia la derecha (el mundo es Y arriba).
local function signedAngle(from: vector, to: vector): number
	local right = vector.create(-from.z, 0, from.x)
	return math.atan2(vector.dot(to, right), vector.dot(to, from))
end

-- Yaw (rad, positivo a la derecha, 0 mirando a -z) de una dirección, o nil si es vertical o inválida.
function CameraAim.yawOf(direction: vector): number?
	local flat = flatten(direction)
	return if flat ~= nil then math.atan2(flat.x, -flat.z) else nil
end

-- Con lock en 1 el marco queda a nivel y solo conserva el yaw del auto; con 0 queda igual. En el medio, mezcla.
function CameraAim.levelFrame(frame: CameraFrame.Frame, lock: number): CameraFrame.Frame
	if not (lock > 0) then
		return frame
	end
	local amount = math.min(lock, 1)
	local up = frame.up + (WORLD_UP - frame.up) * amount
	if not (vector.magnitude(up) > EPSILON) then
		return frame
	end
	up = vector.normalize(up)
	local flat = frame.forward - up * vector.dot(frame.forward, up)
	if not (vector.magnitude(flat) > EPSILON) then
		return frame
	end
	local forward = vector.normalize(flat)
	return { right = vector.cross(forward, up), up = up, forward = forward }
end

local function turnToward(forward: vector, target: vector, factor: number, maxDegrees: number): number
	local from, to = flatten(forward), flatten(target)
	if from == nil or to == nil or not (factor > 0) then
		return 0
	end
	local limit = math.rad(maxDegrees)
	return math.clamp(factor * signedAngle(from, to), -limit, limit)
end

-- Yaw (rad, positivo a la derecha) al que apunta la cámara: hacia la velocidad (solo yendo hacia adelante y rápido)
-- más hacia el punto del camino adelante.
function CameraAim.targetYaw(view: AimView, config: Config): number
	local velocity = view.linearVelocity
	local isMovingForward = vector.dot(velocity, view.forward) > 0
		and vector.magnitude(velocity) >= config.LOOK_INTO_VELOCITY_MIN_SPEED
	local velocityYaw = if isMovingForward
		then turnToward(view.forward, velocity, config.LOOK_INTO_VELOCITY, config.LOOK_INTO_VELOCITY_MAX_DEGREES)
		else 0
	local curveTarget = view.curveTarget
	local curveYaw = if curveTarget ~= nil
		then turnToward(
			view.forward,
			curveTarget - view.headPosition,
			config.LOOK_INTO_CURVE,
			config.LOOK_INTO_CURVE_MAX_DEGREES
		)
		else 0
	local total = velocityYaw + curveYaw
	return if total == total then total else 0
end

-- Suaviza el yaw hacia su objetivo (exponencial, independiente de los cuadros por segundo).
function CameraAim.follow(current: number, target: number, dt: number, config: Config): number
	return current + (target - current) * (1 - math.exp(-config.LOOK_INTO_SMOOTH_RATE * dt))
end

return CameraAim
