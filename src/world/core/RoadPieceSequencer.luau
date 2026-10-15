--!strict
-- Sortea la próxima pieza de ruta. Respeta la curvatura máxima, el corredor de rumbo, la pendiente y el desvío lateral,
-- y empuja el trazado hacia la media (reversión a la media) para que no choque con los límites.

local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPieceProfile = require("./RoadPieceProfile")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type PieceDefinition = RoadPieceCatalog.PieceDefinition
type RoadPiece = RoadPieceProfile.RoadPiece

export type SequencerContext = {
	-- Desvío del rumbo respecto del medio, en radianes. Positivo es hacia la derecha.
	headingDeviationRadians: number,
	-- Desvío lateral de la posición respecto de la recta media, en studs. Positivo es hacia la derecha.
	lateralOffsetStuds: number,
}

local NEUTRAL_PROBABILITY = 0.5
local RAMPS_PER_LOBE = 2
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local MAX_DEVIATION_RADIANS = math.rad(WorldConfig.MAX_HEADING_DEVIATION_DEGREES)
local PLANNING_LIMIT_RADIANS = MAX_DEVIATION_RADIANS - math.rad(WorldConfig.HEADING_PLANNING_MARGIN_DEGREES)
local MAX_SLOPE_DEGREES = WorldConfig.MAX_SLOPE_DEGREES
local FORCED_DRIFT_STUDS = WorldConfig.MAX_LATERAL_DRIFT_STUDS * WorldConfig.STEERING_FORCED_DRIFT_FRACTION
local GOAL_HEADING_RADIANS = MAX_DEVIATION_RADIANS * WorldConfig.STEERING_GOAL_HEADING_FRACTION
local ERROR_SCALE_RADIANS = MAX_DEVIATION_RADIANS * WorldConfig.STEERING_ERROR_SCALE_FRACTION

local function getSign(value: number): number
	return if value < 0 then -1 else 1
end

local function lerp(from: number, to: number, fraction: number): number
	if from == to then
		return from
	end
	return from + (to - from) * fraction
end

local function isTurning(definition: PieceDefinition): boolean
	return definition.lobeCount == 1 and definition.maxRadiusStuds < math.huge
end

local function pickDefinition(random: SeededRandom.SeededRandom, onlyTurning: boolean): PieceDefinition
	local candidates: { PieceDefinition } = {}
	local totalWeight = 0
	for _, definition in RoadPieceCatalog.definitions do
		if not onlyTurning or isTurning(definition) then
			table.insert(candidates, definition)
			totalWeight += definition.weight
		end
	end
	local roll = random.nextNumber() * totalWeight
	local chosen = candidates[1]
	local weightBefore = 0
	for _, definition in candidates do
		if roll >= weightBefore then
			chosen = definition
		end
		weightBefore += definition.weight
	end
	return chosen
end

-- Sentido de la curva: parejo cuando el trazado está centrado y sesgado hacia la media cuando se aleja.
local function pickTurnSign(random: SeededRandom.SeededRandom, context: SequencerContext): number
	local roll = random.nextNumber()
	local lateral = context.lateralOffsetStuds
	if math.abs(lateral) > FORCED_DRIFT_STUDS then
		return -getSign(lateral)
	end
	local driftFraction = math.clamp(lateral / WorldConfig.STEERING_DRIFT_SCALE_STUDS, -1, 1)
	local headingError = -driftFraction * GOAL_HEADING_RADIANS - context.headingDeviationRadians
	local pull = math.clamp(headingError / ERROR_SCALE_RADIANS, -1, 1)
	local probabilityRight = NEUTRAL_PROBABILITY + (1 - NEUTRAL_PROBABILITY) * WorldConfig.STEERING_STRENGTH * pull
	return if roll < probabilityRight then 1 else -1
end

-- Baja la curvatura de la curva si el rumbo se pasaría del corredor. Devuelve nil si quedaría demasiado floja.
local function capPeakCurvature(piece: RoadPiece, headingDeviation: number): number?
	local sign = getSign(piece.peakCurvature)
	local headroom = PLANNING_LIMIT_RADIANS - sign * headingDeviation
	local headingChange = math.abs(RoadPieceProfile.getFirstLobeHeadingChange(piece))
	if headingChange <= headroom then
		return piece.peakCurvature
	end
	local ratio = headroom / headingChange
	if ratio < WorldConfig.MIN_CAPPED_PEAK_FRACTION then
		return nil
	end
	return piece.peakCurvature * ratio
end

local function fitToHeadingCorridor(piece: RoadPiece, headingDeviation: number)
	local capped = capPeakCurvature(piece, headingDeviation)
	if capped == nil then
		piece.peakCurvature = -piece.peakCurvature
		capped = capPeakCurvature(piece, headingDeviation)
	end
	piece.peakCurvature = capped or 0
end

-- Cota conservadora del desvío lateral al terminar la pieza: el rumbo recorre un tramo monótono por lóbulo.
local function getLateralDriftBound(piece: RoadPiece, context: SequencerContext): number
	local endDeviation = context.headingDeviationRadians + RoadPieceProfile.getFirstLobeHeadingChange(piece)
	local worstDeviation = math.max(math.abs(context.headingDeviationRadians), math.abs(endDeviation))
	local totalLength = RoadPieceProfile.getTotalSteps(piece) * STEP_STUDS
	return math.abs(context.lateralOffsetStuds) + totalLength * math.sin(worstDeviation)
end

-- Último recurso: una curva de un solo lóbulo, lo más cerrada posible, hacia la media.
local function turnBackTowardMean(piece: RoadPiece, context: SequencerContext)
	piece.lobeCount = 1
	piece.peakCurvature = -getSign(context.lateralOffsetStuds) / WorldConfig.MIN_CURVE_RADIUS_STUDS
	fitToHeadingCorridor(piece, context.headingDeviationRadians)
end

local function buildPiece(
	definition: PieceDefinition,
	random: SeededRandom.SeededRandom,
	turnSign: number,
	useTightestRadius: boolean
): RoadPiece
	local lengthStuds = random.nextInteger(definition.minLengthStuds, definition.maxLengthStuds)
	-- El sorteo se consume igual con el radio fijo, para que el resto de la secuencia no dependa de esta rama.
	local drawnRadiusFraction = random.nextNumber()
	local radiusFraction = if useTightestRadius then 0 else drawnRadiusFraction
	local slopeFraction = random.nextNumber()
	local radiusStuds = math.max(
		lerp(definition.minRadiusStuds, definition.maxRadiusStuds, radiusFraction),
		WorldConfig.MIN_CURVE_RADIUS_STUDS
	)
	local lobeSteps = math.round(lengthStuds / definition.lobeCount / STEP_STUDS)
	local slopeDegrees = lerp(definition.minSlopeDegrees, definition.maxSlopeDegrees, slopeFraction)
	return {
		kind = definition.kind,
		lobeCount = definition.lobeCount,
		lobeSteps = lobeSteps,
		rampSteps = math.min(math.max(1, math.round(definition.rampFraction * lobeSteps)), lobeSteps // RAMPS_PER_LOBE),
		peakCurvature = turnSign / radiusStuds,
		endSlopeRadians = math.rad(math.clamp(slopeDegrees, -MAX_SLOPE_DEGREES, MAX_SLOPE_DEGREES)),
	}
end

local RoadPieceSequencer = {}

function RoadPieceSequencer.chooseNextPiece(random: SeededRandom.SeededRandom, context: SequencerContext): RoadPiece
	local isForcedBack = math.abs(context.lateralOffsetStuds) > FORCED_DRIFT_STUDS
	local definition = pickDefinition(random, isForcedBack)
	local piece = buildPiece(definition, random, pickTurnSign(random, context), isForcedBack)
	fitToHeadingCorridor(piece, context.headingDeviationRadians)
	if getLateralDriftBound(piece, context) > WorldConfig.MAX_LATERAL_DRIFT_STUDS then
		turnBackTowardMean(piece, context)
	end
	return piece
end

return RoadPieceSequencer
