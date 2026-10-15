--!strict
-- Arma las piezas concretas: sortea la forma de una pieza del catálogo y deriva sus variantes (el otro sentido, una
-- versión más corta) sin volver a sortear, así la cantidad de intentos no cambia el resto de la secuencia.

local RoadPieceCatalog = require("./RoadPieceCatalog")
local RoadPieceProfile = require("./RoadPieceProfile")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type PieceDefinition = RoadPieceCatalog.PieceDefinition
type PiecePart = RoadPieceProfile.PiecePart
type RoadPiece = RoadPieceProfile.RoadPiece

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local RAMPS_PER_LOBE = 2
-- Una recta no tiene rampas, pero el perfil de curvatura divide por sus pasos.
local STRAIGHT_RAMP_STEPS = 1
local STRAIGHT_RAMP_FRACTION = 0

local function lerp(from: number, to: number, fraction: number): number
	return from + (to - from) * fraction
end

local function createPart(
	peakCurvature: number,
	lobeSteps: number,
	rampSteps: number,
	lobeCount: number,
	rampFraction: number
): PiecePart
	return {
		peakCurvature = peakCurvature,
		lobeSteps = lobeSteps,
		rampSteps = rampSteps,
		lobeCount = lobeCount,
		rampFraction = rampFraction,
	}
end

-- La rampa ocupa la fracción pedida del lóbulo, pero entra dos veces en él y dura al menos un paso.
local function getRampSteps(lobeSteps: number, rampFraction: number): number
	return math.min(math.max(1, math.round(rampFraction * lobeSteps)), lobeSteps // RAMPS_PER_LOBE)
end

local function createCurvePart(
	peakCurvature: number,
	lobeSteps: number,
	lobeCount: number,
	rampFraction: number
): PiecePart
	return createPart(peakCurvature, lobeSteps, getRampSteps(lobeSteps, rampFraction), lobeCount, rampFraction)
end

local function createStraightPart(steps: number): PiecePart
	return createPart(0, steps, STRAIGHT_RAMP_STEPS, 1, STRAIGHT_RAMP_FRACTION)
end

local function drawStraight(random: SeededRandom.SeededRandom, definition: PieceDefinition): RoadPiece
	local steps = random.nextInteger(definition.minLengthStuds, definition.maxLengthStuds) // STEP_STUDS
	return RoadPieceProfile.create(definition.kind, { createStraightPart(steps) })
end

local function drawCurve(random: SeededRandom.SeededRandom, definition: PieceDefinition): RoadPiece
	local lengthStuds = random.nextInteger(definition.minLengthStuds, definition.maxLengthStuds)
	local radiusStuds = math.max(
		lerp(definition.minRadiusStuds, definition.maxRadiusStuds, random.nextNumber()),
		WorldConfig.MIN_CURVE_RADIUS_STUDS
	)
	local lobeSteps = math.round(lengthStuds / definition.lobeCount / STEP_STUDS)
	return RoadPieceProfile.create(
		definition.kind,
		{ createCurvePart(1 / radiusStuds, lobeSteps, definition.lobeCount, definition.rampFraction) }
	)
end

-- Horquilla para un lado, recta corta y horquilla para el otro: el rumbo neto es cero. El giro de cada horquilla se
-- reparte en pasos de curvatura constante, y su cantidad se acota con los radios mínimo y máximo.
local function drawHairpinPair(random: SeededRandom.SeededRandom, definition: PieceDefinition): RoadPiece
	local minTurn, maxTurn =
		math.rad(definition.minTurnDegrees :: number), math.rad(definition.maxTurnDegrees :: number)
	local turnRadians = lerp(minTurn, maxTurn, random.nextNumber())
	local radiusStuds = lerp(definition.minRadiusStuds, definition.maxRadiusStuds, random.nextNumber())
	local gapSteps = random.nextInteger(definition.minLengthStuds, definition.maxLengthStuds) // STEP_STUDS
	local fewestTurnSteps = math.ceil(turnRadians * definition.minRadiusStuds / STEP_STUDS)
	local mostTurnSteps = math.floor(turnRadians * definition.maxRadiusStuds / STEP_STUDS)
	local turnSteps = math.clamp(math.round(turnRadians * radiusStuds / STEP_STUDS), fewestTurnSteps, mostTurnSteps)
	local rampSteps = math.max(1, math.round(definition.rampFraction * turnSteps))
	local peakCurvature = turnRadians / (turnSteps * STEP_STUDS)
	local lobeSteps = turnSteps + rampSteps
	return RoadPieceProfile.create(definition.kind, {
		createPart(peakCurvature, lobeSteps, rampSteps, 1, definition.rampFraction),
		createStraightPart(gapSteps),
		createPart(-peakCurvature, lobeSteps, rampSteps, 1, definition.rampFraction),
	})
end

local function shortenPart(part: PiecePart): PiecePart
	local lobeSteps = math.floor(part.lobeSteps * WorldConfig.SHORTENED_PIECE_FRACTION)
	if part.peakCurvature == 0 then
		return createStraightPart(math.max(1, lobeSteps))
	end
	lobeSteps = math.max(WorldConfig.MIN_SHORTENED_LOBE_STEPS, lobeSteps)
	return createCurvePart(part.peakCurvature, lobeSteps, part.lobeCount, part.rampFraction)
end

local RoadPieceBuilder = {}

-- Sortea la forma de una pieza. La primera curva gira a la derecha; `flip` da la otra.
function RoadPieceBuilder.draw(random: SeededRandom.SeededRandom, definition: PieceDefinition): RoadPiece
	if definition.kind == "straight" then
		return drawStraight(random, definition)
	elseif definition.kind == "hairpinPair" then
		return drawHairpinPair(random, definition)
	end
	return drawCurve(random, definition)
end

-- La misma pieza girando para el otro lado.
function RoadPieceBuilder.flip(piece: RoadPiece): RoadPiece
	local parts = {}
	for index, part in piece.parts do
		local flipped = table.clone(part)
		flipped.peakCurvature = -part.peakCurvature
		parts[index] = flipped
	end
	return RoadPieceProfile.create(piece.kind, parts)
end

-- La misma pieza con la mitad de largo en cada lóbulo y la misma curvatura. Devuelve nil si no se puede acortar: la
-- horquilla doble tiene el giro fijado por su forma.
function RoadPieceBuilder.shorten(piece: RoadPiece): RoadPiece?
	if piece.kind == "hairpinPair" then
		return nil
	end
	local parts = {}
	for index, part in piece.parts do
		parts[index] = shortenPart(part)
	end
	return RoadPieceProfile.create(piece.kind, parts)
end

function RoadPieceBuilder.createStraight(steps: number): RoadPiece
	return RoadPieceProfile.create("straight", { createStraightPart(steps) })
end

-- Giro de radio mínimo de `lobeSteps` pasos, con rampas de TIGHT_TURN_RAMP_FRACTION. Positivo gira a la derecha.
function RoadPieceBuilder.createTightTurn(sign: number, lobeSteps: number): RoadPiece
	local peakCurvature = sign / WorldConfig.MIN_CURVE_RADIUS_STUDS
	return RoadPieceProfile.create(
		"sharpCurve",
		{ createCurvePart(peakCurvature, lobeSteps, 1, WorldConfig.TIGHT_TURN_RAMP_FRACTION) }
	)
end

-- Giro de radio mínimo que cambia el rumbo por lo menos `headingChangeRadians` (positivo gira a la derecha).
function RoadPieceBuilder.createTurnOfAtLeast(headingChangeRadians: number): RoadPiece
	local peakCurvature = (if headingChangeRadians >= 0 then 1 else -1) / WorldConfig.MIN_CURVE_RADIUS_STUDS
	local turnSteps = math.ceil(math.abs(headingChangeRadians) * WorldConfig.MIN_CURVE_RADIUS_STUDS / STEP_STUDS)
	local rampSteps = math.max(1, math.round(WorldConfig.TIGHT_TURN_RAMP_FRACTION * turnSteps))
	return RoadPieceProfile.create("sharpCurve", {
		createPart(peakCurvature, turnSteps + rampSteps, rampSteps, 1, WorldConfig.TIGHT_TURN_RAMP_FRACTION),
	})
end

return RoadPieceBuilder
