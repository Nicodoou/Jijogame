--!strict
local ChunkCorridor = require("../../src/world/core/ChunkCorridor")
local ChunkGrid = require("../../src/world/core/ChunkGrid")
local ChunkPlan = require("../../src/world/core/ChunkPlan")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CHUNK = WorldConfig.CHUNK_SIZE_STUDS
local HALF_CHUNK = CHUNK / 2

type Cell = ChunkCorridor.ChunkCell
type Written = ChunkPlan.WrittenChunk

local function cellOf(chunkX: number, chunkZ: number): Cell
	return { chunkX = chunkX, chunkZ = chunkZ, key = ChunkGrid.getKey(chunkX, chunkZ) }
end

local function setOf(cells: { Cell }): { [number]: Cell }
	local set: { [number]: Cell } = {}
	for _, cell in cells do
		set[cell.key] = cell
	end
	return set
end

local function writtenOf(chunkX: number, chunkZ: number): Written
	return { chunkX = chunkX, chunkZ = chunkZ, minVoxelY = 0, maxVoxelY = 10, signature = 1 }
end

local function writtenSetOf(records: { Written }): { [number]: Written }
	local set: { [number]: Written } = {}
	for _, record in records do
		set[ChunkGrid.getKey(record.chunkX, record.chunkZ)] = record
	end
	return set
end

local function never(): boolean
	return false
end

local function describe(plan: { ChunkPlan.PlannedWork }): { string }
	local lines: { string } = {}
	for _, work in plan do
		table.insert(lines, `{work.kind} {work.chunkX},{work.chunkZ}`)
	end
	return lines
end

Runner.test("it writes what is wanted and missing, keeps what is kept and clears the rest", function()
	local wanted = setOf({ cellOf(0, 0), cellOf(1, 0), cellOf(2, 0) })
	local kept = setOf({ cellOf(0, 0), cellOf(1, 0), cellOf(2, 0), cellOf(3, 0) })
	local written = writtenSetOf({ writtenOf(0, 0), writtenOf(3, 0), writtenOf(9, 9) })
	local plan = ChunkPlan.build(wanted, kept, written, nil, HALF_CHUNK, HALF_CHUNK, never)
	Runner.expectEqual(table.concat(describe(plan), "|"), "write 1,0|write 2,0|clear 9,9")
end)

Runner.test("a written chunk that is stale is rewritten, and one that is not stale is left alone", function()
	local wanted = setOf({ cellOf(0, 0), cellOf(1, 0) })
	local written = writtenSetOf({ writtenOf(0, 0), writtenOf(1, 0) })
	local function isStale(record: Written): boolean
		return record.chunkX == 1
	end
	local plan = ChunkPlan.build(wanted, wanted, written, nil, 0, 0, isStale)
	Runner.expectEqual(table.concat(describe(plan), "|"), "rewrite 1,0")
end)

Runner.test("the writes go from the nearest chunk to the vehicle to the farthest, and the clears come last", function()
	local wanted = setOf({ cellOf(0, 0), cellOf(4, 0), cellOf(2, 0), cellOf(-3, 0), cellOf(1, 1) })
	local written = writtenSetOf({ writtenOf(7, 7), writtenOf(-8, 0) })
	local vehicleX, vehicleZ = 2 * CHUNK + HALF_CHUNK, HALF_CHUNK
	local plan = ChunkPlan.build(wanted, wanted, written, nil, vehicleX, vehicleZ, never)
	Runner.expectEqual(
		table.concat(describe(plan), "|"),
		"write 2,0|write 1,1|write 0,0|write 4,0|write -3,0|clear -8,0|clear 7,7"
	)
end)

Runner.test("chunks at the same distance come out in the same order every time", function()
	local cells: { Cell } = {}
	for chunkX = -2, 2 do
		for chunkZ = -2, 2 do
			table.insert(cells, cellOf(chunkX, chunkZ))
		end
	end
	local reference = table.concat(describe(ChunkPlan.build(setOf(cells), setOf(cells), {}, nil, 0, 0, never)), "|")
	for _ = 1, 10 do
		local shuffled = table.clone(cells)
		table.sort(shuffled, function(first: Cell, second: Cell): boolean
			return first.key > second.key
		end)
		local again =
			table.concat(describe(ChunkPlan.build(setOf(shuffled), setOf(shuffled), {}, nil, 0, 0, never)), "|")
		Runner.expectEqual(again, reference)
	end
end)

Runner.test("the chunk being built is not asked for again nor cleared", function()
	local wanted = setOf({ cellOf(0, 0), cellOf(1, 0) })
	local written = writtenSetOf({ writtenOf(5, 5) })
	local busy = ChunkGrid.getKey(1, 0)
	Runner.expectEqual(
		table.concat(describe(ChunkPlan.build(wanted, wanted, written, busy, 0, 0, never)), "|"),
		"write 0,0|clear 5,5"
	)
	local clearBusy = ChunkGrid.getKey(5, 5)
	Runner.expectEqual(
		table.concat(describe(ChunkPlan.build(wanted, wanted, written, clearBusy, 0, 0, never)), "|"),
		"write 0,0|write 1,0"
	)
end)

Runner.test("with nothing wanted and nothing written there is nothing to do", function()
	Runner.expectEqual(#ChunkPlan.build({}, {}, {}, nil, 0, 0, never), 0)
end)

Runner.finish()
