--!strict
-- Bloques de la ruta viva para el terreno: cada tramo se parte en bloques de TERRAIN_ROAD_BLOCK_STEPS pasos, con las
-- coordenadas en listas de números (sin `vector`) y su caja en el plano. Un bloque es lo bastante corto para que la
-- distancia de un punto a su eje tenga un único mínimo, y eso permite buscarlo por bisección.

local RoadFrame = require("./RoadFrame")
local RoadPath = require("./RoadPath")
local WorldConfig = require("./WorldConfig")

-- Los puntos van de 1 a BLOCK_STEPS + 1 y las aristas de 1 a BLOCK_STEPS (la arista i va del punto i al i + 1).
export type RoadBlock = {
	index: number,
	xs: { number },
	ys: { number },
	zs: { number },
	edgeX: { number },
	edgeZ: { number },
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

export type RoadBlocks = {
	-- Agrega los bloques de un tramo. Los tramos llegan en orden, sin saltos.
	addSegment: (segment: RoadPath.Segment) -> (),
	-- Olvida los bloques de los tramos con índice menor que el dado.
	forgetBefore: (segmentIndex: number) -> (),
	-- Bloques cuya caja queda a menos de `reach` del cuadrado dado, por índice, y una firma de cuáles son.
	gather: (minX: number, minZ: number, maxX: number, maxZ: number, reach: number) -> ({ RoadBlock }, number),
	-- La misma firma que da `gather`, sin armar la lista.
	getSignature: (minX: number, minZ: number, maxX: number, maxZ: number, reach: number) -> number,
}

local BLOCK_STEPS = WorldConfig.TERRAIN_ROAD_BLOCK_STEPS
local BLOCKS_PER_SEGMENT = RoadFrame.getStepsPerSegment() // BLOCK_STEPS
local SIGNATURE_MULTIPLIER = 2654435761
local SIGNATURE_MODULUS = 4294967296

if BLOCKS_PER_SEGMENT * BLOCK_STEPS ~= RoadFrame.getStepsPerSegment() then
	error("TERRAIN_ROAD_BLOCK_STEPS has to divide the steps of a segment", 0)
end

local function createBlock(index: number, samples: { RoadPath.RoadSample }, firstSample: number): RoadBlock
	local xs, ys, zs = table.create(BLOCK_STEPS + 1), table.create(BLOCK_STEPS + 1), table.create(BLOCK_STEPS + 1)
	local edgeX, edgeZ = table.create(BLOCK_STEPS), table.create(BLOCK_STEPS)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for point = 1, BLOCK_STEPS + 1 do
		local position = samples[firstSample + point - 1].position
		xs[point], ys[point], zs[point] = position.x, position.y, position.z
		minX, maxX = math.min(minX, position.x), math.max(maxX, position.x)
		minZ, maxZ = math.min(minZ, position.z), math.max(maxZ, position.z)
		if point > 1 then
			edgeX[point - 1], edgeZ[point - 1] = xs[point] - xs[point - 1], zs[point] - zs[point - 1]
		end
	end
	return {
		index = index,
		xs = xs,
		ys = ys,
		zs = zs,
		edgeX = edgeX,
		edgeZ = edgeZ,
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
	}
end

-- Distancia al cuadrado de un punto a una caja (0 si está adentro).
local function getBoxDistanceSquared(block: RoadBlock, minX: number, minZ: number, maxX: number, maxZ: number): number
	local gapX = math.max(block.minX - maxX, minX - block.maxX, 0)
	local gapZ = math.max(block.minZ - maxZ, minZ - block.maxZ, 0)
	return gapX * gapX + gapZ * gapZ
end

local RoadBlocksModule = {}

function RoadBlocksModule.new(): RoadBlocks
	local blocks: { [number]: RoadBlock } = {}
	local firstBlock = 0
	local lastBlock = -1

	local function addSegment(segment: RoadPath.Segment)
		local firstOfSegment = segment.index * BLOCKS_PER_SEGMENT
		if lastBlock >= firstBlock and firstOfSegment ~= lastBlock + 1 then
			error("the segments have to arrive in order, without gaps", 2)
		end
		if lastBlock < firstBlock then
			firstBlock = firstOfSegment
		end
		for offset = 0, BLOCKS_PER_SEGMENT - 1 do
			blocks[firstOfSegment + offset] =
				createBlock(firstOfSegment + offset, segment.samples, offset * BLOCK_STEPS + 1)
		end
		lastBlock = firstOfSegment + BLOCKS_PER_SEGMENT - 1
	end

	local function forgetBefore(segmentIndex: number)
		local firstKept = math.min(segmentIndex * BLOCKS_PER_SEGMENT, lastBlock + 1)
		for index = firstBlock, firstKept - 1 do
			blocks[index] = nil
		end
		firstBlock = math.max(firstBlock, firstKept)
	end

	local function gather(
		minX: number,
		minZ: number,
		maxX: number,
		maxZ: number,
		reach: number
	): ({ RoadBlock }, number)
		local gathered: { RoadBlock } = {}
		local signature = 0
		for index = firstBlock, lastBlock do
			local block = blocks[index]
			if getBoxDistanceSquared(block, minX, minZ, maxX, maxZ) < reach * reach then
				table.insert(gathered, block)
				signature = (signature + (index + 1) * SIGNATURE_MULTIPLIER) % SIGNATURE_MODULUS
			end
		end
		return gathered, signature
	end

	local function getSignature(minX: number, minZ: number, maxX: number, maxZ: number, reach: number): number
		local _, signature = gather(minX, minZ, maxX, maxZ, reach)
		return signature
	end

	return { addSegment = addSegment, forgetBefore = forgetBefore, gather = gather, getSignature = getSignature }
end

return RoadBlocksModule
