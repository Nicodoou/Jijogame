--!strict
-- Forma de una pieza concreta ya sorteada: perfil de curvatura por paso de integración.
-- Una pieza son una o más partes seguidas (la horquilla doble tiene tres: horquilla, recta y horquilla). Cada parte
-- tiene uno o más lóbulos de curvatura que alternan de sentido, y toda parte empieza y termina con curvatura 0.

local RoadPieceCatalog = require("./RoadPieceCatalog")

export type PiecePart = {
	-- Curvatura (1/stud) de la parte constante del primer lóbulo. Positiva gira a la derecha; los demás lóbulos alternan.
	peakCurvature: number,
	-- Pasos de integración de cada lóbulo y de cada rampa de curvatura.
	lobeSteps: number,
	rampSteps: number,
	lobeCount: number,
	-- De dónde sale `rampSteps`, para recalcularlo si la parte se acorta.
	rampFraction: number,
}

export type RoadPiece = {
	kind: RoadPieceCatalog.PieceKind,
	parts: { PiecePart },
	totalSteps: number,
}

local RoadPieceProfile = {}

function RoadPieceProfile.getPartSteps(part: PiecePart): number
	return part.lobeCount * part.lobeSteps
end

function RoadPieceProfile.create(kind: RoadPieceCatalog.PieceKind, parts: { PiecePart }): RoadPiece
	local totalSteps = 0
	for _, part in parts do
		totalSteps += RoadPieceProfile.getPartSteps(part)
	end
	return { kind = kind, parts = parts, totalSteps = totalSteps }
end

local function getPartCurvature(part: PiecePart, step: number): number
	local lobeIndex = math.min(step // part.lobeSteps, part.lobeCount - 1)
	local stepInLobe = step - lobeIndex * part.lobeSteps
	local rampFactor = math.min(1, stepInLobe / part.rampSteps, (part.lobeSteps - stepInLobe) / part.rampSteps)
	local direction = if lobeIndex % 2 == 0 then 1 else -1
	return direction * part.peakCurvature * rampFactor
end

-- La curvatura en el paso `step` (0 al empezar la pieza y `totalSteps` al terminarla).
function RoadPieceProfile.getCurvatureAtStep(piece: RoadPiece, step: number): number
	local stepInPart = step
	for _, part in piece.parts do
		local partSteps = RoadPieceProfile.getPartSteps(part)
		if stepInPart <= partSteps then
			return getPartCurvature(part, stepInPart)
		end
		stepInPart -= partSteps
	end
	return 0
end

return RoadPieceProfile
