--!strict
-- Decide qué pieza probar primero y para qué lado, según dónde queda el objetivo sobre la guía. Siempre consume la misma
-- cantidad de sorteos por decisión, así la secuencia no depende de qué rama se tome.

local RoadPieceCatalog = require("./RoadPieceCatalog")
local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

type PieceDefinition = RoadPieceCatalog.PieceDefinition

-- headingErrorRadians: rumbo hacia el objetivo menos el rumbo actual (positivo es hacia la derecha).
-- lateralOffsetStuds: desvío respecto de la guía (positivo es a la derecha).
export type Steering = {
	headingErrorRadians: number,
	lateralOffsetStuds: number,
}

local CURVES_ONLY_ERROR_RADIANS = math.rad(WorldConfig.SEQUENCER_CURVES_ONLY_ERROR_DEGREES)
local FULL_PULL_ERROR_RADIANS = math.rad(WorldConfig.SEQUENCER_FULL_PULL_ERROR_DEGREES)
local ALWAYS_TOWARD_ERROR_RADIANS = math.rad(WorldConfig.SEQUENCER_ALWAYS_TOWARD_ERROR_DEGREES)
local OFF_CENTER_STUDS = WorldConfig.LOCAL_DEVIATION_MAX_STUDS * WorldConfig.SEQUENCER_OFF_CENTER_FRACTION
local HAIRPIN_MAX_OFFSET_STUDS = WorldConfig.LOCAL_DEVIATION_MAX_STUDS
	* WorldConfig.SEQUENCER_HAIRPIN_MAX_OFFSET_FRACTION

local function isAllowed(definition: PieceDefinition, steering: Steering): boolean
	if math.abs(steering.headingErrorRadians) > CURVES_ONLY_ERROR_RADIANS then
		return definition.isSimpleCurve
	end
	return definition.kind ~= "hairpinPair" or math.abs(steering.lateralOffsetStuds) < HAIRPIN_MAX_OFFSET_STUDS
end

local RoadPieceSelector = {}

function RoadPieceSelector.getDefinition(kind: RoadPieceCatalog.PieceKind): PieceDefinition
	for _, definition in RoadPieceCatalog.definitions do
		if definition.kind == kind then
			return definition
		end
	end
	error(`there is no piece of kind {kind} in the catalog`)
end

-- +1 si el objetivo queda a la derecha del rumbo y -1 si queda a la izquierda.
function RoadPieceSelector.getTowardSign(steering: Steering): number
	return if steering.headingErrorRadians >= 0 then 1 else -1
end

-- Sorteo por pesos, recorriendo el catálogo en su orden.
function RoadPieceSelector.pickDefinition(random: SeededRandom.SeededRandom, steering: Steering): PieceDefinition
	local candidates: { PieceDefinition } = {}
	local totalWeight = 0
	for _, definition in RoadPieceCatalog.definitions do
		if isAllowed(definition, steering) then
			table.insert(candidates, definition)
			totalWeight += definition.weight
		end
	end
	local remaining = random.nextNumber() * totalWeight
	for _, definition in candidates do
		remaining -= definition.weight
		if remaining <= 0 then
			return definition
		end
	end
	return candidates[#candidates]
end

-- +1 si la pieza gira primero a la derecha y -1 si a la izquierda. Se inclina hacia el objetivo; la horquilla doble
-- empieza alejándose de la guía para volver con la segunda.
function RoadPieceSelector.pickTurnSign(
	random: SeededRandom.SeededRandom,
	steering: Steering,
	definition: PieceDefinition
): number
	local roll = random.nextNumber()
	if definition.kind == "hairpinPair" then
		return if steering.lateralOffsetStuds > 0 then -1 else 1
	end
	local errorSize = math.abs(steering.headingErrorRadians)
	local pull = math.clamp(errorSize / FULL_PULL_ERROR_RADIANS, 0, 1)
	local probability = WorldConfig.SEQUENCER_TOWARD_BASE_PROBABILITY + WorldConfig.SEQUENCER_TOWARD_PULL_GAIN * pull
	if errorSize > ALWAYS_TOWARD_ERROR_RADIANS then
		probability = 1
	end
	if math.abs(steering.lateralOffsetStuds) > OFF_CENTER_STUDS then
		probability = math.max(probability, WorldConfig.SEQUENCER_OFF_CENTER_MIN_PROBABILITY)
	end
	local towardSign = RoadPieceSelector.getTowardSign(steering)
	return if roll < probability then towardSign else -towardSign
end

return RoadPieceSelector
