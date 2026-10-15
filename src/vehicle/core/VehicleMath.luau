--!strict
-- Ayudas numéricas del núcleo del auto: lo que hace falta para que un NaN o un infinito
-- de entrada no se propague a las fuerzas.

local VehicleMath = {}

function VehicleMath.isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function VehicleMath.finiteOr(value: number, fallback: number): number
	if VehicleMath.isFinite(value) then
		return value
	end
	return fallback
end

function VehicleMath.isFiniteVector(value: vector): boolean
	return VehicleMath.isFinite(value.x) and VehicleMath.isFinite(value.y) and VehicleMath.isFinite(value.z)
end

-- Un paso con dt que no es un número finito mayor que 0 no cambia nada.
function VehicleMath.isUsableStep(dt: number): boolean
	return VehicleMath.isFinite(dt) and dt > 0
end

function VehicleMath.smoothingAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

return VehicleMath
