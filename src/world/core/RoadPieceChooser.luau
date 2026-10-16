--!strict
-- Elige la próxima pieza: ubica la ruta sobre la guía, apunta al objetivo que está adelante y sortea la clase de pieza, el
-- lado y sus medidas. El orden en que consume el azar es parte del resultado de la semilla.
-- Los primeros START_FLAT_STUDS de la ruta son una sola recta (WP-12), en lugar de la pieza sorteada.

local RoadFrame = require("./RoadFrame")
local RoadGuide = require("./RoadGuide")
local RoadIntegrator = require("./RoadIntegrator")
local RoadPieceBuilder = require("./RoadPieceBuilder")
local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSelector = require("./RoadPieceSelector")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

export type Choice = {
	piece: RoadPieceProfile.RoadPiece,
	-- Hacia qué lado queda la guía (+1 derecha, -1 izquierda): es el de las alternativas que giran hacia ella.
	towardSign: number,
	-- Dónde quedó la ruta sobre la guía.
	guideSegment: number,
	guideArcLength: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local START_FLAT_STUDS = WorldConfig.START_FLAT_STUDS

local RoadPieceChooser = {}

function RoadPieceChooser.choose(
	guide: RoadGuide.RoadGuide,
	random: SeededRandom.SeededRandom,
	state: RoadIntegrator.IntegratorState,
	guideSegment: number,
	guideArcLength: number,
	previousKind: RoadPieceCatalog.PieceKind?
): Choice
	guide.ensureCovers(guideArcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
	local lateralOffset, arcLength, segment = guide.project(state.x, state.z, guideSegment)
	local targetX, targetZ = guide.getPointAt(arcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
	local headingToTarget = math.atan2(targetZ - state.z, targetX - state.x)
	local steering: RoadPieceSelector.Steering = {
		headingErrorRadians = RoadFrame.wrapAngleRadians(headingToTarget - state.heading),
		lateralOffsetStuds = lateralOffset,
		previousKind = previousKind,
	}
	local definition = RoadPieceSelector.pickDefinition(random, steering)
	local turnSign = RoadPieceSelector.pickTurnSign(random, steering, definition)
	local drawn = RoadPieceBuilder.draw(random, definition)
	local piece = if turnSign > 0 then drawn else RoadPieceBuilder.flip(drawn)
	local flatStuds = START_FLAT_STUDS - state.sampleIndex * STEP_STUDS
	if flatStuds > 0 then
		-- Largada: la recta que falta hasta START_FLAT_STUDS en lugar de la pieza sorteada. Se sortea igual, así cada decisión
		-- consume la misma cantidad de azar. La guía sale recta, así que la recta entra siempre.
		piece = RoadPieceBuilder.createStraight(math.ceil(flatStuds / STEP_STUDS))
	end
	return {
		piece = piece,
		towardSign = RoadPieceSelector.getTowardSign(steering),
		guideSegment = segment,
		guideArcLength = arcLength,
	}
end

return RoadPieceChooser
