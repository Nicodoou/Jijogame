--!strict
-- Dónde está el centro de masa respecto de las ruedas: de ahí salen el brazo de cada rueda y la parte del peso
-- que carga cada una. Con el centro de masa en el centro del marco de las ruedas, reparte en partes iguales.
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample
type VehicleSettings = VehicleTypes.VehicleSettings

local WeightDistribution = {}

-- El centro de masa nunca queda más cerca que esto de un borde del reparto, aunque caiga fuera de las ruedas.
local MIN_FRACTION = 0.05
local MAX_FRACTION = 0.95

-- Si el origen del marco no es un punto válido se usa el centro de masa, que es el comportamiento sin lastre.
function WeightDistribution.frameOrigin(chassis: ChassisSample): vector
	if VehicleMath.isFiniteVector(chassis.origin) then
		return chassis.origin
	end
	return chassis.position
end

-- Parte del peso en la rueda de menor coordenada de un par (la delantera o la izquierda), según dónde cae
-- el centro de masa entre las dos coordenadas locales.
local function lowSideFraction(centerCoordinate: number, lowCoordinate: number, highCoordinate: number): number
	local span = highCoordinate - lowCoordinate
	if not (math.abs(span) > 0) then
		return 0.5
	end
	return math.clamp((highCoordinate - centerCoordinate) / span, MIN_FRACTION, MAX_FRACTION)
end

-- Parte del peso total que carga cada rueda, en el orden FL, FR, RL, RR. Suman 1.
function WeightDistribution.wheelShares(chassis: ChassisSample, config: VehicleSettings?): { number }
	local settings = config or VehicleConfig
	local offset = chassis.position - WeightDistribution.frameOrigin(chassis)
	local centerX = vector.dot(offset, chassis.right)
	local centerZ = -vector.dot(offset, chassis.forward)
	local front, rear, left, right =
		settings.WHEELS[1].offset, settings.WHEELS[1].offset, settings.WHEELS[1].offset, settings.WHEELS[1].offset
	for _, wheel in settings.WHEELS do
		front = if wheel.isFront then wheel.offset else front
		rear = if wheel.isFront then rear else wheel.offset
		left = if wheel.isLeft then wheel.offset else left
		right = if wheel.isLeft then right else wheel.offset
	end
	local frontFraction = lowSideFraction(centerZ, front.z, rear.z)
	local leftFraction = lowSideFraction(centerX, left.x, right.x)
	local shares = {}
	for index, wheel in settings.WHEELS do
		local axle = if wheel.isFront then frontFraction else 1 - frontFraction
		local side = if wheel.isLeft then leftFraction else 1 - leftFraction
		shares[index] = axle * side
	end
	return shares
end

return WeightDistribution
