--!strict
-- Del input crudo a los controles suavizados (CP-7). El teclado pasa por rampas lineales;
-- el gamepad pasa por zona muerta y curva, y gana sobre el teclado sin rampa.
local InputConfig = require("./InputConfig")

export type RawInput = {
	isSteerLeftDown: boolean,
	isSteerRightDown: boolean,
	isThrottleDown: boolean,
	isBrakeDown: boolean,
	isHandbrakeDown: boolean,
	isLookBackDown: boolean,
	gamepadSteer: number,
	gamepadThrottle: number,
	gamepadBrake: number,
	-- Movimiento del mouse en el frame, en píxeles (y crece hacia abajo), y stick derecho en [-1, 1] (y hacia arriba).
	lookDeltaX: number,
	lookDeltaY: number,
	gamepadLookX: number,
	gamepadLookY: number,
}

export type SmoothedInput = {
	steer: number,
	throttle: number,
	brake: number,
	isHandbrakeOn: boolean,
	isLookingBack: boolean,
	-- Velocidades de giro de la cabeza en rad/s: yaw positivo hacia la derecha y pitch positivo hacia arriba.
	lookYawRate: number,
	lookPitchRate: number,
}

export type InputState = SmoothedInput

local InputSmoother = {}

-- Un gamepad roto puede dar NaN o valores fuera de rango: se descartan en vez de propagarse.
local function clampAxis(value: number, minimum: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, minimum, 1)
end

local function applyDeadzone(value: number, deadzone: number): number
	local magnitude = math.abs(value)
	if magnitude <= deadzone then
		return 0
	end
	return math.sign(value) * (magnitude - deadzone) / (1 - deadzone)
end

local function processGamepad(value: number, minimum: number, exponent: number, deadzone: number): number
	local shaped = applyDeadzone(clampAxis(value, minimum), deadzone)
	return math.sign(shaped) * math.abs(shaped) ^ exponent
end

-- Lleva `value` hacia `target` (-1, 0 o 1). Si el objetivo está del otro lado, primero vuelve a 0
-- con la rampa de retorno y con el tiempo que sobra sube con la de subida.
local function moveKeyboard(
	value: number,
	target: number,
	riseSeconds: number,
	returnSeconds: number,
	dt: number
): number
	local remaining = dt
	if value ~= 0 and value * target <= 0 then
		local secondsToZero = math.abs(value) * returnSeconds
		if remaining < secondsToZero then
			return value - math.sign(value) * remaining / returnSeconds
		end
		value = 0
		remaining -= secondsToZero
	end
	return math.clamp(value + target * remaining / riseSeconds, -1, 1)
end

local function resolveAxis(
	previous: number,
	gamepadValue: number,
	keyboardTarget: number,
	riseSeconds: number,
	returnSeconds: number,
	dt: number
): number
	if gamepadValue ~= 0 then
		return gamepadValue
	end
	return moveKeyboard(previous, keyboardTarget, riseSeconds, returnSeconds, dt)
end

local function boolToNumber(flag: boolean): number
	return if flag then 1 else 0
end

local function copyState(state: InputState): InputState
	return {
		steer = state.steer,
		throttle = state.throttle,
		brake = state.brake,
		isHandbrakeOn = state.isHandbrakeOn,
		isLookingBack = state.isLookingBack,
		lookYawRate = state.lookYawRate,
		lookPitchRate = state.lookPitchRate,
	}
end

function InputSmoother.newState(): InputState
	return {
		steer = 0,
		throttle = 0,
		brake = 0,
		isHandbrakeOn = false,
		isLookingBack = false,
		lookYawRate = 0,
		lookPitchRate = 0,
	}
end

-- Un mouse roto puede dar NaN o infinito: se descarta igual que en el gamepad.
local function mouseRate(deltaPixels: number, dt: number): number
	if deltaPixels ~= deltaPixels or math.abs(deltaPixels) == math.huge then
		return 0
	end
	return deltaPixels * InputConfig.MOUSE_LOOK_RADIANS_PER_PIXEL / dt
end

local function stickRate(value: number): number
	local deadzone, exponent = InputConfig.GAMEPAD_LOOK_DEADZONE, InputConfig.GAMEPAD_LOOK_EXPONENT
	return processGamepad(value, -1, exponent, deadzone) * InputConfig.GAMEPAD_LOOK_RADIANS_PER_SECOND
end

local function stepLookYaw(raw: RawInput, dt: number): number
	return mouseRate(raw.lookDeltaX, dt) + stickRate(raw.gamepadLookX)
end

-- El eje y del mouse crece hacia abajo; el pitch positivo es mirar hacia arriba.
local function stepLookPitch(raw: RawInput, dt: number): number
	return -mouseRate(raw.lookDeltaY, dt) + stickRate(raw.gamepadLookY)
end

local function stepSteer(previous: number, raw: RawInput, dt: number): number
	local keyboardTarget = boolToNumber(raw.isSteerRightDown) - boolToNumber(raw.isSteerLeftDown)
	local gamepadValue =
		processGamepad(raw.gamepadSteer, -1, InputConfig.GAMEPAD_STEER_EXPONENT, InputConfig.GAMEPAD_DEADZONE)
	local rise, back = InputConfig.STEER_RISE_SECONDS, InputConfig.STEER_RETURN_SECONDS
	return resolveAxis(previous, gamepadValue, keyboardTarget, rise, back, dt)
end

local function stepThrottle(previous: number, raw: RawInput, dt: number): number
	local gamepadValue =
		processGamepad(raw.gamepadThrottle, 0, InputConfig.GAMEPAD_PEDAL_EXPONENT, InputConfig.GAMEPAD_DEADZONE)
	local rise, back = InputConfig.THROTTLE_RISE_SECONDS, InputConfig.THROTTLE_RETURN_SECONDS
	return resolveAxis(previous, gamepadValue, boolToNumber(raw.isThrottleDown), rise, back, dt)
end

local function stepBrake(previous: number, raw: RawInput, dt: number): number
	local gamepadValue =
		processGamepad(raw.gamepadBrake, 0, InputConfig.GAMEPAD_PEDAL_EXPONENT, InputConfig.GAMEPAD_DEADZONE)
	local rise, back = InputConfig.BRAKE_RISE_SECONDS, InputConfig.BRAKE_RETURN_SECONDS
	return resolveAxis(previous, gamepadValue, boolToNumber(raw.isBrakeDown), rise, back, dt)
end

function InputSmoother.step(state: InputState, raw: RawInput, dt: number): InputState
	if dt ~= dt or dt == math.huge or dt <= 0 then
		return copyState(state)
	end
	local stepSeconds = math.min(dt, InputConfig.MAX_STEP_SECONDS)
	return {
		steer = stepSteer(state.steer, raw, stepSeconds),
		throttle = stepThrottle(state.throttle, raw, stepSeconds),
		brake = stepBrake(state.brake, raw, stepSeconds),
		isHandbrakeOn = raw.isHandbrakeDown,
		isLookingBack = raw.isLookBackDown,
		lookYawRate = stepLookYaw(raw, stepSeconds),
		lookPitchRate = stepLookPitch(raw, stepSeconds),
	}
end

return InputSmoother
