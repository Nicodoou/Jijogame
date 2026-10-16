--!strict
-- El registro de los chunks escritos en el Terrain: qué tramo vertical ocupa cada uno y con qué ruta se armó. Con eso
-- responde si el mundo está listo en un punto (IsWorldReadyAt) y si un chunk quedó viejo porque llegó ruta nueva a su
-- alrededor (el caso de la ruta que vuelve por una zona vieja). Un chunk que se descubre viejo queda viejo hasta que se
-- reescribe: el plan puede tirar su cola de trabajo antes de llegar a él, y no puede depender de acordarse de avisos.

local ChunkGrid = require("./ChunkGrid")
local ChunkPlan = require("./ChunkPlan")
local RoadBlocks = require("./RoadBlocks")
local RoadPath = require("./RoadPath")
local VoxelChunkBuilder = require("./VoxelChunkBuilder")
local WorldConfig = require("./WorldConfig")

type WrittenChunk = ChunkPlan.WrittenChunk

export type ChunkRegistry = {
	get: (key: number) -> WrittenChunk?,
	-- Todos los chunks escritos por clave, para armar el plan.
	getAll: () -> { [number]: WrittenChunk },
	getCount: () -> number,
	-- Anota un chunk recién escrito. Devuelve true si la ruta de su zona ya cambió mientras se armaba.
	record: (voxels: VoxelChunkBuilder.ChunkVoxels) -> boolean,
	remove: (key: number) -> (),
	-- Avisa que llegó un tramo de ruta nuevo: los chunks escritos cerca de él pueden haber quedado viejos.
	noteNewSegment: (segment: RoadPath.Segment) -> (),
	-- Marca que hay que revisar un chunk en el próximo plan, aunque no haya llegado ruta nueva cerca.
	flagForCheck: (key: number) -> (),
	-- Olvida los avisos de ruta nueva, una vez que el plan los revisó. No olvida los chunks que ya se descubrieron viejos.
	clearNotes: () -> (),
	-- true si el chunk se armó con una ruta distinta de la que lo influye ahora, hasta que se vuelva a escribir. Solo mira
	-- la firma de los chunks avisados; los que ya se descubrieron viejos no hace falta volver a mirarlos.
	isStale: (record: WrittenChunk) -> boolean,
	-- true si todos los chunks que tocan el círculo de `radiusStuds` alrededor del punto están escritos y no se saben viejos.
	isReadyAt: (position: vector, radiusStuds: number) -> boolean,
}

type Box = { minX: number, minZ: number, maxX: number, maxZ: number }

local CHUNK_STUDS = WorldConfig.CHUNK_SIZE_STUDS

local ChunkRegistryModule = {}

-- `influenceStuds` es hasta dónde influye la ruta sobre las columnas de un chunk (TerrainHeightField.getInfluenceStuds).
function ChunkRegistryModule.new(blocks: RoadBlocks.RoadBlocks, influenceStuds: number): ChunkRegistry
	local written: { [number]: WrittenChunk } = {}
	local count = 0
	local newSegmentBoxes: { Box } = {}
	local flaggedKeys: { [number]: boolean } = {}
	-- Los chunks escritos que se descubrieron viejos y todavía no se reescribieron.
	local staleKeys: { [number]: boolean } = {}

	local function getSignatureOfChunk(chunkX: number, chunkZ: number): number
		local originX, originZ = ChunkGrid.getOriginStuds(chunkX), ChunkGrid.getOriginStuds(chunkZ)
		return blocks.getSignature(originX, originZ, originX + CHUNK_STUDS, originZ + CHUNK_STUDS, influenceStuds)
	end

	local function isNearNewSegment(chunkX: number, chunkZ: number): boolean
		local originX, originZ = ChunkGrid.getOriginStuds(chunkX), ChunkGrid.getOriginStuds(chunkZ)
		for _, box in newSegmentBoxes do
			local gapX = math.max(box.minX - (originX + CHUNK_STUDS), originX - box.maxX, 0)
			local gapZ = math.max(box.minZ - (originZ + CHUNK_STUDS), originZ - box.maxZ, 0)
			if gapX * gapX + gapZ * gapZ < influenceStuds * influenceStuds then
				return true
			end
		end
		return false
	end

	local function record(voxels: VoxelChunkBuilder.ChunkVoxels): boolean
		local key = ChunkGrid.getKey(voxels.chunkX, voxels.chunkZ)
		if written[key] == nil then
			count += 1
		end
		staleKeys[key] = nil
		written[key] = {
			chunkX = voxels.chunkX,
			chunkZ = voxels.chunkZ,
			minVoxelY = voxels.minVoxelY,
			maxVoxelY = voxels.minVoxelY + voxels.sizeY - 1,
			signature = voxels.signature,
		}
		return getSignatureOfChunk(voxels.chunkX, voxels.chunkZ) ~= voxels.signature
	end

	local function remove(key: number)
		if written[key] ~= nil then
			written[key] = nil
			count -= 1
		end
		staleKeys[key] = nil
	end

	local function noteNewSegment(segment: RoadPath.Segment)
		local box: Box = { minX = math.huge, minZ = math.huge, maxX = -math.huge, maxZ = -math.huge }
		for _, sample in segment.samples do
			box.minX, box.maxX = math.min(box.minX, sample.position.x), math.max(box.maxX, sample.position.x)
			box.minZ, box.maxZ = math.min(box.minZ, sample.position.z), math.max(box.maxZ, sample.position.z)
		end
		table.insert(newSegmentBoxes, box)
	end

	local function isStale(chunk: WrittenChunk): boolean
		local key = ChunkGrid.getKey(chunk.chunkX, chunk.chunkZ)
		if staleKeys[key] == true then
			return true
		end
		if not (flaggedKeys[key] == true or isNearNewSegment(chunk.chunkX, chunk.chunkZ)) then
			return false
		end
		if getSignatureOfChunk(chunk.chunkX, chunk.chunkZ) == chunk.signature then
			return false
		end
		-- Se recuerda: el plan siguiente se arma sin los avisos de este, y la cola de este puede no llegar a correr.
		staleKeys[key] = true
		return true
	end

	-- Antes de olvidar los avisos se revisan todos los chunks escritos, no solo los que el plan quiere ahora: un chunk
	-- que quedó fuera de lo querido (atrás del auto) y vuelve a entrar más tarde tiene que acordarse de que está viejo.
	local function clearNotes()
		for _, chunk in written do
			isStale(chunk)
		end
		newSegmentBoxes, flaggedKeys = {}, {}
	end

	local function isReadyAt(position: vector, radiusStuds: number): boolean
		for chunkX = ChunkGrid.getCoordinate(position.x - radiusStuds), ChunkGrid.getCoordinate(position.x + radiusStuds) do
			for chunkZ = ChunkGrid.getCoordinate(position.z - radiusStuds), ChunkGrid.getCoordinate(position.z + radiusStuds) do
				local distance = ChunkGrid.getDistanceToChunk(chunkX, chunkZ, position.x, position.z)
				local key = ChunkGrid.getKey(chunkX, chunkZ)
				if distance <= radiusStuds and (written[key] == nil or staleKeys[key] == true) then
					return false
				end
			end
		end
		return true
	end

	return {
		get = function(key: number): WrittenChunk?
			return written[key]
		end,
		getAll = function(): { [number]: WrittenChunk }
			return written
		end,
		getCount = function(): number
			return count
		end,
		record = record,
		remove = remove,
		noteNewSegment = noteNewSegment,
		flagForCheck = function(key: number)
			flaggedKeys[key] = true
		end,
		clearNotes = clearNotes,
		isStale = isStale,
		isReadyAt = isReadyAt,
	}
end

return ChunkRegistryModule
