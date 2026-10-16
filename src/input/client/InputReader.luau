--!strict
-- Lee el teclado y el gamepad en cada frame y entrega valores crudos al núcleo del input.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputSmoother = require(ReplicatedStorage.input.core.InputSmoother)

type RawInput = InputSmoother.RawInput

local KEYS = {
	steerLeft = { Enum.KeyCode.A, Enum.KeyCode.Left },
	steerRight = { Enum.KeyCode.D, Enum.KeyCode.Right },
	throttle = { Enum.KeyCode.W, Enum.KeyCode.Up },
	brake = { Enum.KeyCode.S, Enum.KeyCode.Down },
	handbrake = { Enum.KeyCode.Space },
	lookBack = { Enum.KeyCode.C },
}
local GAMEPAD = {
	device = Enum.UserInputType.Gamepad1,
	steerStick = Enum.KeyCode.Thumbstick1,
	throttleTrigger = Enum.KeyCode.ButtonR2,
	brakeTrigger = Enum.KeyCode.ButtonL2,
	handbrakeButton = Enum.KeyCode.ButtonX,
	lookBackButton = Enum.KeyCode.ButtonY,
}
-- Un botón del gamepad cuenta como apretado cuando su valor pasa de la mitad del recorrido.
local BUTTON_PRESSED_THRESHOLD = 0.5

type GamepadReading = {
	steer: number,
	throttle: number,
	brake: number,
	isHandbrakeDown: boolean,
	isLookBackDown: boolean,
}

local InputReader = {}
InputReader.__index = InputReader

export type InputReader = typeof(setmetatable({}, InputReader))

function InputReader.new(): InputReader
	return setmetatable({}, InputReader)
end

local function isAnyKeyDown(keyCodes: { Enum.KeyCode }): boolean
	for _, keyCode in keyCodes do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

-- Sin gamepad conectado, la lista de estados viene vacía y todo da 0.
local function readGamepad(): GamepadReading
	local reading: GamepadReading =
		{ steer = 0, throttle = 0, brake = 0, isHandbrakeDown = false, isLookBackDown = false }
	for _, input in UserInputService:GetGamepadState(GAMEPAD.device) do
		local keyCode = input.KeyCode
		if keyCode == GAMEPAD.steerStick then
			reading.steer = input.Position.X
		elseif keyCode == GAMEPAD.throttleTrigger then
			reading.throttle = input.Position.Z
		elseif keyCode == GAMEPAD.brakeTrigger then
			reading.brake = input.Position.Z
		elseif keyCode == GAMEPAD.handbrakeButton then
			reading.isHandbrakeDown = input.Position.Z > BUTTON_PRESSED_THRESHOLD
		elseif keyCode == GAMEPAD.lookBackButton then
			reading.isLookBackDown = input.Position.Z > BUTTON_PRESSED_THRESHOLD
		end
	end
	return reading
end

function InputReader.read(_self: InputReader): RawInput
	local gamepad = readGamepad()
	return {
		isSteerLeftDown = isAnyKeyDown(KEYS.steerLeft),
		isSteerRightDown = isAnyKeyDown(KEYS.steerRight),
		isThrottleDown = isAnyKeyDown(KEYS.throttle),
		isBrakeDown = isAnyKeyDown(KEYS.brake),
		isHandbrakeDown = isAnyKeyDown(KEYS.handbrake) or gamepad.isHandbrakeDown,
		isLookBackDown = isAnyKeyDown(KEYS.lookBack) or gamepad.isLookBackDown,
		gamepadSteer = gamepad.steer,
		gamepadThrottle = gamepad.throttle,
		gamepadBrake = gamepad.brake,
	}
end

return InputReader
