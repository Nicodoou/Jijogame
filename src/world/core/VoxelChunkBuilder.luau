--!strict
-- Arma las tablas de material y de ocupación de un chunk, de a pasos chicos para entrar en el presupuesto de un frame:
-- un paso de preparación (el clima y la ruta de la zona), una fila de columnas por paso (altura y material de cada
-- una) y una fila de vóxeles por paso. No llama a la API de Roblox: el resultado se escribe afuera.
--
-- La ocupación se calcula para (altura - TERRAIN_SURFACE_OFFSET_STUDS): en Studio la superficie del Terrain queda esos
-- studs más arriba de la que dice la ocupación (medido, ver terreno.md).

local BiomeBlend = require("./BiomeBlend")
local BiomeMap = require("./BiomeMap")
local BiomeTypes = require("./BiomeTypes")
local ChunkGrid = require("./ChunkGrid")
local TerrainHeightField = require("./TerrainHeightField")
local VoxelTables = require("./VoxelTables")
local WorldConfig = require("./WorldConfig")

-- Posiciones de vóxel en índices enteros: el vóxel i cubre de TERRAIN_VOXEL_STUDS * i a TERRAIN_VOXEL_STUDS * (i + 1).
export type ChunkVoxels = {
	chunkX: number,
	chunkZ: number,
	minVoxelX: number,
	minVoxelY: number,
	minVoxelZ: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	materials: { { { string } } },
	occupancy: { { { number } } },
	-- Firma de la ruta que se usó (RoadBlocks.getSignature de la zona del chunk): sirve para saber si quedó vieja.
	signature: number,
}

-- Tramo vertical de vóxeles que ya tiene algo escrito. Al reescribir un chunk se cubre también, con aire donde haga falta.
export type VoxelRange = {
	minVoxelY: number,
	maxVoxelY: number,
}

export type Dependencies = {
	heightField: TerrainHeightField.TerrainHeightField,
	biomeMap: BiomeMap.BiomeMap,
	picker: BiomeBlend.Picker,
	catalog: { BiomeTypes.BiomeDefinition },
}

export type VoxelChunkBuilder = {
	-- Empieza un chunk nuevo. Lo que estuviera armándose se abandona.
	begin: (chunkX: number, chunkZ: number, coverRange: VoxelRange?) -> (),
	-- Cuántos pasos faltan para terminar el chunk que se está armando (0 si ya terminó o no empezó).
	getRemainingSteps: () -> number,
	runStep: () -> (),
	-- El chunk terminado. Las tablas se reutilizan: valen hasta el próximo `begin`.
	getResult: () -> ChunkVoxels,
}

local VOXEL_STUDS = WorldConfig.TERRAIN_VOXEL_STUDS
local CHUNK_VOXELS = WorldConfig.CHUNK_SIZE_STUDS // VOXEL_STUDS
local COLUMN_COUNT = CHUNK_VOXELS * CHUNK_VOXELS
local SURFACE_OFFSET_STUDS = WorldConfig.TERRAIN_SURFACE_OFFSET_STUDS
local DEPTH_STUDS = WorldConfig.TERRAIN_DEPTH_STUDS
local HALF = 0.5
-- Un paso de preparación, una fila de columnas por cada x y una fila de vóxeles por cada x.
local PREPARE_STEPS = 1
local TOTAL_STEPS = PREPARE_STEPS + 2 * CHUNK_VOXELS
-- Claves de material propias: el adaptador las traduce a Enum.Material.
local AIR_MATERIAL = "Air"
local ROAD_MATERIAL = "Ground"
local MUD_SURFACE = "Mud"

if CHUNK_VOXELS * VOXEL_STUDS ~= WorldConfig.CHUNK_SIZE_STUDS then
	error("CHUNK_SIZE_STUDS has to be a whole number of voxels", 0)
end

local VoxelChunkBuilderModule = {}

function VoxelChunkBuilderModule.new(dependencies: Dependencies): VoxelChunkBuilder
	local heightField, biomeMap, picker, catalog =
		dependencies.heightField, dependencies.biomeMap, dependencies.picker, dependencies.catalog
	local tables = VoxelTables.new(CHUNK_VOXELS, CHUNK_VOXELS, AIR_MATERIAL)
	local columnSurfaceVoxels = table.create(COLUMN_COUNT, 0)
	local columnFillHeights = table.create(COLUMN_COUNT, 0)
	local columnTopMaterials = table.create(COLUMN_COUNT, AIR_MATERIAL)
	local columnDeepMaterials = table.create(COLUMN_COUNT, AIR_MATERIAL)
	local result: ChunkVoxels = {
		chunkX = 0,
		chunkZ = 0,
		minVoxelX = 0,
		minVoxelY = 0,
		minVoxelZ = 0,
		sizeX = CHUNK_VOXELS,
		sizeY = 0,
		sizeZ = CHUNK_VOXELS,
		materials = tables.materials,
		occupancy = tables.occupancy,
		signature = 0,
	}
	local stepsDone = 0
	local hasBegun = false
	local lowestVoxelY, highestVoxelY = 0, 0
	local lowestHeight = 0
	local coverBelow, coverAbove = math.huge, -math.huge

	local function prepareChunk()
		local originX, originZ = ChunkGrid.getOriginStuds(result.chunkX), ChunkGrid.getOriginStuds(result.chunkZ)
		local size = WorldConfig.CHUNK_SIZE_STUDS
		heightField.setArea(originX, originZ, originX + size, originZ + size)
		biomeMap.prepareArea(originX, originZ, size)
		result.signature = heightField.getAreaSignature()
		highestVoxelY, lowestHeight = -math.huge, math.huge
	end

	-- Altura y materiales de las columnas de una fila de x.
	local function measureColumnRow(row: number)
		local originX, originZ = ChunkGrid.getOriginStuds(result.chunkX), ChunkGrid.getOriginStuds(result.chunkZ)
		local x = originX + (row - HALF) * VOXEL_STUDS
		for column = 1, CHUNK_VOXELS do
			local z = originZ + (column - HALF) * VOXEL_STUDS
			local weights = biomeMap.getWeightsInArea(x, z)
			local height, beyondShoulder = heightField.sampleColumn(x, z, weights)
			local index = (row - 1) * CHUNK_VOXELS + column
			local fillHeight = (height - SURFACE_OFFSET_STUDS) / VOXEL_STUDS
			-- El vóxel más alto con algo de terreno: si la superficie cae justo en un borde, es el de abajo.
			local surfaceVoxel = math.ceil(fillHeight) - 1
			columnFillHeights[index], columnSurfaceVoxels[index] = fillHeight, surfaceVoxel
			columnDeepMaterials[index] = BiomeBlend.pickDeepMaterial(weights, catalog)
			if beyondShoulder == 0 then
				columnTopMaterials[index] = ROAD_MATERIAL
			elseif picker.pickOffroadSurface(weights, x, z, beyondShoulder) == MUD_SURFACE then
				columnTopMaterials[index] = MUD_SURFACE
			else
				columnTopMaterials[index] = picker.pickMaterial(weights, x, z)
			end
			highestVoxelY = math.max(highestVoxelY, surfaceVoxel + 1)
			lowestHeight = math.min(lowestHeight, height)
		end
	end

	-- Con todas las alturas medidas se sabe cuántas capas hacen falta, y se dimensionan las tablas.
	local function layOutTables()
		lowestVoxelY = math.floor((lowestHeight - SURFACE_OFFSET_STUDS - DEPTH_STUDS) / VOXEL_STUDS)
		lowestVoxelY, highestVoxelY = math.min(lowestVoxelY, coverBelow), math.max(highestVoxelY, coverAbove)
		result.minVoxelY, result.sizeY = lowestVoxelY, highestVoxelY - lowestVoxelY + 1
		result.minVoxelX = result.chunkX * CHUNK_VOXELS
		result.minVoxelZ = result.chunkZ * CHUNK_VOXELS
		tables.setLayerCount(result.sizeY)
	end

	local function fillVoxelRow(row: number)
		local materialLayers, occupancyLayers = tables.materials[row], tables.occupancy[row]
		for column = 1, CHUNK_VOXELS do
			local index = (row - 1) * CHUNK_VOXELS + column
			local fillHeight, surfaceVoxel = columnFillHeights[index], columnSurfaceVoxels[index]
			local topMaterial, deepMaterial = columnTopMaterials[index], columnDeepMaterials[index]
			for layer = 1, result.sizeY do
				local voxel = lowestVoxelY + layer - 1
				occupancyLayers[layer][column] = math.clamp(fillHeight - voxel, 0, 1)
				materialLayers[layer][column] = if voxel == surfaceVoxel
					then topMaterial
					elseif voxel < surfaceVoxel then deepMaterial
					else AIR_MATERIAL
			end
		end
	end

	local function begin(chunkX: number, chunkZ: number, coverRange: VoxelRange?)
		if math.floor(chunkX) ~= chunkX or math.floor(chunkZ) ~= chunkZ then
			error("the chunk coordinates have to be integers", 2)
		end
		result.chunkX, result.chunkZ = chunkX, chunkZ
		coverBelow, coverAbove = math.huge, -math.huge
		if coverRange ~= nil then
			coverBelow, coverAbove = coverRange.minVoxelY, coverRange.maxVoxelY
		end
		stepsDone, hasBegun = 0, true
	end

	local function getRemainingSteps(): number
		return if hasBegun then TOTAL_STEPS - stepsDone else 0
	end

	local function runStep()
		if not hasBegun or stepsDone >= TOTAL_STEPS then
			error("there is no chunk being built: call begin first", 2)
		end
		local step = stepsDone + 1
		if step == 1 then
			prepareChunk()
		elseif step <= PREPARE_STEPS + CHUNK_VOXELS then
			measureColumnRow(step - PREPARE_STEPS)
		else
			local row = step - PREPARE_STEPS - CHUNK_VOXELS
			if row == 1 then
				layOutTables()
			end
			fillVoxelRow(row)
		end
		stepsDone = step
	end

	local function getResult(): ChunkVoxels
		if not hasBegun or stepsDone < TOTAL_STEPS then
			error("the chunk is not finished", 2)
		end
		return result
	end

	return { begin = begin, getRemainingSteps = getRemainingSteps, runStep = runStep, getResult = getResult }
end

return VoxelChunkBuilderModule
