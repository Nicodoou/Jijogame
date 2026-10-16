--!strict
local Runner = require("../Runner")
local TerrainWindow = require("../../src/world/core/TerrainWindow")
local WorldConfig = require("../../src/world/core/WorldConfig")

Runner.test(
	"what is kept is wider and longer than what is wanted, and the road blocks remember more than both",
	function()
		Runner.expectEqual(TerrainWindow.KEPT_HALF_WIDTH_STUDS > TerrainWindow.WANTED_HALF_WIDTH_STUDS, true)
		Runner.expectEqual(TerrainWindow.KEPT_BEHIND_STUDS > TerrainWindow.WANTED_BEHIND_STUDS, true)
		Runner.expectEqual(TerrainWindow.BLOCK_MEMORY_STUDS > TerrainWindow.KEPT_BEHIND_STUDS, true)
		Runner.expectEqual(TerrainWindow.WANTED_BEHIND_STUDS, WorldConfig.TERRAIN_BEHIND_STUDS)
		Runner.expectEqual(TerrainWindow.WANTED_HALF_WIDTH_STUDS, WorldConfig.TERRAIN_CORRIDOR_HALF_WIDTH_STUDS)
	end
)

Runner.test("the road blocks remember the kept corridor, its chunk and what the road reaches over it", function()
	local reachOfRoad = WorldConfig.TERRAIN_ROAD_REACH_STUDS
		+ WorldConfig.ROAD_WIDTH_STUDS / 2
		+ WorldConfig.SHOULDER_WIDTH_STUDS
	local minimum = TerrainWindow.KEPT_BEHIND_STUDS
		+ TerrainWindow.KEPT_HALF_WIDTH_STUDS
		+ WorldConfig.CHUNK_SIZE_STUDS
		+ reachOfRoad
	Runner.expectEqual(TerrainWindow.BLOCK_MEMORY_STUDS >= minimum, true)
	Runner.expectEqual(TerrainWindow.BLOCK_MEMORY_STUDS <= minimum + WorldConfig.CHUNK_SIZE_STUDS, true)
end)

Runner.test("the window fits in the live route exactly up to the live lookback", function()
	local ahead = 1000
	local memory = WorldConfig.LIVE_LOOKBACK_STUDS - ahead - WorldConfig.SEGMENT_LENGTH_STUDS
	Runner.expectEqual(TerrainWindow.fitsInLiveRoute(memory, ahead), true)
	Runner.expectEqual(TerrainWindow.fitsInLiveRoute(memory + 1, ahead), false)
	Runner.expectEqual(TerrainWindow.fitsInLiveRoute(memory, ahead + 1), false)
	Runner.expectEqual(TerrainWindow.fitsInLiveRoute(0, 0), true)
end)

Runner.test("the window of the configuration fits in the live route", function()
	Runner.expectEqual(
		TerrainWindow.fitsInLiveRoute(TerrainWindow.BLOCK_MEMORY_STUDS, WorldConfig.ROUTE_AHEAD_STUDS),
		true
	)
end)

Runner.finish()
