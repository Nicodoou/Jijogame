--!strict
-- Guía grande de la ruta: puntos de paso separados GUIDE_STEP_STUDS, sorteados con la semilla, que recorren el área
-- dando vueltas sin acercarse a sí mismos. La ruta local sigue esta guía. Se genera de a poco, siempre unos puntos
-- por delante de lo que usa la ruta, y retrocede (descarta los últimos puntos) cuando se queda sin salida.
-- No se descartan los puntos viejos: son uno cada 1.200 studs y no pesan.

local RoadFrame = require("./RoadFrame")
local SeededRandom = require("./SeededRandom")
local SegmentGeometry = require("./SegmentGeometry")
local WorldConfig = require("./WorldConfig")

export type GuideStatistics = {
	-- Veces que la guía retrocedió, puntos descartados en total y más puntos descartados de una vez.
	backtrackCount: number,
	discardedWaypointCount: number,
	maxDiscardedAtOnce: number,
}

export type RoadGuide = {
	-- Genera puntos hasta cubrir `arcLength` más GUIDE_AHEAD_WAYPOINTS puntos. Puede descartar puntos de más adelante,
	-- nunca los que cubren `arcLength`.
	ensureCovers: (arcLength: number) -> (),
	-- Proyecta (x, z) sobre los segmentos vecinos al de `hintSegment`: devuelve el desvío lateral con signo (positivo a
	-- la derecha de la guía), el arcLength sobre la guía y el segmento (desde 1) más cercano.
	project: (x: number, z: number, hintSegment: number) -> (number, number, number),
	getPointAt: (arcLength: number) -> (number, number),
	-- Rumbo (radianes) del segmento que va del punto `segment` al siguiente.
	getSegmentHeading: (segment: number) -> number,
	getStatistics: () -> GuideStatistics,
}

local STEP_STUDS = WorldConfig.GUIDE_STEP_STUDS
local MAX_TURN_RADIANS = math.rad(WorldConfig.GUIDE_MAX_TURN_DEGREES)
local STEERING_RADIUS_STUDS = WorldConfig.AREA_RADIUS_STUDS - WorldConfig.AREA_STEERING_MARGIN_STUDS
local LIMIT_RADIUS_STUDS = WorldConfig.AREA_RADIUS_STUDS - WorldConfig.GUIDE_EDGE_MARGIN_STUDS
-- Cuántos puntos hacia atrás se comparan con uno nuevo: lo que alcanza la ruta viva más dos de colchón.
local CLEARANCE_WINDOW_WAYPOINTS = math.ceil(WorldConfig.LIVE_LOOKBACK_STUDS / STEP_STUDS) + 2
local CLEARANCE_STUDS = WorldConfig.GUIDE_CLEARANCE_STUDS

-- Alternativas en orden fijo: +30°, -30°, +60°, -60°, +90°, -90°.
local function buildAlternativeTurns(): { number }
	local turns = {}
	for _, degrees in WorldConfig.GUIDE_ALTERNATIVE_TURNS_DEGREES do
		table.insert(turns, math.rad(degrees))
		table.insert(turns, -math.rad(degrees))
	end
	return turns
end

local ALTERNATIVE_TURNS = buildAlternativeTurns()

-- Cerca del borde, el giro sorteado se inclina hacia el centro del área.
local function steerTowardCenter(turn: number, last: vector, heading: number): number
	local radius = math.sqrt(last.x * last.x + last.z * last.z)
	if radius <= STEERING_RADIUS_STUDS then
		return turn
	end
	local toCenter = math.atan2(-last.z, -last.x)
	local wanted = math.clamp(RoadFrame.wrapAngleRadians(toCenter - heading), -MAX_TURN_RADIANS, MAX_TURN_RADIANS)
	local weight = math.clamp((radius - STEERING_RADIUS_STUDS) / WorldConfig.GUIDE_PULL_RANGE_STUDS, 0, 1)
	return turn + (wanted - turn) * weight
end

local RoadGuideModule = {}

function RoadGuideModule.new(random: SeededRandom.SeededRandom): RoadGuide
	local start = WorldConfig.START_POSITION
	local waypoints: { vector } = { vector.create(start.x, 0, start.z) }
	-- headings[i] es el rumbo con el que se llegó al punto i.
	local headings: { number } = { RoadFrame.getStartHeadingRadians() }
	local statistics: GuideStatistics = { backtrackCount = 0, discardedWaypointCount = 0, maxDiscardedAtOnce = 0 }
	local failStreak = 0
	local longestCount = 1

	-- Un punto nuevo sirve si queda dentro del área y sus segmentos quedan a distancia libre de los vivos.
	local function isAcceptable(candidate: vector): boolean
		if math.sqrt(candidate.x * candidate.x + candidate.z * candidate.z) > LIMIT_RADIUS_STUDS then
			return false
		end
		local count = #waypoints
		local last = waypoints[count]
		for index = math.max(1, count - CLEARANCE_WINDOW_WAYPOINTS + 1), count do
			local waypoint = waypoints[index]
			local offsetX, offsetZ = candidate.x - waypoint.x, candidate.z - waypoint.z
			if offsetX * offsetX + offsetZ * offsetZ < CLEARANCE_STUDS * CLEARANCE_STUDS then
				return false
			end
		end
		for index = math.max(1, count - CLEARANCE_WINDOW_WAYPOINTS + 1), count - 2 do
			if
				SegmentGeometry.getSegmentToSegmentDistance(last, candidate, waypoints[index], waypoints[index + 1])
				< CLEARANCE_STUDS
			then
				return false
			end
		end
		return true
	end

	local function tryToGrow(): boolean
		local count = #waypoints
		local last, heading = waypoints[count], headings[count]
		local drawn = (random.nextNumber() * 2 - 1) * MAX_TURN_RADIANS
		local candidates = { steerTowardCenter(drawn, last, heading) }
		table.move(ALTERNATIVE_TURNS, 1, #ALTERNATIVE_TURNS, 2, candidates)
		for _, turn in candidates do
			local newHeading = heading + turn
			local candidate =
				vector.create(last.x + STEP_STUDS * math.cos(newHeading), 0, last.z + STEP_STUDS * math.sin(newHeading))
			if isAcceptable(candidate) then
				table.insert(waypoints, candidate)
				table.insert(headings, newHeading)
				return true
			end
		end
		return false
	end

	local function discardLastWaypoints(requested: number, keptWaypointCount: number)
		local discarded = math.min(requested, #waypoints - keptWaypointCount)
		if discarded < 1 or failStreak > WorldConfig.GUIDE_FAIL_LIMIT then
			error("the road guide has no way out", 3)
		end
		for _ = 1, discarded do
			table.remove(waypoints)
			table.remove(headings)
		end
		statistics.backtrackCount += 1
		statistics.discardedWaypointCount += discarded
		statistics.maxDiscardedAtOnce = math.max(statistics.maxDiscardedAtOnce, discarded)
	end

	local function ensureCovers(arcLength: number)
		local usedWaypointCount = math.floor(arcLength / STEP_STUDS) + 1
		local wantedWaypointCount = usedWaypointCount + 1 + WorldConfig.GUIDE_AHEAD_WAYPOINTS
		while #waypoints < wantedWaypointCount do
			if tryToGrow() then
				if #waypoints > longestCount then
					longestCount = #waypoints
					failStreak = 0
				end
			else
				failStreak += 1
				discardLastWaypoints(
					1 + failStreak // WorldConfig.GUIDE_BACKTRACK_FAILS_PER_EXTRA_WAYPOINT,
					usedWaypointCount
				)
			end
		end
	end

	local function project(x: number, z: number, hintSegment: number): (number, number, number)
		local segmentCount = #waypoints - 1
		local hint = math.clamp(hintSegment, 1, segmentCount)
		local bestDistance, bestOffset, bestArc, bestSegment = math.huge, 0, 0, hint
		for segment = math.max(1, hint - 1), math.min(segmentCount, hint + 2) do
			local from, to = waypoints[segment], waypoints[segment + 1]
			local edgeX, edgeZ = to.x - from.x, to.z - from.z
			local fromX, fromZ = x - from.x, z - from.z
			local fraction = math.clamp((fromX * edgeX + fromZ * edgeZ) / (edgeX * edgeX + edgeZ * edgeZ), 0, 1)
			local offsetX, offsetZ = fromX - edgeX * fraction, fromZ - edgeZ * fraction
			local distance = math.sqrt(offsetX * offsetX + offsetZ * offsetZ)
			if distance < bestDistance then
				local isOnRight = edgeX * fromZ - edgeZ * fromX >= 0
				bestDistance = distance
				bestOffset = if isOnRight then distance else -distance
				bestArc = (segment - 1) * STEP_STUDS + fraction * STEP_STUDS
				bestSegment = segment
			end
		end
		return bestOffset, bestArc, bestSegment
	end

	local function getPointAt(arcLength: number): (number, number)
		local segment = math.clamp(math.floor(arcLength / STEP_STUDS) + 1, 1, #waypoints - 1)
		local fraction = math.clamp((arcLength - (segment - 1) * STEP_STUDS) / STEP_STUDS, 0, 1)
		local from, to = waypoints[segment], waypoints[segment + 1]
		return from.x + (to.x - from.x) * fraction, from.z + (to.z - from.z) * fraction
	end

	local function getSegmentHeading(segment: number): number
		return headings[segment + 1]
	end

	local function getStatistics(): GuideStatistics
		return statistics
	end

	return {
		ensureCovers = ensureCovers,
		project = project,
		getPointAt = getPointAt,
		getSegmentHeading = getSegmentHeading,
		getStatistics = getStatistics,
	}
end

return RoadGuideModule
