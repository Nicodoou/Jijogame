--!strict
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadGuide = require("../../src/world/core/RoadGuide")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local SegmentGeometry = require("../../src/world/core/SegmentGeometry")
local WorldConfig = require("../../src/world/core/WorldConfig")

local TOLERANCE = 1e-3
local STEP = WorldConfig.GUIDE_STEP_STUDS
local MAX_ALTERNATIVE_TURN =
	math.rad(math.max(WorldConfig.GUIDE_MAX_TURN_DEGREES, table.unpack(WorldConfig.GUIDE_ALTERNATIVE_TURNS_DEGREES)))
local LIMIT_RADIUS = WorldConfig.AREA_RADIUS_STUDS - WorldConfig.GUIDE_EDGE_MARGIN_STUDS
-- Con esta longitud la guía da varias vueltas al área y retrocede más de una vez.
local LONG_GUIDE_STUDS = 120 * STEP
local SEED_COUNT = 30
-- Los puntos que se comparan entre sí: los que alcanza la ruta viva (LIVE_LOOKBACK_STUDS) más dos de colchón.
local CHECKED_WAYPOINTS = math.ceil(WorldConfig.LIVE_LOOKBACK_STUDS / STEP) + 2

-- La ruta va pidiendo la guía de a poco, a medida que avanza.
local function createGuide(seed: number, lengthStuds: number): RoadGuide.RoadGuide
	local guide = RoadGuide.new(SeededRandom.new(seed))
	for arcLength = 0, lengthStuds, STEP do
		guide.ensureCovers(arcLength)
	end
	return guide
end

-- Los puntos de paso, leídos con la propia guía: el punto al comienzo de cada segmento.
local function readWaypoints(guide: RoadGuide.RoadGuide, count: number): { vector }
	local waypoints = {}
	for index = 0, count - 1 do
		local x, z = guide.getPointAt(index * STEP)
		waypoints[index + 1] = vector.create(x, 0, z)
	end
	return waypoints
end

Runner.test("the first waypoint is the start of the road and the segments are one step long", function()
	local guide = createGuide(1, 30 * STEP)
	local waypoints = readWaypoints(guide, 30)
	Runner.expectNear(waypoints[1].x, WorldConfig.START_POSITION.x, TOLERANCE)
	Runner.expectNear(waypoints[1].z, WorldConfig.START_POSITION.z, TOLERANCE)
	for index = 2, #waypoints do
		Runner.expectNear(vector.magnitude(waypoints[index] - waypoints[index - 1]), STEP, TOLERANCE)
	end
end)

Runner.test("the guide covers the arc length asked for plus the waypoints ahead", function()
	local guide = createGuide(2, 10 * STEP)
	local ahead = (10 + 1 + WorldConfig.GUIDE_AHEAD_WAYPOINTS) * STEP
	local x, z = guide.getPointAt(ahead)
	local beyondX, beyondZ = guide.getPointAt(ahead + 50 * STEP)
	-- Más allá del final el punto queda en el último y no sigue de largo.
	Runner.expectNear(beyondX, x, TOLERANCE)
	Runner.expectNear(beyondZ, z, TOLERANCE)
	local insideX, insideZ = guide.getPointAt(ahead - STEP)
	Runner.expectNear(math.sqrt((x - insideX) ^ 2 + (z - insideZ) ^ 2), STEP, TOLERANCE)
end)

Runner.test("asking again for less than what is covered does not change the guide", function()
	local guide = createGuide(3, 40 * STEP)
	local before = readWaypoints(guide, 40)
	guide.ensureCovers(5 * STEP)
	guide.ensureCovers(0)
	local after = readWaypoints(guide, 40)
	for index = 1, 40 do
		Runner.expectEqual(before[index], after[index])
	end
end)

Runner.test("the same random stream builds the same guide and another one builds another", function()
	local first, second, other = createGuide(4, 40 * STEP), createGuide(4, 40 * STEP), createGuide(5, 40 * STEP)
	local differences = 0
	for index = 1, 40 do
		local firstX, firstZ = first.getPointAt((index - 1) * STEP)
		local secondX, secondZ = second.getPointAt((index - 1) * STEP)
		local otherX = other.getPointAt((index - 1) * STEP)
		Runner.expectEqual(firstX, secondX)
		Runner.expectEqual(firstZ, secondZ)
		differences += if firstX ~= otherX then 1 else 0
	end
	Runner.expectEqual(differences > 30, true)
end)

Runner.test("every waypoint stays inside the area, away from its edge", function()
	for seed = 1, SEED_COUNT do
		for _, waypoint in readWaypoints(createGuide(seed, LONG_GUIDE_STUDS), 120) do
			Runner.expectEqual(
				vector.magnitude(vector.create(waypoint.x, 0, waypoint.z)) <= LIMIT_RADIUS + TOLERANCE,
				true
			)
		end
	end
end)

Runner.test("each turn is at most the largest alternative turn", function()
	for seed = 1, SEED_COUNT do
		local guide = createGuide(seed, LONG_GUIDE_STUDS)
		for segment = 2, 119 do
			local turn =
				RoadFrame.wrapAngleRadians(guide.getSegmentHeading(segment) - guide.getSegmentHeading(segment - 1))
			Runner.expectEqual(math.abs(turn) <= MAX_ALTERNATIVE_TURN + TOLERANCE, true)
		end
	end
end)

Runner.test("the segment heading matches the direction between its waypoints", function()
	local guide = createGuide(6, 30 * STEP)
	local waypoints = readWaypoints(guide, 30)
	for segment = 1, 29 do
		local direction = waypoints[segment + 1] - waypoints[segment]
		Runner.expectNear(math.cos(guide.getSegmentHeading(segment)), direction.x / STEP, 1e-6)
		Runner.expectNear(math.sin(guide.getSegmentHeading(segment)), direction.z / STEP, 1e-6)
	end
end)

Runner.test("segments within reach of each other keep the guide clearance", function()
	for seed = 1, SEED_COUNT do
		local waypoints = readWaypoints(createGuide(seed, LONG_GUIDE_STUDS), 120)
		for first = 1, #waypoints - 1 do
			for second = first + 2, math.min(#waypoints - 1, first + CHECKED_WAYPOINTS - 1) do
				local distance = SegmentGeometry.getSegmentToSegmentDistance(
					waypoints[first],
					waypoints[first + 1],
					waypoints[second],
					waypoints[second + 1]
				)
				Runner.expectEqual(distance >= WorldConfig.GUIDE_CLEARANCE_STUDS - TOLERANCE, true)
			end
		end
	end
end)

Runner.test("when the guide gets stuck it takes back waypoints and keeps its rules", function()
	local backtracks, discarded, largest = 0, 0, 0
	for seed = 1, SEED_COUNT do
		local statistics = createGuide(seed, LONG_GUIDE_STUDS).getStatistics()
		backtracks += statistics.backtrackCount
		discarded += statistics.discardedWaypointCount
		largest = math.max(largest, statistics.maxDiscardedAtOnce)
	end
	Runner.expectEqual(backtracks > 0, true)
	Runner.expectEqual(discarded >= backtracks, true)
	Runner.expectEqual(largest >= 1 and largest <= WorldConfig.GUIDE_AHEAD_WAYPOINTS + 1, true)
end)

Runner.test("a waypoint on the guide has no offset, and the sign tells the side", function()
	local guide = createGuide(7, 30 * STEP)
	local x, z = guide.getPointAt(2.5 * STEP)
	local heading = guide.getSegmentHeading(3)
	local offset, arcLength, segment = guide.project(x, z, 3)
	Runner.expectNear(offset, 0, TOLERANCE)
	Runner.expectNear(arcLength, 2.5 * STEP, TOLERANCE)
	Runner.expectEqual(segment, 3)
	local rightX, rightZ = -math.sin(heading), math.cos(heading)
	Runner.expectNear((guide.project(x + 30 * rightX, z + 30 * rightZ, 3)), 30, TOLERANCE)
	Runner.expectNear((guide.project(x - 30 * rightX, z - 30 * rightZ, 3)), -30, TOLERANCE)
end)

Runner.test("projecting before the start or past the last segment clamps to the ends", function()
	local guide = createGuide(8, 10 * STEP)
	local startX, startZ = guide.getPointAt(0)
	local _, startArc, startSegment = guide.project(startX - 500, startZ, 1)
	Runner.expectNear(startArc, 0, TOLERANCE)
	Runner.expectEqual(startSegment, 1)
	local endX, endZ = guide.getPointAt(1e9)
	local lastHeading = guide.getSegmentHeading(15)
	local _, endArc = guide.project(endX + 500 * math.cos(lastHeading), endZ + 500 * math.sin(lastHeading), 15)
	Runner.expectNear(endArc, 15 * STEP, TOLERANCE)
end)

Runner.test("a hint outside the guide is brought inside it", function()
	local guide = createGuide(9, 10 * STEP)
	local x, z = guide.getPointAt(3 * STEP)
	local _, lowArc = guide.project(x, z, -50)
	local _, highArc = guide.project(x, z, 5000)
	Runner.expectEqual(lowArc >= 0 and lowArc <= 15 * STEP, true)
	Runner.expectEqual(highArc >= 0 and highArc <= 15 * STEP, true)
end)

Runner.test("the guide keeps turning to the same side most of the time, so it winds around in spirals", function()
	local sameSide, total = 0, 0
	for seed = 1, SEED_COUNT do
		local guide = createGuide(seed, LONG_GUIDE_STUDS)
		local previous = 0
		for segment = 2, 119 do
			local turn = guide.getSegmentHeading(segment) - guide.getSegmentHeading(segment - 1)
			sameSide += if turn * previous > 0 then 1 else 0
			total += 1
			previous = turn
		end
	end
	Runner.expectEqual(sameSide / total > 0.6, true)
end)

Runner.finish()
