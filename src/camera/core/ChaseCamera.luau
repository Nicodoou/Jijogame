--!strict
-- Cámara de seguimiento (CP-11 y CP-12). El yaw sale del plano horizontal (xz): el rumbo es
-- (sin yaw, cos yaw) y el yaw crece hacia la derecha del eje z.
local CameraConfig = require("./CameraConfig")

export type VehicleView = {
	position: vector,
	forward: vector,
	linearVelocity: vector,
}

export type CameraState = {
	yawRadians: number,
	focus: vector,
}

export type CameraPose = {
	position: vector,
	lookAt: vector,
}

local ChaseCamera = {}

local FULL_TURN = 2 * math.pi
local UP = vector.create(0, 1, 0)

local function wrapAngle(angle: number): number
	return angle - FULL_TURN * math.floor((angle + math.pi) / FULL_TURN)
end

-- Diferencia entre dos ángulos por el camino corto, en [-π, π).
local function shortestDifference(from: number, to: number): number
	return wrapAngle(to - from)
end

local function headingOf(yawRadians: number): vector
	return vector.create(math.sin(yawRadians), 0, math.cos(yawRadians))
end

local function horizontalYaw(direction: vector): number
	return math.atan2(direction.x, direction.z)
end

local function horizontalLength(direction: vector): number
	return math.sqrt(direction.x * direction.x + direction.z * direction.z)
end

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) ~= math.huge
end

-- Con el auto volcado el frente no tiene rumbo horizontal: se mantiene el yaw anterior.
local function frontYaw(view: VehicleView, fallbackYaw: number): number
	if not (horizontalLength(view.forward) >= CameraConfig.MIN_HORIZONTAL_FORWARD) then
		return fallbackYaw
	end
	return horizontalYaw(view.forward)
end

local function movesForward(view: VehicleView): boolean
	local velocity = view.linearVelocity
	local forward = view.forward
	return velocity.x * forward.x + velocity.z * forward.z > 0
end

local function targetYaw(view: VehicleView, previousYaw: number): number
	local front = frontYaw(view, previousYaw)
	local velocity = view.linearVelocity
	local speed = horizontalLength(velocity)
	if not (speed >= CameraConfig.MIN_SPEED_FOR_VELOCITY_HEADING) or not movesForward(view) then
		return front
	end
	local toVelocity = shortestDifference(front, horizontalYaw(velocity))
	return front + CameraConfig.VELOCITY_HEADING_WEIGHT * toVelocity
end

local function buildPose(state: CameraState, isLookingBack: boolean): CameraPose
	local yaw = if isLookingBack then state.yawRadians + math.pi else state.yawRadians
	local heading = headingOf(yaw)
	return {
		position = state.focus - heading * CameraConfig.DISTANCE_STUDS + UP * CameraConfig.HEIGHT_STUDS,
		lookAt = state.focus + heading * CameraConfig.LOOK_AHEAD_STUDS + UP * CameraConfig.LOOK_HEIGHT_STUDS,
	}
end

local function followAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function ChaseCamera.newState(view: VehicleView): CameraState
	return { yawRadians = wrapAngle(frontYaw(view, 0)), focus = view.position }
end

function ChaseCamera.step(
	state: CameraState,
	view: VehicleView,
	isLookingBack: boolean,
	dt: number
): (CameraState, CameraPose)
	if not isFiniteNumber(dt) or dt <= 0 then
		return { yawRadians = state.yawRadians, focus = state.focus }, buildPose(state, isLookingBack)
	end
	local stepSeconds = math.min(dt, CameraConfig.MAX_STEP_SECONDS)
	local yawGap = shortestDifference(state.yawRadians, targetYaw(view, state.yawRadians))
	local nextState = {
		yawRadians = wrapAngle(state.yawRadians + yawGap * followAlpha(CameraConfig.YAW_FOLLOW_RATE, stepSeconds)),
		focus = state.focus
			+ (view.position - state.focus) * followAlpha(CameraConfig.POSITION_FOLLOW_RATE, stepSeconds),
	}
	return nextState, buildPose(nextState, isLookingBack)
end

return ChaseCamera
