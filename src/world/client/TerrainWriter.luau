--!strict
-- Lo único del área que toca Workspace.Terrain: traduce las claves de material del núcleo a Enum.Material, escribe los
-- chunks con WriteVoxels y los borra con aire. Sin decisiones: el planificador del núcleo dice qué escribir y cuándo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VoxelChunkBuilder = require(ReplicatedStorage.world.core.VoxelChunkBuilder)
local WorldConfig = require(ReplicatedStorage.world.core.WorldConfig)
local WorldPlanner = require(ReplicatedStorage.world.core.WorldPlanner)

-- Los vóxeles del Terrain miden 4 studs: es un valor fijo del motor y también la resolución de WriteVoxels.
local VOXEL_STUDS = WorldConfig.TERRAIN_VOXEL_STUDS
local HALF = 0.5

-- Un material nuevo en un bioma se suma acá; si falta, escribir el chunk falla en vez de dejar un hueco.
local MATERIAL_BY_KEY: { [string]: Enum.Material } = {
	Air = Enum.Material.Air,
	Ground = Enum.Material.Ground,
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Mud = Enum.Material.Mud,
}

local TerrainWriter = {}

-- Devuelve una función que traduce las claves de un chunk a una tabla [x][y][z] de Enum.Material. La tabla se reutiliza
-- entre escrituras: las filas de z pasan de una pila a otra cuando cambia la altura, así no queda basura para el recolector.
local function newMaterialTranslator(
	sizeZ: number
): (voxels: VoxelChunkBuilder.ChunkVoxels) -> { { { Enum.Material } } }
	local layersByX: { { { Enum.Material } } } = {}
	local freeRows: { { Enum.Material } } = {}

	local function setLayerCount(sizeX: number, layerCount: number)
		for x = 1, sizeX do
			local layers = layersByX[x]
			if layers == nil then
				layers = {}
				layersByX[x] = layers
			end
			while #layers > layerCount do
				table.insert(freeRows, table.remove(layers) :: { Enum.Material })
			end
			while #layers < layerCount do
				table.insert(layers, table.remove(freeRows) or table.create(sizeZ, Enum.Material.Air))
			end
		end
	end

	return function(voxels)
		setLayerCount(voxels.sizeX, voxels.sizeY)
		for x = 1, voxels.sizeX do
			local keyLayers, enumLayers = voxels.materials[x], layersByX[x]
			for y = 1, voxels.sizeY do
				local keyRow, enumRow = keyLayers[y], enumLayers[y]
				for z = 1, voxels.sizeZ do
					local material = MATERIAL_BY_KEY[keyRow[z]]
					if material == nil then
						error(`unknown material key "{keyRow[z]}": add it to MATERIAL_BY_KEY`, 2)
					end
					enumRow[z] = material
				end
			end
		end
		return layersByX
	end
end

function TerrainWriter.new(terrain: Terrain): WorldPlanner.ChunkSink
	-- El camino es Mud: se pinta de marrón oscuro (el color es global del Terrain). Hoy el Mud solo se usa en el camino.
	local roadColor = WorldConfig.ROAD_COLOR_RGB
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(roadColor[1], roadColor[2], roadColor[3]))
	local translateMaterials = newMaterialTranslator(WorldConfig.CHUNK_SIZE_STUDS // VOXEL_STUDS)

	local function writeChunk(voxels: VoxelChunkBuilder.ChunkVoxels)
		local materials = translateMaterials(voxels)
		local corner = Vector3.new(voxels.minVoxelX, voxels.minVoxelY, voxels.minVoxelZ) * VOXEL_STUDS
		local size = Vector3.new(voxels.sizeX, voxels.sizeY, voxels.sizeZ) * VOXEL_STUDS
		terrain:WriteVoxels(Region3.new(corner, corner + size), VOXEL_STUDS, materials, voxels.occupancy)
	end

	local function clearChunk(chunkX: number, chunkZ: number, range: VoxelChunkBuilder.VoxelRange)
		local chunkStuds = WorldConfig.CHUNK_SIZE_STUDS
		local corner = Vector3.new(chunkX * chunkStuds, range.minVoxelY * VOXEL_STUDS, chunkZ * chunkStuds)
		local size = Vector3.new(chunkStuds, (range.maxVoxelY - range.minVoxelY + 1) * VOXEL_STUDS, chunkStuds)
		terrain:FillBlock(CFrame.new(corner + size * HALF), size, Enum.Material.Air)
	end

	return { writeChunk = writeChunk, clearChunk = clearChunk }
end

return TerrainWriter
