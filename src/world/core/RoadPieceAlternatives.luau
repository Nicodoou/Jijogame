--!strict
-- Las alternativas que se prueban, en orden fijo, cuando la pieza sorteada no entra:
--   1. la pieza sorteada; 2. la misma para el otro lado (menos la recta); 3. la misma más corta;
--   4. una curva cerrada hacia la guía; 5. una recta corta;
--   6. el último recurso: giros de radio mínimo hacia la guía, del más largo al más corto.
-- Solo la 4 sortea de nuevo, y solo si llega hasta ahí.

local RoadPieceBuilder = require("./RoadPieceBuilder")
local RoadPiecePreview = require("./RoadPiecePreview")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSelector = require("./RoadPieceSelector")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type PreviewResult = RoadPiecePreview.PreviewResult
type RoadPiece = RoadPieceProfile.RoadPiece

-- Previsualiza una pieza desde donde está la ruta y devuelve el resultado si la acepta.
export type TryPiece = (piece: RoadPiece) -> PreviewResult?

local sharpDefinition = RoadPieceSelector.getDefinition("sharpCurve")

local function tryLastResort(towardSign: number, tryPiece: TryPiece): PreviewResult?
	for _, sign in { towardSign, -towardSign } do
		for _, lobeSteps in WorldConfig.LAST_RESORT_LOBE_STEPS do
			local result = tryPiece(RoadPieceBuilder.createTightTurn(sign, lobeSteps))
			if result ~= nil then
				return result
			end
		end
	end
	return nil
end

local function tryBeforeLastResort(
	piece: RoadPiece,
	towardSign: number,
	tryPiece: TryPiece,
	random: SeededRandom.SeededRandom
): PreviewResult?
	local result = tryPiece(piece)
	if result == nil and piece.kind ~= "straight" then
		result = tryPiece(RoadPieceBuilder.flip(piece))
	end
	local shorter = if result == nil then RoadPieceBuilder.shorten(piece) else nil
	if shorter ~= nil then
		result = tryPiece(shorter)
	end
	if result == nil then
		local sharp = RoadPieceBuilder.draw(random, sharpDefinition)
		result = tryPiece(if towardSign > 0 then sharp else RoadPieceBuilder.flip(sharp))
	end
	return result or tryPiece(RoadPieceBuilder.createStraight(WorldConfig.EMERGENCY_STRAIGHT_STEPS))
end

local RoadPieceAlternatives = {}

-- La primera alternativa que entra, y si hizo falta el último recurso. Devuelve nil si ninguna entra.
function RoadPieceAlternatives.findFirstAccepted(
	piece: RoadPiece,
	towardSign: number,
	tryPiece: TryPiece,
	random: SeededRandom.SeededRandom
): (PreviewResult?, boolean)
	local result = tryBeforeLastResort(piece, towardSign, tryPiece, random)
	if result ~= nil then
		return result, false
	end
	return tryLastResort(towardSign, tryPiece), true
end

return RoadPieceAlternatives
