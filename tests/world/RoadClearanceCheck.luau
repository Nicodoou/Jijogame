--!strict
-- Verificación del anti-cruce escrita aparte de LiveRoadIndex, para que una falla de uno no tape la del otro.
-- No es una prueba: no termina en Runner.finish().

local WorldConfig = require("../../src/world/core/WorldConfig")

export type Polyline = {
	xs: { number },
	zs: { number },
}

export type ClearanceReport = {
	violationCount: number,
	-- Menor distancia entre dos muestras no vecinas, o math.huge si no hubo ninguna.
	minimumDistance: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local CELL_STUDS = WorldConfig.LIVE_CLEARANCE_STUDS
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
-- Primer y último desfase de muestras (en pasos) que cuentan como no vecinas.
local NEAREST_NON_NEIGHBOR_OFFSET = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS // STEP_STUDS + 1
local FARTHEST_OFFSET = WorldConfig.LIVE_LOOKBACK_STUDS // STEP_STUDS
-- Se revisa una de cada tantas muestras: un cruce dura cientos de muestras seguidas.
local PROBE_STRIDE = 4

local ClearanceCheck = {}

local function getCellKey(cellX: number, cellZ: number): number
	return cellX * KEY_STRIDE + cellZ
end

local function getCellCoordinate(value: number): number
	return math.floor(value / CELL_STUDS)
end

-- Primer lugar de la lista (ordenada) cuyo valor es >= wanted.
local function findFirstAtLeast(sorted: { number }, wanted: number): number
	local low, high = 1, #sorted + 1
	while low < high do
		local middle = (low + high) // 2
		if sorted[middle] < wanted then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function buildGrid(line: Polyline): { [number]: { number } }
	local cells: { [number]: { number } } = {}
	for id = 1, #line.xs do
		local key = getCellKey(getCellCoordinate(line.xs[id]), getCellCoordinate(line.zs[id]))
		local cell = cells[key]
		if cell == nil then
			cell = {}
			cells[key] = cell
		end
		table.insert(cell, id)
	end
	return cells
end

-- Cuenta los pares de muestras no vecinas (a NEAREST..FARTHEST pasos una de otra) que quedan a menos de
-- LIVE_CLEARANCE_STUDS menos la tolerancia.
function ClearanceCheck.measure(line: Polyline, tolerance: number): ClearanceReport
	local cells = buildGrid(line)
	local report: ClearanceReport = { violationCount = 0, minimumDistance = math.huge }
	local limit = WorldConfig.LIVE_CLEARANCE_STUDS - tolerance
	for probe = 1, #line.xs, PROBE_STRIDE do
		local x, z = line.xs[probe], line.zs[probe]
		local cellX, cellZ = getCellCoordinate(x), getCellCoordinate(z)
		for offsetX = -1, 1 do
			for offsetZ = -1, 1 do
				local cell = cells[getCellKey(cellX + offsetX, cellZ + offsetZ)]
				if cell ~= nil then
					local position = findFirstAtLeast(cell, probe - FARTHEST_OFFSET)
					while position <= #cell and cell[position] <= probe - NEAREST_NON_NEIGHBOR_OFFSET do
						local id = cell[position]
						local distance = math.sqrt((x - line.xs[id]) ^ 2 + (z - line.zs[id]) ^ 2)
						report.minimumDistance = math.min(report.minimumDistance, distance)
						if distance < limit then
							report.violationCount += 1
						end
						position += 1
					end
				end
			end
		end
	end
	return report
end

return ClearanceCheck
