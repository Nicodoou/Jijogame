--!strict
-- Mueve las ruedas visuales con el `Transform` de su Motor6D: compresión, dirección y giro.
-- El cilindro tiene su eje en x, así que girar hacia adelante (-z) es un ángulo negativo alrededor de x.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings
type WheelOutput = VehicleTypes.WheelOutput

local WheelVisuals = {}
WheelVisuals.__index = WheelVisuals

export type WheelVisuals = typeof(setmetatable(
	{} :: {
		_motors: { Motor6D },
		_spinRadians: { number },
	},
	WheelVisuals
))

function WheelVisuals.new(motors: { Motor6D }): WheelVisuals
	local spinRadians = table.create(#motors, 0)
	return setmetatable({ _motors = motors, _spinRadians = spinRadians }, WheelVisuals)
end

function WheelVisuals.update(self: WheelVisuals, outputs: { WheelOutput }, dt: number, config: VehicleSettings)
	for index, motor in self._motors do
		local output = outputs[index]
		self._spinRadians[index] += output.spinRadiansPerSecond * dt
		local dropStuds = config.SUSPENSION_REST_LENGTH_STUDS - output.compressionStuds
		local steerRadians = if config.WHEELS[index].isFront then -output.steerAngleRadians else 0
		motor.Transform = CFrame.new(0, -dropStuds, 0)
			* CFrame.Angles(0, steerRadians, 0)
			* CFrame.Angles(-self._spinRadians[index], 0, 0)
	end
end

return WheelVisuals
