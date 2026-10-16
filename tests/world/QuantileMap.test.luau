--!strict
local QuantileMap = require("../../src/world/core/QuantileMap")
local QuantileTables = require("../../src/world/core/QuantileTables")
local Runner = require("../Runner")

local EXAMPLE = { -1, 0, 1, 3 }
local LAST_INDEX = #EXAMPLE
local TOLERANCE = 1e-12

Runner.test("a value on each entry gives its own fraction of the table", function()
	for index, value in EXAMPLE do
		Runner.expectNear(QuantileMap.toUnit(value, EXAMPLE), (index - 1) / (LAST_INDEX - 1), TOLERANCE)
	end
end)

Runner.test("values below the first entry give 0 and above the last give 1", function()
	Runner.expectEqual(QuantileMap.toUnit(-1000, EXAMPLE), 0)
	Runner.expectEqual(QuantileMap.toUnit(-math.huge, EXAMPLE), 0)
	Runner.expectEqual(QuantileMap.toUnit(1000, EXAMPLE), 1)
	Runner.expectEqual(QuantileMap.toUnit(math.huge, EXAMPLE), 1)
end)

Runner.test("between two entries the result is linear", function()
	Runner.expectNear(QuantileMap.toUnit(-0.5, EXAMPLE), 0.5 / (LAST_INDEX - 1), TOLERANCE)
	Runner.expectNear(QuantileMap.toUnit(2, EXAMPLE), 2.5 / (LAST_INDEX - 1), TOLERANCE)
end)

Runner.test("a run of equal entries does not divide by zero", function()
	local flat = { 0, 1, 1, 1, 2 }
	for _, value in { 0.999, 1, 1.001 } do
		local unit = QuantileMap.toUnit(value, flat)
		Runner.expectEqual(unit >= 0 and unit <= 1, true)
	end
	Runner.expectEqual(QuantileMap.toUnit(1, flat), 0.75)
end)

Runner.test("a table of two entries maps its range linearly", function()
	Runner.expectNear(QuantileMap.toUnit(0.25, { 0, 1 }), 0.25, TOLERANCE)
end)

Runner.test("NaN is an error instead of a silent number", function()
	Runner.expectError(function()
		QuantileMap.toUnit(0 / 0, EXAMPLE)
	end)
end)

Runner.test("the result never decreases when the value grows, on every shipped table", function()
	for _, table_ in
		{ QuantileTables.RELIEF, QuantileTables.HUMIDITY, QuantileTables.TEMPERATURE, QuantileTables.PATCH }
	do
		local previous = 0
		local first, last = table_[1], table_[#table_]
		local span = last - first
		for step = -5, 1005 do
			local unit = QuantileMap.toUnit(first + span * step / 1000, table_)
			Runner.expectEqual(unit >= previous, true)
			Runner.expectEqual(unit >= 0 and unit <= 1, true)
			previous = unit
		end
	end
end)

Runner.test("the shipped tables are strictly growing, read only and have the same number of entries", function()
	local count = #QuantileTables.RELIEF
	for _, table_ in
		{ QuantileTables.RELIEF, QuantileTables.HUMIDITY, QuantileTables.TEMPERATURE, QuantileTables.PATCH }
	do
		Runner.expectEqual(#table_, count)
		for index = 2, #table_ do
			Runner.expectEqual(table_[index] > table_[index - 1], true)
		end
		Runner.expectError(function()
			(table_ :: any)[1] = 0
		end)
	end
end)

Runner.finish()
