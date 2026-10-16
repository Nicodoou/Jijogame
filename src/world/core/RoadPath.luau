--!strict
-- Ruta infinita con semilla: agrupa en tramos las muestras que produce el secuenciador, que se generan adelante y se
-- liberan atrás. Como el secuenciador puede retroceder sobre sus últimas piezas, las muestras esperan en un buffer y
-- un tramo se publica recién cuando ya no cambia. Cada tramo depende solo de la semilla, aunque se hayan liberado los
-- anteriores.
-- La generación se puede hacer de a pasos (`generateStep`), para repartirla en una cola de trabajo con presupuesto.

local RoadFrame = require("./RoadFrame")
local RoadIntegrator = require("./RoadIntegrator")
local RoadPieceSequencer = require("./RoadPieceSequencer")

export type RoadSample = RoadIntegrator.RoadSample

-- Las muestras incluyen la última del tramo anterior como primera, así los tramos se tocan.
export type Segment = {
	index: number,
	samples: { RoadSample },
}

export type RoadPath = {
	-- Avanza la generación un paso acotado (a lo sumo una pieza, una alternativa o un retroceso) y devuelve el tramo cuando
	-- queda completo; mientras tanto, nil. Da exactamente los mismos tramos que `generateNextSegment`.
	generateStep: () -> Segment?,
	-- Repite pasos hasta tener el próximo tramo.
	generateNextSegment: () -> Segment,
	releaseSegmentsBefore: (index: number) -> (),
	getSegment: (index: number) -> Segment?,
	getLoadedRange: () -> (number, number),
}

local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()

local function assertIsInteger(value: number)
	if math.floor(value) ~= value then
		error("the segment index has to be an integer", 3)
	end
end

local RoadPathModule = {}

-- Igual que `new`, y además devuelve una función con los contadores del secuenciador (último recurso y retrocesos).
function RoadPathModule.newWithStatistics(seed: number): (RoadPath, () -> RoadPieceSequencer.SequencerStatistics)
	local sequencer = RoadPieceSequencer.new(seed)
	-- Muestras todavía no publicadas, por número (arcLength / paso). `pendingLast` es el mayor número guardado.
	local pending: { [number]: RoadSample } = { [0] = sequencer.getInitialSample() }
	local pendingLast = 0
	local finalizedNumber = 0
	local segments: { [number]: Segment } = {}
	local firstIndex = 0
	local lastIndex = -1

	local function receivePiece(piece: RoadPieceSequencer.PieceResult)
		for number = pendingLast, piece.retractedAfterSampleNumber + 1, -1 do
			pending[number] = nil
		end
		for offset, sample in piece.samples do
			pending[piece.retractedAfterSampleNumber + offset] = sample
		end
		pendingLast = piece.retractedAfterSampleNumber + #piece.samples
		finalizedNumber = piece.finalizedSampleNumber
	end

	local function publishNextSegment(): Segment
		local firstNumber = (lastIndex + 1) * STEPS_PER_SEGMENT
		local lastNumber = firstNumber + STEPS_PER_SEGMENT
		local samples = table.create(STEPS_PER_SEGMENT + 1)
		for offset = 0, STEPS_PER_SEGMENT do
			samples[offset + 1] = pending[firstNumber + offset]
		end
		-- La última muestra queda para el tramo siguiente.
		for number = firstNumber, lastNumber - 1 do
			pending[number] = nil
		end
		lastIndex += 1
		local segment = { index = lastIndex, samples = samples }
		segments[lastIndex] = segment
		return segment
	end

	local function generateStep(): Segment?
		local lastNumber = (lastIndex + 2) * STEPS_PER_SEGMENT
		if finalizedNumber < lastNumber then
			local piece = sequencer.generatePieceStep()
			if piece == nil then
				return nil
			end
			receivePiece(piece)
			if finalizedNumber < lastNumber then
				return nil
			end
		end
		return publishNextSegment()
	end

	local function generateNextSegment(): Segment
		local segment = generateStep()
		while segment == nil do
			segment = generateStep()
		end
		return segment :: Segment
	end

	local function releaseSegmentsBefore(index: number)
		assertIsInteger(index)
		local releaseUpTo = math.min(index, lastIndex + 1)
		for released = firstIndex, releaseUpTo - 1 do
			segments[released] = nil
		end
		firstIndex = math.max(firstIndex, releaseUpTo)
	end

	local function getSegment(index: number): Segment?
		return segments[index]
	end

	-- Si no hay tramos cargados, el último índice es menor que el primero.
	local function getLoadedRange(): (number, number)
		return firstIndex, lastIndex
	end

	local path = {
		generateStep = generateStep,
		generateNextSegment = generateNextSegment,
		releaseSegmentsBefore = releaseSegmentsBefore,
		getSegment = getSegment,
		getLoadedRange = getLoadedRange,
	}
	return path, sequencer.getStatistics
end

function RoadPathModule.new(seed: number): RoadPath
	local path = RoadPathModule.newWithStatistics(seed)
	return path
end

return RoadPathModule
