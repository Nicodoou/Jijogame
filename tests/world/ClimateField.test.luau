--!strict
local ClimateField = require("../../src/world/core/ClimateField")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local Runner = require("../Runner")

type Axis = "relief" | "humidity" | "temperature"

local AXES: { Axis } = { "relief", "humidity", "temperature" }
local UNIFORMITY_SEEDS = 200
local UNIFORMITY_POINTS_PER_SEED = 1000
local UNIFORMITY_FIRST_SEED = 9001
local DECILE_COUNT = 10
local MIN_DECILE_SHARE = 0.08
local MAX_DECILE_SHARE = 0.12
local GRID_SEEDS = 40
local GRID_SIZE_STUDS = 128
local GRID_POINTS_PER_SEED = 300
local GRID_FIRST_SEED = 7001
-- Mayor valor absoluto que puede dar math.noise (medido: 0,86).
local NOISE_RANGE = 0.87
local NOISE_PERIOD = 256
local WRAP_TOLERANCE = 1e-6
local CORRELATION_SEEDS = 1000
local CORRELATION_POINTS_PER_SEED = 20
local CORRELATION_FIRST_SEED = 500001
local MAX_INDEPENDENT_CORRELATION = 0.1
local FAR_COORDINATE_STUDS = 2 ^ 22
local ONE_STUD_MAX_CHANGE = 0.01

local function drawPointInArea(random: SeededRandom.SeededRandom): (number, number)
	local radius = WorldConfig.AREA_RADIUS_STUDS * math.sqrt(random.nextNumber())
	local angle = 2 * math.pi * random.nextNumber()
	return radius * math.cos(angle), radius * math.sin(angle)
end

local function expectInUnitRange(sample: ClimateField.ClimateSample)
	for _, axis in AXES do
		Runner.expectEqual(sample[axis] >= 0 and sample[axis] <= 1, true)
	end
end

Runner.test("the same seed and position give the same climate, in any order", function()
	local first, second = ClimateField.new(12345), ClimateField.new(12345)
	local random = SeededRandom.new(1)
	local points = {}
	for _ = 1, 200 do
		local x, z = drawPointInArea(random)
		table.insert(points, { x, z })
	end
	local expected = {}
	for index, point in points do
		expected[index] = first.sample(point[1], point[2])
	end
	for index = #points, 1, -1 do
		local again = second.sample(points[index][1], points[index][2])
		for _, axis in AXES do
			Runner.expectEqual(again[axis], expected[index][axis])
		end
	end
end)

Runner.test("different seeds give different climates", function()
	local first, second = ClimateField.new(1), ClimateField.new(2)
	local differences = 0
	for step = 0, 99 do
		if first.sample(step * 80, -step * 50).relief ~= second.sample(step * 80, -step * 50).relief then
			differences += 1
		end
	end
	Runner.expectEqual(differences > 90, true)
end)

Runner.test("seeds zero, negative, fractional and huge build a field with values in [0, 1]", function()
	for _, seed in { 0, -3, 0.75, 1e12 } do
		local field = ClimateField.new(seed)
		for _, position in { { 0, 0 }, { 8000, -8000 }, { -1234.5, 99.25 } } do
			expectInUnitRange(field.sample(position[1], position[2]))
		end
	end
	Runner.expectError(function()
		ClimateField.new(0 / 0)
	end)
end)

Runner.test("far away, at negative positions and at the origin the climate is in range and not constant", function()
	local field = ClimateField.new(5)
	local seen: { [number]: boolean } = {}
	for _, coordinate in { -FAR_COORDINATE_STUDS, -1, 0, 1, FAR_COORDINATE_STUDS, FAR_COORDINATE_STUDS + 0.37 } do
		local sample = field.sample(coordinate, -coordinate * 0.7)
		expectInUnitRange(sample)
		seen[sample.relief] = true
	end
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	Runner.expectEqual(distinct > 2, true)
end)

Runner.test("a position that is not a number is an error", function()
	local field = ClimateField.new(1)
	Runner.expectError(function()
		field.sample(0 / 0, 0)
	end)
end)

Runner.test("the raw maps stay inside the range of math.noise", function()
	local field = ClimateField.new(77)
	local random = SeededRandom.new(2)
	for _ = 1, 2000 do
		local x, z = drawPointInArea(random)
		local raw = field.sampleRaw(x, z)
		Runner.expectEqual(math.abs(raw.relief) < NOISE_RANGE, true)
		Runner.expectEqual(math.abs(raw.humidity) < NOISE_RANGE, true)
	end
end)

Runner.test(
	"the maps repeat after 256 wavelengths of the longest octave, because the input wraps with % 256",
	function()
		local field = ClimateField.new(31)
		local period = NOISE_PERIOD * WorldConfig.CLIMATE_RELIEF_WAVELENGTH_STUDS
		local shifted = field.sampleRaw(123.4 + period, 56.7)
		local base = field.sampleRaw(123.4, 56.7)
		Runner.expectNear(shifted.relief, base.relief, WRAP_TOLERANCE)
	end
)

Runner.test("the climate changes smoothly: points one stud apart differ by very little", function()
	local field = ClimateField.new(8)
	local random = SeededRandom.new(3)
	for _ = 1, 500 do
		local x, z = drawPointInArea(random)
		local here, following = field.sample(x, z), field.sample(x + 1, z)
		for _, axis in AXES do
			Runner.expectEqual(math.abs(here[axis] - following[axis]) < ONE_STUD_MAX_CHANGE, true)
		end
	end
end)

Runner.test("with 200,000 samples each map is almost uniform: every tenth holds 8% to 12%", function()
	local random = SeededRandom.new(4)
	local counts: { [string]: { number } } = {}
	for _, axis in AXES do
		counts[axis] = table.create(DECILE_COUNT, 0)
	end
	for seed = UNIFORMITY_FIRST_SEED, UNIFORMITY_FIRST_SEED + UNIFORMITY_SEEDS - 1 do
		local field = ClimateField.new(seed)
		for _ = 1, UNIFORMITY_POINTS_PER_SEED do
			local x, z = drawPointInArea(random)
			local sample = field.sample(x, z)
			for _, axis in AXES do
				local decile = math.min(DECILE_COUNT, math.floor(sample[axis] * DECILE_COUNT) + 1)
				counts[axis][decile] += 1
			end
		end
	end
	local total = UNIFORMITY_SEEDS * UNIFORMITY_POINTS_PER_SEED
	for _, axis in AXES do
		for decile = 1, DECILE_COUNT do
			local share = counts[axis][decile] / total
			Runner.expectEqual(share >= MIN_DECILE_SHARE and share <= MAX_DECILE_SHARE, true)
		end
	end
end)

local function correlate(first: { number }, second: { number }): number
	local count = #first
	local meanFirst, meanSecond = 0, 0
	for index = 1, count do
		meanFirst += first[index] / count
		meanSecond += second[index] / count
	end
	local covariance, varianceFirst, varianceSecond = 0, 0, 0
	for index = 1, count do
		local deltaFirst, deltaSecond = first[index] - meanFirst, second[index] - meanSecond
		covariance += deltaFirst * deltaSecond
		varianceFirst += deltaFirst * deltaFirst
		varianceSecond += deltaSecond * deltaSecond
	end
	return covariance / math.sqrt(varianceFirst * varianceSecond)
end

Runner.test("relief and humidity are independent maps and the temperature goes down with the relief", function()
	local random = SeededRandom.new(5)
	local relief, humidity, temperature = {}, {}, {}
	for seed = CORRELATION_FIRST_SEED, CORRELATION_FIRST_SEED + CORRELATION_SEEDS - 1 do
		local field = ClimateField.new(seed)
		for _ = 1, CORRELATION_POINTS_PER_SEED do
			local x, z = drawPointInArea(random)
			local sample = field.sample(x, z)
			table.insert(relief, sample.relief)
			table.insert(humidity, sample.humidity)
			table.insert(temperature, sample.temperature)
		end
	end
	Runner.expectEqual(math.abs(correlate(relief, humidity)) < MAX_INDEPENDENT_CORRELATION, true)
	Runner.expectEqual(math.abs(correlate(humidity, temperature)) < MAX_INDEPENDENT_CORRELATION, true)
	Runner.expectEqual(correlate(relief, temperature) < -MAX_INDEPENDENT_CORRELATION, true)
end)

Runner.test("a grid of one chunk differs from the direct sampling by less than CLIMATE_GRID_MAX_ERROR", function()
	local random = SeededRandom.new(6)
	local worst = 0
	for seed = GRID_FIRST_SEED, GRID_FIRST_SEED + GRID_SEEDS - 1 do
		local field = ClimateField.new(seed)
		local originX, originZ = drawPointInArea(random)
		local grid = field.sampleGrid(originX, originZ, GRID_SIZE_STUDS, WorldConfig.CLIMATE_GRID_STEP_STUDS)
		for _ = 1, GRID_POINTS_PER_SEED do
			local x = originX + random.nextNumber() * GRID_SIZE_STUDS
			local z = originZ + random.nextNumber() * GRID_SIZE_STUDS
			local direct, interpolated = field.sample(x, z), grid.sampleAt(x, z)
			for _, axis in AXES do
				worst = math.max(worst, math.abs(direct[axis] - interpolated[axis]))
			end
		end
	end
	Runner.expectEqual(worst < WorldConfig.CLIMATE_GRID_MAX_ERROR, true)
end)

Runner.test("the grid is exact at its nodes and has one node more than the steps along each side", function()
	local field = ClimateField.new(9)
	local step = WorldConfig.CLIMATE_GRID_STEP_STUDS
	local grid = field.sampleGrid(-300, 700, GRID_SIZE_STUDS, step)
	Runner.expectEqual(grid.columnCount, GRID_SIZE_STUDS / step + 1)
	Runner.expectEqual(grid.rowCount, GRID_SIZE_STUDS / step + 1)
	for column = 0, grid.columnCount - 1 do
		local x, z = -300 + column * step, 700 + (grid.rowCount - 1 - column) * step
		local direct, interpolated = field.sample(x, z), grid.sampleAt(x, z)
		for _, axis in AXES do
			Runner.expectNear(interpolated[axis], direct[axis], WRAP_TOLERANCE)
		end
	end
end)

Runner.test("a size that is not a whole number of steps still gets covered", function()
	local field = ClimateField.new(10)
	local grid = field.sampleGrid(0, 0, 100, 16)
	Runner.expectEqual(grid.columnCount, 8)
	Runner.expectNear(grid.sampleAt(100, 100).relief, field.sample(100, 100).relief, WorldConfig.CLIMATE_GRID_MAX_ERROR)
end)

Runner.test("a grid with a size or a step that is zero, negative, infinite or NaN is an error", function()
	local field = ClimateField.new(11)
	for _, bad in { 0, -16, math.huge, 0 / 0 } do
		Runner.expectError(function()
			field.sampleGrid(0, 0, bad, 16)
		end)
		Runner.expectError(function()
			field.sampleGrid(0, 0, 128, bad)
		end)
	end
end)

Runner.finish()
