--!strict
-- Punto más cercano del eje dentro de un bloque de ruta. Como un bloque es un arco de menos de 180 grados, la
-- pregunta "¿el punto queda más allá del final de la arista i?" cambia una sola vez a lo largo del bloque: se busca
-- la arista con una bisección (unas cinco vueltas) en vez de recorrerlas todas.

local RoadBlocks = require("./RoadBlocks")

local RoadBlockNearest = {}

-- Devuelve la distancia en el plano al eje y la altura del eje en el punto más cercano del bloque.
function RoadBlockNearest.find(block: RoadBlocks.RoadBlock, x: number, z: number): (number, number)
	local xs, zs, edgeX, edgeZ = block.xs, block.zs, block.edgeX, block.edgeZ
	local low, high = 1, #edgeX
	while low < high do
		local middle = (low + high) // 2
		-- true si el punto queda más allá del final de la arista: el mínimo está más adelante.
		local isBeyondEnd = (x - xs[middle + 1]) * edgeX[middle] + (z - zs[middle + 1]) * edgeZ[middle] > 0
		if isBeyondEnd then
			low = middle + 1
		else
			high = middle
		end
	end
	local edgeFromX, edgeFromZ = edgeX[low], edgeZ[low]
	local fromX, fromZ = xs[low], zs[low]
	local fraction =
		math.clamp(((x - fromX) * edgeFromX + (z - fromZ) * edgeFromZ) / (edgeFromX ^ 2 + edgeFromZ ^ 2), 0, 1)
	local offsetX, offsetZ = x - (fromX + edgeFromX * fraction), z - (fromZ + edgeFromZ * fraction)
	local ys = block.ys
	return math.sqrt(offsetX * offsetX + offsetZ * offsetZ), ys[low] + (ys[low + 1] - ys[low]) * fraction
end

-- Lo mismo, pero contra la cuerda del bloque (la recta del primer al último punto). A diferencia del arco, la cuerda
-- tiene un punto más cercano que cambia de forma continua con la posición: no hay empates entre los extremos.
function RoadBlockNearest.findAlongChord(block: RoadBlocks.RoadBlock, x: number, z: number): (number, number)
	local xs, ys, zs = block.xs, block.ys, block.zs
	local last = #xs
	local chordX, chordZ = xs[last] - xs[1], zs[last] - zs[1]
	local fraction = math.clamp(((x - xs[1]) * chordX + (z - zs[1]) * chordZ) / (chordX ^ 2 + chordZ ^ 2), 0, 1)
	local offsetX, offsetZ = x - (xs[1] + chordX * fraction), z - (zs[1] + chordZ * fraction)
	return math.sqrt(offsetX * offsetX + offsetZ * offsetZ), ys[1] + (ys[last] - ys[1]) * fraction
end

return RoadBlockNearest
