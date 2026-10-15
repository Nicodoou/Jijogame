--!strict
-- Las medidas de rally también se prueban con rutas armadas a mano.
local RoadPath = require("../../src/world/core/RoadPath")
local RoadRallyMetrics = require("./RoadRallyMetrics")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

type Sample = RoadPath.RoadSample

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local ROAD_STUDS = 6000
local WINDOW_STUDS = 2000
local HEIGHT_VARIATION_STUDS = 60

-- Una ruta de `ROAD_STUDS` con el rumbo y la altura que den las funciones, según el arcLength.
local function createRoad(heading: (arcLength: number) -> number, height: (arcLength: number) -> number): { Sample }
	local road = {}
	for index = 0, ROAD_STUDS // STEP_STUDS do
		local arcLength = index * STEP_STUDS
		road[index + 1] = {
			position = vector.create(arcLength, height(arcLength), 0),
			heading = heading(arcLength),
			curvature = 0,
			slope = 0,
			arcLength = arcLength,
		}
	end
	return road
end

local function flat(): number
	return 0
end

Runner.test("a road that always heads the same way has no big turn and one quadrant", function()
	local road = createRoad(flat, flat)
	Runner.expectEqual(RoadRallyMetrics.hasWindowWithBigTurn(road), false)
	Runner.expectEqual(RoadRallyMetrics.passesAllQuadrants(road), false)
end)

Runner.test("a turn of more than 180 degrees in 2000 studs counts, one of less does not", function()
	local steep = createRoad(function(arcLength)
		return math.rad(200) * arcLength / WINDOW_STUDS
	end, flat)
	local gentle = createRoad(function(arcLength)
		return math.rad(170) * arcLength / WINDOW_STUDS
	end, flat)
	Runner.expectEqual(RoadRallyMetrics.hasWindowWithBigTurn(steep), true)
	Runner.expectEqual(RoadRallyMetrics.hasWindowWithBigTurn(gentle), false)
end)

Runner.test("the turn counts in both directions", function()
	local left = createRoad(function(arcLength)
		return -math.rad(300) * arcLength / WINDOW_STUDS
	end, flat)
	Runner.expectEqual(RoadRallyMetrics.hasWindowWithBigTurn(left), true)
end)

Runner.test("a road that turns all the way round passes through the four quadrants", function()
	local round = createRoad(function(arcLength)
		return 2 * math.pi * arcLength / ROAD_STUDS
	end, flat)
	Runner.expectEqual(RoadRallyMetrics.passesAllQuadrants(round), true)
	local half = createRoad(function(arcLength)
		return math.pi * arcLength / ROAD_STUDS
	end, flat)
	Runner.expectEqual(RoadRallyMetrics.passesAllQuadrants(half), false)
end)

Runner.test("a heading just below zero counts as the first quadrant and not as a fifth one", function()
	local headings = { -1e-17, math.pi / 2 + 0.1, math.pi + 0.1, 3 * math.pi / 2 + 0.1 }
	local road = createRoad(flat, flat)
	for index, sample in road do
		sample.heading = headings[(index - 1) // 10 % #headings + 1]
	end
	Runner.expectEqual(RoadRallyMetrics.passesAllQuadrants(road), true)
	for index, sample in road do
		sample.heading = headings[(index - 1) // 10 % 3 + 1]
	end
	Runner.expectEqual(RoadRallyMetrics.passesAllQuadrants(road), false)
end)

Runner.test("a flat road has no hilly window and a sawtooth road has only hilly ones", function()
	local flatWindows, flatHilly = RoadRallyMetrics.countHeightWindows(createRoad(flat, flat))
	Runner.expectEqual(flatWindows > 0, true)
	Runner.expectEqual(flatHilly, 0)
	local sawtooth = createRoad(flat, function(arcLength)
		return (arcLength // 500 % 2) * 2 * HEIGHT_VARIATION_STUDS
	end)
	local windows, hilly = RoadRallyMetrics.countHeightWindows(sawtooth)
	Runner.expectEqual(windows, flatWindows)
	Runner.expectEqual(hilly, windows)
end)

Runner.test("a variation of exactly 60 studs is not enough and a bit more is", function()
	local exact = createRoad(flat, function(arcLength)
		return if arcLength > ROAD_STUDS / 2 then HEIGHT_VARIATION_STUDS else 0
	end)
	local _, exactHilly = RoadRallyMetrics.countHeightWindows(exact)
	Runner.expectEqual(exactHilly, 0)
	local more = createRoad(flat, function(arcLength)
		return if arcLength > ROAD_STUDS / 2 then HEIGHT_VARIATION_STUDS + 1 else 0
	end)
	local _, moreHilly = RoadRallyMetrics.countHeightWindows(more)
	Runner.expectEqual(moreHilly > 0, true)
end)

Runner.test("a road shorter than a window has no windows", function()
	local short = createRoad(flat, flat)
	for _ = 1, #short - 100 do
		table.remove(short)
	end
	local windows = RoadRallyMetrics.countHeightWindows(short)
	Runner.expectEqual(windows, 0)
	Runner.expectEqual(RoadRallyMetrics.hasWindowWithBigTurn(short), false)
end)

Runner.finish()
