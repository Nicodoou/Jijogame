--!strict
-- Decide qué trabajo hace falta sobre los chunks: escribir los que se quieren y no están, reescribir los que quedaron
-- viejos y borrar los que ya no se conservan. Los que se escriben van primero, del más cercano al auto al más lejano;
-- los borrados, después. No escribe nada ni mide tiempo.

local ChunkCorridor = require("./ChunkCorridor")
local ChunkGrid = require("./ChunkGrid")
local WorldConfig = require("./WorldConfig")

-- Lo que se sabe de un chunk ya escrito: el tramo vertical que ocupa y con qué ruta se armó.
export type WrittenChunk = {
	chunkX: number,
	chunkZ: number,
	minVoxelY: number,
	maxVoxelY: number,
	signature: number,
}

export type WorkKind = "write" | "rewrite" | "clear"

export type PlannedWork = {
	kind: WorkKind,
	chunkX: number,
	chunkZ: number,
	key: number,
}

local HALF_CHUNK_STUDS = WorldConfig.CHUNK_SIZE_STUDS / 2

local ChunkPlan = {}

-- `wanted` son los chunks que tienen que estar; `kept`, los que se conservan si ya están (incluye a `wanted`, con
-- histéresis). `busyKey` es el chunk que se está armando, que no se vuelve a pedir. `isStale` dice si un chunk
-- escrito se armó con una ruta que ya cambió.
function ChunkPlan.build(
	wanted: { [number]: ChunkCorridor.ChunkCell },
	kept: { [number]: ChunkCorridor.ChunkCell },
	written: { [number]: WrittenChunk },
	busyKey: number?,
	vehicleX: number,
	vehicleZ: number,
	isStale: (WrittenChunk) -> boolean
): { PlannedWork }
	local writes: { PlannedWork } = {}
	local distances: { [number]: number } = {}
	for key, cell in wanted do
		if key ~= busyKey then
			local record = written[key]
			if record == nil or isStale(record) then
				table.insert(writes, {
					kind = if record == nil then "write" else "rewrite",
					chunkX = cell.chunkX,
					chunkZ = cell.chunkZ,
					key = key,
				})
				local centerX = ChunkGrid.getOriginStuds(cell.chunkX) + HALF_CHUNK_STUDS
				local centerZ = ChunkGrid.getOriginStuds(cell.chunkZ) + HALF_CHUNK_STUDS
				distances[key] = (centerX - vehicleX) ^ 2 + (centerZ - vehicleZ) ^ 2
			end
		end
	end
	-- La clave desempata, así el orden no depende del orden en que Luau recorre la tabla.
	table.sort(writes, function(first: PlannedWork, second: PlannedWork): boolean
		if distances[first.key] ~= distances[second.key] then
			return distances[first.key] < distances[second.key]
		end
		return first.key < second.key
	end)
	local clears: { PlannedWork } = {}
	for key, record in written do
		if kept[key] == nil and key ~= busyKey then
			table.insert(clears, { kind = "clear", chunkX = record.chunkX, chunkZ = record.chunkZ, key = key })
		end
	end
	table.sort(clears, function(first: PlannedWork, second: PlannedWork): boolean
		return first.key < second.key
	end)
	table.move(clears, 1, #clears, #writes + 1, writes)
	return writes
end

return ChunkPlan
