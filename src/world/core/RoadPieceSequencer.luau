--!strict
-- Secuenciador de la ruta: sortea la próxima pieza, la previsualiza y la acepta o prueba otra (RoadPieceAlternatives, en
-- un orden fijo que termina en el último recurso: giros de radio mínimo hacia la guía).
-- Trabaja de a pasos acotados (sortear una pieza, probar una alternativa o retroceder), así el costo de cada llamada es chico.
-- Si ni el último recurso entra, la ruta retrocede: descarta las últimas piezas (1 a ROAD_BACKTRACK_MAX_PIECES, más
-- cuantas más fallas seguidas) y vuelve a sortear. Si no queda nada para retroceder, la ruta está encerrada y es un error.
-- Una muestra es definitiva recién cuando ya no hay forma de retroceder sobre ella.

local HillProfile = require("./HillProfile")
local LiveRoadIndex = require("./LiveRoadIndex")
local RoadFrame = require("./RoadFrame")
local RoadGuide = require("./RoadGuide")
local RoadIntegrator = require("./RoadIntegrator")
local RoadPieceAlternatives = require("./RoadPieceAlternatives")
local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPieceChooser = require("./RoadPieceChooser")
local RoadPiecePreview = require("./RoadPiecePreview")
local RoadPieceProfile = require("./RoadPieceProfile")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type IntegratorState = RoadIntegrator.IntegratorState
type PreviewResult = RoadPiecePreview.PreviewResult
type RoadPiece = RoadPieceProfile.RoadPiece

-- Las muestras con número (arcLength / paso) mayor que `retractedAfterSampleNumber` se retiran y las nuevas siguen a
-- partir de ahí. Las de número menor o igual que `finalizedSampleNumber` ya no cambian.
export type PieceResult = {
	retractedAfterSampleNumber: number,
	samples: { RoadIntegrator.RoadSample },
	finalizedSampleNumber: number,
}

export type SequencerStatistics = {
	pieceCount: number,
	-- Piezas vigentes (sin contar las retiradas) por clase.
	pieceCountByKind: { [RoadPieceCatalog.PieceKind]: number },
	-- Largo recorrido por la ruta generada, en studs, incluido lo que todavía puede retirarse.
	arcLengthStuds: number,
	-- Veces que ninguna alternativa entró y se llegó al último recurso (aunque después haya entrado).
	lastResortCount: number,
	-- Veces que la ruta retrocedió y piezas descartadas en total.
	backtrackCount: number,
	retractedPieceCount: number,
	guide: RoadGuide.GuideStatistics,
}

export type RoadPieceSequencer = {
	getInitialSample: () -> RoadIntegrator.RoadSample,
	-- Hace un paso y devuelve la pieza cuando la acepta; si no, nil. Un paso es sortear una pieza, probar una alternativa o retroceder.
	generatePieceStep: () -> PieceResult?,
	-- Repite pasos hasta tener una pieza aceptada.
	generateNextPiece: () -> PieceResult,
	getStatistics: () -> SequencerStatistics,
}

-- Dónde estaba la ruta antes de una pieza, para volver ahí.
type Checkpoint = {
	state: IntegratorState,
	guideSegment: number,
	guideArcLength: number,
	-- Clase de la pieza que se agregó después de este punto.
	pieceKind: RoadPieceCatalog.PieceKind,
}

-- Lo que hace el próximo paso: sortear una pieza, probar la siguiente alternativa o retroceder.
type Phase = "draw" | "try" | "takeBack"

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS

local RoadPieceSequencerModule = {}

function RoadPieceSequencerModule.new(seed: number): RoadPieceSequencer
	-- Tres secuencias independientes (guía, cerros y piezas), así lo que consume una no mueve a las otras.
	local seedRandom = SeededRandom.new(seed)
	local guide = RoadGuide.new(SeededRandom.new(seedRandom.nextNumber()))
	local hill = HillProfile.new(seedRandom.nextNumber())
	local random = SeededRandom.new(seedRandom.nextNumber())
	local index = LiveRoadIndex.new()
	local previewer = RoadPiecePreview.new(guide, index, hill)

	local initialState = RoadIntegrator.createState(WorldConfig.START_POSITION, RoadFrame.getStartHeadingRadians())
	local state = initialState
	local guideSegment, guideArcLength = 1, 0
	local checkpoints: { Checkpoint } = {}
	local failStreak = 0
	local bestArcLength = 0
	local phase: Phase = "draw"
	local alternatives: RoadPieceAlternatives.RoadPieceAlternatives? = nil
	local isUsingLastResort = false
	local statistics: SequencerStatistics = {
		pieceCount = 0,
		pieceCountByKind = {},
		arcLengthStuds = 0,
		lastResortCount = 0,
		backtrackCount = 0,
		retractedPieceCount = 0,
		guide = guide.getStatistics(),
	}
	index.add(state.x, state.y, state.z, 0)

	local function tryPiece(piece: RoadPiece): PreviewResult?
		return (previewer.preview(state, piece, guideSegment))
	end

	local function drawPiece()
		local previousKind: RoadPieceCatalog.PieceKind? = if #checkpoints > 0
			then checkpoints[#checkpoints].pieceKind
			else nil
		local choice = RoadPieceChooser.choose(guide, random, state, guideSegment, guideArcLength, previousKind)
		guideSegment, guideArcLength = choice.guideSegment, choice.guideArcLength
		alternatives = RoadPieceAlternatives.new(choice.piece, choice.towardSign, random)
		isUsingLastResort = false
		phase = "try"
	end

	-- Prueba la próxima alternativa. Cuando no queda ninguna, el siguiente paso es retroceder.
	local function tryNextAlternative(): PreviewResult?
		local candidate, isLastResort = (alternatives :: RoadPieceAlternatives.RoadPieceAlternatives).next()
		if isLastResort and not isUsingLastResort then
			isUsingLastResort = true
			statistics.lastResortCount += 1
		end
		if candidate == nil then
			phase = "takeBack"
			return nil
		end
		return tryPiece(candidate)
	end

	local function commit(result: PreviewResult)
		table.insert(checkpoints, {
			state = state,
			guideSegment = guideSegment,
			guideArcLength = guideArcLength,
			pieceKind = result.pieceKind,
		})
		if #checkpoints > WorldConfig.ROAD_BACKTRACK_MAX_PIECES then
			table.remove(checkpoints, 1)
		end
		for _, sample in result.samples do
			index.add(sample.position.x, sample.position.y, sample.position.z, sample.arcLength)
		end
		state, guideSegment, guideArcLength = result.endState, result.guideSegment, result.guideArcLength
		statistics.pieceCount += 1
		statistics.pieceCountByKind[result.pieceKind] = (statistics.pieceCountByKind[result.pieceKind] or 0) + 1
		statistics.arcLengthStuds = state.sampleIndex * STEP_STUDS
		if statistics.arcLengthStuds > bestArcLength then
			bestArcLength = statistics.arcLengthStuds
			failStreak = 0
		end
	end

	local function takeBack()
		failStreak += 1
		if #checkpoints == 0 or failStreak > WorldConfig.ROAD_FAIL_LIMIT then
			error("the road is enclosed: no piece fits and there is nothing left to take back", 3)
		end
		local count = math.min(#checkpoints, 1 + failStreak // WorldConfig.ROAD_BACKTRACK_FAILS_PER_EXTRA_PIECE)
		local checkpoint = checkpoints[#checkpoints - count + 1]
		for _ = 1, count do
			local retracted = table.remove(checkpoints) :: Checkpoint
			statistics.pieceCount -= 1
			statistics.pieceCountByKind[retracted.pieceKind] -= 1
		end
		state, guideSegment, guideArcLength = checkpoint.state, checkpoint.guideSegment, checkpoint.guideArcLength
		index.removeAfter(state.sampleIndex * STEP_STUDS)
		statistics.arcLengthStuds = state.sampleIndex * STEP_STUDS
		statistics.backtrackCount += 1
		statistics.retractedPieceCount += count
	end

	local function acceptPiece(result: PreviewResult): PieceResult
		local retractedAfter = state.sampleIndex
		commit(result)
		phase = "draw"
		return {
			retractedAfterSampleNumber = retractedAfter,
			samples = result.samples,
			finalizedSampleNumber = checkpoints[1].state.sampleIndex,
		}
	end

	local function generatePieceStep(): PieceResult?
		if phase == "draw" then
			drawPiece()
		elseif phase == "takeBack" then
			takeBack()
			phase = "draw"
		else
			local result = tryNextAlternative()
			if result ~= nil then
				return acceptPiece(result)
			end
		end
		return nil
	end

	local function generateNextPiece(): PieceResult
		local piece = generatePieceStep()
		while piece == nil do
			piece = generatePieceStep()
		end
		return piece :: PieceResult
	end

	local function getInitialSample(): RoadIntegrator.RoadSample
		return RoadIntegrator.toSample(initialState)
	end

	local function getStatistics(): SequencerStatistics
		return statistics
	end

	return {
		getInitialSample = getInitialSample,
		generatePieceStep = generatePieceStep,
		generateNextPiece = generateNextPiece,
		getStatistics = getStatistics,
	}
end

return RoadPieceSequencerModule
