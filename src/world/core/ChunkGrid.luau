--!strict
-- La grilla de chunks del mundo: cada chunk es un cuadrado de CHUNK_SIZE_STUDS de lado en el plano, y el chunk (0, 0)
-- empieza en el origen. Las coordenadas de chunk son enteras.

local WorldConfig = require("./WorldConfig")

local CHUNK_STUDS = WorldConfig.CHUNK_SIZE_STUDS
local KEY_STRIDE = WorldConfig.TERRAIN_CHUNK_KEY_STRIDE

local ChunkGrid = {}

-- Coordenada de chunk que contiene a una coordenada en studs.
function ChunkGrid.getCoordinate(studs: number): number
	return math.floor(studs / CHUNK_STUDS)
end

-- Clave única de un chunk, para usarla como índice de tablas.
function ChunkGrid.getKey(chunkX: number, chunkZ: number): number
	return chunkX * KEY_STRIDE + chunkZ
end

-- Esquina de menor x y z de un chunk, en studs.
function ChunkGrid.getOriginStuds(chunkCoordinate: number): number
	return chunkCoordinate * CHUNK_STUDS
end

-- Distancia en el plano de un punto al cuadrado de un chunk (0 si el punto está adentro).
function ChunkGrid.getDistanceToChunk(chunkX: number, chunkZ: number, x: number, z: number): number
	local minX, minZ = chunkX * CHUNK_STUDS, chunkZ * CHUNK_STUDS
	local gapX = math.max(minX - x, x - (minX + CHUNK_STUDS), 0)
	local gapZ = math.max(minZ - z, z - (minZ + CHUNK_STUDS), 0)
	return math.sqrt(gapX * gapX + gapZ * gapZ)
end

return ChunkGrid
