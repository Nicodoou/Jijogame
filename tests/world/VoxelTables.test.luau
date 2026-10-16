--!strict
local Runner = require("../Runner")
local VoxelTables = require("../../src/world/core/VoxelTables")

local SIZE_X = 4
local SIZE_Z = 3
local EMPTY = "Air"

local function expectShape(tables: VoxelTables.VoxelTables, layers: number)
	Runner.expectEqual(#tables.materials, SIZE_X)
	Runner.expectEqual(#tables.occupancy, SIZE_X)
	for x = 1, SIZE_X do
		Runner.expectEqual(#tables.materials[x], layers)
		Runner.expectEqual(#tables.occupancy[x], layers)
		for y = 1, layers do
			Runner.expectEqual(#tables.materials[x][y], SIZE_Z)
			Runner.expectEqual(#tables.occupancy[x][y], SIZE_Z)
		end
	end
	Runner.expectEqual(tables.getLayerCount(), layers)
end

Runner.test("the layer count gives exactly that many layers in every column of x", function()
	local tables = VoxelTables.new(SIZE_X, SIZE_Z, EMPTY)
	expectShape(tables, 0)
	for _, layers in { 5, 1, 9, 0, 3, 3 } do
		tables.setLayerCount(layers)
		expectShape(tables, layers)
	end
end)

Runner.test("new rows start empty and hold one entry per column of z", function()
	local tables = VoxelTables.new(SIZE_X, SIZE_Z, EMPTY)
	tables.setLayerCount(2)
	for x = 1, SIZE_X do
		for y = 1, 2 do
			for z = 1, SIZE_Z do
				Runner.expectEqual(tables.materials[x][y][z], EMPTY)
				Runner.expectEqual(tables.occupancy[x][y][z], 0)
			end
		end
	end
end)

Runner.test("shrinking and growing again reuses the rows instead of creating new ones", function()
	local tables = VoxelTables.new(SIZE_X, SIZE_Z, EMPTY)
	tables.setLayerCount(6)
	local before: { [{ string }]: boolean } = {}
	for x = 1, SIZE_X do
		for y = 1, 6 do
			before[tables.materials[x][y]] = true
		end
	end
	tables.setLayerCount(2)
	tables.setLayerCount(6)
	for x = 1, SIZE_X do
		for y = 1, 6 do
			Runner.expectEqual(before[tables.materials[x][y]], true)
		end
	end
end)

Runner.test("the outer tables keep their identity when the shape changes", function()
	local tables = VoxelTables.new(SIZE_X, SIZE_Z, EMPTY)
	local materials, occupancy = tables.materials, tables.occupancy
	tables.setLayerCount(4)
	tables.setLayerCount(7)
	Runner.expectEqual(tables.materials == materials, true)
	Runner.expectEqual(tables.occupancy == occupancy, true)
end)

Runner.finish()
