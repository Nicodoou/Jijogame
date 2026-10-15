--!strict
-- Secuenciador de la ruta: sortea la próxima pieza, la previsualiza y la acepta o prueba otra (RoadPieceAlternatives, en
-- un orden fijo que termina en el último recurso: giros de radio mínimo hacia la guía).
-- Si ni el último recurso entra, la ruta retrocede: descarta las últimas piezas (1 a ROAD_BACKTRACK_MAX_PIECES, más
-- cuantas más fallas seguidas) y vuelve a sortear. Si no queda nada para retroceder, la ruta está encerrada y es un error.
-- Una muestra es definitiva recién cuando ya no hay forma de retroceder sobre ella.

local HillProfile = require("./HillProfile")
local LiveRoadIndex = require("./LiveRoadIndex")
local RoadFrame = require("./RoadFrame")
local RoadGuide = require("./RoadGuide")
local RoadIntegrator = require("./RoadIntegrator")
local RoadPieceAlternatives = require("./RoadPieceAlternatives")
local RoadPieceBuilder = require("./RoadPieceBuilder")
local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPiecePreview = require("./RoadPiecePreview")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSelector = require("./RoadPieceSelector")
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
	local statistics: SequencerStatistics = {
		pieceCount = 0,
		pieceCountByKind = {},
		arcLengthStuds = 0,
		lastResortCount = 0,
		backtrackCount = 0,
		retractedPieceCount = 0,
		guide = guide.getStatistics(),
	}
	index.add(state.x, state.z, 0)

	local function tryPiece(piece: RoadPiece): PreviewResult?
		return (previewer.preview(state, piece, guideSegment))
	end

	local function findNextPiece(): PreviewResult?
		guide.ensureCovers(guideArcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
		local lateralOffset, arcLength, segment = guide.project(state.x, state.z, guideSegment)
		guideArcLength, guideSegment = arcLength, segment
		local targetX, targetZ = guide.getPointAt(arcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
		local headingToTarget = math.atan2(targetZ - state.z, targetX - state.x)
		local steering: RoadPieceSelector.Steering = {
			headingErrorRadians = RoadFrame.wrapAngleRadians(headingToTarget - state.heading),
			lateralOffsetStuds = lateralOffset,
			previousKind = if #checkpoints > 0 then checkpoints[#checkpoints].pieceKind else nil,
		}
		local definition = RoadPieceSelector.pickDefinition(random, steering)
		local turnSign = RoadPieceSelector.pickTurnSign(random, steering, definition)
		local drawn = RoadPieceBuilder.draw(random, definition)
		local piece = if turnSign > 0 then drawn else RoadPieceBuilder.flip(drawn)
		local result, usedLastResort =
			RoadPieceAlternatives.findFirstAccepted(piece, RoadPieceSelector.getTowardSign(steering), tryPiece, random)
		statistics.lastResortCount += if usedLastResort then 1 else 0
		return result
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
			index.add(sample.position.x, sample.position.z, sample.arcLength)
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

	local function findPieceTakingBack(): PreviewResult
		local result = findNextPiece()
		while result == nil do
			takeBack()
			result = findNextPiece()
		end
		return result :: PreviewResult
	end

	local function generateNextPiece(): PieceResult
		local result = findPieceTakingBack()
		local retractedAfter = state.sampleIndex
		commit(result)
		return {
			retractedAfterSampleNumber = retractedAfter,
			samples = result.samples,
			finalizedSampleNumber = checkpoints[1].state.sampleIndex,
		}
	end

	local function getInitialSample(): RoadIntegrator.RoadSample
		return RoadIntegrator.toSample(initialState)
	end

	local function getStatistics(): SequencerStatistics
		return statistics
	end

	return {
		getInitialSample = getInitialSample,
		generateNextPiece = generateNextPiece,
		getStatistics = getStatistics,
	}
end

return RoadPieceSequencerModule
