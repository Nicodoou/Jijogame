--!strict
-- Las alternativas que se prueban, en orden fijo, cuando la pieza sorteada no entra:
--   1. la pieza sorteada; 2. la misma para el otro lado (menos la recta); 3. la misma más corta;
--   4. una curva cerrada hacia la guía; 5. una recta corta;
--   6. el último recurso: giros de radio mínimo hacia la guía, del más largo al más corto, y después los del otro lado.
-- Se entregan de a una, y cada una se arma recién cuando se la pide: solo la 4 sortea, y solo si llega hasta ahí.
-- Así el secuenciador puede probar una alternativa por paso sin cambiar el orden en que se consume el azar.

local RoadPieceBuilder = require("./RoadPieceBuilder")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSelector = require("./RoadPieceSelector")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type RoadPiece = RoadPieceProfile.RoadPiece

export type RoadPieceAlternatives = {
	-- La próxima pieza a probar y si es del último recurso, o nil cuando ya no quedan.
	next: () -> (RoadPiece?, boolean),
}

local sharpDefinition = RoadPieceSelector.getDefinition("sharpCurve")
local LOBE_STEPS = WorldConfig.LAST_RESORT_LOBE_STEPS

local RoadPieceAlternativesModule = {}

function RoadPieceAlternativesModule.new(
	piece: RoadPiece,
	towardSign: number,
	random: SeededRandom.SeededRandom
): RoadPieceAlternatives
	-- Cada etapa devuelve su pieza, o nil si no aplica (la recta no se da vuelta y no toda pieza se acorta).
	local stages: { () -> RoadPiece? } = {
		function()
			return piece
		end,
		function()
			return if piece.kind ~= "straight" then RoadPieceBuilder.flip(piece) else nil
		end,
		function()
			return RoadPieceBuilder.shorten(piece)
		end,
		function()
			local sharp = RoadPieceBuilder.draw(random, sharpDefinition)
			return if towardSign > 0 then sharp else RoadPieceBuilder.flip(sharp)
		end,
		function()
			return RoadPieceBuilder.createStraight(WorldConfig.EMERGENCY_STRAIGHT_STEPS)
		end,
	}
	local stage = 0
	local lastResortPosition = 0

	local function nextLastResort(): (RoadPiece?, boolean)
		lastResortPosition += 1
		if lastResortPosition > 2 * #LOBE_STEPS then
			return nil, true
		end
		local sign = if lastResortPosition <= #LOBE_STEPS then towardSign else -towardSign
		return RoadPieceBuilder.createTightTurn(sign, LOBE_STEPS[(lastResortPosition - 1) % #LOBE_STEPS + 1]), true
	end

	local function next(): (RoadPiece?, boolean)
		while stage < #stages do
			stage += 1
			local candidate = stages[stage]()
			if candidate ~= nil then
				return candidate, false
			end
		end
		return nextLastResort()
	end

	return { next = next }
end

return RoadPieceAlternativesModule
