--!strict
-- Verificación del anti-cruce y de la regla de altura, escrita aparte de LiveRoadIndex, para que una falla de uno no tape la
-- del otro.
-- No es una prueba: no termina en Runner.finish().

local WorldConfig = require("../../src/world/core/WorldConfig")

export type Polyline = {
	xs: { number },
	zs: { number },
	-- Alturas, si se quiere medir también la regla de altura.
	ys: { number }?,
}

export type ClearanceReport = {
	violationCount: number,
	-- Menor distancia entre dos muestras no vecinas lejanas, o math.huge si no hubo ninguna.
	minimumDistance: number,
	-- Pares de muestras no vecinas a menos de LIVE_HEIGHT_RULE_RADIUS_STUDS cuya diferencia de altura supera lo que salva la
	-- pendiente máxima del terreno entre las dos banquinas (sin el margen de la regla, pero con la tolerancia).
	heightViolationCount: number,
	-- Mayor pendiente, en grados, entre dos muestras no vecinas dentro del radio, medida sobre el espacio entre banquinas.
	steepestSlopeDegrees: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local CELL_STUDS = math.max(WorldConfig.LIVE_CLEARANCE_STUDS, WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS)
local HEIGHT_RADIUS_STUDS = WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS
local ROAD_AND_SHOULDERS_STUDS = WorldConfig.ROAD_WIDTH_STUDS + 2 * WorldConfig.SHOULDER_WIDTH_STUDS
local MAX_RISE_PER_STUD = math.tan(math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES))
local KEY_STRIDE = WorldConfig.ROAD_QUERY_GRID_KEY_STRIDE
-- Desfases de muestras (en pasos): desde el primero no vecino cercano, desde el primero no vecino lejano y el último.
local NEAREST_NON_NEIGHBOR_OFFSET = WorldConfig.LIVE_NEAR_ARC_STUDS // STEP_STUDS + 1
local FAR_OFFSET = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS // STEP_STUDS + 1
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

local function measureHeightRule(report: ClearanceReport, rise: number, distance: number, tolerance: number)
	local freeStuds = math.max(0, distance - ROAD_AND_SHOULDERS_STUDS)
	report.steepestSlopeDegrees = math.max(report.steepestSlopeDegrees, math.deg(math.atan2(rise, freeStuds)))
	if rise > MAX_RISE_PER_STUD * math.max(0, freeStuds + tolerance) + tolerance then
		report.heightViolationCount += 1
	end
end

local function measurePair(report: ClearanceReport, line: Polyline, probe: number, id: number, tolerance: number)
	local distance = math.sqrt((line.xs[probe] - line.xs[id]) ^ 2 + (line.zs[probe] - line.zs[id]) ^ 2)
	local isFar = probe - id >= FAR_OFFSET
	if isFar then
		report.minimumDistance = math.min(report.minimumDistance, distance)
	end
	local limit = if isFar then WorldConfig.LIVE_CLEARANCE_STUDS else WorldConfig.LIVE_NEAR_CLEARANCE_STUDS
	if distance < limit - tolerance then
		report.violationCount += 1
	end
	local heights = line.ys
	if heights ~= nil and distance < HEIGHT_RADIUS_STUDS then
		measureHeightRule(report, math.abs(heights[probe] - heights[id]), distance, tolerance)
	end
end

-- Cuenta los pares de muestras no vecinas (a NEAREST..FARTHEST pasos una de otra) que quedan a menos de
-- LIVE_CLEARANCE_STUDS menos la tolerancia, y los que rompen la regla de altura.
function ClearanceCheck.measure(line: Polyline, tolerance: number): ClearanceReport
	local cells = buildGrid(line)
	local report: ClearanceReport = {
		violationCount = 0,
		minimumDistance = math.huge,
		heightViolationCount = 0,
		steepestSlopeDegrees = 0,
	}
	for probe = 1, #line.xs, PROBE_STRIDE do
		local cellX, cellZ = getCellCoordinate(line.xs[probe]), getCellCoordinate(line.zs[probe])
		for offsetX = -1, 1 do
			for offsetZ = -1, 1 do
				local cell = cells[getCellKey(cellX + offsetX, cellZ + offsetZ)]
				if cell ~= nil then
					local position = findFirstAtLeast(cell, probe - FARTHEST_OFFSET)
					while position <= #cell and cell[position] <= probe - NEAREST_NON_NEIGHBOR_OFFSET do
						measurePair(report, line, probe, cell[position], tolerance)
						position += 1
					end
				end
			end
		end
	end
	return report
end

return ClearanceCheck
