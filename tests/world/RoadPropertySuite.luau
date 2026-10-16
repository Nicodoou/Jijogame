--!strict
-- Propiedades de la ruta sobre muchas semillas y las pruebas de "rally de verdad". Las usan el CI (pocas semillas) y la
-- corrida completa a mano (muchas), con los mismos criterios. No es una prueba: no termina en Runner.finish().
-- Cada semilla se genera, se mide y se descarta, así la memoria no crece con la cantidad de semillas.

local ClearanceCheck = require("./RoadClearanceCheck")
local RoadPath = require("../../src/world/core/RoadPath")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local RoadPieceSequencer = require("../../src/world/core/RoadPieceSequencer")
local RoadRallyMetrics = require("./RoadRallyMetrics")
local RoadSampleChecks = require("./RoadSampleChecks")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

export type Report = {
	seedCount: number,
	enclosedSeedCount: number,
	violations: RoadSampleChecks.Violations,
	continuityViolations: number,
	clearanceViolations: number,
	minimumClearance: number,
	lastResortCount: number,
	backtrackCount: number,
	retractedPieceCount: number,
	guideBacktrackCount: number,
	seedsWithBigTurn: number,
	seedsWithAllQuadrants: number,
	sharpCurvesPerKm: number,
	hairpinsPerKm: number,
	heightWindowCount: number,
	hilliestWindowCount: number,
	bigTurnWindowPercent: number,
	uTurnsPerKm: number,
	meanStraightStuds: number,
	longestStraightStuds: number,
	steepPercent: number,
	meanClimbStuds: number,
}

type Totals = {
	sharpCurves: number,
	hairpins: number,
	studs: number,
	turnWindows: number,
	bigTurnWindows: number,
	uTurns: number,
	straights: number,
	straightStuds: number,
	steepSamples: number,
	climbs: number,
	samples: number,
}

local SEGMENT_COUNT = 400
local STUDS_PER_KM = 1000
local MIN_HAIRPINS_PER_KM = 0.3
local MIN_SHARP_CURVES_PER_KM = 1
-- Lo que se pide de la ruta de rally, con un poco de margen sobre lo medido (el objetivo era 25 % de giros y 1 U por km).
local MIN_BIG_TURN_WINDOW_PERCENT = 20
local MIN_U_TURNS_PER_KM = 0.9
local MAX_STRAIGHT_STUDS = 250
local MIN_STEEP_PERCENT = 25
local MAX_MEAN_CLIMB_STUDS = 150
local HAIRPINS_PER_PAIR = 2
local SHARP_KIND: RoadPieceCatalog.PieceKind = "sharpCurve"
local HAIRPIN_KIND: RoadPieceCatalog.PieceKind = "hairpinPair"

local function toPolyline(road: { RoadPath.RoadSample }): ClearanceCheck.Polyline
	local line = { xs = table.create(#road), zs = table.create(#road) }
	for index, sample in road do
		line.xs[index], line.zs[index] = sample.position.x, sample.position.z
	end
	return line
end

-- Genera los tramos de una semilla. Si la ruta se encierra, devuelve los que alcanzó a publicar.
local function generate(seed: number): ({ RoadPath.Segment }, boolean, RoadPieceSequencer.SequencerStatistics)
	local path, getStatistics = RoadPath.newWithStatistics(seed)
	local segments = {}
	for _ = 1, SEGMENT_COUNT do
		local succeeded, segment = pcall(path.generateNextSegment)
		if not succeeded then
			return segments, true, getStatistics()
		end
		table.insert(segments, segment)
	end
	return segments, false, getStatistics()
end

local function addViolations(total: RoadSampleChecks.Violations, added: RoadSampleChecks.Violations)
	total.curvature += added.curvature
	total.curvatureJump += added.curvatureJump
	total.slope += added.slope
	total.slopeChange += added.slopeChange
	total.height += added.height
	total.area += added.area
	total.step += added.step
	total.notFinite += added.notFinite
end

-- Giros netos, vueltas en U, rectas y lomas de una ruta, sumados a los totales.
local function addRallyTotals(report: Report, totals: Totals, road: { RoadPath.RoadSample })
	local turnWindows, bigTurnWindows = RoadRallyMetrics.countBigTurnWindows(road)
	totals.turnWindows += turnWindows
	totals.bigTurnWindows += bigTurnWindows
	totals.uTurns += RoadRallyMetrics.countUTurns(road)
	local straights, straightStuds, longestStuds = RoadRallyMetrics.measureStraights(road)
	totals.straights += straights
	totals.straightStuds += straightStuds
	report.longestStraightStuds = math.max(report.longestStraightStuds, longestStuds)
	local steepSamples, climbs, samples = RoadRallyMetrics.measureHills(road)
	totals.steepSamples += steepSamples
	totals.climbs += climbs
	totals.samples += samples
end

local function measureSeed(seed: number, report: Report, totals: Totals)
	local segments, isEnclosed, statistics = generate(seed)
	local road = RoadSampleChecks.flatten(segments)
	report.enclosedSeedCount += if isEnclosed then 1 else 0
	report.continuityViolations += RoadSampleChecks.countContinuityViolations(segments)
	addViolations(report.violations, RoadSampleChecks.countViolations(road))
	local clearance = ClearanceCheck.measure(toPolyline(road), RoadSampleChecks.vectorPrecisionStuds)
	report.clearanceViolations += clearance.violationCount
	report.minimumClearance = math.min(report.minimumClearance, clearance.minimumDistance)
	report.lastResortCount += statistics.lastResortCount
	report.backtrackCount += statistics.backtrackCount
	report.retractedPieceCount += statistics.retractedPieceCount
	report.guideBacktrackCount += statistics.guide.backtrackCount
	report.seedsWithBigTurn += if RoadRallyMetrics.hasWindowWithBigTurn(road) then 1 else 0
	report.seedsWithAllQuadrants += if RoadRallyMetrics.passesAllQuadrants(road) then 1 else 0
	local windowCount, hillyCount = RoadRallyMetrics.countHeightWindows(road)
	report.heightWindowCount += windowCount
	report.hilliestWindowCount += hillyCount
	totals.sharpCurves += statistics.pieceCountByKind[SHARP_KIND] or 0
	totals.hairpins += (statistics.pieceCountByKind[HAIRPIN_KIND] or 0) * HAIRPINS_PER_PAIR
	totals.studs += statistics.arcLengthStuds
	addRallyTotals(report, totals, road)
end

local function createReport(seedCount: number): Report
	return {
		seedCount = seedCount,
		enclosedSeedCount = 0,
		violations = RoadSampleChecks.createViolations(),
		continuityViolations = 0,
		clearanceViolations = 0,
		minimumClearance = math.huge,
		lastResortCount = 0,
		backtrackCount = 0,
		retractedPieceCount = 0,
		guideBacktrackCount = 0,
		seedsWithBigTurn = 0,
		seedsWithAllQuadrants = 0,
		sharpCurvesPerKm = 0,
		hairpinsPerKm = 0,
		heightWindowCount = 0,
		hilliestWindowCount = 0,
		bigTurnWindowPercent = 0,
		uTurnsPerKm = 0,
		meanStraightStuds = 0,
		longestStraightStuds = 0,
		steepPercent = 0,
		meanClimbStuds = 0,
	}
end

local RoadPropertySuite = {}

RoadPropertySuite.segmentCount = SEGMENT_COUNT

function RoadPropertySuite.measure(seedCount: number): Report
	local report = createReport(seedCount)
	local totals: Totals = {
		sharpCurves = 0,
		hairpins = 0,
		studs = 0,
		turnWindows = 0,
		bigTurnWindows = 0,
		uTurns = 0,
		straights = 0,
		straightStuds = 0,
		steepSamples = 0,
		climbs = 0,
		samples = 0,
	}
	for seed = 1, seedCount do
		measureSeed(seed, report, totals)
	end
	local kilometers = totals.studs / STUDS_PER_KM
	report.sharpCurvesPerKm = totals.sharpCurves / kilometers
	report.hairpinsPerKm = totals.hairpins / kilometers
	report.bigTurnWindowPercent = 100 * totals.bigTurnWindows / totals.turnWindows
	report.uTurnsPerKm = totals.uTurns / kilometers
	report.meanStraightStuds = totals.straightStuds / math.max(1, totals.straights)
	report.steepPercent = 100 * totals.steepSamples / totals.samples
	report.meanClimbStuds = totals.samples * WorldConfig.INTEGRATION_STEP_STUDS / math.max(1, totals.climbs)
	return report
end

-- Registra las pruebas de propiedades y de rally sobre `seedCount` semillas × SEGMENT_COUNT tramos.
function RoadPropertySuite.defineTests(seedCount: number): Report
	local report = RoadPropertySuite.measure(seedCount)
	local violations = report.violations
	local function expectZero(name: string, count: number)
		Runner.test(name, function()
			Runner.expectEqual(count, 0)
		end)
	end
	expectZero("no seed ends enclosed", report.enclosedSeedCount)
	expectZero("the curvature never exceeds the limit of the minimum radius", violations.curvature)
	expectZero("the curvature never jumps more than the shortest ramp allows", violations.curvatureJump)
	expectZero("the slope never exceeds the maximum slope", violations.slope)
	expectZero("the slope never changes by more than the maximum per step", violations.slopeChange)
	expectZero("the height stays inside the band", violations.height)
	expectZero("every sample is inside the area", violations.area)
	expectZero("each segment starts where the previous one ended", report.continuityViolations)
	expectZero("consecutive samples are one step apart on the ground", violations.step)
	expectZero("every value of every sample is a finite number", violations.notFinite)
	expectZero("the road keeps its distance from non neighbor parts of itself", report.clearanceViolations)
	Runner.test("every seed has a window of 2000 studs that turns more than 180 degrees", function()
		Runner.expectEqual(report.seedsWithBigTurn, seedCount)
	end)
	Runner.test("every seed heads through the four quadrants", function()
		Runner.expectEqual(report.seedsWithAllQuadrants, seedCount)
	end)
	Runner.test("there are more than 0.3 hairpins and 1 sharp curve per kilometer", function()
		Runner.expectEqual(report.hairpinsPerKm > MIN_HAIRPINS_PER_KM, true)
		Runner.expectEqual(report.sharpCurvesPerKm > MIN_SHARP_CURVES_PER_KM, true)
	end)
	Runner.test("a quarter of the windows of 2000 studs turn more than 180 degrees", function()
		Runner.expectEqual(report.bigTurnWindowPercent >= MIN_BIG_TURN_WINDOW_PERCENT, true)
	end)
	Runner.test("there is about one U turn per kilometer", function()
		Runner.expectEqual(report.uTurnsPerKm >= MIN_U_TURNS_PER_KM, true)
	end)
	Runner.test("the straights are short", function()
		Runner.expectEqual(report.longestStraightStuds <= MAX_STRAIGHT_STUDS, true)
	end)
	Runner.test(
		"the hills are steep and short: a quarter of the road is over 10 degrees and climbs are brief",
		function()
			Runner.expectEqual(report.steepPercent >= MIN_STEEP_PERCENT, true)
			Runner.expectEqual(report.meanClimbStuds < MAX_MEAN_CLIMB_STUDS, true)
		end
	)
	return report
end

return RoadPropertySuite
