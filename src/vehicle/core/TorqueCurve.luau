--!strict
-- Fracción del torque pico que da la curva de un motor a unas RPM, interpolada en línea recta entre puntos.
local SpecTypes = require("./specs/SpecTypes")

local TorqueCurve = {}

-- Antes del primer punto y después del último vale el valor del extremo.
function TorqueCurve.fractionAt(curve: { SpecTypes.TorquePoint }, rpm: number): number
	local first = curve[1]
	if rpm <= first.rpm then
		return first.fraction
	end
	for index = 2, #curve do
		local upper = curve[index]
		if rpm <= upper.rpm then
			local lower = curve[index - 1]
			local blend = (rpm - lower.rpm) / (upper.rpm - lower.rpm)
			return lower.fraction + (upper.fraction - lower.fraction) * blend
		end
	end
	return curve[#curve].fraction
end

return TorqueCurve
