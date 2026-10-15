--!strict
local LiveRoadIndex = require("../../src/world/core/LiveRoadIndex")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CLEARANCE = WorldConfig.LIVE_CLEARANCE_STUDS
local NEIGHBOR_ARC = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local LOOKBACK = WorldConfig.LIVE_LOOKBACK_STUDS
local KEPT_ARC = LOOKBACK + WorldConfig.LIVE_BACKTRACK_MEMORY_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local JUST_INSIDE = 1e-6
local RANDOM_SAMPLES = 300
local ARC_SPACING_STUDS = 20
local RANDOM_QUERIES = 600
local AREA_STUDS = 2500

-- Una muestra en el origen con arcLength 0 y una consulta lejos de ahí en arcLength, a `distance` de la muestra.
local function isClearAt(distance: number, queryArc: number): boolean
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0)
	return index.isClear(distance, 0, queryArc)
end

Runner.test("an empty index is clear everywhere", function()
	local index = LiveRoadIndex.new()
	Runner.expectEqual(index.getSampleCount(), 0)
	Runner.expectEqual(index.isClear(0, 0, 0), true)
	Runner.expectEqual(index.isClear(-5000, 7000, 99999), true)
end)

Runner.test("a point exactly at the clearance distance is clear and a hair closer is not", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	Runner.expectEqual(isClearAt(CLEARANCE, queryArc), true)
	Runner.expectEqual(isClearAt(CLEARANCE - JUST_INSIDE, queryArc), false)
	Runner.expectEqual(isClearAt(0, queryArc), false)
end)

Runner.test(
	"samples at exactly the neighbor distance along the axis are neighbors, one step farther are not",
	function()
		Runner.expectEqual(isClearAt(1, NEIGHBOR_ARC), true)
		Runner.expectEqual(isClearAt(1, NEIGHBOR_ARC + STEP_STUDS), false)
	end
)

Runner.test(
	"samples farther along the axis than the lookback are not looked at, exactly at the lookback they are",
	function()
		Runner.expectEqual(isClearAt(1, LOOKBACK), false)
		Runner.expectEqual(isClearAt(1, LOOKBACK + STEP_STUDS), true)
	end
)

Runner.test("neighbors on the axis never count, however close they are", function()
	local index = LiveRoadIndex.new()
	for step = 0, NEIGHBOR_ARC // STEP_STUDS do
		index.add(step * STEP_STUDS, 0, step * STEP_STUDS)
	end
	Runner.expectEqual(index.isClear(600, 0, NEIGHBOR_ARC), true)
	Runner.expectEqual(index.isClear(600, 0, NEIGHBOR_ARC + STEP_STUDS), true)
	Runner.expectEqual(index.isClear(0, 0, NEIGHBOR_ARC + STEP_STUDS), false)
end)

Runner.test("a sample in a neighboring cell is found, also with negative coordinates and across the origin", function()
	local queryArc = NEIGHBOR_ARC + STEP_STUDS
	local index = LiveRoadIndex.new()
	index.add(0.05, 0.05, 0)
	Runner.expectEqual(index.isClear(-0.05, -0.05, queryArc), false)
	local negative = LiveRoadIndex.new()
	negative.add(-CLEARANCE + 0.05, -2 * CLEARANCE + 0.05, 0)
	Runner.expectEqual(negative.isClear(-CLEARANCE - 0.05, -2 * CLEARANCE - 0.05, queryArc), false)
	Runner.expectEqual(negative.isClear(-CLEARANCE - 0.05, -5 * CLEARANCE, queryArc), true)
end)

Runner.test("removing the newer samples brings back the answer they hid and leaves the older ones", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0)
	index.add(10, 0, 3000)
	index.add(20, 0, 6000)
	Runner.expectEqual(index.getSampleCount(), 3)
	Runner.expectEqual(index.isClear(20, 0, 7500), false)
	index.removeAfter(3000)
	Runner.expectEqual(index.getSampleCount(), 2)
	Runner.expectEqual(index.isClear(20, 0, 7500), true)
	Runner.expectEqual(index.isClear(10, 0, 4300), false)
	index.removeAfter(3000)
	Runner.expectEqual(index.getSampleCount(), 2)
	index.removeAfter(-1)
	Runner.expectEqual(index.getSampleCount(), 0)
	Runner.expectEqual(index.isClear(0, 0, LOOKBACK), true)
	index.add(0, 0, 0)
	Runner.expectEqual(index.getSampleCount(), 1)
	Runner.expectEqual(index.isClear(0, 0, LOOKBACK), false)
end)

Runner.test(
	"a sample past the lookback is still kept for the backtrack and counts again when the road goes back",
	function()
		local index = LiveRoadIndex.new()
		index.add(0, 0, 0)
		index.add(5000, 5000, LOOKBACK + STEP_STUDS)
		Runner.expectEqual(index.getSampleCount(), 2)
		Runner.expectEqual(index.isClear(0, 0, LOOKBACK + STEP_STUDS), true)
		index.removeAfter(LOOKBACK // 2)
		Runner.expectEqual(index.isClear(0, 0, LOOKBACK // 2 + NEIGHBOR_ARC + STEP_STUDS), false)
	end
)

Runner.test("a sample older than the backtrack memory is forgotten", function()
	local index = LiveRoadIndex.new()
	index.add(0, 0, 0)
	index.add(5000, 5000, KEPT_ARC)
	Runner.expectEqual(index.getSampleCount(), 2)
	index.add(6000, 6000, KEPT_ARC + STEP_STUDS)
	Runner.expectEqual(index.getSampleCount(), 2)
end)

Runner.test("a long road keeps a bounded number of samples and still answers right after the ring wraps", function()
	local index = LiveRoadIndex.new()
	local sampleCount = 4 * KEPT_ARC // STEP_STUDS
	for step = 0, sampleCount do
		index.add(step * STEP_STUDS, 0, step * STEP_STUDS)
		Runner.expectEqual(index.getSampleCount() <= KEPT_ARC // STEP_STUDS + 1, true)
	end
	local lastArc = sampleCount * STEP_STUDS
	Runner.expectEqual(index.isClear(lastArc - LOOKBACK, 0, lastArc), false)
	Runner.expectEqual(index.isClear(lastArc - LOOKBACK, CLEARANCE, lastArc), true)
	Runner.expectEqual(index.isClear(lastArc, 0, lastArc), true)
	Runner.expectEqual(index.isClear(0, 0, lastArc), true)
end)

Runner.test("it answers like a search over every sample, on a scattered road", function()
	local random = SeededRandom.new(11)
	local index = LiveRoadIndex.new()
	local xs, zs, arcs = {}, {}, {}
	for id = 1, RANDOM_SAMPLES do
		xs[id], zs[id], arcs[id] =
			random.nextNumber() * AREA_STUDS, random.nextNumber() * AREA_STUDS, (id - 1) * ARC_SPACING_STUDS
		index.add(xs[id], zs[id], arcs[id])
	end
	local clearCount = 0
	for _ = 1, RANDOM_QUERIES do
		local x, z = random.nextNumber() * AREA_STUDS, random.nextNumber() * AREA_STUDS
		local arc = RANDOM_SAMPLES * ARC_SPACING_STUDS + random.nextInteger(0, LOOKBACK)
		local expected = true
		for id = 1, RANDOM_SAMPLES do
			local arcDifference = arc - arcs[id]
			if arcDifference > NEIGHBOR_ARC and arcDifference <= LOOKBACK then
				expected = expected and (x - xs[id]) ^ 2 + (z - zs[id]) ^ 2 >= CLEARANCE ^ 2
			end
		end
		Runner.expectEqual(index.isClear(x, z, arc), expected)
		clearCount += if expected then 1 else 0
	end
	Runner.expectEqual(clearCount > 0 and clearCount < RANDOM_QUERIES, true)
end)

Runner.finish()
