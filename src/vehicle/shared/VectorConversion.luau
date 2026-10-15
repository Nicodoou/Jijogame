--!strict
-- Traduce entre los tipos de Roblox y el `vector` del núcleo, que no conoce `Vector3`.
local VectorConversion = {}

function VectorConversion.toVector(value: Vector3): vector
	return vector.create(value.X, value.Y, value.Z)
end

function VectorConversion.toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

return VectorConversion
