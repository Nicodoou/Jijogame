--!strict
-- Grilla hash de las muestras cargadas. Guarda cada muestra por su número global (arcLength / paso) y por la celda
-- del plano horizontal donde cae, para buscar las cercanas a un punto sin recorrer toda la ruta.

local RoadFrame = require("./RoadFrame")
local RoadPath = require("./RoadPath")
local WorldConfig = require("./WorldConfig")

type RoadSample = RoadPath.RoadSample

export type RoadSampleGrid = {
	-- Pone la grilla al día con los tramos cargados de la ruta: quita los liberados y agrega los nuevos.
	syncWithPath: () -> (),
	-- Primer y último número de muestra guardados. Si no hay ninguna, el último es menor que el primero.
	getLoadedSampleRange: () -> (number, number),
	getSample: (sampleIndex: number) -> RoadSample?,
	getSampleIndicesInCell: (cellX: number, cellZ: number) -> { number }?,
}

local CELL_STUDS = WorldConfig.ROAD_QUERY_GRID_CELL_STUDS
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()

local function getCellKey(cellX: number, cellZ: number): number
	return cellX * KEY_STRIDE + cellZ
end

local RoadSampleGridModule = {}

function RoadSampleGridModule.getCellCoordinate(value: number): number
	return math.floor(value / CELL_STUDS)
end

function RoadSampleGridModule.new(path: RoadPath.RoadPath): RoadSampleGrid
	local samples: { [number]: RoadSample } = {}
	local cells: { [number]: { number } } = {}
	local lowestIndex = 0
	local highestIndex = -1

	local function getKeyOf(sample: RoadSample): number
		local position = sample.position
		return getCellKey(
			RoadSampleGridModule.getCellCoordinate(position.x),
			RoadSampleGridModule.getCellCoordinate(position.z)
		)
	end

	local function addSample(sampleIndex: number, sample: RoadSample)
		samples[sampleIndex] = sample
		local key = getKeyOf(sample)
		local cell = cells[key]
		if cell == nil then
			cells[key] = { sampleIndex }
		else
			table.insert(cell, sampleIndex)
		end
	end

	local function removeSample(sampleIndex: number)
		local key = getKeyOf(samples[sampleIndex])
		local cell = cells[key]
		local positionInCell = table.find(cell, sampleIndex)
		assert(positionInCell, "a stored sample has to be in its cell")
		table.remove(cell, positionInCell)
		if #cell == 0 then
			cells[key] = nil
		end
		samples[sampleIndex] = nil
	end

	local function addSegmentSamples(segmentIndex: number)
		local segment = path.getSegment(segmentIndex)
		assert(segment, "a loaded segment has to exist")
		for offset, sample in segment.samples do
			local sampleIndex = segmentIndex * STEPS_PER_SEGMENT + offset - 1
			-- La última muestra de un tramo es la primera del siguiente.
			if samples[sampleIndex] == nil then
				addSample(sampleIndex, sample)
			end
		end
	end

	local function syncWithPath()
		local firstSegment, lastSegment = path.getLoadedRange()
		if lastSegment < firstSegment then
			for sampleIndex = lowestIndex, highestIndex do
				removeSample(sampleIndex)
			end
			lowestIndex, highestIndex = 0, -1
			return
		end
		local wantedLowest, wantedHighest = firstSegment * STEPS_PER_SEGMENT, (lastSegment + 1) * STEPS_PER_SEGMENT
		if wantedLowest == lowestIndex and wantedHighest == highestIndex then
			return
		end
		for sampleIndex = lowestIndex, math.min(wantedLowest - 1, highestIndex) do
			removeSample(sampleIndex)
		end
		local firstNewSegment = if highestIndex < lowestIndex then firstSegment else highestIndex // STEPS_PER_SEGMENT
		for segmentIndex = math.max(firstSegment, firstNewSegment), lastSegment do
			addSegmentSamples(segmentIndex)
		end
		lowestIndex, highestIndex = wantedLowest, wantedHighest
	end

	local function getLoadedSampleRange(): (number, number)
		return lowestIndex, highestIndex
	end

	local function getSample(sampleIndex: number): RoadSample?
		return samples[sampleIndex]
	end

	local function getSampleIndicesInCell(cellX: number, cellZ: number): { number }?
		return cells[getCellKey(cellX, cellZ)]
	end

	return {
		syncWithPath = syncWithPath,
		getLoadedSampleRange = getLoadedSampleRange,
		getSample = getSample,
		getSampleIndicesInCell = getSampleIndicesInCell,
	}
end

return RoadSampleGridModule
