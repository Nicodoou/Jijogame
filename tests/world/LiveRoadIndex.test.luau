--!strict
local LiveRoadIndex = require("../../src/world/core/LiveRoadIndex")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CLEARANCE = WorldConfig.LIVE_CLEARANCE_STUDS
local NEIGHBOR_ARC = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local NEAR_ARC = WorldConfig.LIVE_NEAR_ARC_STUDS
local NEAR_CLEARANCE = WorldConfig.LIVE_NEAR_CLEARANCE_STUDS
local LOOKBACK = WorldConfig.LIVE_LOOKBACK_STUDS
local KEPT_ARC = LOOKBACK + WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local JUST_INSIDE = 1e-6
local RANDOM_SAMPLES = 300
local ARC_SPACING_STUDS = 20
local RANDOM_QUERIES = 600
local AREA_STUDS = 2500
local CROWDED_AREA_STUDS = 600
local MAX_HEIGHT_STUDS = 150
local ZIGZAG_LEG_STUDS = 400
local ZIGZAG_LEGS = 6
local ZIGZAG_QUERIES = 300
local ZIGZAG_BASE_HEIGHT_STUDS = 50
local ZIGZAG_HILL_STUDS = 35
local ZIGZAG_HILL_WAVELENGTH_STUDS = 120
local HEIGHT_RADIUS = WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS
local ROAD_AND_SHOULDERS = WorldConfig.ROAD_WIDTH_STUDS + 2 * WorldConfig.SHOULDER_WIDTH_STUDS

-- Una muestra en el origen con arcLength 0 y una consulta lejos de ahí en arcLength, a `distance` de la muestra.
local function isClearAt(distance: number, queryArc: number): boolean
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	return index.isClear(distance, 0, 0, queryArc)
end

Runner.test("an empty index is clear everywhere", function()
	local index = LiveRoadIndex.new()
	Runner.expectEqual(index.getSampleCount(), 0)
	Runner.expectEqual(index.isClear(0, 0, 0, 0), true)
	Runner.expectEqual(index.isClear(-5000, 0, 7000, 99999), true)
end)

Runner.test("a point exactly at the clearance distance is clear and a hair closer is not", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	Runner.expectEqual(isClearAt(CLEARANCE, queryArc), true)
	Runner.expectEqual(isClearAt(CLEARANCE - JUST_INSIDE, queryArc), false)
	Runner.expectEqual(isClearAt(0, queryArc), false)
end)

Runner.test("samples at exactly the near distance along the axis are neighbors, one step farther are not", function()
	Runner.expectEqual(isClearAt(1, NEAR_ARC), true)
	Runner.expectEqual(isClearAt(1, NEAR_ARC + STEP_STUDS), false)
end)

Runner.test("between the near and the neighbor distance a sample only has to be not crossed, not kept far", function()
	local queryArc = NEAR_ARC + STEP_STUDS
	Runner.expectEqual(isClearAt(NEAR_CLEARANCE, queryArc), true)
	Runner.expectEqual(isClearAt(NEAR_CLEARANCE - JUST_INSIDE, queryArc), false)
	Runner.expectEqual(isClearAt(NEAR_CLEARANCE, NEIGHBOR_ARC), true)
	Runner.expectEqual(isClearAt(NEAR_CLEARANCE, NEIGHBOR_ARC + STEP_STUDS), (NEAR_CLEARANCE >= CLEARANCE))
	Runner.expectEqual(isClearAt(0, NEIGHBOR_ARC), false)
end)

Runner.test(
	"samples farther along the axis than the lookback are not looked at, exactly at the lookback they are",
	function()
		Runner.expectEqual(isClearAt(1, LOOKBACK), false)
		Runner.expectEqual(isClearAt(1, LOOKBACK + STEP_STUDS), true)
	end
)

Runner.test("neighbors on the axis never count, however close they are", function()
	local index = LiveRoadIndex.new()
	for step = 0, NEAR_ARC // STEP_STUDS do
		index.add(step * STEP_STUDS, 0, 0, step * STEP_STUDS)
	end
	Runner.expectEqual(index.isClear(200, 0, 0, NEAR_ARC), true)
	Runner.expectEqual(index.isClear(200, 0, 0, NEAR_ARC + STEP_STUDS), true)
	Runner.expectEqual(index.isClear(0, 0, 0, NEAR_ARC + STEP_STUDS), false)
end)

Runner.test("a sample in a neighboring cell is found, also with negative coordinates and across the origin", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	local index = LiveRoadIndex.new()
	index.add(0.05, 0, 0.05, 0)
	Runner.expectEqual(index.isClear(-0.05, 0, -0.05, queryArc), false)
	local negative = LiveRoadIndex.new()
	negative.add(-CLEARANCE + 0.05, 0, -2 * CLEARANCE + 0.05, 0)
	Runner.expectEqual(negative.isClear(-CLEARANCE - 0.05, 0, -2 * CLEARANCE - 0.05, queryArc), false)
	Runner.expectEqual(negative.isClear(-CLEARANCE - 0.05, 0, -5 * CLEARANCE, queryArc), true)
end)

Runner.test("removing the newer samples brings back the answer they hid and leaves the older ones", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	index.add(10, 0, 0, 3000)
	index.add(20, 0, 0, 6000)
	Runner.expectEqual(index.getSampleCount(), 3)
	Runner.expectEqual(index.isClear(20, 0, 0, 7500), false)
	index.removeAfter(3000)
	Runner.expectEqual(index.getSampleCount(), 2)
	Runner.expectEqual(index.isClear(20, 0, 0, 7500), true)
	Runner.expectEqual(index.isClear(10, 0, 0, 4300), false)
	index.removeAfter(3000)
	Runner.expectEqual(index.getSampleCount(), 2)
	index.removeAfter(-1)
	Runner.expectEqual(index.getSampleCount(), 0)
	Runner.expectEqual(index.isClear(0, 0, 0, LOOKBACK), true)
	index.add(0, 0, 0, 0)
	Runner.expectEqual(index.getSampleCount(), 1)
	Runner.expectEqual(index.isClear(0, 0, 0, LOOKBACK), false)
end)

Runner.test(
	"a sample past the lookback is still kept for the backtrack and counts again when the road goes back",
	function()
		local index = LiveRoadIndex.new()
		index.add(0, 0, 0, 0)
		index.add(5000, 0, 5000, LOOKBACK + STEP_STUDS)
		Runner.expectEqual(index.getSampleCount(), 2)
		Runner.expectEqual(index.isClear(0, 0, 0, LOOKBACK + STEP_STUDS), true)
		index.removeAfter(LOOKBACK // 2)
		Runner.expectEqual(index.isClear(0, 0, 0, LOOKBACK // 2 + NEIGHBOR_ARC + STEP_STUDS), false)
	end
)

Runner.test("a sample older than the backtrack memory is forgotten", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	index.add(5000, 0, 5000, KEPT_ARC)
	Runner.expectEqual(index.getSampleCount(), 2)
	index.add(6000, 0, 6000, KEPT_ARC + STEP_STUDS)
	Runner.expectEqual(index.getSampleCount(), 2)
end)

Runner.test("a long road keeps a bounded number of samples and still answers right after the ring wraps", function()
	local index = LiveRoadIndex.new()
	local sampleCount = 4 * KEPT_ARC // STEP_STUDS
	for step = 0, sampleCount do
		index.add(step * STEP_STUDS, 0, 0, step * STEP_STUDS)
		Runner.expectEqual(index.getSampleCount() <= KEPT_ARC // STEP_STUDS + 1, true)
	end
	local lastArc = sampleCount * STEP_STUDS
	Runner.expectEqual(index.isClear(lastArc - LOOKBACK, 0, 0, lastArc), false)
	Runner.expectEqual(index.isClear(lastArc - LOOKBACK, 0, CLEARANCE, lastArc), true)
	Runner.expectEqual(index.isClear(lastArc, 0, 0, lastArc), true)
	Runner.expectEqual(index.isClear(0, 0, 0, lastArc), true)
end)

Runner.test("it answers like a search over every sample, on a scattered road", function()
	local random = SeededRandom.new(11)
	local index = LiveRoadIndex.new()
	local xs, zs, arcs = {}, {}, {}
	for id = 1, RANDOM_SAMPLES do
		xs[id], zs[id], arcs[id] =
			random.nextNumber() * AREA_STUDS, random.nextNumber() * AREA_STUDS, (id - 1) * ARC_SPACING_STUDS
		index.add(xs[id], 0, zs[id], arcs[id])
	end
	local clearCount = 0
	for _ = 1, RANDOM_QUERIES do
		local x, z = random.nextNumber() * AREA_STUDS, random.nextNumber() * AREA_STUDS
		local arc = RANDOM_SAMPLES * ARC_SPACING_STUDS + random.nextInteger(0, LOOKBACK)
		local expected = true
		for id = 1, RANDOM_SAMPLES do
			local arcDifference = arc - arcs[id]
			if arcDifference > NEAR_ARC and arcDifference <= LOOKBACK then
				local required = if arcDifference <= NEIGHBOR_ARC then NEAR_CLEARANCE else CLEARANCE
				expected = expected and (x - xs[id]) ^ 2 + (z - zs[id]) ^ 2 >= required ^ 2
			end
		end
		Runner.expectEqual(index.isClear(x, 0, z, arc), expected)
		clearCount += if expected then 1 else 0
	end
	Runner.expectEqual(clearCount > 0 and clearCount < RANDOM_QUERIES, true)
end)

-- Regla de altura: la diferencia que admite el terreno a esa distancia entre ejes.
local function getAllowedRise(distance: number): number
	local slope = math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES - WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES)
	return math.tan(slope) * math.max(0, distance - ROAD_AND_SHOULDERS)
end

-- Una muestra en el origen a altura 0 y una consulta a `distance` y `rise` más arriba (o más abajo si es negativa).
local function isClearAtRise(distance: number, rise: number, queryArc: number): boolean
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	return index.isClear(distance, rise, 0, queryArc)
end

Runner.test("two passes can differ in height by what the terrain climbs between their shoulders, no more", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	for _, distance in { CLEARANCE, 80, 120, HEIGHT_RADIUS - 1 } do
		local allowed = getAllowedRise(distance)
		Runner.expectEqual(isClearAtRise(distance, allowed - JUST_INSIDE, queryArc), true)
		Runner.expectEqual(isClearAtRise(distance, allowed + JUST_INSIDE, queryArc), false)
		Runner.expectEqual(isClearAtRise(distance, -allowed + JUST_INSIDE, queryArc), true)
		Runner.expectEqual(isClearAtRise(distance, -allowed - JUST_INSIDE, queryArc), false)
	end
end)

Runner.test("the height rule also applies to the near distance, where passes may be much closer", function()
	local queryArc = NEAR_ARC + STEP_STUDS
	local allowed = getAllowedRise(NEAR_CLEARANCE)
	Runner.expectEqual(allowed > 0 and allowed < ROAD_AND_SHOULDERS, true)
	Runner.expectEqual(isClearAtRise(NEAR_CLEARANCE, allowed - JUST_INSIDE, queryArc), true)
	Runner.expectEqual(isClearAtRise(NEAR_CLEARANCE, allowed + JUST_INSIDE, queryArc), false)
end)

Runner.test("the height rule does not apply from the radius on, nor to neighbors, nor past the lookback", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	local hugeRise = 1e6
	Runner.expectEqual(isClearAtRise(HEIGHT_RADIUS, hugeRise, queryArc), true)
	Runner.expectEqual(isClearAtRise(HEIGHT_RADIUS - JUST_INSIDE, hugeRise, queryArc), false)
	Runner.expectEqual(isClearAtRise(NEAR_CLEARANCE, hugeRise, NEAR_ARC), true)
	Runner.expectEqual(isClearAtRise(NEAR_CLEARANCE, hugeRise, LOOKBACK + STEP_STUDS), true)
	Runner.expectEqual(isClearAtRise(NEAR_CLEARANCE, hugeRise, LOOKBACK), false)
end)

Runner.test("a sample far away in the plane but inside the radius is found across several cells", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	local distance = HEIGHT_RADIUS - 1
	Runner.expectEqual(index.isClear(-distance, getAllowedRise(distance) + 1, 0, queryArc), false)
	Runner.expectEqual(index.isClear(0, getAllowedRise(distance) + 1, -distance, queryArc), false)
	Runner.expectEqual(index.isClear(-distance, getAllowedRise(distance) - 1, 0, queryArc), true)
end)

Runner.test("removing the newer samples also brings back the answer of the height rule", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0, 0)
	index.add(100, 200, 0, 3000)
	local queryArc = 3000 + NEIGHBOR_ARC + STEP_STUDS
	Runner.expectEqual(index.isClear(100, 0, 100, queryArc), false)
	index.removeAfter(0)
	Runner.expectEqual(index.isClear(100, 0, 100, queryArc), true)
end)

Runner.test("it answers both rules like a search over every sample, on a crowded and hilly road", function()
	local random = SeededRandom.new(23)
	local index = LiveRoadIndex.new()
	local xs, ys, zs, arcs = {}, {}, {}, {}
	for id = 1, RANDOM_SAMPLES do
		xs[id], ys[id], zs[id] =
			random.nextNumber() * CROWDED_AREA_STUDS,
			random.nextNumber() * MAX_HEIGHT_STUDS,
			random.nextNumber() * CROWDED_AREA_STUDS
		arcs[id] = (id - 1) * ARC_SPACING_STUDS
		index.add(xs[id], ys[id], zs[id], arcs[id])
	end
	local clearCount = 0
	for _ = 1, RANDOM_QUERIES do
		local x, y, z =
			random.nextNumber() * CROWDED_AREA_STUDS,
			random.nextNumber() * MAX_HEIGHT_STUDS,
			random.nextNumber() * CROWDED_AREA_STUDS
		local arc = RANDOM_SAMPLES * ARC_SPACING_STUDS + random.nextInteger(0, LOOKBACK)
		local expected = true
		for id = 1, RANDOM_SAMPLES do
			local arcDifference = arc - arcs[id]
			if arcDifference > NEAR_ARC and arcDifference <= LOOKBACK then
				local required = if arcDifference <= NEIGHBOR_ARC then NEAR_CLEARANCE else CLEARANCE
				local distance = math.sqrt((x - xs[id]) ^ 2 + (z - zs[id]) ^ 2)
				local isHigh = distance < HEIGHT_RADIUS and math.abs(y - ys[id]) > getAllowedRise(distance)
				expected = expected and distance >= required and not isHigh
			end
		end
		Runner.expectEqual(index.isClear(x, y, z, arc), expected)
		clearCount += if expected then 1 else 0
	end
	Runner.expectEqual(clearCount > RANDOM_QUERIES / 10 and clearCount < RANDOM_QUERIES * 9 / 10, true)
end)

Runner.test("asking again from the same place sees the samples added and removed in between", function()
	local index = LiveRoadIndex.new()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	Runner.expectEqual(index.isClear(10, 0, 10, queryArc), true)
	index.add(10, 0, 10, 0)
	Runner.expectEqual(index.isClear(10, 0, 10, queryArc), false)
	Runner.expectEqual(index.isClear(11, 0, 10, queryArc), false)
	index.removeAfter(-1)
	Runner.expectEqual(index.isClear(10, 0, 10, queryArc), true)
	index.add(10, 0, 10, 0)
	Runner.expectEqual(index.isClear(10, 0, 10, queryArc), false)
end)

Runner.test("a cell that emptied out and came back is found again by the same query", function()
	local index = LiveRoadIndex.new()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	index.add(0, 0, 0, 0)
	Runner.expectEqual(index.isClear(0, 0, 0, queryArc), false)
	index.removeAfter(-1)
	Runner.expectEqual(index.isClear(0, 0, 0, queryArc), true)
	index.add(0, 0, 0, 0)
	index.add(0, 0, 0, STEP_STUDS)
	Runner.expectEqual(index.isClear(0, 0, 0, queryArc), false)
end)

-- Una ruta en zigzag de pasos de un paso de integración, con lomas: tramos paralelos separados `legSpacing` que se unen en las
-- puntas. Es lo que permite saltear muestras seguidas.
local function createZigzag(legSpacing: number, legCount: number): ({ number }, { number }, { number }, { number })
	local xs, ys, zs, arcs = {}, {}, {}, {}
	local x, z, direction = 0, 0, 1
	for _ = 1, legCount do
		for _ = 1, ZIGZAG_LEG_STUDS // STEP_STUDS do
			x += direction * STEP_STUDS
			table.insert(xs, x)
			table.insert(zs, z)
		end
		for _ = 1, legSpacing // STEP_STUDS do
			z += STEP_STUDS
			table.insert(xs, x)
			table.insert(zs, z)
		end
		direction = -direction
	end
	for id = 1, #xs do
		arcs[id] = id * STEP_STUDS
		ys[id] = ZIGZAG_BASE_HEIGHT_STUDS + ZIGZAG_HILL_STUDS * math.sin(arcs[id] / ZIGZAG_HILL_WAVELENGTH_STUDS)
	end
	return xs, ys, zs, arcs
end

Runner.test("skipping samples along a continuous road never changes the answer", function()
	local random = SeededRandom.new(31)
	local clearCount, queryCount = 0, 0
	for _, legSpacing in { 40, 100, 160 } do
		local xs, ys, zs, arcs = createZigzag(legSpacing, ZIGZAG_LEGS)
		local index = LiveRoadIndex.new()
		for id = 1, #xs do
			index.add(xs[id], ys[id], zs[id], arcs[id])
		end
		local lastArc = arcs[#arcs]
		for _ = 1, ZIGZAG_QUERIES do
			local x = random.nextNumber() * ZIGZAG_LEG_STUDS
			local z = random.nextNumber() * legSpacing * ZIGZAG_LEGS
			local y = ZIGZAG_BASE_HEIGHT_STUDS + (random.nextNumber() * 2 - 1) * ZIGZAG_HILL_STUDS * 2
			local arc = lastArc + STEP_STUDS * random.nextInteger(0, LOOKBACK // STEP_STUDS)
			local expected = true
			for id = 1, #xs do
				local arcDifference = arc - arcs[id]
				if arcDifference > NEAR_ARC and arcDifference <= LOOKBACK then
					local required = if arcDifference <= NEIGHBOR_ARC then NEAR_CLEARANCE else CLEARANCE
					local distance = math.sqrt((x - xs[id]) ^ 2 + (z - zs[id]) ^ 2)
					local isHigh = distance < HEIGHT_RADIUS and math.abs(y - ys[id]) > getAllowedRise(distance)
					expected = expected and distance >= required and not isHigh
				end
			end
			Runner.expectEqual(index.isClear(x, y, z, arc), expected)
			queryCount += 1
			clearCount += if expected then 1 else 0
		end
	end
	Runner.expectEqual(clearCount > queryCount / 20 and clearCount < queryCount * 19 / 20, true)
end)

Runner.test("a jump in the road stops the skipping, so a sample after it is still found", function()
	local index = LiveRoadIndex.new()
	for step = 0, 99 do
		index.add(step * STEP_STUDS, 0, 0, step * STEP_STUDS)
	end
	index.add(5000, 0, 0, 100 * STEP_STUDS)
	for step = 101, 200 do
		index.add(5000 + (step - 100) * STEP_STUDS, 0, 0, step * STEP_STUDS)
	end
	local queryArc = 200 * STEP_STUDS + NEIGHBOR_ARC
	Runner.expectEqual(index.isClear(5001, 0, 0, queryArc), false)
	Runner.expectEqual(index.isClear(5001, 0, 2 * CLEARANCE, queryArc), true)
	Runner.expectEqual(index.isClear(150, 0, 0, queryArc), false)
end)

Runner.finish()
