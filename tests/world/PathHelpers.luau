--!strict
-- Ayudas compartidas por las pruebas de la ruta. No es una prueba: no termina en Runner.finish().

local RoadPath = require("../../src/world/core/RoadPath")

local HASH_MULTIPLIER = 31
local HASH_MODULUS = 4294967296
local SAMPLE_FORMAT = "<ddddddd"

local PathHelpers = {}

function PathHelpers.generateSegments(path: RoadPath.RoadPath, count: number): { RoadPath.Segment }
	local segments = {}
	for index = 1, count do
		segments[index] = path.generateNextSegment()
	end
	return segments
end

-- Hash de los bits de todas las muestras: dos rutas iguales dan el mismo número, aunque difieran en un bit.
function PathHelpers.hashSegments(segments: { RoadPath.Segment }): number
	local hash = 0
	for _, segment in segments do
		for _, sample in segment.samples do
			local position = sample.position
			local packed = string.pack(
				SAMPLE_FORMAT,
				position.x,
				position.y,
				position.z,
				sample.heading,
				sample.curvature,
				sample.slope,
				sample.arcLength
			)
			for byteIndex = 1, #packed do
				hash = (hash * HASH_MULTIPLIER + string.byte(packed, byteIndex)) % HASH_MODULUS
			end
		end
	end
	return hash
end

return PathHelpers
