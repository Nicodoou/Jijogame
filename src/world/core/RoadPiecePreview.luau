--!strict
-- Previsualiza una pieza: la integra con RoadIntegrator, sin tocar el estado de nadie, y la acepta solo si cumple las
-- cuatro condiciones:
--   1. todas sus muestras quedan dentro del área y a no más de LOCAL_DEVIATION_MAX_STUDS de la guía (el túnel);
--   2. cumple el anti-cruce y la regla de altura entre pasadas (LiveRoadIndex);
--   3. su rumbo relativo a la guía no pasa de MAX_RELATIVE_HEADING_DEGREES (la horquilla doble queda exenta);
--   4. desde su final cabe una salida de emergencia: un giro de radio mínimo hacia la guía.

local HillProfile = require("./HillProfile")
local LiveRoadIndex = require("./LiveRoadIndex")
local RoadFrame = require("./RoadFrame")
local RoadGuide = require("./RoadGuide")
local RoadIntegrator = require("./RoadIntegrator")
local RoadPieceBuilder = require("./RoadPieceBuilder")
local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSelector = require("./RoadPieceSelector")
local WorldConfig = require("./WorldConfig")

type IntegratorState = RoadIntegrator.IntegratorState
type RoadPiece = RoadPieceProfile.RoadPiece

export type RejectionReason = "area" | "deviation" | "crowded" | "heading" | "escape"

-- Lo que queda después de una pieza aceptada: sus muestras (sin la de partida), el estado final y dónde cae sobre la guía.
export type PreviewResult = {
	pieceKind: RoadPieceCatalog.PieceKind,
	samples: { RoadIntegrator.RoadSample },
	endState: IntegratorState,
	guideArcLength: number,
	guideSegment: number,
}

export type RoadPiecePreview = {
	preview: (start: IntegratorState, piece: RoadPiece, guideSegment: number) -> (PreviewResult?, RejectionReason?),
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
-- Una pieza que arranca afuera del túnel y sigue en paralelo a la guía no cuenta como alejarse por el redondeo.
local DEVIATION_TOLERANCE_STUDS = 1
local AREA_SQUARED = WorldConfig.AREA_RADIUS_STUDS ^ 2
local MAX_RELATIVE_HEADING_RADIANS = math.rad(WorldConfig.MAX_RELATIVE_HEADING_DEGREES)
local ESCAPE_MIN_ERROR_RADIANS = math.rad(WorldConfig.ESCAPE_MIN_HEADING_ERROR_DEGREES)

local RoadPiecePreviewModule = {}

function RoadPiecePreviewModule.new(
	guide: RoadGuide.RoadGuide,
	index: LiveRoadIndex.LiveRoadIndex,
	hill: HillProfile.HillProfile
): RoadPiecePreview
	local function getRelativeHeading(heading: number, guideSegment: number): number
		return math.abs(RoadFrame.wrapAngleRadians(heading - guide.getSegmentHeading(guideSegment)))
	end

	-- La pieza no puede alejar el rumbo de la guía más que el límite, ni más que lo que ya estaba al empezar.
	local function getHeadingLimit(start: IntegratorState, piece: RoadPiece, guideSegment: number): number
		if RoadPieceSelector.getDefinition(piece.kind).turnsBack then
			return math.huge
		end
		local _, _, startSegment = guide.project(start.x, start.z, guideSegment)
		return math.max(MAX_RELATIVE_HEADING_RADIANS, getRelativeHeading(start.heading, startSegment))
	end

	-- Hasta dónde puede alejarse una pieza de la guía: el túnel (más ancho para las piezas que dan la vuelta, que desplazan la
	-- ruta hacia un costado) o, si ya empezó afuera, lo que ya estaba. Así una pieza nunca empeora un desvío.
	local function getDeviationLimit(
		position: IntegratorState,
		guideSegment: number,
		tunnel: number,
		tolerance: number
	): number
		local startOffset = guide.project(position.x, position.z, guideSegment)
		return math.max(tunnel, math.abs(startOffset) + tolerance)
	end

	local function getTunnel(piece: RoadPiece): number
		if RoadPieceSelector.getDefinition(piece.kind).turnsBack then
			return WorldConfig.LOCAL_DEVIATION_MAX_STUDS + WorldConfig.TURN_BACK_EXTRA_DEVIATION_STUDS
		end
		return WorldConfig.LOCAL_DEVIATION_MAX_STUDS
	end

	local function walk(
		start: IntegratorState,
		piece: RoadPiece,
		startSegment: number,
		headingLimit: number,
		deviationLimit: number
	): (PreviewResult?, RejectionReason?)
		local state = table.clone(start)
		local samples = table.create(piece.totalSteps)
		local segment = startSegment
		for step = 1, piece.totalSteps do
			RoadIntegrator.step(state, RoadPieceProfile.getCurvatureAtStep(piece, step), hill)
			if state.x * state.x + state.z * state.z > AREA_SQUARED then
				return nil, "area"
			end
			local lateralOffset, _, projectedSegment = guide.project(state.x, state.z, segment)
			segment = projectedSegment
			if math.abs(lateralOffset) > deviationLimit then
				return nil, "deviation"
			elseif not index.isClear(state.x, state.y, state.z, state.sampleIndex * STEP_STUDS) then
				return nil, "crowded"
			elseif getRelativeHeading(state.heading, segment) > headingLimit then
				return nil, "heading"
			end
			samples[step] = RoadIntegrator.toSample(state)
		end
		local _, arcLength, endSegment = guide.project(state.x, state.z, segment)
		local result: PreviewResult = {
			pieceKind = piece.kind,
			samples = samples,
			endState = state,
			guideArcLength = arcLength,
			guideSegment = endSegment,
		}
		return result, nil
	end

	-- Desde el final tiene que caber el giro cerrado que vuelve a apuntar al objetivo de la guía.
	local function hasEscape(result: PreviewResult): boolean
		local finalState = result.endState
		local targetX, targetZ = guide.getPointAt(result.guideArcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
		local headingError =
			RoadFrame.wrapAngleRadians(math.atan2(targetZ - finalState.z, targetX - finalState.x) - finalState.heading)
		if math.abs(headingError) <= ESCAPE_MIN_ERROR_RADIANS then
			return true
		end
		local escape = walk(
			finalState,
			RoadPieceBuilder.createTurnOfAtLeast(headingError),
			result.guideSegment,
			math.huge,
			getDeviationLimit(
				finalState,
				result.guideSegment,
				WorldConfig.LOCAL_DEVIATION_MAX_STUDS,
				DEVIATION_TOLERANCE_STUDS
			)
		)
		return escape ~= nil
	end

	local function preview(
		start: IntegratorState,
		piece: RoadPiece,
		guideSegment: number
	): (PreviewResult?, RejectionReason?)
		local result: PreviewResult?, reason: RejectionReason? = walk(
			start,
			piece,
			guideSegment,
			getHeadingLimit(start, piece, guideSegment),
			getDeviationLimit(start, guideSegment, getTunnel(piece), DEVIATION_TOLERANCE_STUDS)
		)
		if result == nil then
			return nil, reason
		elseif not hasEscape(result) then
			return nil, "escape"
		end
		return result, nil
	end

	return { preview = preview }
end

return RoadPiecePreviewModule
