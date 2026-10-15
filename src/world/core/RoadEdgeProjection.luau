--!strict
-- Proyección de un punto sobre una arista del eje (el tramo recto entre dos muestras vecinas), en el plano horizontal.

-- La arista que empieza en la muestra `startIndex` y el punto de ella más cercano a la consulta.
-- `rawFraction` es la posición de la proyección sobre la arista sin recortar: fuera de [0, 1] cae más allá de un extremo.
export type Candidate = {
	startIndex: number,
	fraction: number,
	rawFraction: number,
	distanceSquared: number,
}

local RoadEdgeProjection = {}

function RoadEdgeProjection.project(
	start: vector,
	finish: vector,
	startIndex: number,
	queryX: number,
	queryZ: number
): Candidate
	local edgeX, edgeZ = finish.x - start.x, finish.z - start.z
	local rawFraction = ((queryX - start.x) * edgeX + (queryZ - start.z) * edgeZ) / (edgeX * edgeX + edgeZ * edgeZ)
	local fraction = math.clamp(rawFraction, 0, 1)
	local offsetX = start.x + edgeX * fraction - queryX
	local offsetZ = start.z + edgeZ * fraction - queryZ
	return {
		startIndex = startIndex,
		fraction = fraction,
		rawFraction = rawFraction,
		distanceSquared = offsetX * offsetX + offsetZ * offsetZ,
	}
end

function RoadEdgeProjection.pickCloser(best: Candidate?, candidate: Candidate): Candidate
	if best == nil or candidate.distanceSquared < best.distanceSquared then
		return candidate
	end
	return best
end

return RoadEdgeProjection
