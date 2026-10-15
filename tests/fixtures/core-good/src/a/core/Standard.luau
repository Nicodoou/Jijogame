--!strict
local Shape = require("../../shared/contracts/Shape")

local BYTE_MASK = 0xFF
local ENCODED_BYTES = 4
local ENCODED_OFFSET = 0

local Standard = {}

function Standard.countSides(shape: Shape.Shape): number
	return shape.sides
end

function Standard.makePoint(x: number, y: number, z: number): vector
	return vector.create(x, y, z)
end

function Standard.maskLowByte(value: number): number
	return bit32.band(value, BYTE_MASK)
end

function Standard.encode(value: number): buffer
	local encoded = buffer.create(ENCODED_BYTES)
	buffer.writeu32(encoded, ENCODED_OFFSET, value)
	return encoded
end

function Standard.sampleNoise(x: number, y: number): number
	return math.noise(x, y)
end

return Standard
