--!strict
-- Ruta viva: grilla con las muestras recientes del eje y su arcLength. Responde si un punto nuevo respeta el anti-cruce:
-- no puede quedar a menos de LIVE_CLEARANCE_STUDS de una muestra cuyo arcLength lo preceda en más de
-- LIVE_NEIGHBOR_ARC_STUDS (las más cercanas sobre el eje son vecinas y siempre están cerca) y hasta LIVE_LOOKBACK_STUDS,
-- ni a menos de LIVE_NEAR_CLEARANCE_STUDS de una que lo preceda en más de LIVE_NEAR_ARC_STUDS.
-- Regla de altura: una muestra que queda a menos de LIVE_HEIGHT_RULE_RADIUS_STUDS de otra no vecina (las mismas que cuentan
-- para el anti-cruce) no puede estar a más altura de la que el terreno logra salvar con la pendiente máxima en el espacio libre
-- que queda entre las dos banquinas (menos un margen). Así no quedan paredes entre pasadas cercanas (WP-9). Las reglas
-- están en LiveRoadRules.
-- Guarda además LIVE_BACKTRACK_MEMORY_STUDS más hacia atrás, para poder retroceder y volver a mirar esas muestras.

local LiveRoadRules = require("./LiveRoadRules")
local WorldConfig = require("./WorldConfig")

export type LiveRoadIndex = {
	-- Agrega una muestra. Su arcLength tiene que ser mayor que el de la anterior.
	add: (x: number, y: number, z: number, arcLength: number) -> (),
	-- Quita las muestras con arcLength mayor que el dado: es el retroceso de la ruta.
	removeAfter: (arcLength: number) -> (),
	isClear: (x: number, y: number, z: number, arcLength: number) -> boolean,
	getSampleCount: () -> number,
}

-- Los ids de las muestras de una celda van en orden, del `head` al `last`, y por lo tanto también por arcLength.
type Cell = { head: number, last: number, [number]: number }

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
-- Las dos reglas miran muestras hasta un radio; la celda es la tercera parte del mayor, así que alcanzan las celdas a tres
-- de distancia. Celdas más grandes hacen revisar muchas muestras que quedan fuera del radio: la consulta es lo más caro de la ruta.
local CELLS_PER_RADIUS = 3
local CELL_STUDS = math.max(WorldConfig.LIVE_CLEARANCE_STUDS, WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS)
	/ CELLS_PER_RADIUS
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
local NEAR_ARC_STUDS = WorldConfig.LIVE_NEAR_ARC_STUDS
local LOOKBACK_STUDS = WorldConfig.LIVE_LOOKBACK_STUDS
local Exp86 = require("./Exp86")
local KEPT_ARC_STUDS = LOOKBACK_STUDS + (Exp86.memory or WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS)
-- Anillo de muestras: cada una ocupa el lugar `id % RING_SIZE`, que ya se liberó cuando llega el id nuevo.
local RING_SIZE = KEPT_ARC_STUDS // STEP_STUDS + 2

local function getCellCoordinate(value: number): number
	return math.floor(value / CELL_STUDS)
end

local function getCellKey(cellX: number, cellZ: number): number
	return cellX * KEY_STRIDE + cellZ
end

local LiveRoadIndexModule = {}

function LiveRoadIndexModule.new(): LiveRoadIndex
	local xs = table.create(RING_SIZE, 0)
	local ys = table.create(RING_SIZE, 0)
	local zs = table.create(RING_SIZE, 0)
	local arcs = table.create(RING_SIZE, 0)
	-- Cuántas veces, hasta cada muestra, la ruta dio un salto mayor que un paso: entre dos muestras con el mismo número no
	-- hay saltos y se pueden saltear las del medio (ver LiveRoadRules).
	local jumps = table.create(RING_SIZE, 0)
	local cells: { [number]: Cell } = {}
	-- Las celdas que rodean a la última consulta. Una pieza se previsualiza paso a paso desde el mismo estado de la grilla,
	-- y mientras no cambie la celda del centro se reutilizan en vez de buscarlas de nuevo.
	local neighborhoodKey: number? = nil
	local neighborhood: { Cell } = {}
	local neighborhoodCount = 0
	local oldestId = 1
	local newestId = 0

	local function getKeyOf(id: number): number
		local slot = id % RING_SIZE + 1
		return getCellKey(getCellCoordinate(xs[slot]), getCellCoordinate(zs[slot]))
	end

	local function forgetOldest()
		local key = getKeyOf(oldestId)
		local cell = cells[key]
		cell[cell.head] = nil
		cell.head += 1
		if cell.head > cell.last then
			cells[key] = nil
		end
		oldestId += 1
	end

	local function forgetNewest()
		local key = getKeyOf(newestId)
		local cell = cells[key]
		cell[cell.last] = nil
		cell.last -= 1
		if cell.last < cell.head then
			cells[key] = nil
		end
		newestId -= 1
	end

	-- Saltos de la ruta hasta la muestra nueva (`newestId` ya cuenta la nueva).
	local function countJumps(x: number, y: number, z: number): number
		if newestId - 1 < oldestId then
			return 0
		end
		local previousSlot = (newestId - 1) % RING_SIZE + 1
		local offsetX, offsetZ = x - xs[previousSlot], z - zs[previousSlot]
		local planDistanceSquared = offsetX * offsetX + offsetZ * offsetZ
		local isStep = LiveRoadRules.isContinuousStep(planDistanceSquared, math.abs(y - ys[previousSlot]))
		return jumps[previousSlot] + (if isStep then 0 else 1)
	end

	local function add(x: number, y: number, z: number, arcLength: number)
		neighborhoodKey = nil
		newestId += 1
		local slot = newestId % RING_SIZE + 1
		jumps[slot] = countJumps(x, y, z)
		xs[slot], ys[slot], zs[slot], arcs[slot] = x, y, z, arcLength
		local key = getCellKey(getCellCoordinate(x), getCellCoordinate(z))
		local cell = cells[key]
		if cell == nil then
			cell = { head = 1, last = 0 }
			cells[key] = cell
		end
		cell.last += 1
		cell[cell.last] = newestId
		while oldestId < newestId and arcLength - arcs[oldestId % RING_SIZE + 1] > KEPT_ARC_STUDS do
			forgetOldest()
		end
	end

	local function removeAfter(arcLength: number)
		neighborhoodKey = nil
		while newestId >= oldestId and arcs[newestId % RING_SIZE + 1] > arcLength do
			forgetNewest()
		end
	end

	-- Primer lugar de la celda cuya muestra todavía está dentro del límite hacia atrás. Las anteriores se guardan solo para el
	-- retroceso y son muchas: se las salta con una búsqueda binaria en vez de recorrerlas.
	local function findFirstWithinLookback(cell: Cell, arcLength: number): number
		local low, high = cell.head, cell.last + 1
		local oldestArcLength = arcLength - LOOKBACK_STUDS
		while low < high do
			local middle = (low + high) // 2
			if arcs[cell[middle] % RING_SIZE + 1] < oldestArcLength then
				low = middle + 1
			else
				high = middle
			end
		end
		return low
	end

	-- Dónde sigue la revisión de la celda después de la muestra de `position`, que cumplió y deja saltear las `safeSteps`
	-- siguientes de la ruta. Solo se saltea si esas muestras están realmente todas en la celda, una detrás de otra (ids
	-- consecutivos) y sin saltos de la ruta en el medio; si no, se sigue con la que viene.
	local function getNextPosition(cell: Cell, position: number, safeSteps: number): number
		local skippedCount = math.floor(safeSteps)
		local target = math.min(position + skippedCount + 1, cell.last)
		local firstId, targetId = cell[position], cell[target]
		local isSameRun = targetId - firstId == target - position
			and jumps[targetId % RING_SIZE + 1] == jumps[firstId % RING_SIZE + 1]
		if not isSameRun then
			return position + 1
		end
		-- Si el salto llega al final de la celda sin pasar por una muestra sin revisar, ya no queda nada.
		return if target - position <= skippedCount then cell.last + 1 else target
	end

	-- Las muestras de la celda van de las más viejas a las más nuevas y se corta en la primera que es vecina. Las que están a más
	-- de NEAR_ARC_STUDS y hasta NEIGHBOR_ARC_STUDS solo piden no cruzarse (NEAR_CLEARANCE_STUDS): así la ruta puede cerrar un
	-- círculo o una horquilla, pero no pasar por encima de sí misma.
	local function isCellClear(cell: Cell, x: number, y: number, z: number, arcLength: number): boolean
		-- Lo más común es una celda con solo la ruta reciente: si la más vieja ya es vecina, lo son todas.
		local oldestDifference = arcLength - arcs[cell[cell.head] % RING_SIZE + 1]
		if oldestDifference <= NEAR_ARC_STUDS then
			return true
		end
		local position = if oldestDifference <= LOOKBACK_STUDS
			then cell.head
			else findFirstWithinLookback(cell, arcLength)
		while position <= cell.last do
			local slot = cell[position] % RING_SIZE + 1
			local arcDifference = arcLength - arcs[slot]
			if arcDifference <= NEAR_ARC_STUDS then
				return true
			end
			local offsetX, offsetZ = x - xs[slot], z - zs[slot]
			local safeSteps = LiveRoadRules.getSafeSteps(
				math.sqrt(offsetX * offsetX + offsetZ * offsetZ),
				arcDifference,
				math.abs(y - ys[slot])
			)
			if safeSteps < 0 then
				return false
			end
			position = if safeSteps < 1 then position + 1 else getNextPosition(cell, position, safeSteps)
		end
		return true
	end

	local function gatherNeighborhood(centerKey: number)
		-- La clave es lineal en las dos celdas, así las vecinas se alcanzan sumando.
		neighborhoodCount = 0
		for offsetX = -CELLS_PER_RADIUS, CELLS_PER_RADIUS do
			for offsetZ = -CELLS_PER_RADIUS, CELLS_PER_RADIUS do
				local cell = cells[centerKey + offsetX * KEY_STRIDE + offsetZ]
				if cell ~= nil then
					neighborhoodCount += 1
					neighborhood[neighborhoodCount] = cell
				end
			end
		end
		neighborhoodKey = centerKey
	end

	local function isClear(x: number, y: number, z: number, arcLength: number): boolean
		local centerKey = getCellKey(getCellCoordinate(x), getCellCoordinate(z))
		if centerKey ~= neighborhoodKey then
			gatherNeighborhood(centerKey)
		end
		for position = 1, neighborhoodCount do
			if not isCellClear(neighborhood[position], x, y, z, arcLength) then
				return false
			end
		end
		return true
	end

	local function getSampleCount(): number
		return newestId - oldestId + 1
	end

	return { add = add, removeAfter = removeAfter, isClear = isClear, getSampleCount = getSampleCount }
end

return LiveRoadIndexModule
