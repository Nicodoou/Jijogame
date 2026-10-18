--!strict
-- Validación del estado de daño que el cliente le manda al servidor (WP-18). Puro: no confía en nada del mensaje.
local DamageConfig = require("./DamageConfig")
local DamageTypes = require("./DamageTypes")

type DamageState = DamageTypes.DamageState
type PieceSpecs = DamageTypes.PieceSpecs
type PieceState = DamageTypes.PieceState

local DamageReport = {}

local FULL_DAMAGE = DamageConfig.RULES.DETACH_DAMAGE

local function isNumberBetween(value: unknown, minimum: number, maximum: number): boolean
	return type(value) == "number" and value >= minimum and value <= maximum
end

local function readPiece(raw: unknown, wearLimit: number): PieceState?
	if type(raw) ~= "table" then
		return nil
	end
	local piece = raw :: { [string]: unknown }
	local damage, wear, isDetached = piece.damage, piece.wear, piece.isDetached
	if not isNumberBetween(damage, 0, FULL_DAMAGE) or not isNumberBetween(wear, 0, wearLimit) then
		return nil
	end
	if type(isDetached) ~= "boolean" then
		return nil
	end
	return { damage = damage :: number, wear = wear :: number, isDetached = isDetached }
end

-- El estado completo si el mensaje trae exactamente las piezas de la ficha, cada una con daño de 0 a 100, desgaste
-- de 0 a lo que daría el daño máximo e `isDetached` booleano; nil si algo no cumple. Devuelve una copia.
function DamageReport.validate(payload: unknown, specs: PieceSpecs): DamageState?
	if type(payload) ~= "table" then
		return nil
	end
	local sent = (payload :: { [string]: unknown }).pieces
	if type(sent) ~= "table" then
		return nil
	end
	local pieces: { [string]: PieceState } = {}
	for id, spec in specs do
		local piece = readPiece((sent :: { [string]: unknown })[id], FULL_DAMAGE * spec.wearPerDamage)
		if piece == nil then
			return nil
		end
		pieces[id] = piece
	end
	for id in sent :: { [unknown]: unknown } do
		if type(id) ~= "string" or specs[id] == nil then
			return nil
		end
	end
	return { pieces = pieces }
end

return DamageReport
