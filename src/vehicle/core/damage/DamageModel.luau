--!strict
-- Modelo del daño por pieza (WP-15). Puro: recibe un golpe (pieza, velocidad de impacto) y devuelve el estado nuevo y
-- los eventos. El daño pasa a las piezas que la golpeada cubre; una pieza caída ya no protege.
local DamageConfig = require("./DamageConfig")
local DamageTypes = require("./DamageTypes")

type DamageEvent = DamageTypes.DamageEvent
type DamageState = DamageTypes.DamageState
type PieceSpecs = DamageTypes.PieceSpecs
type PieceState = DamageTypes.PieceState

local DamageModel = {}

local RULES = DamageConfig.RULES

local function newPieceState(): PieceState
	return { damage = 0, wear = 0, isDetached = false }
end

function DamageModel.newState(specs: PieceSpecs): DamageState
	local pieces = {}
	for id in specs do
		pieces[id] = newPieceState()
	end
	return { pieces = pieces }
end

local function copyState(state: DamageState): DamageState
	local pieces = {}
	for id, piece in state.pieces do
		pieces[id] = { damage = piece.damage, wear = piece.wear, isDetached = piece.isDetached }
	end
	return { pieces = pieces }
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Daño de un golpe: crece con el cuadrado de lo que pasa del umbral.
local function impactDamage(damagePerImpact: number, impactThreshold: number, impactSpeed: number): number
	local excess = math.max(0, math.abs(impactSpeed) - impactThreshold)
	return damagePerImpact * excess * excess
end

-- Suma daño a una pieza que sigue en el auto. Devuelve el daño que realmente entró.
local function receive(piece: PieceState, spec: DamageTypes.PieceSpec, amount: number, events: { DamageEvent }): number
	local applied = math.min(amount, RULES.DETACH_DAMAGE - piece.damage)
	if applied <= 0 then
		return 0
	end
	piece.damage += applied
	piece.wear += spec.wearPerDamage * applied
	table.insert(events, { pieceId = spec.id, kind = "damaged", damage = applied })
	if piece.damage >= RULES.DETACH_DAMAGE then
		piece.isDetached = true
		table.insert(events, { pieceId = spec.id, kind = "detached", damage = piece.damage })
	end
	return applied
end

-- Un golpe en una pieza: la que sigue en el auto recibe el daño y pasa `factor` de él a lo que cubre; una caída ya no
-- protege y el daño va entero a lo que cubría.
local function propagate(
	state: DamageState,
	specs: PieceSpecs,
	pieceId: string,
	amount: number,
	depth: number,
	events: { DamageEvent }
)
	local piece, spec = state.pieces[pieceId], specs[pieceId]
	if piece == nil or spec == nil or depth > RULES.MAX_PROTECTION_DEPTH then
		return
	end
	local wasDetached = piece.isDetached
	if not wasDetached then
		receive(piece, spec, amount, events)
	end
	for _, protection in spec.protects do
		local passed = if wasDetached then amount else amount * protection.factor
		propagate(state, specs, protection.pieceId, passed, depth + 1, events)
	end
end

-- El golpe llega en la caja de `pieceId` con `impactSpeed` (studs/s, el signo no importa). Ignora una pieza que no
-- existe y un valor que no es finito. No modifica sus argumentos.
function DamageModel.applyImpact(
	state: DamageState,
	pieceId: string,
	impactSpeed: number,
	specs: PieceSpecs
): (DamageState, { DamageEvent })
	local nextState = copyState(state)
	local events: { DamageEvent } = {}
	local spec = specs[pieceId]
	if spec == nil or nextState.pieces[pieceId] == nil or not isFinite(impactSpeed) then
		return nextState, events
	end
	local amount = impactDamage(spec.damagePerImpact, spec.impactThreshold, impactSpeed)
	if amount > 0 then
		propagate(nextState, specs, pieceId, amount, 0, events)
	end
	return nextState, events
end

return DamageModel
