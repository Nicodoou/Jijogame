--!strict
-- Cámara en primera persona (CP-11, CP-12 y CP-2). La cabeza va en el asiento del conductor: mira
-- alrededor dentro de un límite y se mueve con la aceleración del auto, con un resorte por eje.
local CameraAim = require("./CameraAim")
local CameraConfig = require("./CameraConfig")
local CameraFrame = require("./CameraFrame")
local CameraYawLag = require("./CameraYawLag")
local HeadSpring = require("./HeadSpring")

export type VehicleView = {
	right: vector,
	up: vector,
	forward: vector,
	headPosition: vector,
	linearVelocity: vector,
	-- Punto del camino adelante del auto (nil si no hay), para mirar hacia la curva.
	curveTarget: vector?,
}

-- Velocidades de giro de la cabeza en rad/s: yaw hacia la derecha y pitch hacia arriba.
export type LookRates = {
	yawRate: number,
	pitchRate: number,
}

export type CameraState = {
	lookYawRadians: number,
	lookPitchRadians: number,
	aimYaw: number,
	yawLag: CameraYawLag.YawLag,
	previousVelocity: vector?,
	travelledStuds: number,
	swayRight: HeadSpring.HeadSpring,
	swayForward: HeadSpring.HeadSpring,
	tiltRoll: HeadSpring.HeadSpring,
	tiltPitch: HeadSpring.HeadSpring,
}

export type CameraPose = {
	position: vector,
	right: vector,
	up: vector,
	forward: vector,
}

type Config = typeof(CameraConfig)

local FirstPersonCamera = {}

local MAX_LOOK_YAW = math.rad(CameraConfig.LOOK_MAX_YAW_DEGREES)
local MAX_LOOK_PITCH = math.rad(CameraConfig.LOOK_MAX_PITCH_DEGREES)
local TILT_PER_ACCELERATION = math.rad(CameraConfig.HEAD_TILT_PER_ACCELERATION)
local MAX_TILT = math.rad(CameraConfig.HEAD_TILT_MAX_DEGREES)

local function isFiniteNumber(value: number): boolean
	return value == value and math.abs(value) ~= math.huge
end

local function finiteOrZero(value: number): number
	return if isFiniteNumber(value) then value else 0
end

local function isFiniteVector(value: vector): boolean
	return isFiniteNumber(value.x) and isFiniteNumber(value.y) and isFiniteNumber(value.z)
end

function FirstPersonCamera.newState(): CameraState
	return {
		lookYawRadians = 0,
		lookPitchRadians = 0,
		aimYaw = 0,
		yawLag = CameraYawLag.new(),
		previousVelocity = nil,
		travelledStuds = 0,
		swayRight = HeadSpring.new(),
		swayForward = HeadSpring.new(),
		tiltRoll = HeadSpring.new(),
		tiltPitch = HeadSpring.new(),
	}
end

-- Con entrada gira a la velocidad pedida hasta el límite; sin entrada vuelve al frente.
local function moveLookAngle(angle: number, rate: number, limit: number, dt: number): number
	if rate == 0 then
		return angle * math.exp(-CameraConfig.LOOK_RETURN_RATE * dt)
	end
	return math.clamp(angle + rate * dt, -limit, limit)
end

-- Aceleración del auto en su propio marco (derecha, adelante), a partir de la velocidad anterior.
local function localAcceleration(state: CameraState, view: VehicleView, dt: number): (number, number)
	local previous = state.previousVelocity
	if previous == nil or not isFiniteVector(view.linearVelocity) then
		return 0, 0
	end
	local acceleration = (view.linearVelocity - previous) / dt
	return finiteOrZero(vector.dot(acceleration, view.right)), finiteOrZero(vector.dot(acceleration, view.forward))
end

local function speedOf(view: VehicleView): number
	if not isFiniteVector(view.linearVelocity) then
		return 0
	end
	return vector.magnitude(view.linearVelocity)
end

local function stepLook(state: CameraState, look: LookRates, dt: number): CameraState
	local nextState = table.clone(state)
	nextState.lookYawRadians = moveLookAngle(state.lookYawRadians, finiteOrZero(look.yawRate), MAX_LOOK_YAW, dt)
	nextState.lookPitchRadians = moveLookAngle(state.lookPitchRadians, finiteOrZero(look.pitchRate), MAX_LOOK_PITCH, dt)
	return nextState
end

-- Frenar (aceleración hacia atrás) tira la cabeza hacia adelante; en curva la tira hacia afuera.
local function stepHead(state: CameraState, view: VehicleView, dt: number): CameraState
	local lateral, longitudinal = localAcceleration(state, view, dt)
	local sway, swayMax = CameraConfig.HEAD_SWAY_PER_ACCELERATION, CameraConfig.HEAD_SWAY_MAX_STUDS
	local nextState = table.clone(state)
	if isFiniteVector(view.linearVelocity) then
		nextState.previousVelocity = view.linearVelocity
	end
	nextState.travelledStuds = state.travelledStuds + speedOf(view) * dt
	nextState.swayRight = HeadSpring.step(state.swayRight, -lateral * sway, swayMax, dt)
	nextState.swayForward = HeadSpring.step(state.swayForward, -longitudinal * sway, swayMax, dt)
	nextState.tiltRoll = HeadSpring.step(state.tiltRoll, -lateral * TILT_PER_ACCELERATION, MAX_TILT, dt)
	nextState.tiltPitch = HeadSpring.step(state.tiltPitch, longitudinal * TILT_PER_ACCELERATION, MAX_TILT, dt)
	return nextState
end

-- Vale 0 con el auto quieto y nunca pasa de la amplitud configurada.
local function verticalVibration(state: CameraState, view: VehicleView): number
	local speedFactor = math.min(speedOf(view) / CameraConfig.HEAD_VIBRATION_FULL_SPEED, 1)
	local phase = state.travelledStuds * CameraConfig.HEAD_VIBRATION_RADIANS_PER_STUD
	local waves = (math.sin(phase) + math.sin(phase * CameraConfig.HEAD_VIBRATION_SECOND_WAVE_RATIO)) / 2
	return waves * speedFactor * CameraConfig.HEAD_VIBRATION_AMPLITUDE_STUDS
end

local function buildPose(state: CameraState, view: VehicleView, isLookingBack: boolean, config: Config): CameraPose
	local chassis: CameraFrame.Frame = { right = view.right, up = view.up, forward = view.forward }
	local frame = CameraAim.levelFrame(chassis, config.HORIZON_LOCK)
	local tilt = config.HEAD_TILT
	frame = CameraFrame.pitch(CameraFrame.roll(frame, state.tiltRoll.offset * tilt), state.tiltPitch.offset * tilt)
	frame = CameraFrame.yaw(
		frame,
		state.lookYawRadians + state.aimYaw + state.yawLag.offset + if isLookingBack then math.pi else 0
	)
	frame = CameraFrame.pitch(frame, state.lookPitchRadians)
	local position = view.headPosition
		+ view.right * (state.swayRight.offset * config.HEAD_SWAY)
		+ view.forward * (state.swayForward.offset * config.HEAD_SWAY)
		+ view.up * (verticalVibration(state, view) * config.HEAD_VIBRATION)
	return { position = position, right = frame.right, up = frame.up, forward = frame.forward }
end

function FirstPersonCamera.step(
	state: CameraState,
	view: VehicleView,
	look: LookRates,
	isLookingBack: boolean,
	dt: number,
	config: Config?
): (CameraState, CameraPose)
	local settings = config or CameraConfig
	if not isFiniteNumber(dt) or dt <= 0 then
		return state, buildPose(state, view, isLookingBack, settings)
	end
	local stepSeconds = math.min(dt, CameraConfig.MAX_STEP_SECONDS)
	local nextState = stepHead(stepLook(state, look, stepSeconds), view, stepSeconds)
	local aimTarget = if isLookingBack then 0 else CameraAim.targetYaw(view, settings)
	nextState.aimYaw = CameraAim.follow(state.aimYaw, aimTarget, stepSeconds, settings)
	nextState.yawLag = CameraYawLag.step(state.yawLag, view.forward, stepSeconds, isLookingBack, settings)
	return nextState, buildPose(nextState, view, isLookingBack, settings)
end

return FirstPersonCamera
