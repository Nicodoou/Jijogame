--!strict
-- Afinación en vivo, solo en Studio (cliente y servidor): los atributos `Cfg_<NOMBRE>` de un objeto pisan los valores de
-- una configuración (VehicleConfig, CameraConfig...).
-- Los nombres que no existen en la configuración y los valores de otro tipo se ignoran.

local ATTRIBUTE_PREFIX = "Cfg_"

local TuningOverrides = {}
TuningOverrides.__index = TuningOverrides

export type TuningOverrides<T> = typeof(setmetatable(
	{} :: {
		_config: T,
	},
	TuningOverrides
))

local function buildConfig<T>(baseConfig: T, source: Instance): T
	local copy: { [string]: any } = table.clone(baseConfig :: any)
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

function TuningOverrides.new<T>(baseConfig: T, source: Instance, isStudio: boolean): TuningOverrides<T>
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

function TuningOverrides.getConfig<T>(self: TuningOverrides<T>): T
	return self._config
end

return TuningOverrides
