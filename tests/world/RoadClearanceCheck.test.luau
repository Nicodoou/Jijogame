--!strict
-- La verificación del anti-cruce también se prueba: si midiera mal, las pruebas de la ruta no servirían de nada.
local ClearanceCheck = require("./RoadClearanceCheck")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local CLEARANCE = WorldConfig.LIVE_CLEARANCE_STUDS
local LEG_STUDS = 3000
local FILLER_ORIGIN_STUDS = 1e6
local FILLER_SPACING_STUDS = 10
local NO_TOLERANCE = 0
-- Primer y último desfase, en muestras, que cuentan como no vecinos; y una muestra de más para llegar a un sondeo.
local FIRST_NON_NEIGHBOR_OFFSET = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS // STEP_STUDS + 1
local LAST_OFFSET = WorldConfig.LIVE_LOOKBACK_STUDS // STEP_STUDS

-- Va hacia +x y vuelve por otra línea a `separation` studs: una ida y vuelta.
local function createOutAndBack(separation: number): ClearanceCheck.Polyline
	local line: ClearanceCheck.Polyline = { xs = {}, zs = {} }
	for step = 0, LEG_STUDS // STEP_STUDS do
		table.insert(line.xs, step * STEP_STUDS)
		table.insert(line.zs, 0)
	end
	for step = LEG_STUDS // STEP_STUDS, 0, -1 do
		table.insert(line.xs, step * STEP_STUDS)
		table.insert(line.zs, separation)
	end
	return line
end

-- Muestras lejísimos entre sí, salvo dos: una vieja y un punto de sondeo, a 10 studs, en los lugares pedidos.
local function createPair(olderId: number, probeId: number): ClearanceCheck.Polyline
	local line: ClearanceCheck.Polyline = { xs = {}, zs = {} }
	for id = 1, probeId do
		line.xs[id] = FILLER_ORIGIN_STUDS + id * FILLER_SPACING_STUDS
		line.zs[id] = FILLER_ORIGIN_STUDS
	end
	line.xs[olderId], line.zs[olderId] = 10, 0
	line.xs[probeId], line.zs[probeId] = 0, 0
	return line
end

Runner.test("a straight road has no violations and no non neighbor pair", function()
	local line: ClearanceCheck.Polyline = { xs = {}, zs = {} }
	for step = 0, 2 * LEG_STUDS // STEP_STUDS do
		table.insert(line.xs, step * STEP_STUDS)
		table.insert(line.zs, 0)
	end
	local report = ClearanceCheck.measure(line, NO_TOLERANCE)
	Runner.expectEqual(report.violationCount, 0)
	Runner.expectEqual(report.minimumDistance >= WorldConfig.LIVE_NEIGHBOR_ARC_STUDS, true)
end)

Runner.test("an out and back road with its legs too close counts violations and finds their distance", function()
	local report = ClearanceCheck.measure(createOutAndBack(CLEARANCE / 2), NO_TOLERANCE)
	Runner.expectEqual(report.violationCount > 0, true)
	Runner.expectNear(report.minimumDistance, CLEARANCE / 2, 1e-9)
end)

Runner.test("an out and back road with its legs far enough has no violations", function()
	local report = ClearanceCheck.measure(createOutAndBack(CLEARANCE * 1.5), NO_TOLERANCE)
	Runner.expectEqual(report.violationCount, 0)
	Runner.expectNear(report.minimumDistance, CLEARANCE * 1.5, 1e-9)
end)

Runner.test("the tolerance forgives a gap of that size and no more", function()
	local line = createOutAndBack(CLEARANCE - 0.03)
	Runner.expectEqual(ClearanceCheck.measure(line, 0.05).violationCount, 0)
	Runner.expectEqual(ClearanceCheck.measure(line, 0.01).violationCount > 0, true)
end)

Runner.test("a tight loop that stays inside the neighbor distance is not a violation", function()
	local line: ClearanceCheck.Polyline = { xs = {}, zs = {} }
	local circleSteps = 150
	for step = 0, circleSteps do
		local angle = 2 * math.pi * step / circleSteps
		table.insert(line.xs, 60 * math.cos(angle))
		table.insert(line.zs, 60 * math.sin(angle))
	end
	Runner.expectEqual(ClearanceCheck.measure(line, NO_TOLERANCE).violationCount, 0)
end)

Runner.test("samples exactly at the first non neighbor offset count, one closer do not", function()
	local probeId = 1 + 4 * 151
	Runner.expectEqual(probeId - FIRST_NON_NEIGHBOR_OFFSET, 4)
	Runner.expectEqual(ClearanceCheck.measure(createPair(4, probeId), NO_TOLERANCE).violationCount, 1)
	Runner.expectEqual(ClearanceCheck.measure(createPair(5, probeId), NO_TOLERANCE).violationCount, 0)
end)

Runner.test("samples exactly at the last offset count, one farther do not", function()
	local probeId = 1 + 4 * 501
	Runner.expectEqual(probeId - LAST_OFFSET, 5)
	Runner.expectEqual(ClearanceCheck.measure(createPair(5, probeId), NO_TOLERANCE).violationCount, 1)
	Runner.expectEqual(ClearanceCheck.measure(createPair(4, probeId), NO_TOLERANCE).violationCount, 0)
end)

Runner.test("an empty or single sample road has nothing to measure", function()
	local empty = ClearanceCheck.measure({ xs = {}, zs = {} }, NO_TOLERANCE)
	Runner.expectEqual(empty.violationCount, 0)
	Runner.expectEqual(empty.minimumDistance, math.huge)
	Runner.expectEqual(ClearanceCheck.measure({ xs = { 5 }, zs = { 5 } }, NO_TOLERANCE).violationCount, 0)
end)

Runner.finish()
