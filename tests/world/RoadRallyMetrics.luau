--!strict
-- Medidas de "rally de verdad" sobre una ruta ya generada: giro neto, cuadrantes y desnivel en ventanas de 2.000 studs.
-- No es una prueba: no termina en Runner.finish().

local RoadPath = require("../../src/world/core/RoadPath")
local WorldConfig = require("../../src/world/core/WorldConfig")

local RALLY_WINDOW_STUDS = 2000
local WINDOW_SAMPLES = RALLY_WINDOW_STUDS // WorldConfig.INTEGRATION_STEP_STUDS
local WINDOW_STRIDE_SAMPLES = 100
local QUADRANT_STRIDE_SAMPLES = 10
local QUADRANT_COUNT = 4
local FULL_TURN_RADIANS = 2 * math.pi
local MIN_NET_TURN_RADIANS = math.pi
local MIN_HEIGHT_VARIATION_STUDS = 60

local RoadRallyMetrics = {}

-- ¿Hay una ventana de 2.000 studs en la que el rumbo gire más de 180° de punta a punta?
function RoadRallyMetrics.hasWindowWithBigTurn(road: { RoadPath.RoadSample }): boolean
	for first = 1, #road - WINDOW_SAMPLES, WINDOW_STRIDE_SAMPLES do
		if math.abs(road[first + WINDOW_SAMPLES].heading - road[first].heading) > MIN_NET_TURN_RADIANS then
			return true
		end
	end
	return false
end

-- ¿Pasa el rumbo por los cuatro cuadrantes de la brújula?
function RoadRallyMetrics.passesAllQuadrants(road: { RoadPath.RoadSample }): boolean
	local quadrants = {}
	local quadrantRadians = FULL_TURN_RADIANS / QUADRANT_COUNT
	for index = 1, #road, QUADRANT_STRIDE_SAMPLES do
		-- Un rumbo apenas negativo da exactamente 2 pi al envolverlo: cuenta como el primer cuadrante.
		quadrants[math.floor((road[index].heading % FULL_TURN_RADIANS) / quadrantRadians) % QUADRANT_COUNT] = true
	end
	local count = 0
	for _ in quadrants do
		count += 1
	end
	return count == QUADRANT_COUNT
end

-- Cuántas ventanas de 2.000 studs hay y en cuántas la altura varía más de 60 studs.
function RoadRallyMetrics.countHeightWindows(road: { RoadPath.RoadSample }): (number, number)
	local windowCount, hillyCount = 0, 0
	for first = 1, #road - WINDOW_SAMPLES, WINDOW_STRIDE_SAMPLES do
		local lowest, highest = math.huge, -math.huge
		for index = first, first + WINDOW_SAMPLES do
			lowest = math.min(lowest, road[index].position.y)
			highest = math.max(highest, road[index].position.y)
		end
		windowCount += 1
		hillyCount += if highest - lowest > MIN_HEIGHT_VARIATION_STUDS then 1 else 0
	end
	return windowCount, hillyCount
end

return RoadRallyMetrics
