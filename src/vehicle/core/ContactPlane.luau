--!strict
-- Dirección "arriba" del suelo a partir de los puntos de contacto de las ruedas apoyadas (de 2 a 4).
-- Ignora la normal de cada rayo por la ondulación del Terrain (#31).
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")

type VehicleSettings = VehicleTypes.VehicleSettings

local ContactPlane = {}

local FOUR_POINTS = 4
local THREE_POINTS = 3
local TWO_POINTS = 2

local function crossOfDiagonals(points: { vector }): vector
	return vector.cross(points[2] - points[3], points[1] - points[4])
end

local function crossOfSides(points: { vector }): vector
	return vector.cross(points[2] - points[1], points[3] - points[1])
end

-- Con dos puntos el plano no queda definido: se queda con el "arriba" del chasis sin la parte a lo largo de la línea.
local function upFromLine(points: { vector }, chassisUp: vector): vector
	local line = points[2] - points[1]
	local lineLength = vector.magnitude(line)
	if not (lineLength > 0) then
		return chassisUp
	end
	local direction = line / lineLength
	return chassisUp - direction * vector.dot(chassisUp, direction)
end

local function rawUp(points: { vector }, chassisUp: vector): vector
	if #points == FOUR_POINTS then
		return crossOfDiagonals(points)
	elseif #points == THREE_POINTS then
		return crossOfSides(points)
	elseif #points == TWO_POINTS then
		return upFromLine(points, chassisUp)
	end
	return chassisUp
end

-- Puntos de contacto de las ruedas con rayo que pegó, en el orden FL, FR, RL, RR.
function ContactPlane.hitPoints(contacts: { VehicleTypes.WheelContact? }, settings: VehicleSettings): { vector }
	local points = {}
	for index = 1, #settings.WHEELS do
		local contact = contacts[index]
		if contact ~= nil and contact.hasHit and VehicleMath.isFiniteVector(contact.point) then
			table.insert(points, contact.point)
		end
	end
	return points
end

function ContactPlane.upDirection(points: { vector }, chassisUp: vector, config: VehicleSettings?): vector
	local settings = config or VehicleConfig
	local candidate = rawUp(points, chassisUp)
	local length = vector.magnitude(candidate)
	if not (length >= settings.CONTACT_PLANE_DEGENERATE_THRESHOLD) then
		return chassisUp
	end
	local up = candidate / length
	if vector.dot(up, chassisUp) < 0 then
		return -up
	end
	return up
end

return ContactPlane
