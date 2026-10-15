--!strict
-- Forma de una pieza concreta ya sorteada: perfil de curvatura por paso de integración.

local WorldConfig = require("./WorldConfig")
local RoadPieceCatalog = require("./RoadPieceCatalog")

export type RoadPiece = {
	kind: RoadPieceCatalog.PieceKind,
	lobeCount: number,
	-- Pasos de integración de cada lóbulo y de cada rampa de curvatura.
	lobeSteps: number,
	rampSteps: number,
	-- Curvatura (1/stud) de la parte constante del primer lóbulo. Positiva gira a la derecha; los demás lóbulos alternan.
	peakCurvature: number,
	endSlopeRadians: number,
}

local RoadPieceProfile = {}

function RoadPieceProfile.getTotalSteps(piece: RoadPiece): number
	return piece.lobeCount * piece.lobeSteps
end

-- La curvatura en el paso `step` (0 al empezar la pieza y total de pasos al terminarla).
function RoadPieceProfile.getCurvatureAtStep(piece: RoadPiece, step: number): number
	local lobeIndex = math.min(step // piece.lobeSteps, piece.lobeCount - 1)
	local stepInLobe = step - lobeIndex * piece.lobeSteps
	local rampFactor = math.min(1, stepInLobe / piece.rampSteps, (piece.lobeSteps - stepInLobe) / piece.rampSteps)
	local direction = if lobeIndex % 2 == 0 then 1 else -1
	return direction * piece.peakCurvature * rampFactor
end

-- Cambio de rumbo (radianes) que produce el primer lóbulo. Es exacto porque las rampas empiezan y terminan en un paso.
function RoadPieceProfile.getFirstLobeHeadingChange(piece: RoadPiece): number
	return piece.peakCurvature * WorldConfig.INTEGRATION_STEP_STUDS * (piece.lobeSteps - piece.rampSteps)
end

return RoadPieceProfile
