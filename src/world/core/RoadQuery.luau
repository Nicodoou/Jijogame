--!strict
-- Punto más cercano del eje de la ruta. Usa una grilla hash de muestras (búsqueda general, para el reset) y, si llega
-- el resultado anterior como cursor, una ventana de muestras (rápida, para cada frame).

local RoadEdgeProjection = require("./RoadEdgeProjection")
local RoadFrame = require("./RoadFrame")
local RoadPath = require("./RoadPath")
local RoadSampleGrid = require("./RoadSampleGrid")
local WorldConfig = require("./WorldConfig")

type Candidate = RoadEdgeProjection.Candidate

-- Todo en el plano horizontal: la altura no cuenta. lateralOffset es positivo a la derecha del sentido de marcha.
export type RoadQueryResult = {
	position: vector,
	direction: vector,
	lateralOffset: number,
	arcLength: number,
	segmentIndex: number,
}

export type RoadQuery = {
	findNearest: (position: vector, cursor: RoadQueryResult?) -> RoadQueryResult?,
	getExaminedSampleCount: () -> number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()
local CELL_STUDS = WorldConfig.ROAD_QUERY_GRID_CELL_STUDS
local MAX_DISTANCE_SQUARED = WorldConfig.ROAD_QUERY_MAX_DISTANCE_STUDS ^ 2
local WINDOW_SAMPLES = WorldConfig.ROAD_QUERY_CURSOR_WINDOW_SAMPLES
-- Dentro de este radio el punto más cercano del eje es único (la curvatura está acotada), así que un mínimo local
-- de la ventana es también el global.
local UNIQUE_NEAREST_SQUARED = WorldConfig.MIN_CURVE_RADIUS_STUDS ^ 2
local MAX_RING = math.ceil((WorldConfig.ROAD_QUERY_MAX_DISTANCE_STUDS + STEP_STUDS) / CELL_STUDS)

local function isFinite(value: number): boolean
	return value == value and math.abs(value) ~= math.huge
end

local RoadQueryModule = {}

function RoadQueryModule.new(path: RoadPath.RoadPath): RoadQuery
	local grid = RoadSampleGrid.new(path)
	local lowestIndex = 0
	local highestIndex = -1
	local examinedSampleCount = 0

	local function considerEdge(startIndex: number, queryX: number, queryZ: number, best: Candidate?): Candidate?
		local start, finish = grid.getSample(startIndex), grid.getSample(startIndex + 1)
		if start == nil or finish == nil then
			return best
		end
		return RoadEdgeProjection.pickCloser(
			best,
			RoadEdgeProjection.project(start.position, finish.position, startIndex, queryX, queryZ)
		)
	end

	local function considerCell(
		cellX: number,
		cellZ: number,
		queryX: number,
		queryZ: number,
		best: Candidate?
	): Candidate?
		local sampleIndices = grid.getSampleIndicesInCell(cellX, cellZ)
		local result = best
		if sampleIndices ~= nil then
			for _, sampleIndex in sampleIndices do
				examinedSampleCount += 1
				result = considerEdge(sampleIndex - 1, queryX, queryZ, result)
				result = considerEdge(sampleIndex, queryX, queryZ, result)
			end
		end
		return result
	end

	-- Recorre anillos de celdas alrededor de la consulta hasta que ninguna celda más lejana pueda traer algo mejor.
	local function searchGrid(queryX: number, queryZ: number): Candidate?
		local centerX = RoadSampleGrid.getCellCoordinate(queryX)
		local centerZ = RoadSampleGrid.getCellCoordinate(queryZ)
		local best = considerCell(centerX, centerZ, queryX, queryZ, nil)
		for ring = 1, MAX_RING do
			if best ~= nil and math.sqrt(best.distanceSquared) + STEP_STUDS <= (ring - 1) * CELL_STUDS then
				break
			end
			for offset = -ring, ring do
				best = considerCell(centerX + offset, centerZ - ring, queryX, queryZ, best)
				best = considerCell(centerX + offset, centerZ + ring, queryX, queryZ, best)
			end
			for offset = -ring + 1, ring - 1 do
				best = considerCell(centerX - ring, centerZ + offset, queryX, queryZ, best)
				best = considerCell(centerX + ring, centerZ + offset, queryX, queryZ, best)
			end
		end
		return best
	end

	-- Busca solo alrededor del cursor. Devuelve nil si el resultado no se puede garantizar como el mejor.
	local function searchWindow(cursor: RoadQueryResult, queryX: number, queryZ: number): Candidate?
		local cursorIndex = math.floor(cursor.arcLength / STEP_STUDS)
		local fromIndex = math.max(lowestIndex, cursorIndex - WINDOW_SAMPLES)
		local toIndex = math.min(highestIndex - 1, cursorIndex + WINDOW_SAMPLES)
		local best: Candidate? = nil
		for startIndex = fromIndex, toIndex do
			best = considerEdge(startIndex, queryX, queryZ, best)
		end
		examinedSampleCount += math.max(0, toIndex - fromIndex + 2)
		if best == nil then
			return nil
		end
		local touchesOpenStart = best.startIndex == fromIndex and fromIndex > lowestIndex
		local touchesOpenEnd = best.startIndex == toIndex and toIndex < highestIndex - 1
		if touchesOpenStart or touchesOpenEnd or best.distanceSquared >= UNIQUE_NEAREST_SQUARED then
			return nil
		end
		return best
	end

	local function isBeyondLoadedEnds(candidate: Candidate): boolean
		return (candidate.startIndex == lowestIndex and candidate.rawFraction < 0)
			or (candidate.startIndex == highestIndex - 1 and candidate.rawFraction > 1)
	end

	-- Las cuentas van con componentes sueltos (doubles): un `vector` guarda floats de 32 bits, que a miles de studs del
	-- origen pierden cerca de 0,001 studs en cada operación.
	local function buildResult(candidate: Candidate, queryX: number, queryZ: number): RoadQueryResult
		local start, finish = grid.getSample(candidate.startIndex), grid.getSample(candidate.startIndex + 1)
		assert(start and finish, "a candidate edge has both of its samples")
		local from, to = start.position, finish.position
		local edgeX, edgeY, edgeZ = to.x - from.x, to.y - from.y, to.z - from.z
		local pointX = from.x + edgeX * candidate.fraction
		local pointZ = from.z + edgeZ * candidate.fraction
		local edgeLength = math.sqrt(edgeX * edgeX + edgeY * edgeY + edgeZ * edgeZ)
		local isOnRight = (queryX - pointX) * -edgeZ + (queryZ - pointZ) * edgeX >= 0
		-- Con signo, pero con la distancia real: si el punto más cercano es un vértice, no es la proyección sobre la arista.
		local lateralOffset = math.sqrt(candidate.distanceSquared) * (if isOnRight then 1 else -1)
		return {
			position = vector.create(pointX, from.y + edgeY * candidate.fraction, pointZ),
			direction = vector.create(edgeX / edgeLength, edgeY / edgeLength, edgeZ / edgeLength),
			lateralOffset = lateralOffset,
			arcLength = start.arcLength + candidate.fraction * STEP_STUDS,
			segmentIndex = candidate.startIndex // STEPS_PER_SEGMENT,
		}
	end

	local function findNearest(position: vector, cursor: RoadQueryResult?): RoadQueryResult?
		examinedSampleCount = 0
		grid.syncWithPath()
		lowestIndex, highestIndex = grid.getLoadedSampleRange()
		local queryX, queryZ = position.x, position.z
		if highestIndex < lowestIndex or not isFinite(queryX) or not isFinite(queryZ) then
			return nil
		end
		local candidate = if cursor ~= nil then searchWindow(cursor, queryX, queryZ) else nil
		candidate = candidate or searchGrid(queryX, queryZ)
		if candidate == nil or candidate.distanceSquared > MAX_DISTANCE_SQUARED or isBeyondLoadedEnds(candidate) then
			return nil
		end
		return buildResult(candidate, queryX, queryZ)
	end

	local function getExaminedSampleCount(): number
		return examinedSampleCount
	end

	return { findNearest = findNearest, getExaminedSampleCount = getExaminedSampleCount }
end

return RoadQueryModule
