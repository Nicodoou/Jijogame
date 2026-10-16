--!strict
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local ClimateGrid = require("../../src/world/core/ClimateGrid")
local Runner = require("../Runner")

local STEP = 10
local COLUMNS = 4
local ROWS = 3
local ORIGIN_X = -20
local ORIGIN_Z = 100
local TOLERANCE = 1e-12
local FAR_STUDS = 500

-- Un clima que crece linealmente con la posición: la interpolación bilineal lo reproduce sin error.
local function linearSample(x: number, z: number): BiomeTypes.ClimateSample
	return { relief = 0.1 + 0.01 * x + 0.002 * z, humidity = 0.5 - 0.004 * x, temperature = 0.001 * z }
end

local function createLinearGrid(): ClimateGrid.ClimateGrid
	local samples = {}
	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			table.insert(samples, linearSample(ORIGIN_X + column * STEP, ORIGIN_Z + row * STEP))
		end
	end
	return ClimateGrid.new(ORIGIN_X, ORIGIN_Z, STEP, COLUMNS, ROWS, samples)
end

local function expectSampleNear(actual: BiomeTypes.ClimateSample, expected: BiomeTypes.ClimateSample)
	Runner.expectNear(actual.relief, expected.relief, TOLERANCE)
	Runner.expectNear(actual.humidity, expected.humidity, TOLERANCE)
	Runner.expectNear(actual.temperature, expected.temperature, TOLERANCE)
end

Runner.test("the grid gives back the sample at every node", function()
	local grid = createLinearGrid()
	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			local x, z = ORIGIN_X + column * STEP, ORIGIN_Z + row * STEP
			expectSampleNear(grid.sampleAt(x, z), linearSample(x, z))
		end
	end
end)

Runner.test("inside a cell the interpolation reproduces a linear climate", function()
	local grid = createLinearGrid()
	for _, offset in { { 1, 1 }, { 4.25, 7.5 }, { 9.99, 0.01 }, { 15, 12 }, { 29.9, 19.9 } } do
		local x, z = ORIGIN_X + offset[1], ORIGIN_Z + offset[2]
		expectSampleNear(grid.sampleAt(x, z), linearSample(x, z))
	end
end)

Runner.test("outside the grid the value is the one of the nearest edge", function()
	local grid = createLinearGrid()
	local lastX, lastZ = ORIGIN_X + (COLUMNS - 1) * STEP, ORIGIN_Z + (ROWS - 1) * STEP
	expectSampleNear(grid.sampleAt(ORIGIN_X - FAR_STUDS, ORIGIN_Z - FAR_STUDS), linearSample(ORIGIN_X, ORIGIN_Z))
	expectSampleNear(grid.sampleAt(lastX + FAR_STUDS, lastZ + FAR_STUDS), linearSample(lastX, lastZ))
	expectSampleNear(grid.sampleAt(lastX + FAR_STUDS, ORIGIN_Z + 5), linearSample(lastX, ORIGIN_Z + 5))
end)

Runner.test("the grid keeps its description", function()
	local grid = createLinearGrid()
	Runner.expectEqual(grid.originX, ORIGIN_X)
	Runner.expectEqual(grid.originZ, ORIGIN_Z)
	Runner.expectEqual(grid.stepStuds, STEP)
	Runner.expectEqual(grid.columnCount, COLUMNS)
	Runner.expectEqual(grid.rowCount, ROWS)
end)

Runner.test("a grid with fewer than two nodes per axis or the wrong sample count is an error", function()
	local sample = linearSample(0, 0)
	Runner.expectError(function()
		ClimateGrid.new(0, 0, STEP, 1, 2, { sample, sample })
	end)
	Runner.expectError(function()
		ClimateGrid.new(0, 0, STEP, 2, 1, { sample, sample })
	end)
	Runner.expectError(function()
		ClimateGrid.new(0, 0, STEP, 2, 2, { sample, sample, sample })
	end)
end)

Runner.finish()
