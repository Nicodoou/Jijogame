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
}

export type SmoothedInput = {
	steer: number,
	throttle: number,
	brake: number,
	isHandbrakeOn: boolean,
	isLookingBack: boolean,
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

local function applyDeadzone(value: number): number
	local magnitude = math.abs(value)
	if magnitude <= InputConfig.GAMEPAD_DEADZONE then
		return 0
	end
	return math.sign(value) * (magnitude - InputConfig.GAMEPAD_DEADZONE) / (1 - InputConfig.GAMEPAD_DEADZONE)
end

local function processGamepad(value: number, minimum: number, exponent: number): number
	local shaped = applyDeadzone(clampAxis(value, minimum))
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
	}
end

function InputSmoother.newState(): InputState
	return { steer = 0, throttle = 0, brake = 0, isHandbrakeOn = false, isLookingBack = false }
end

function InputSmoother.step(state: InputState, raw: RawInput, dt: number): InputState
	if dt ~= dt or dt == math.huge or dt <= 0 then
		return copyState(state)
	end
	local stepSeconds = math.min(dt, InputConfig.MAX_STEP_SECONDS)
	local steerTarget = boolToNumber(raw.isSteerRightDown) - boolToNumber(raw.isSteerLeftDown)
	local gamepadSteer = processGamepad(raw.gamepadSteer, -1, InputConfig.GAMEPAD_STEER_EXPONENT)
	local gamepadThrottle = processGamepad(raw.gamepadThrottle, 0, InputConfig.GAMEPAD_PEDAL_EXPONENT)
	local gamepadBrake = processGamepad(raw.gamepadBrake, 0, InputConfig.GAMEPAD_PEDAL_EXPONENT)
	return {
		steer = resolveAxis(
			state.steer,
			gamepadSteer,
			steerTarget,
			InputConfig.STEER_RISE_SECONDS,
			InputConfig.STEER_RETURN_SECONDS,
			stepSeconds
		),
		throttle = resolveAxis(
			state.throttle,
			gamepadThrottle,
			boolToNumber(raw.isThrottleDown),
			InputConfig.THROTTLE_RISE_SECONDS,
			InputConfig.THROTTLE_RETURN_SECONDS,
			stepSeconds
		),
		brake = resolveAxis(
			state.brake,
			gamepadBrake,
			boolToNumber(raw.isBrakeDown),
			InputConfig.BRAKE_RISE_SECONDS,
			InputConfig.BRAKE_RETURN_SECONDS,
			stepSeconds
		),
		isHandbrakeOn = raw.isHandbrakeDown,
		isLookingBack = raw.isLookBackDown,
	}
end

return InputSmoother
