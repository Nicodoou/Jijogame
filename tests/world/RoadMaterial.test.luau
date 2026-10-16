--!strict
-- El material de la superficie del camino (WP-11): ripio en la ruta, tierra en la banquina y el del bioma afuera. La distancia
-- al eje se mide acá por separado, contra la poligonal de las muestras, sin pasar por el terreno.
local BiomeBlend = require("../../src/world/core/BiomeBlend")
local BiomeMap = require("../../src/world/core/BiomeMap")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local TerrainHeightField = require("../../src/world/core/TerrainHeightField")
local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local WorldConfig = require("../../src/world/core/WorldConfig")

local VOXEL = WorldConfig.TERRAIN_VOXEL_STUDS
local CHUNK_VOXELS = WorldConfig.CHUNK_SIZE_STUDS // VOXEL
local ROAD_HALF_WIDTH = WorldConfig.ROAD_WIDTH_STUDS / 2
local SHOULDER_EDGE = ROAD_HALF_WIDTH + WorldConfig.SHOULDER_WIDTH_STUDS
local SEGMENTS = 5
local SEED = 12
local STRAIGHT_CHUNK_X = 2
local SURFACE_HEIGHT = 50.5
local OFFROAD_MATERIAL = "Rock"
-- La poligonal de muestras y el arco del terreno difieren en milésimas: no se juzgan las columnas pegadas al borde.
local EDGE_MARGIN = 0.1
local MIN_COLUMNS_PER_KIND = 150
-- Media vuelta de radio mínimo (pi * R studs de arco), en pasos de integración.
local TURN_STEPS = math.floor(math.pi * WorldConfig.MIN_CURVE_RADIUS_STUDS / WorldConfig.INTEGRATION_STEP_STUDS)

local rockyBiome: BiomeTypes.BiomeDefinition = {
	id = "rocky",
	climate = {
		relief = { min = 0, max = 1 },
		humidity = { min = 0, max = 1 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 1, hillRoughness = 1 },
	materials = {
		surface = { { material = OFFROAD_MATERIAL, proportion = 1 } },
		transition = "Slate",
		deep = "Basalt",
	},
	surfaces = { offroad = "Grass", patches = {} },
	decoration = {},
}
local ROCKY: { BiomeTypes.BiomeDefinition } = { rockyBiome }

local function createSegments(startZ: number, curvatureAt: (number) -> number): { RoadPath.Segment }
	return SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		startX = 0,
		startZ = startZ,
		startHeadingRadians = 0,
		curvatureAt = curvatureAt,
		heightAt = function()
			return SURFACE_HEIGHT
		end,
	})
end

local function createBuilder(segments: { RoadPath.Segment }): VoxelChunkBuilder.VoxelChunkBuilder
	local blocks = RoadBlocks.new()
	for _, segment in segments do
		blocks.addSegment(segment)
	end
	return VoxelChunkBuilder.new({
		heightField = TerrainHeightField.new(SEED, ROCKY, blocks),
		biomeMap = BiomeMap.new(SEED, ROCKY),
		picker = BiomeBlend.newPicker(SEED, ROCKY),
		catalog = ROCKY,
	})
end

local function buildChunk(builder: VoxelChunkBuilder.VoxelChunkBuilder, chunkX: number, chunkZ: number)
	builder.begin(chunkX, chunkZ, nil)
	while builder.getRemainingSteps() > 0 do
		builder.runStep()
	end
	return builder.getResult()
end

local function findTopMaterial(result: VoxelChunkBuilder.ChunkVoxels, row: number, column: number): string
	for layer = result.sizeY, 1, -1 do
		if result.occupancy[row][layer][column] > 0 then
			return result.materials[row][layer][column]
		end
	end
	error("the column has no terrain")
end

local function distanceToSegment(x: number, z: number, from: vector, to: vector): number
	local deltaX, deltaZ = to.x - from.x, to.z - from.z
	local lengthSquared = deltaX * deltaX + deltaZ * deltaZ
	local along = if lengthSquared == 0 then 0 else ((x - from.x) * deltaX + (z - from.z) * deltaZ) / lengthSquared
	along = math.clamp(along, 0, 1)
	return math.sqrt((x - from.x - along * deltaX) ^ 2 + (z - from.z - along * deltaZ) ^ 2)
end

local function distanceToPolyline(positions: { vector }, x: number, z: number): number
	local nearest = math.huge
	for index = 2, #positions do
		nearest = math.min(nearest, distanceToSegment(x, z, positions[index - 1], positions[index]))
	end
	return nearest
end

local function collectPositions(segments: { RoadPath.Segment }): { vector }
	local positions: { vector } = {}
	for _, segment in segments do
		for _, sample in segment.samples do
			table.insert(positions, sample.position)
		end
	end
	return positions
end

local function expectedMaterial(distance: number): string
	if distance <= ROAD_HALF_WIDTH then
		return "Limestone"
	end
	return if distance <= SHOULDER_EDGE then "Ground" else OFFROAD_MATERIAL
end

local function isNearEdge(distance: number): boolean
	return math.abs(distance - ROAD_HALF_WIDTH) < EDGE_MARGIN or math.abs(distance - SHOULDER_EDGE) < EDGE_MARGIN
end

-- Revisa todas las columnas de los chunks dados contra la distancia a la poligonal y cuenta cuántas hay de cada material.
local function checkChunks(
	segments: { RoadPath.Segment },
	chunks: { { number } },
	skipsEdges: boolean
): { [string]: number }
	local builder = createBuilder(segments)
	local positions = collectPositions(segments)
	local counts: { [string]: number } = {}
	for _, chunk in chunks do
		local chunkX, chunkZ = chunk[1], chunk[2]
		local result = buildChunk(builder, chunkX, chunkZ)
		for row = 1, CHUNK_VOXELS do
			for column = 1, CHUNK_VOXELS do
				local x = chunkX * WorldConfig.CHUNK_SIZE_STUDS + (row - 0.5) * VOXEL
				local z = chunkZ * WorldConfig.CHUNK_SIZE_STUDS + (column - 0.5) * VOXEL
				local distance = distanceToPolyline(positions, x, z)
				if not (skipsEdges and isNearEdge(distance)) then
					local top = findTopMaterial(result, row, column)
					Runner.expectEqual(top, expectedMaterial(distance))
					counts[top] = (counts[top] or 0) + 1
				end
			end
		end
	end
	return counts
end

local function straightCurvature(): number
	return 0
end

local function uTurnCurvature(step: number): number
	return if step < TURN_STEPS then 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS else 0
end

Runner.test(
	"on a straight road the center columns are Limestone, the shoulder Ground and the rest the biome",
	function()
		local counts = checkChunks(
			createSegments(0, straightCurvature),
			{ { STRAIGHT_CHUNK_X, 0 }, { STRAIGHT_CHUNK_X, -1 } },
			false
		)
		Runner.expectEqual(counts.Limestone, 2 * 2 * CHUNK_VOXELS)
		Runner.expectEqual(counts.Ground, 2 * CHUNK_VOXELS)
		Runner.expectEqual(counts.Rock, 2 * (CHUNK_VOXELS - 3) * CHUNK_VOXELS)
	end
)

Runner.test(
	"a column whose center is exactly on the edge of the road is Limestone, and on the edge of the shoulder Ground",
	function()
		-- Con el eje en z = 2 los centros de las columnas quedan a 0, 4, 8, 12, 16...: el 8 y el 12 caen justo en los bordes.
		local startZ = 2
		local builder = createBuilder(createSegments(startZ, straightCurvature))
		local result = buildChunk(builder, STRAIGHT_CHUNK_X, 0)
		for column = 1, 6 do
			local distance = math.abs((column - 0.5) * VOXEL - startZ)
			local expected = if distance <= ROAD_HALF_WIDTH
				then "Limestone"
				elseif distance <= SHOULDER_EDGE then "Ground"
				else OFFROAD_MATERIAL
			Runner.expectEqual(findTopMaterial(result, 7, column), expected)
		end
		Runner.expectEqual(findTopMaterial(result, 7, 3), "Limestone")
		Runner.expectEqual(findTopMaterial(result, 7, 4), "Ground")
		Runner.expectEqual(findTopMaterial(result, 7, 5), OFFROAD_MATERIAL)
	end
)

Runner.test(
	"on a tight U-turn the material follows the distance to the nearest point of the road, not the lateral one",
	function()
		local chunks = { { 0, 0 }, { -1, 0 }, { 0, 1 }, { -1, 1 } }
		local counts = checkChunks(createSegments(0, uTurnCurvature), chunks, true)
		Runner.expectEqual((counts.Limestone or 0) > MIN_COLUMNS_PER_KIND, true)
		Runner.expectEqual((counts.Ground or 0) > MIN_COLUMNS_PER_KIND / 3, true)
		Runner.expectEqual((counts.Rock or 0) > MIN_COLUMNS_PER_KIND, true)
	end
)

Runner.test("the same road gives the same materials twice", function()
	local segments = createSegments(0, uTurnCurvature)
	local first = checkChunks(segments, { { 0, 0 } }, true)
	local second = checkChunks(segments, { { 0, 0 } }, true)
	Runner.expectEqual(first.Limestone, second.Limestone)
	Runner.expectEqual(first.Ground, second.Ground)
	Runner.expectEqual(first.Rock, second.Rock)
end)

Runner.finish()
