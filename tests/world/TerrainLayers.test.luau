--!strict
-- Capas de material del terreno (bug 2026-10-16-manchones-de-capas): en pendiente la superficie sube a escalones de un
-- vóxel y el de arriba queda casi vacío, así que el material de la superficie tiene que ocupar también los vóxeles de
-- abajo, hasta TERRAIN_TOP_LAYER_STUDS. Más abajo va el material profundo.
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
local TOP_LAYER = WorldConfig.TERRAIN_TOP_LAYER_STUDS
local ROAD_HALF_WIDTH = WorldConfig.ROAD_WIDTH_STUDS / 2
-- Los centros de las columnas quedan a 2, 6, 10... studs del eje: las que no pasan de la mitad del ancho son camino
-- (el borde cuenta como camino) y la siguiente es banquina.
local ROAD_COLUMNS = math.floor(ROAD_HALF_WIDTH / VOXEL + 0.5)
local SEED = 12
local SEGMENTS = 5
-- Un chunk que queda entero sobre la recta de 5 tramos que arranca en x = 0.
local ROAD_CHUNK_X = 1
local BASE_HEIGHTS = { 50, 50.5, 51.3, 53.9, 100.7 }
local ROAD_SLOPES_DEGREES = { 5, 10, 20 }
local HILL_SLOPES_DEGREES = { 20, 45, 62 }
-- Una columna con el borde de la capa a menos de esto del límite no se juzga: es el redondeo de los floats.
local BORDER_MARGIN = 1e-6
local ROAD = "Mud"
local BIOME_SURFACE = "Rock"
local BIOME_DEEP = "Basalt"
local FAR = math.huge

local function createBiome(surface: string, deep: string): { BiomeTypes.BiomeDefinition }
	return {
		{
			id = "layered",
			climate = {
				relief = { min = 0, max = 1 },
				humidity = { min = 0, max = 1 },
				temperature = { min = 0, max = 1 },
			},
			terrain = { hillAmplitudeScale = 1, hillRoughness = 1 },
			materials = { surface = { { material = surface, proportion = 1 } }, transition = "Slate", deep = deep },
			surfaces = { offroad = "Grass", patches = {} },
			decoration = {},
		},
	}
end

local function createBuilder(
	heightField: TerrainHeightField.TerrainHeightField,
	catalog: { BiomeTypes.BiomeDefinition }
): VoxelChunkBuilder.VoxelChunkBuilder
	return VoxelChunkBuilder.new({
		heightField = heightField,
		biomeMap = BiomeMap.new(SEED, catalog),
		picker = BiomeBlend.newPicker(SEED, catalog),
		catalog = catalog,
	})
end

local function buildChunk(builder: VoxelChunkBuilder.VoxelChunkBuilder, chunkX: number, chunkZ: number)
	builder.begin(chunkX, chunkZ, nil)
	while builder.getRemainingSteps() > 0 do
		builder.runStep()
	end
	return builder.getResult()
end

-- Un terreno sin ruta cuya altura sube con la pendiente dada en la dirección (directionX, directionZ), sin banquina.
local function createSlopedField(
	baseHeight: number,
	slopeDegrees: number,
	directionX: number,
	directionZ: number
): TerrainHeightField.TerrainHeightField
	local slope = math.tan(math.rad(slopeDegrees))
	return {
		setArea = function() end,
		getInfluenceStuds = function()
			return 0
		end,
		getAreaSignature = function()
			return 0
		end,
		sampleColumn = function(x: number, z: number)
			return baseHeight + slope * (directionX * x + directionZ * z), FAR, FAR
		end,
	}
end

-- Revisa una columna: los vóxeles con terreno cuyo borde de arriba queda a menos de TOP_LAYER bajo la superficie llevan
-- `topMaterial`; los de más abajo, `deepMaterial`. Devuelve cuántos vóxeles juzgó de cada clase.
local function checkColumn(
	result: VoxelChunkBuilder.ChunkVoxels,
	row: number,
	column: number,
	topMaterial: string,
	deepMaterial: string
): (number, number)
	local fill = -math.huge
	for layer = result.sizeY, 1, -1 do
		local occupancy = result.occupancy[row][layer][column]
		if occupancy > 0 then
			fill = (result.minVoxelY + layer - 1 + occupancy) * VOXEL
			break
		end
	end
	local topCount, deepCount = 0, 0
	for layer = 1, result.sizeY do
		if result.occupancy[row][layer][column] > 0 then
			local border = (result.minVoxelY + layer) * VOXEL - (fill - TOP_LAYER)
			if border > BORDER_MARGIN then
				Runner.expectEqual(result.materials[row][layer][column], topMaterial)
				topCount += 1
			elseif border < -BORDER_MARGIN then
				Runner.expectEqual(result.materials[row][layer][column], deepMaterial)
				deepCount += 1
			end
		end
	end
	return topCount, deepCount
end

local function createRamp(slopeDegrees: number, baseHeight: number): TerrainHeightField.TerrainHeightField
	local rise = math.tan(math.rad(slopeDegrees)) * WorldConfig.INTEGRATION_STEP_STUDS
	local segments: { RoadPath.Segment } = SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function(step: number)
			return baseHeight + rise * step
		end,
	})
	local blocks = RoadBlocks.new()
	for _, segment in segments do
		blocks.addSegment(segment)
	end
	return TerrainHeightField.new(SEED, createBiome(BIOME_SURFACE, BIOME_DEEP), blocks)
end

Runner.test(
	"on a ramp the road columns have the road material down to the top layer, and the deep one below",
	function()
		local catalog = createBiome(BIOME_SURFACE, BIOME_DEEP)
		local roadColumns, topVoxels, deepVoxels = 0, 0, 0
		for _, slopeDegrees in ROAD_SLOPES_DEGREES do
			for _, baseHeight in BASE_HEIGHTS do
				local builder = createBuilder(createRamp(slopeDegrees, baseHeight), catalog)
				for _, chunkZ in { 0, -1 } do
					local result = buildChunk(builder, ROAD_CHUNK_X, chunkZ)
					for row = 1, CHUNK_VOXELS do
						for column = 1, CHUNK_VOXELS do
							local z = chunkZ * WorldConfig.CHUNK_SIZE_STUDS + (column - 0.5) * VOXEL
							if math.abs(z) <= ROAD_HALF_WIDTH then
								local top, deep = checkColumn(result, row, column, ROAD, BIOME_DEEP)
								roadColumns, topVoxels, deepVoxels = roadColumns + 1, topVoxels + top, deepVoxels + deep
							end
						end
					end
				end
			end
		end
		-- Las columnas de camino a los dos lados del eje, en los dos chunks que lo cruzan.
		Runner.expectEqual(roadColumns, #ROAD_SLOPES_DEGREES * #BASE_HEIGHTS * 2 * ROAD_COLUMNS * CHUNK_VOXELS)
		-- Hay vóxeles de las dos clases: no vale una prueba que juzga solo las columnas de un lado.
		Runner.expectEqual(topVoxels >= 2 * roadColumns, true)
		Runner.expectEqual(deepVoxels >= 2 * roadColumns, true)
	end
)

Runner.test("on a ramp the shoulder columns have the material of the biome, not the deep one", function()
	local catalog = createBiome(BIOME_SURFACE, BIOME_DEEP)
	local shoulderColumns = 0
	for _, baseHeight in BASE_HEIGHTS do
		local builder = createBuilder(createRamp(20, baseHeight), catalog)
		local result = buildChunk(builder, ROAD_CHUNK_X, 0)
		for row = 1, CHUNK_VOXELS do
			-- La primera columna después de las de camino es banquina.
			checkColumn(result, row, ROAD_COLUMNS + 1, BIOME_SURFACE, BIOME_DEEP)
			shoulderColumns += 1
		end
	end
	Runner.expectEqual(shoulderColumns, #BASE_HEIGHTS * CHUNK_VOXELS)
end)

Runner.test("on a grass hill the grass goes down to the top layer, whatever the slope and the direction", function()
	local catalog = createBiome("Grass", "Ground")
	local directions = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { -1, 0 } }
	local columns, topVoxels, deepVoxels = 0, 0, 0
	for _, slopeDegrees in HILL_SLOPES_DEGREES do
		for _, baseHeight in BASE_HEIGHTS do
			for _, direction in directions do
				local field = createSlopedField(baseHeight, slopeDegrees, direction[1], direction[2])
				local result = buildChunk(createBuilder(field, catalog), 0, 0)
				for row = 1, CHUNK_VOXELS do
					for column = 1, CHUNK_VOXELS do
						local top, deep = checkColumn(result, row, column, "Grass", "Ground")
						columns, topVoxels, deepVoxels = columns + 1, topVoxels + top, deepVoxels + deep
					end
				end
			end
		end
	end
	Runner.expectEqual(columns, #HILL_SLOPES_DEGREES * #BASE_HEIGHTS * #directions * CHUNK_VOXELS * CHUNK_VOXELS)
	Runner.expectEqual(topVoxels >= 2 * columns, true)
	Runner.expectEqual(deepVoxels >= 2 * columns, true)
end)

Runner.test("on flat ground the top layer is the surface voxels that are within the depth of the layer", function()
	local catalog = createBiome("Grass", "Ground")
	-- Altura 50,5: el relleno llega a 12,125 vóxeles. El vóxel 12 (casi vacío) y los dos de abajo (11 y 10, con su borde
	-- de arriba a 4, 8 y 12 studs bajo la superficie) llevan pasto; del 9 para abajo, tierra.
	local result = buildChunk(createBuilder(createSlopedField(50.5, 0, 0, 0), catalog), 0, 0)
	local firstVoxel = result.minVoxelY
	for voxel = firstVoxel, 12 do
		local expected = if voxel >= 10 then "Grass" else "Ground"
		Runner.expectEqual(result.materials[5][voxel - firstVoxel + 1][5], expected)
	end
	Runner.expectEqual(result.materials[5][12 - firstVoxel + 2][5], "Air")
end)

Runner.test("a surface exactly on a voxel border has the two voxels of the layer below it", function()
	local catalog = createBiome("Grass", "Ground")
	-- Altura 50: el relleno llega a 12 vóxeles justos. El vóxel 11 es el más alto y con el 10 forman la capa de 8 studs.
	local result = buildChunk(createBuilder(createSlopedField(50, 0, 0, 0), catalog), 0, 0)
	local firstVoxel = result.minVoxelY
	for voxel = firstVoxel, 11 do
		local expected = if voxel >= 10 then "Grass" else "Ground"
		Runner.expectEqual(result.materials[5][voxel - firstVoxel + 1][5], expected)
	end
	Runner.expectEqual(result.materials[5][11 - firstVoxel + 2][5], "Air")
end)

Runner.finish()
