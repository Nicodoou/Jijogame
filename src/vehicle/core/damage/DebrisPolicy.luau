--!strict
-- Cuáles piezas sueltas hay que borrar (WP-18). Puro: recibe cuándo nació cada una, de la más vieja a la más nueva.
local DamageConfig = require("./DamageConfig")

local DEBRIS = DamageConfig.DEBRIS

local DebrisPolicy = {}

-- Posiciones a borrar, de mayor a menor (así se pueden quitar de la lista una por una sin que se corran): las que
-- cumplieron su vida y, si quedan más de `MAX_COUNT`, las más viejas que sobran.
function DebrisPolicy.selectToRemove(bornSeconds: { number }, nowSeconds: number): { number }
	local removable: { [number]: boolean } = {}
	local kept = 0
	for index, born in bornSeconds do
		if nowSeconds - born >= DEBRIS.LIFETIME_SECONDS then
			removable[index] = true
		else
			kept += 1
		end
	end
	local excess = kept - DEBRIS.MAX_COUNT
	for index = 1, #bornSeconds do
		if excess <= 0 then
			break
		end
		if not removable[index] then
			removable[index] = true
			excess -= 1
		end
	end
	local result: { number } = {}
	for index = #bornSeconds, 1, -1 do
		if removable[index] then
			table.insert(result, index)
		end
	end
	return result
end

return DebrisPolicy
