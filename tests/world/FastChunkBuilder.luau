--!strict
-- Un armador de chunks de mentira para probar el planificador sin pagar el costo de armar cada chunk de verdad: cumple la
-- misma interfaz que VoxelChunkBuilder, usa la ruta real (la firma sale de la altura) pero solo mide una columna del
-- chunk y arma tablas de tres capas. No es una prueba: no termina en Runner.finish().

local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local VoxelTables = require("../../src/world/core/VoxelTables")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CHUNK_VOXELS = WorldConfig.CHUNK_SIZE_STUDS // WorldConfig.TERRAIN_VOXEL_STUDS
local LAYERS = 3
local TOTAL_STEPS = 3
local EMPTY = "Air"
local FOREST_WEIGHTS = { forest = 1 }

local FastChunkBuilder = {}

function FastChunkBuilder.create(dependencies: VoxelChunkBuilder.Dependencies): VoxelChunkBuilder.VoxelChunkBuilder
	local tables = VoxelTables.new(CHUNK_VOXELS, CHUNK_VOXELS, EMPTY)
	tables.setLayerCount(LAYERS)
	local result: VoxelChunkBuilder.ChunkVoxels = {
		chunkX = 0,
		chunkZ = 0,
		minVoxelX = 0,
		minVoxelY = 0,
		minVoxelZ = 0,
		sizeX = CHUNK_VOXELS,
		sizeY = LAYERS,
		sizeZ = CHUNK_VOXELS,
		materials = tables.materials,
		occupancy = tables.occupancy,
		signature = 0,
	}
	local stepsDone = TOTAL_STEPS
	local coverBelow, coverAbove = math.huge, -math.huge
	local sampledHeight = 0

	local function begin(chunkX: number, chunkZ: number, coverRange: VoxelChunkBuilder.VoxelRange?)
		result.chunkX, result.chunkZ = chunkX, chunkZ
		coverBelow, coverAbove = math.huge, -math.huge
		if coverRange ~= nil then
			coverBelow, coverAbove = coverRange.minVoxelY, coverRange.maxVoxelY
		end
		stepsDone = 0
	end

	local function runStep()
		stepsDone += 1
		local size = WorldConfig.CHUNK_SIZE_STUDS
		local originX, originZ = result.chunkX * size, result.chunkZ * size
		if stepsDone == 1 then
			dependencies.heightField.setArea(originX, originZ, originX + size, originZ + size)
			result.signature = dependencies.heightField.getAreaSignature()
		elseif stepsDone == 2 then
			sampledHeight =
				dependencies.heightField.sampleColumn(originX + size / 2, originZ + size / 2, FOREST_WEIGHTS)
		else
			local lowest = math.min(math.floor(sampledHeight / WorldConfig.TERRAIN_VOXEL_STUDS) - 1, coverBelow)
			local highest = math.max(lowest + LAYERS - 1, coverAbove)
			result.minVoxelY, result.sizeY = lowest, highest - lowest + 1
			tables.setLayerCount(result.sizeY)
			for layer = 1, result.sizeY do
				tables.occupancy[CHUNK_VOXELS // 2][layer][1] = sampledHeight + layer
			end
		end
	end

	return {
		begin = begin,
		getRemainingSteps = function(): number
			return TOTAL_STEPS - stepsDone
		end,
		runStep = runStep,
		getResult = function(): VoxelChunkBuilder.ChunkVoxels
			return result
		end,
	}
end

return FastChunkBuilder
