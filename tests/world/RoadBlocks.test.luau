--!strict
local PathHelpers = require("./PathHelpers")
local RoadBlockNearest = require("../../src/world/core/RoadBlockNearest")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local SyntheticRoad = require("./SyntheticRoad")
local WorldConfig = require("../../src/world/core/WorldConfig")

local BLOCK_STEPS = WorldConfig.TERRAIN_ROAD_BLOCK_STEPS
local BLOCKS_PER_SEGMENT = SyntheticRoad.STEPS_PER_SEGMENT // BLOCK_STEPS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local REAL_SEEDS = { 3, 77, 1234 }
local REAL_SEGMENTS = 14
local QUERIES_PER_SEED = 1500
local QUERY_RANGE_STUDS = 150
local TOLERANCE_STUDS = 1e-6
-- Cerca del eje la bisección acierta con milímetros de diferencia; lejos, en el centro de una curva cerrada, puede equivocarse
-- por varios studs, y ahí la altura no usa el arco (ver TerrainHeightField).
local NEAR_FIELD_STUDS = 30
local NEAR_FIELD_TOLERANCE_STUDS = 0.01
local MIN_NEAR_FIELD_QUERIES = 300
local HEIGHT_PER_STEP = 0.25
local HUGE_STUDS = 1e6

local function createStraightSegments(firstIndex: number, count: number): { RoadPath.Segment }
	return SyntheticRoad.createSegments({
		segmentCount = count,
		firstSegmentIndex = firstIndex,
		startX = firstIndex * SyntheticRoad.STEPS_PER_SEGMENT * STEP_STUDS,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function(step: number)
			return step * HEIGHT_PER_STEP
		end,
	})
end

local function addAll(blocks: RoadBlocks.RoadBlocks, segments: { RoadPath.Segment })
	for _, segment in segments do
		blocks.addSegment(segment)
	end
end

-- Distancia y altura del punto más cercano de un bloque, probando todas las aristas.
local function findNearestByBruteForce(block: RoadBlocks.RoadBlock, x: number, z: number): (number, number)
	local bestDistance, bestHeight = math.huge, 0
	for edge = 1, #block.edgeX do
		local ex, ez = block.edgeX[edge], block.edgeZ[edge]
		local fraction = math.clamp(((x - block.xs[edge]) * ex + (z - block.zs[edge]) * ez) / (ex * ex + ez * ez), 0, 1)
		local offsetX, offsetZ = x - (block.xs[edge] + ex * fraction), z - (block.zs[edge] + ez * fraction)
		local distance = math.sqrt(offsetX * offsetX + offsetZ * offsetZ)
		if distance < bestDistance then
			bestDistance = distance
			bestHeight = block.ys[edge] + (block.ys[edge + 1] - block.ys[edge]) * fraction
		end
	end
	return bestDistance, bestHeight
end

Runner.test("a segment becomes consecutive blocks that cover it point by point", function()
	local blocks = RoadBlocks.new()
	local segments = createStraightSegments(0, 1)
	blocks.addSegment(segments[1])
	local gathered = blocks.gather(-10, -10, 1000, 10, 0.5)
	Runner.expectEqual(#gathered, BLOCKS_PER_SEGMENT)
	for blockNumber, block in gathered do
		Runner.expectEqual(block.index, blockNumber - 1)
		Runner.expectEqual(#block.xs, BLOCK_STEPS + 1)
		Runner.expectEqual(#block.edgeX, BLOCK_STEPS)
		local firstSample = segments[1].samples[(blockNumber - 1) * BLOCK_STEPS + 1]
		Runner.expectEqual(block.xs[1], firstSample.position.x)
		Runner.expectEqual(block.ys[1], firstSample.position.y)
		Runner.expectEqual(block.minX, block.xs[1])
		Runner.expectEqual(block.maxX, block.xs[BLOCK_STEPS + 1])
	end
end)

Runner.test("gather returns only the blocks whose box is within reach of the area, in index order", function()
	local blocks = RoadBlocks.new()
	addAll(blocks, createStraightSegments(0, 4))
	local inside = blocks.gather(300, -5, 340, 5, 0.5)
	Runner.expectEqual(#inside, 2)
	Runner.expectEqual(inside[1].index + 1, inside[2].index)
	local withReach = blocks.gather(300, 100, 340, 120, 100.1)
	Runner.expectEqual(#withReach, 2)
	Runner.expectEqual(#blocks.gather(300, 100, 340, 120, 100), 0)
	Runner.expectEqual(#blocks.gather(-1000, -5, -900, 5, 50), 0)
end)

Runner.test("forgetBefore drops the blocks of the released segments and keeps the rest", function()
	local blocks = RoadBlocks.new()
	addAll(blocks, createStraightSegments(0, 4))
	local all = #blocks.gather(-10, -10, 10000, 10, 1)
	blocks.forgetBefore(2)
	local kept = blocks.gather(-10, -10, 10000, 10, 1)
	Runner.expectEqual(all, 4 * BLOCKS_PER_SEGMENT)
	Runner.expectEqual(#kept, 2 * BLOCKS_PER_SEGMENT)
	Runner.expectEqual(kept[1].index, 2 * BLOCKS_PER_SEGMENT)
	blocks.forgetBefore(100)
	Runner.expectEqual(#blocks.gather(-10, -10, 10000, 10, 1), 0)
	blocks.forgetBefore(1)
	Runner.expectEqual(#blocks.gather(-10, -10, 10000, 10, 1), 0)
end)

Runner.test("segments can start at any index, and arriving out of order is an error", function()
	local blocks = RoadBlocks.new()
	addAll(blocks, createStraightSegments(5, 2))
	Runner.expectEqual(blocks.gather(-HUGE_STUDS, -10, HUGE_STUDS, 10, 1)[1].index, 5 * BLOCKS_PER_SEGMENT)
	Runner.expectError(function()
		blocks.addSegment(createStraightSegments(9, 1)[1])
	end)
	Runner.expectError(function()
		blocks.addSegment(createStraightSegments(6, 1)[1])
	end)
end)

Runner.test("the signature changes when a block enters or leaves the area and is the same otherwise", function()
	local blocks = RoadBlocks.new()
	addAll(blocks, createStraightSegments(0, 3))
	local before = blocks.getSignature(100, -5, 140, 5, 20)
	local _, gatheredSignature = blocks.gather(100, -5, 140, 5, 20)
	Runner.expectEqual(gatheredSignature, before)
	Runner.expectEqual(blocks.getSignature(100, -5, 140, 5, 20), before)
	blocks.forgetBefore(1)
	Runner.expectEqual(blocks.getSignature(100, -5, 140, 5, 20) ~= before, true)
	Runner.expectEqual(blocks.getSignature(-HUGE_STUDS, HUGE_STUDS, -HUGE_STUDS, HUGE_STUDS, 1), 0)
end)

Runner.test("the bisection finds the same nearest point as trying every edge, on real routes", function()
	local random = SeededRandom.new(8)
	local compared = 0
	for _, seed in REAL_SEEDS do
		local path = RoadPath.new(seed)
		local blocks = RoadBlocks.new()
		addAll(blocks, PathHelpers.generateSegments(path, REAL_SEGMENTS))
		local all = blocks.gather(-HUGE_STUDS, -HUGE_STUDS, HUGE_STUDS, HUGE_STUDS, 1)
		for _ = 1, QUERIES_PER_SEED do
			local block = all[random.nextInteger(1, #all)]
			local edge = random.nextInteger(1, BLOCK_STEPS)
			local x = block.xs[edge] + (random.nextNumber() - 0.5) * 2 * QUERY_RANGE_STUDS
			local z = block.zs[edge] + (random.nextNumber() - 0.5) * 2 * QUERY_RANGE_STUDS
			local distance, height = RoadBlockNearest.find(block, x, z)
			local expectedDistance, expectedHeight = findNearestByBruteForce(block, x, z)
			if expectedDistance < NEAR_FIELD_STUDS then
				compared += 1
				Runner.expectNear(distance, expectedDistance, NEAR_FIELD_TOLERANCE_STUDS)
				Runner.expectNear(height, expectedHeight, NEAR_FIELD_TOLERANCE_STUDS * 5)
			end
		end
	end
	Runner.expectEqual(compared > MIN_NEAR_FIELD_QUERIES, true)
end)

Runner.test("a point on the axis is at distance zero with the height of the axis, and the ends clamp", function()
	local blocks = RoadBlocks.new()
	addAll(blocks, createStraightSegments(0, 1))
	local block = blocks.gather(0, -1, 10, 1, 0.5)[1]
	local distance, height = RoadBlockNearest.find(block, 20, 0)
	Runner.expectNear(distance, 0, TOLERANCE_STUDS)
	Runner.expectNear(height, 20 / STEP_STUDS * HEIGHT_PER_STEP, 1e-4)
	local beforeStart, beforeStartHeight = RoadBlockNearest.find(block, -30, 40)
	Runner.expectNear(beforeStart, 50, TOLERANCE_STUDS)
	Runner.expectNear(beforeStartHeight, block.ys[1], TOLERANCE_STUDS)
	local pastEnd, pastEndHeight = RoadBlockNearest.find(block, block.maxX + 30, -40)
	Runner.expectNear(pastEnd, 50, TOLERANCE_STUDS)
	Runner.expectNear(pastEndHeight, block.ys[BLOCK_STEPS + 1], TOLERANCE_STUDS)
end)

Runner.test("against the chord a straight block gives what the arc gives and a curved one stays close", function()
	local random = SeededRandom.new(12)
	local straight = RoadBlocks.new()
	addAll(straight, createStraightSegments(0, 1))
	local block = straight.gather(0, -1, 10, 1, 0.5)[1]
	for _ = 1, 200 do
		local x, z = random.nextNumber() * 120, (random.nextNumber() - 0.5) * 200
		local arcDistance, arcHeight = RoadBlockNearest.find(block, x, z)
		local chordDistance, chordHeight = RoadBlockNearest.findAlongChord(block, x, z)
		Runner.expectNear(chordDistance, arcDistance, 1e-6)
		Runner.expectNear(chordHeight, arcHeight, 1e-4)
	end
	local curved = RoadBlocks.new()
	addAll(
		curved,
		SyntheticRoad.createSegments({
			segmentCount = 1,
			startX = 0,
			startZ = 0,
			startHeadingRadians = 0,
			curvatureAt = function()
				return 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS
			end,
			heightAt = function()
				return 0
			end,
		})
	)
	local curvedBlock = curved.gather(-1e4, -1e4, 1e4, 1e4, 1)[1]
	local halfArcRadians = BLOCK_STEPS * STEP_STUDS / WorldConfig.MIN_CURVE_RADIUS_STUDS / 2
	local sagitta = WorldConfig.MIN_CURVE_RADIUS_STUDS * (1 - math.cos(halfArcRadians))
	for _ = 1, 200 do
		local x, z = random.nextNumber() * 80, random.nextNumber() * 80 - 20
		local arcDistance = RoadBlockNearest.find(curvedBlock, x, z)
		local chordDistance = RoadBlockNearest.findAlongChord(curvedBlock, x, z)
		Runner.expectEqual(math.abs(arcDistance - chordDistance) <= sagitta + 1e-6, true)
	end
end)

Runner.finish()
