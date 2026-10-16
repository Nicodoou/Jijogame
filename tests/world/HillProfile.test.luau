--!strict
local HillProfile = require("../../src/world/core/HillProfile")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local TOLERANCE = 1e-9
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local MAX_SLOPE = math.rad(WorldConfig.MAX_SLOPE_DEGREES)
local MAX_SLOPE_CHANGE = math.rad(WorldConfig.HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP)
local MIN_HEIGHT = WorldConfig.HILL_MIN_HEIGHT_STUDS
local MAX_HEIGHT = WorldConfig.HILL_MAX_HEIGHT_STUDS
local SIMULATED_SEEDS = 10
local SIMULATED_STEPS = 20000
local TARGET_SAMPLES = 2000
local TARGET_SAMPLE_SPACING_STUDS = 37
-- Una sesión de 30 minutos a 150 studs/s (RC-6): el perfil no puede repetirse antes.
local NO_REPEAT_STUDS = 30 * 60 * 150
local MIN_REPEAT_LAG_STUDS = 5000
local REPEAT_LAG_STEP_STUDS = 25
local REPEAT_WINDOW_POINTS = 32
local REPEAT_TOLERANCE_STUDS = 0.5
local REPEAT_SEEDS = 3

type Summary = {
	lowestHeight: number,
	highestHeight: number,
	largestSlope: number,
	largestSlopeChange: number,
}

-- Recorre el perfil como lo hace RoadIntegrator: la altura sube con la tangente de la pendiente media.
local function simulate(hill: HillProfile.HillProfile, startHeight: number, startSlope: number, steps: number): Summary
	local height, slope = startHeight, startSlope
	local summary = { lowestHeight = height, highestHeight = height, largestSlope = 0, largestSlopeChange = 0 }
	for step = 0, steps - 1 do
		local nextSlope = hill.nextSlope(height, slope, step * STEP_STUDS)
		height += STEP_STUDS * math.tan(0.5 * (slope + nextSlope))
		summary.largestSlopeChange = math.max(summary.largestSlopeChange, math.abs(nextSlope - slope))
		slope = nextSlope
		summary.lowestHeight = math.min(summary.lowestHeight, height)
		summary.highestHeight = math.max(summary.highestHeight, height)
		summary.largestSlope = math.max(summary.largestSlope, math.abs(slope))
	end
	return summary
end

local function createNarrowSettings(): HillProfile.HillSettings
	local settings = table.clone(HillProfile.defaultSettings)
	settings.amplitudeStuds = 2000
	settings.minHeightStuds = 0
	settings.maxHeightStuds = 100
	settings.baseHeightStuds = 50
	return settings
end

Runner.test("the same seed gives the same target heights and another seed gives other ones", function()
	local first, second, other = HillProfile.new(5), HillProfile.new(5), HillProfile.new(6)
	local differences = 0
	for arcLength = 0, TARGET_SAMPLES * TARGET_SAMPLE_SPACING_STUDS, TARGET_SAMPLE_SPACING_STUDS do
		Runner.expectEqual(first.getTargetHeight(arcLength), second.getTargetHeight(arcLength))
		differences += if first.getTargetHeight(arcLength) ~= other.getTargetHeight(arcLength) then 1 else 0
	end
	Runner.expectEqual(differences > TARGET_SAMPLES / 2, true)
end)

Runner.test("seeds that are zero, negative, fractional or huge all give a finite target inside the band", function()
	for _, seed in { 0, -1, -7.5, 0.25, 1e15, -1e15, 1e300 } do
		local hill = HillProfile.new(seed)
		for arcLength = 0, TARGET_SAMPLES * TARGET_SAMPLE_SPACING_STUDS, TARGET_SAMPLE_SPACING_STUDS do
			local height = hill.getTargetHeight(arcLength)
			Runner.expectEqual(height >= MIN_HEIGHT and height <= MAX_HEIGHT, true)
		end
	end
end)

Runner.test("the target is clamped to the band when the hills are taller than it", function()
	local hill = HillProfile.new(3, createNarrowSettings())
	local touchesLow, touchesHigh = false, false
	for arcLength = 0, TARGET_SAMPLES * TARGET_SAMPLE_SPACING_STUDS, TARGET_SAMPLE_SPACING_STUDS do
		local height = hill.getTargetHeight(arcLength)
		Runner.expectEqual(height >= 0 and height <= 100, true)
		touchesLow = touchesLow or height == 0
		touchesHigh = touchesHigh or height == 100
	end
	Runner.expectEqual(touchesLow and touchesHigh, true)
end)

Runner.test("with the hills as high as zero the target is the base height and the slope stays zero", function()
	local settings = table.clone(HillProfile.defaultSettings)
	settings.amplitudeStuds = 0
	local hill = HillProfile.new(1, settings)
	Runner.expectEqual(hill.getTargetHeight(1234), WorldConfig.HILL_BASE_HEIGHT_STUDS)
	local summary = simulate(hill, WorldConfig.HILL_BASE_HEIGHT_STUDS, 0, 500)
	Runner.expectNear(summary.largestSlope, 0, TOLERANCE)
	Runner.expectNear(summary.highestHeight, WorldConfig.HILL_BASE_HEIGHT_STUDS, TOLERANCE)
end)

Runner.test("the slope, its change per step and the height respect their limits over many seeds", function()
	for seed = 1, SIMULATED_SEEDS do
		local summary = simulate(HillProfile.new(seed), WorldConfig.START_POSITION.y, 0, SIMULATED_STEPS)
		Runner.expectEqual(summary.largestSlope <= MAX_SLOPE + TOLERANCE, true)
		Runner.expectEqual(summary.largestSlopeChange <= MAX_SLOPE_CHANGE + TOLERANCE, true)
		Runner.expectEqual(summary.lowestHeight >= MIN_HEIGHT and summary.highestHeight <= MAX_HEIGHT, true)
	end
end)

Runner.test(
	"the hills are short and sharp: the slope reaches the maximum and the height ranges over more than 50 studs",
	function()
		local summary = simulate(HillProfile.new(1), WorldConfig.START_POSITION.y, 0, SIMULATED_STEPS)
		Runner.expectEqual(summary.highestHeight - summary.lowestHeight > 50, true)
		Runner.expectEqual(summary.largestSlope > MAX_SLOPE * 0.95, true)
	end
)

Runner.test("with tall hills in a narrow band the road reaches both edges and never leaves the band", function()
	for seed = 1, SIMULATED_SEEDS do
		local summary = simulate(HillProfile.new(seed, createNarrowSettings()), 50, 0, SIMULATED_STEPS)
		Runner.expectEqual(summary.lowestHeight >= 0, true)
		Runner.expectEqual(summary.highestHeight <= 100, true)
		Runner.expectEqual(summary.lowestHeight < 1 and summary.highestHeight > 99, true)
		Runner.expectEqual(summary.largestSlope <= MAX_SLOPE + TOLERANCE, true)
		Runner.expectEqual(summary.largestSlopeChange <= MAX_SLOPE_CHANGE + TOLERANCE, true)
	end
end)

Runner.test(
	"at the upper edge the slope can no longer go up, and at the lower edge it can no longer go down",
	function()
		local hill = HillProfile.new(2, createNarrowSettings())
		for arcLength = 0, 40 * TARGET_SAMPLE_SPACING_STUDS, TARGET_SAMPLE_SPACING_STUDS do
			Runner.expectEqual(hill.nextSlope(100, 0, arcLength) <= TOLERANCE, true)
			Runner.expectEqual(hill.nextSlope(0, 0, arcLength) >= -TOLERANCE, true)
		end
	end
)

Runner.test("reaching the upper edge with a steep slope brakes as hard as allowed", function()
	local settings = createNarrowSettings()
	local hill = HillProfile.new(2, settings)
	Runner.expectNear(hill.nextSlope(100, MAX_SLOPE, 0), MAX_SLOPE - MAX_SLOPE_CHANGE, TOLERANCE)
	Runner.expectNear(hill.nextSlope(0, -MAX_SLOPE, 0), -MAX_SLOPE + MAX_SLOPE_CHANGE, TOLERANCE)
end)
Runner.test(
	"the slope changes by exactly the maximum when the target is far and never goes past the maximum slope",
	function()
		local settings = table.clone(HillProfile.defaultSettings)
		settings.amplitudeStuds = 0
		local hill = HillProfile.new(1, settings)
		local farBelow, farAbove = settings.baseHeightStuds - 150, settings.baseHeightStuds + 150
		Runner.expectNear(hill.nextSlope(farBelow, 0, 0), MAX_SLOPE_CHANGE, TOLERANCE)
		Runner.expectNear(hill.nextSlope(farBelow, MAX_SLOPE, 0), MAX_SLOPE, TOLERANCE)
		Runner.expectNear(hill.nextSlope(farAbove, 0, 0), -MAX_SLOPE_CHANGE, TOLERANCE)
		Runner.expectNear(hill.nextSlope(farAbove, -MAX_SLOPE, 0), -MAX_SLOPE, TOLERANCE)
	end
)

-- Altura que todavía se sube si, desde esta pendiente, se frena al máximo hasta quedar en cero.
local function getBrakingClimb(slope: number): number
	local climb = 0
	local current = slope
	while current > 0 do
		local following = math.max(0, current - MAX_SLOPE_CHANGE)
		climb += STEP_STUDS * math.tan(0.5 * (current + following))
		current = following
	end
	return climb
end

Runner.test("close to the edge the slope is capped to what still lets the road brake in time", function()
	-- Con la mirada a un stud, la ruta pediría subir lo más posible hasta el borde mismo.
	local settings = createNarrowSettings()
	settings.amplitudeStuds = 0
	settings.baseHeightStuds = settings.maxHeightStuds
	settings.lookaheadStuds = 1
	local hill = HillProfile.new(2, settings)
	local slope = math.rad(8)
	local needsIfHolding = STEP_STUDS * math.tan(slope) + getBrakingClimb(slope)
	local needsIfRising = STEP_STUDS * math.tan(slope + 0.5 * MAX_SLOPE_CHANGE)
		+ getBrakingClimb(slope + MAX_SLOPE_CHANGE)
	Runner.expectEqual(needsIfRising > needsIfHolding, true)
	local headroom = 0.5 * (needsIfHolding + needsIfRising)
	local limited = hill.nextSlope(settings.maxHeightStuds - headroom, slope, 0)
	Runner.expectEqual(limited > slope - MAX_SLOPE_CHANGE and limited < slope + MAX_SLOPE_CHANGE, true)
	local needsNow = STEP_STUDS * math.tan(0.5 * (slope + limited)) + getBrakingClimb(limited)
	Runner.expectEqual(needsNow <= headroom + TOLERANCE, true)
end)

-- Primer desfase (en studs, de a LAG_STEP_STUDS) en el que el perfil de una ventana vuelve a ser el mismo, o nil.
local function findFirstRepeatedLag(hill: HillProfile.HillProfile): number?
	for lag = MIN_REPEAT_LAG_STUDS, NO_REPEAT_STUDS, REPEAT_LAG_STEP_STUDS do
		local largestDifference = 0
		for point = 0, REPEAT_WINDOW_POINTS - 1 do
			local arcLength = point * TARGET_SAMPLE_SPACING_STUDS
			largestDifference = math.max(
				largestDifference,
				math.abs(hill.getTargetHeight(arcLength + lag) - hill.getTargetHeight(arcLength))
			)
		end
		if largestDifference < REPEAT_TOLERANCE_STUDS then
			return lag
		end
	end
	return nil
end

Runner.test("the hill profile does not repeat itself during a 30 minute session (#57)", function()
	for seed = 1, REPEAT_SEEDS do
		Runner.expectEqual(findFirstRepeatedLag(HillProfile.new(seed)), nil)
	end
end)

Runner.finish()
