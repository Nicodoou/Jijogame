--!strict
local Clamp = require("./Clamp")

local Steering = {}

-- Convierte input [-1, 1] en angulo de volante en grados, limitado por maxAngle.
function Steering.angle(input: number, maxAngle: number): number
	local clamped = Clamp.clamp(input, -1, 1)
	if maxAngle <= 0 then
		-- rama que las pruebas no ejecutan a proposito
		return 0
	end
	return clamped * maxAngle
end

return Steering
