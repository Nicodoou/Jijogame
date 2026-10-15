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
local U_TURN_STUDS = 300
local U_TURN_SAMPLES = U_TURN_STUDS // WorldConfig.INTEGRATION_STEP_STUDS
local U_TURN_MIN_RADIANS = math.rad(150)
-- Radio de más de 1.000 studs: recta a todos los efectos.
local STRAIGHT_MAX_CURVATURE = 0.001
local STRAIGHT_MIN_STUDS = 20
local STEEP_SLOPE_RADIANS = math.rad(10)

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

-- Cuántas ventanas de 2.000 studs hay y en cuántas el rumbo gira más de 180° de punta a punta.
function RoadRallyMetrics.countBigTurnWindows(road: { RoadPath.RoadSample }): (number, number)
	local windowCount, bigCount = 0, 0
	for first = 1, #road - WINDOW_SAMPLES, WINDOW_STRIDE_SAMPLES do
		windowCount += 1
		local netTurn = math.abs(road[first + WINDOW_SAMPLES].heading - road[first].heading)
		bigCount += if netTurn > MIN_NET_TURN_RADIANS then 1 else 0
	end
	return windowCount, bigCount
end

-- Cuántas vueltas en U hay: un giro neto de al menos 150° en no más de 300 studs de arco. Después de contar una, se
-- sigue desde el final de su ventana, así una misma vuelta no se cuenta dos veces.
function RoadRallyMetrics.countUTurns(road: { RoadPath.RoadSample }): number
	local count = 0
	local first = 1
	while first + U_TURN_SAMPLES <= #road do
		local netTurn = math.abs(road[first + U_TURN_SAMPLES].heading - road[first].heading)
		if netTurn >= U_TURN_MIN_RADIANS then
			count += 1
			first += U_TURN_SAMPLES
		else
			first += 1
		end
	end
	return count
end

-- Tramos rectos (curvatura casi cero) de al menos STRAIGHT_MIN_STUDS: cuántos hay, el largo total y el más largo.
function RoadRallyMetrics.measureStraights(road: { RoadPath.RoadSample }): (number, number, number)
	local count, totalStuds, longestStuds = 0, 0, 0
	local runStart: number? = nil
	for index = 1, #road + 1 do
		local isStraight = index <= #road and math.abs(road[index].curvature) < STRAIGHT_MAX_CURVATURE
		if isStraight and runStart == nil then
			runStart = index
		elseif not isStraight and runStart ~= nil then
			local lengthStuds = (index - runStart) * WorldConfig.INTEGRATION_STEP_STUDS
			if lengthStuds >= STRAIGHT_MIN_STUDS then
				count += 1
				totalStuds += lengthStuds
			end
			longestStuds = math.max(longestStuds, lengthStuds)
			runStart = nil
		end
	end
	return count, totalStuds, longestStuds
end

-- Lomas: muestras con pendiente de más de 10°, y cuántas subidas o bajadas hay (una por cada signo de pendiente seguido)
-- con su largo total.
function RoadRallyMetrics.measureHills(road: { RoadPath.RoadSample }): (number, number, number)
	local steepCount, climbCount, previousSign = 0, 0, 0
	for _, sample in road do
		steepCount += if math.abs(sample.slope) > STEEP_SLOPE_RADIANS then 1 else 0
		local sign = if sample.slope > 0 then 1 elseif sample.slope < 0 then -1 else 0
		if sign ~= 0 and sign ~= previousSign then
			climbCount += 1
		end
		previousSign = if sign ~= 0 then sign else previousSign
	end
	return steepCount, climbCount, #road
end

return RoadRallyMetrics
