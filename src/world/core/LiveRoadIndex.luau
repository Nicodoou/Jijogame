--!strict
-- Ruta viva: grilla con las muestras recientes del eje y su arcLength. Responde si un punto nuevo respeta el anti-cruce:
-- no puede quedar a menos de LIVE_CLEARANCE_STUDS de una muestra cuyo arcLength lo preceda en más de
-- LIVE_NEIGHBOR_ARC_STUDS (las más cercanas sobre el eje son vecinas y siempre están cerca) y hasta LIVE_LOOKBACK_STUDS,
-- ni a menos de LIVE_NEAR_CLEARANCE_STUDS de una que lo preceda en más de LIVE_NEAR_ARC_STUDS.
-- Guarda además LIVE_BACKTRACK_MEMORY_STUDS más hacia atrás, para poder retroceder y volver a mirar esas muestras.

local WorldConfig = require("./WorldConfig")

export type LiveRoadIndex = {
	-- Agrega una muestra. Su arcLength tiene que ser mayor que el de la anterior.
	add: (x: number, z: number, arcLength: number) -> (),
	-- Quita las muestras con arcLength mayor que el dado: es el retroceso de la ruta.
	removeAfter: (arcLength: number) -> (),
	isClear: (x: number, z: number, arcLength: number) -> boolean,
	getSampleCount: () -> number,
}

-- Los ids de las muestras de una celda van en orden, del `head` al `last`, y por lo tanto también por arcLength.
type Cell = { head: number, last: number, [number]: number }

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local CELL_STUDS = WorldConfig.LIVE_CLEARANCE_STUDS
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
local CLEARANCE_SQUARED = WorldConfig.LIVE_CLEARANCE_STUDS ^ 2
local NEIGHBOR_ARC_STUDS = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local NEAR_ARC_STUDS = WorldConfig.LIVE_NEAR_ARC_STUDS
local NEAR_CLEARANCE_SQUARED = WorldConfig.LIVE_NEAR_CLEARANCE_STUDS ^ 2
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
	local zs = table.create(RING_SIZE, 0)
	local arcs = table.create(RING_SIZE, 0)
	local cells: { [number]: Cell } = {}
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

	local function add(x: number, z: number, arcLength: number)
		newestId += 1
		local slot = newestId % RING_SIZE + 1
		xs[slot], zs[slot], arcs[slot] = x, z, arcLength
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
		while newestId >= oldestId and arcs[newestId % RING_SIZE + 1] > arcLength do
			forgetNewest()
		end
	end

	-- Las muestras de la celda van de las más viejas a las más nuevas: se saltean las que pasaron el límite hacia atrás y se
	-- corta en la primera que es vecina. Las que están a más de NEAR_ARC_STUDS y hasta NEIGHBOR_ARC_STUDS solo piden no
	-- cruzarse (NEAR_CLEARANCE_STUDS): así la ruta puede cerrar un círculo o una horquilla, pero no pasar por encima de sí misma.
	local function isCellClear(cell: Cell, x: number, z: number, arcLength: number): boolean
		for position = cell.head, cell.last do
			local slot = cell[position] % RING_SIZE + 1
			local arcDifference = arcLength - arcs[slot]
			if arcDifference <= NEAR_ARC_STUDS then
				break
			elseif arcDifference <= LOOKBACK_STUDS then
				local offsetX, offsetZ = x - xs[slot], z - zs[slot]
				local required = if arcDifference <= NEIGHBOR_ARC_STUDS
					then NEAR_CLEARANCE_SQUARED
					else CLEARANCE_SQUARED
				if offsetX * offsetX + offsetZ * offsetZ < required then
					return false
				end
			end
		end
		return true
	end

	local function isClear(x: number, z: number, arcLength: number): boolean
		-- La clave es lineal en las dos celdas, así las vecinas se alcanzan sumando.
		local centerKey = getCellKey(getCellCoordinate(x), getCellCoordinate(z))
		for offsetX = -1, 1 do
			for offsetZ = -1, 1 do
				local cell = cells[centerKey + offsetX * KEY_STRIDE + offsetZ]
				if cell ~= nil and not isCellClear(cell, x, z, arcLength) then
					return false
				end
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
