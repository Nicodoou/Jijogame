--!strict
local ChunkGrid = require("../../src/world/core/ChunkGrid")
local ChunkPlan = require("../../src/world/core/ChunkPlan")
local ChunkRegistry = require("../../src/world/core/ChunkRegistry")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local WorldConfig = require("../../src/world/core/WorldConfig")

type RoadPathSegment = RoadPath.Segment

local CHUNK = WorldConfig.CHUNK_SIZE_STUDS
local INFLUENCE_STUDS = 100
local READY_RADIUS = 64
local MIN_VOXEL_Y = 4
local LAYERS = 6

-- Un tramo recto hacia +x, a z = 0, que empieza en `startX`.
local function createSegment(index: number, startX: number): RoadPathSegment
	return SyntheticRoad.createSegments({
		segmentCount = 1,
		firstSegmentIndex = index,
		startX = startX,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return 50
		end,
	})[1]
end

local function createVoxels(chunkX: number, chunkZ: number, signature: number): VoxelChunkBuilder.ChunkVoxels
	return {
		chunkX = chunkX,
		chunkZ = chunkZ,
		minVoxelX = 0,
		minVoxelY = MIN_VOXEL_Y,
		minVoxelZ = 0,
		sizeX = 1,
		sizeY = LAYERS,
		sizeZ = 1,
		materials = {},
		occupancy = {},
		signature = signature,
	}
end

local function createBlocksWithSegments(count: number): RoadBlocks.RoadBlocks
	local blocks = RoadBlocks.new()
	for index = 0, count - 1 do
		blocks.addSegment(
			createSegment(index, index * SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS)
		)
	end
	return blocks
end

local function signatureOfChunk(blocks: RoadBlocks.RoadBlocks, chunkX: number, chunkZ: number): number
	return blocks.getSignature(
		chunkX * CHUNK,
		chunkZ * CHUNK,
		(chunkX + 1) * CHUNK,
		(chunkZ + 1) * CHUNK,
		INFLUENCE_STUDS
	)
end

Runner.test("recording a chunk keeps its vertical range, counts it once and removing it forgets it", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	local key = ChunkGrid.getKey(1, 0)
	Runner.expectEqual(registry.getCount(), 0)
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0)))
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0)))
	Runner.expectEqual(registry.getCount(), 1)
	local chunk = registry.get(key) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(chunk.minVoxelY, MIN_VOXEL_Y)
	Runner.expectEqual(chunk.maxVoxelY, MIN_VOXEL_Y + LAYERS - 1)
	Runner.expectEqual(registry.getAll()[key] == chunk, true)
	registry.remove(key)
	registry.remove(key)
	Runner.expectEqual(registry.getCount(), 0)
	Runner.expectEqual(registry.get(key), nil)
end)

Runner.test("a chunk recorded with the signature of its road is up to date, another one comes out outdated", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	Runner.expectEqual(registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0))), false)
	Runner.expectEqual(registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0) + 1)), true)
end)

Runner.test("a chunk is stale only if new road arrived near it and its signature changed", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0)))
	registry.record(createVoxels(8, 0, signatureOfChunk(blocks, 8, 0)))
	local near = registry.get(ChunkGrid.getKey(0, 0)) :: ChunkPlan.WrittenChunk
	local far = registry.get(ChunkGrid.getKey(8, 0)) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(registry.isStale(near), false)
	local newSegment = createSegment(1, SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS)
	blocks.addSegment(newSegment)
	-- Sin avisar que llegó un tramo, el registro no revisa nada.
	Runner.expectEqual(registry.isStale(near), false)
	registry.noteNewSegment(newSegment)
	-- El tramo nuevo (x de 256 a 512) está a más de la influencia del chunk 0 (x de 0 a 128)... pero no del chunk 1.
	Runner.expectEqual(registry.isStale(near), false)
	Runner.expectEqual(registry.isStale(far), false)
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0) + 1))
	local touched = registry.get(ChunkGrid.getKey(1, 0)) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(registry.isStale(touched), true)
	registry.clearNotes()
	-- Lo descubierto viejo sigue viejo aunque se olviden las notas: el plan puede descartar su cola antes de reescribirlo.
	Runner.expectEqual(registry.isStale(touched), true)
	-- Reescrito con la ruta de ahora, deja de estar viejo.
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0)))
	touched = registry.get(ChunkGrid.getKey(1, 0)) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(registry.isStale(touched), false)
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0) + 1))
	touched = registry.get(ChunkGrid.getKey(1, 0)) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(registry.isStale(touched), false)
	registry.flagForCheck(ChunkGrid.getKey(1, 0))
	Runner.expectEqual(registry.isStale(touched), true)
	Runner.expectEqual(registry.isStale(near), false)
	registry.clearNotes()
	Runner.expectEqual(registry.isStale(touched), true)
	-- Si se borra el chunk, no queda nada de lo que se sabía de él.
	registry.remove(ChunkGrid.getKey(1, 0))
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0)))
	touched = registry.get(ChunkGrid.getKey(1, 0)) :: ChunkPlan.WrittenChunk
	Runner.expectEqual(registry.isStale(touched), false)
end)

Runner.test("clearing the notes remembers the chunks that went stale even if no plan asked about them", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	registry.record(createVoxels(1, 0, signatureOfChunk(blocks, 1, 0)))
	registry.record(createVoxels(8, 0, signatureOfChunk(blocks, 8, 0)))
	local newSegment = createSegment(1, SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS)
	blocks.addSegment(newSegment)
	registry.noteNewSegment(newSegment)
	-- Ningún plan preguntó por el chunk (por ejemplo, está atrás del auto): igual tiene que saber que quedó viejo cuando el
	-- auto vuelva y lo quiera de nuevo.
	registry.clearNotes()
	Runner.expectEqual(registry.isStale(registry.get(ChunkGrid.getKey(1, 0)) :: ChunkPlan.WrittenChunk), true)
	Runner.expectEqual(registry.isStale(registry.get(ChunkGrid.getKey(8, 0)) :: ChunkPlan.WrittenChunk), false)
end)

Runner.test("a stale chunk is not ready until it is rewritten, even if it is written", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	local position = vector.create(CHUNK / 2, 0, CHUNK / 2)
	registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0)))
	Runner.expectEqual(registry.isReadyAt(position, READY_RADIUS / 2), true)
	local newSegment = createSegment(1, SyntheticRoad.STEPS_PER_SEGMENT * WorldConfig.INTEGRATION_STEP_STUDS)
	blocks.addSegment(newSegment)
	registry.noteNewSegment(newSegment)
	registry.flagForCheck(ChunkGrid.getKey(0, 0))
	-- Todavía no se miró su firma: el registro no sabe que quedó viejo, y la ruta nueva no cambió su zona.
	Runner.expectEqual(registry.isReadyAt(position, READY_RADIUS / 2), true)
	registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0) + 1))
	registry.flagForCheck(ChunkGrid.getKey(0, 0))
	Runner.expectEqual(registry.isStale(registry.get(ChunkGrid.getKey(0, 0)) :: ChunkPlan.WrittenChunk), true)
	Runner.expectEqual(registry.isReadyAt(position, READY_RADIUS / 2), false)
	registry.record(createVoxels(0, 0, signatureOfChunk(blocks, 0, 0)))
	Runner.expectEqual(registry.isReadyAt(position, READY_RADIUS / 2), true)
end)

Runner.test("a position is ready only when every chunk within the radius is recorded", function()
	local blocks = createBlocksWithSegments(1)
	local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
	local corner = vector.create(CHUNK, 0, CHUNK)
	Runner.expectEqual(registry.isReadyAt(corner, READY_RADIUS), false)
	for _, cell in { { 0, 0 }, { 1, 0 }, { 0, 1 } } do
		registry.record(createVoxels(cell[1], cell[2], 0))
		Runner.expectEqual(registry.isReadyAt(corner, READY_RADIUS), false)
	end
	registry.record(createVoxels(1, 1, 0))
	Runner.expectEqual(registry.isReadyAt(corner, READY_RADIUS), true)
	registry.remove(ChunkGrid.getKey(1, 1))
	Runner.expectEqual(registry.isReadyAt(corner, READY_RADIUS), false)
end)

Runner.test(
	"chunks that the circle does not touch do not matter, even if they are inside the square around it",
	function()
		local blocks = createBlocksWithSegments(1)
		local registry = ChunkRegistry.new(blocks, INFLUENCE_STUDS)
		-- A 2 studs de la esquina de cuatro chunks: los dos vecinos laterales quedan a 2 studs y el diagonal a 2,83.
		local position = vector.create(CHUNK - 2, 0, CHUNK - 2)
		registry.record(createVoxels(0, 0, 0))
		registry.record(createVoxels(1, 0, 0))
		registry.record(createVoxels(0, 1, 0))
		Runner.expectEqual(registry.isReadyAt(position, 2.5), true)
		Runner.expectEqual(registry.isReadyAt(position, 3), false)
		registry.record(createVoxels(1, 1, 0))
		Runner.expectEqual(registry.isReadyAt(position, 3), true)
	end
)

Runner.finish()
