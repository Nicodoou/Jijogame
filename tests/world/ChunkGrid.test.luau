--!strict
local ChunkGrid = require("../../src/world/core/ChunkGrid")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CHUNK = WorldConfig.CHUNK_SIZE_STUDS
local KEY_RANGE = 70
local JUST_BELOW = 0.001

Runner.test("the coordinate of a chunk rounds down, also for negative studs and the exact borders", function()
	Runner.expectEqual(ChunkGrid.getCoordinate(0), 0)
	Runner.expectEqual(ChunkGrid.getCoordinate(CHUNK - JUST_BELOW), 0)
	Runner.expectEqual(ChunkGrid.getCoordinate(CHUNK), 1)
	Runner.expectEqual(ChunkGrid.getCoordinate(-JUST_BELOW), -1)
	Runner.expectEqual(ChunkGrid.getCoordinate(-CHUNK), -1)
	Runner.expectEqual(ChunkGrid.getCoordinate(-CHUNK - JUST_BELOW), -2)
end)

Runner.test("the origin of a chunk is its first stud", function()
	for coordinate = -5, 5 do
		Runner.expectEqual(ChunkGrid.getCoordinate(ChunkGrid.getOriginStuds(coordinate)), coordinate)
		Runner.expectEqual(ChunkGrid.getCoordinate(ChunkGrid.getOriginStuds(coordinate) - JUST_BELOW), coordinate - 1)
	end
end)

Runner.test("every chunk of a square of the world has its own key", function()
	local seen: { [number]: boolean } = {}
	for chunkX = -KEY_RANGE, KEY_RANGE do
		for chunkZ = -KEY_RANGE, KEY_RANGE do
			local key = ChunkGrid.getKey(chunkX, chunkZ)
			Runner.expectEqual(seen[key], nil)
			seen[key] = true
		end
	end
end)

Runner.test(
	"the distance to a chunk is zero inside it and the distance to its nearest border or corner outside",
	function()
		Runner.expectEqual(ChunkGrid.getDistanceToChunk(0, 0, 10, 10), 0)
		Runner.expectEqual(ChunkGrid.getDistanceToChunk(0, 0, 0, CHUNK), 0)
		Runner.expectEqual(ChunkGrid.getDistanceToChunk(0, 0, CHUNK + 30, 50), 30)
		Runner.expectEqual(ChunkGrid.getDistanceToChunk(0, 0, 50, -40), 40)
		Runner.expectNear(ChunkGrid.getDistanceToChunk(0, 0, -30, -40), 50, 1e-9)
		Runner.expectNear(ChunkGrid.getDistanceToChunk(-1, 2, 20, 20), math.sqrt(20 ^ 2 + (2 * CHUNK - 20) ^ 2), 1e-9)
	end
)

Runner.finish()
