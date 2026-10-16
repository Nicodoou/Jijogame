--!strict
-- Afinación en vivo, solo en Studio: los atributos `Cfg_<NOMBRE>` de un objeto pisan los valores de VehicleConfig.
-- Los nombres que no existen en la configuración y los valores de otro tipo se ignoran.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings

local ATTRIBUTE_PREFIX = "Cfg_"

local TuningOverrides = {}
TuningOverrides.__index = TuningOverrides

export type TuningOverrides = typeof(setmetatable(
	{} :: {
		_config: VehicleSettings,
	},
	TuningOverrides
))

local function buildConfig(baseConfig: VehicleSettings, source: Instance): VehicleSettings
	local copy: { [string]: any } = table.clone(baseConfig) :: any
	for attributeName, value in source:GetAttributes() do
		if string.sub(attributeName, 1, #ATTRIBUTE_PREFIX) == ATTRIBUTE_PREFIX then
			local settingName = string.sub(attributeName, #ATTRIBUTE_PREFIX + 1)
			if typeof(copy[settingName]) == typeof(value) then
				copy[settingName] = value
			end
		end
	end
	return table.freeze(copy) :: any
end

function TuningOverrides.new(baseConfig: VehicleSettings, source: Instance, isStudio: boolean): TuningOverrides
	local self = setmetatable({
		_config = if isStudio then buildConfig(baseConfig, source) else baseConfig,
	}, TuningOverrides)
	if isStudio then
		source.AttributeChanged:Connect(function()
			self._config = buildConfig(baseConfig, source)
		end)
	end
	return self
end

function TuningOverrides.getConfig(self: TuningOverrides): VehicleSettings
	return self._config
end

return TuningOverrides
