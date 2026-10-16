--!strict
-- Ruta viva: grilla con las muestras recientes del eje y su arcLength. Responde si un punto nuevo respeta el anti-cruce:
-- no puede quedar a menos de LIVE_CLEARANCE_STUDS de una muestra cuyo arcLength lo preceda en más de
-- LIVE_NEIGHBOR_ARC_STUDS (las más cercanas sobre el eje son vecinas y siempre están cerca) y hasta LIVE_LOOKBACK_STUDS,
-- ni a menos de LIVE_NEAR_CLEARANCE_STUDS de una que lo preceda en más de LIVE_NEAR_ARC_STUDS.
-- Regla de altura: una muestra que queda a menos de LIVE_HEIGHT_RULE_RADIUS_STUDS de otra no vecina (las mismas que cuentan
-- para el anti-cruce) no puede estar a más altura de la que el terreno logra salvar con la pendiente máxima en el espacio libre
-- que queda entre las dos banquinas (menos un margen). Así no quedan paredes entre pasadas cercanas (WP-9).
-- Guarda además LIVE_BACKTRACK_MEMORY_STUDS más hacia atrás, para poder retroceder y volver a mirar esas muestras.

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
-- Las dos reglas miran muestras hasta un radio; la celda es la tercera parte del mayor, así que alcanzan las celdas a tres de distancia.
-- Celdas más grandes hacen revisar muchas muestras que quedan fuera del radio: la consulta es la parte cara de la ruta.
local CELLS_PER_RADIUS = 3
local CELL_STUDS = math.max(WorldConfig.LIVE_CLEARANCE_STUDS, WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS)
	/ CELLS_PER_RADIUS
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
local CLEARANCE_SQUARED = WorldConfig.LIVE_CLEARANCE_STUDS ^ 2
local NEIGHBOR_ARC_STUDS = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local NEAR_ARC_STUDS = WorldConfig.LIVE_NEAR_ARC_STUDS
local NEAR_CLEARANCE_SQUARED = WorldConfig.LIVE_NEAR_CLEARANCE_STUDS ^ 2
local HEIGHT_RADIUS_SQUARED = WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS ^ 2
-- Espacio entre los ejes de dos pasadas que ocupan la ruta y las dos banquinas: ahí el terreno no puede subir.
local ROAD_AND_SHOULDERS_STUDS = WorldConfig.ROAD_WIDTH_STUDS + 2 * WorldConfig.SHOULDER_WIDTH_STUDS
local RISE_PER_STUD =
	math.tan(math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES - WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES))
local LOOKBACK_STUDS = WorldConfig.LIVE_LOOKBACK_STUDS
local KEPT_ARC_STUDS = LOOKBACK_STUDS + WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS
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

	local function add(x: number, y: number, z: number, arcLength: number)
		neighborhoodKey = nil
		newestId += 1
		local slot = newestId % RING_SIZE + 1
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

	-- Las muestras de la celda van de las más viejas a las más nuevas y se corta en la primera que es vecina. Las que están a más
	-- de NEAR_ARC_STUDS y hasta NEIGHBOR_ARC_STUDS solo piden no cruzarse (NEAR_CLEARANCE_STUDS): así la ruta puede cerrar un
	-- círculo o una horquilla, pero no pasar por encima de sí misma.
	local function isCellClear(cell: Cell, x: number, y: number, z: number, arcLength: number): boolean
		-- Lo más común es una celda con solo la ruta reciente: si la más vieja ya es vecina, lo son todas.
		local oldestDifference = arcLength - arcs[cell[cell.head] % RING_SIZE + 1]
		if oldestDifference <= NEAR_ARC_STUDS then
			return true
		end
		local first = if oldestDifference <= LOOKBACK_STUDS then cell.head else findFirstWithinLookback(cell, arcLength)
		for position = first, cell.last do
			local slot = cell[position] % RING_SIZE + 1
			local arcDifference = arcLength - arcs[slot]
			if arcDifference <= NEAR_ARC_STUDS then
				break
			else
				local offsetX, offsetZ = x - xs[slot], z - zs[slot]
				local required = if arcDifference <= NEIGHBOR_ARC_STUDS
					then NEAR_CLEARANCE_SQUARED
					else CLEARANCE_SQUARED
				local distanceSquared = offsetX * offsetX + offsetZ * offsetZ
				if distanceSquared < required then
					return false
				elseif distanceSquared < HEIGHT_RADIUS_SQUARED then
					-- Dentro del radio, la diferencia de altura admitida crece con la distancia entre los ejes.
					local allowedRise = RISE_PER_STUD
						* math.max(0, math.sqrt(distanceSquared) - ROAD_AND_SHOULDERS_STUDS)
					if math.abs(y - ys[slot]) > allowedRise then
						return false
					end
				end
			end
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
