--!strict
local ChunkCorridor = require("../../src/world/core/ChunkCorridor")
local ChunkGrid = require("../../src/world/core/ChunkGrid")
local RoadWindow = require("../../src/world/core/RoadWindow")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local WorldConfig = require("../../src/world/core/WorldConfig")

local AHEAD_STUDS = 1000
local MEMORY_STUDS = 2000
local SEGMENTS = 12
local ROAD_Z = 40
local HALF_WIDTH = 100

-- Un camino recto hacia +x a z = ROAD_Z.
local function createWindow(): RoadWindow.RoadWindow
	local path = SyntheticRoad.createPath(SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		startX = 0,
		startZ = ROAD_Z,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return 50
		end,
	}))
	local window = RoadWindow.new(path, AHEAD_STUDS, MEMORY_STUDS)
	for _ = 1, SEGMENTS do
		window.extend()
	end
	return window
end

Runner.test("a straight road touches exactly the chunks within the half width of its axis", function()
	local window = createWindow()
	local cells = ChunkCorridor.collect(window, 0, 1000, HALF_WIDTH)
	-- El eje va de x = 0 a 992 (el último punto cada 32 studs) en z = 40: en z toca los chunks -1, 0 y 1, y en x del -1 al 8.
	local count = 0
	for _ in cells do
		count += 1
	end
	Runner.expectEqual(count, 10 * 3)
	for chunkX = -2, 9 do
		for chunkZ = -3, 3 do
			local isExpected = chunkX >= -1 and chunkX <= 8 and chunkZ >= -1 and chunkZ <= 1
			Runner.expectEqual(cells[ChunkGrid.getKey(chunkX, chunkZ)] ~= nil, isExpected)
		end
	end
end)

Runner.test("each cell knows its chunk and its key", function()
	local window = createWindow()
	for key, cell in ChunkCorridor.collect(window, 100, 600, HALF_WIDTH) do
		Runner.expectEqual(cell.key, key)
		Runner.expectEqual(ChunkGrid.getKey(cell.chunkX, cell.chunkZ), key)
	end
end)

Runner.test(
	"every chunk of the corridor is within the half width of some sampled point and every such chunk is in it",
	function()
		local window = createWindow()
		local points: { { number } } = {}
		window.forEachAxisPoint(200, 900, WorldConfig.TERRAIN_CORRIDOR_SAMPLE_STUDS, function(x, z)
			table.insert(points, { x, z })
		end)
		local cells = ChunkCorridor.collect(window, 200, 900, HALF_WIDTH)
		for chunkX = -2, 10 do
			for chunkZ = -3, 4 do
				local isNear = false
				for _, point in points do
					isNear = isNear or ChunkGrid.getDistanceToChunk(chunkX, chunkZ, point[1], point[2]) <= HALF_WIDTH
				end
				Runner.expectEqual(cells[ChunkGrid.getKey(chunkX, chunkZ)] ~= nil, isNear)
			end
		end
	end
)

Runner.test("a wider corridor contains the narrower one, and an arc range with no road gives no chunks", function()
	local window = createWindow()
	local narrow = ChunkCorridor.collect(window, 100, 800, HALF_WIDTH)
	local wide = ChunkCorridor.collect(window, 100, 800, HALF_WIDTH + 64)
	local narrowCount, wideCount = 0, 0
	for key in narrow do
		narrowCount += 1
		Runner.expectEqual(wide[key] ~= nil, true)
	end
	for _ in wide do
		wideCount += 1
	end
	Runner.expectEqual(wideCount >= narrowCount, true)
	local none = ChunkCorridor.collect(window, 90000, 91000, HALF_WIDTH)
	Runner.expectEqual(next(none), nil)
	local reversed = ChunkCorridor.collect(window, 800, 100, HALF_WIDTH)
	Runner.expectEqual(next(reversed), nil)
end)

Runner.finish()
