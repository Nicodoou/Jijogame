--!strict
-- Qué golpes cuentan como daño (WP-18). Puro: el tiempo llega por parámetro y la tabla de enfriamientos es del que llama.
local DamageConfig = require("./DamageConfig")
local DamageTypes = require("./DamageTypes")

type PieceSpec = DamageTypes.PieceSpec

export type Cooldowns = { [string]: number }

local HITBOX = DamageConfig.HITBOX

local HitFilter = {}

function HitFilter.newCooldowns(): Cooldowns
	return {}
end

-- Un golpe cuenta si pasa el umbral de la pieza y no es el auto apoyándose en el terreno con la cara de abajo.
function HitFilter.shouldCount(spec: PieceSpec, impactSpeed: number, normalY: number, isTerrain: boolean): boolean
	local speed = math.abs(impactSpeed)
	if not (speed > spec.impactThreshold) then
		return false
	end
	local isBottomFace = math.abs(normalY) >= HITBOX.BOTTOM_FACE_NORMAL_Y
	return not (isTerrain and isBottomFace and speed < HITBOX.GROUND_IMPACT_SPEED)
end

-- Anota el golpe del par y dice si cuenta: un mismo par cuenta una vez cada `HIT_COOLDOWN_SECONDS`.
-- Borra de la tabla los pares que ya vencieron, para que no crezca.
function HitFilter.registerHit(cooldowns: Cooldowns, pairKey: string, nowSeconds: number): boolean
	for key, hitSeconds in cooldowns do
		if nowSeconds - hitSeconds >= HITBOX.HIT_COOLDOWN_SECONDS then
			cooldowns[key] = nil
		end
	end
	if cooldowns[pairKey] ~= nil then
		return false
	end
	cooldowns[pairKey] = nowSeconds
	return true
end

return HitFilter
