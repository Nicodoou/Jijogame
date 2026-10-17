--!strict
local BiomeBlend = require("../../src/world/core/BiomeBlend")
local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeMap = require("../../src/world/core/BiomeMap")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local BiomeTestCatalog = require("./BiomeTestCatalog")
local RoadBlocks = require("../../src/world/core/RoadBlocks")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SyntheticRoad = require("./SyntheticRoad")
local TerrainHeightField = require("../../src/world/core/TerrainHeightField")
local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local WorldConfig = require("../../src/world/core/WorldConfig")

local VOXEL = WorldConfig.TERRAIN_VOXEL_STUDS
local CHUNK_VOXELS = WorldConfig.CHUNK_SIZE_STUDS // VOXEL
local OFFSET = WorldConfig.TERRAIN_SURFACE_OFFSET_STUDS
local TOTAL_STEPS = 1 + 2 * CHUNK_VOXELS
local SEGMENTS = 5
local SEED = 12
local ROAD_CHUNK_X = 2
local ROAD_HALF_WIDTH = WorldConfig.ROAD_WIDTH_STUDS / 2
-- Los centros de las columnas quedan a 2, 6, 10, 14... studs del eje: las que no pasan de la mitad del ancho son camino
-- (el borde cuenta como camino) y la siguiente es banquina.
local ROAD_COLUMNS = math.floor(ROAD_HALF_WIDTH / VOXEL + 0.5)
local NEAR_COLUMNS = ROAD_COLUMNS + 1
-- A los dos lados del eje: el eje cae en el borde entre dos columnas.
local ROAD_WIDTH_COLUMNS = 2 * ROAD_COLUMNS
-- Con la superficie en 50,5 el relleno llega a 12,125 vóxeles: la capa de superficie (8 studs) arranca en el vóxel 10.
local TOP_FLOOR_VOXEL = 10
local TOLERANCE = 1e-9
-- La altura de la ruta viene de un vector, que guarda floats de 32 bits.
local HEIGHT_TOLERANCE = 1e-4
local AIR = "Air"
local FAR_CHUNK_Z = 6

-- Un bioma único con materiales distintos entre sí, para ver de dónde sale cada uno.
local rockyBiome: BiomeTypes.BiomeDefinition = {
	id = "rocky",
	climate = {
		relief = { min = 0, max = 1 },
		humidity = { min = 0, max = 1 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 1, hillRoughness = 1 },
	materials = {
		surface = { { material = "Rock", proportion = 1 } },
		transition = "Slate",
		deep = "Basalt",
	},
	surfaces = { offroad = "Grass", patches = {} },
	decoration = {},
}
local ROCKY: { BiomeTypes.BiomeDefinition } = { rockyBiome }

local function createRoad(height: number): { RoadPath.Segment }
	return SyntheticRoad.createSegments({
		segmentCount = SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return height
		end,
	})
end

type World = {
	builder: VoxelChunkBuilder.VoxelChunkBuilder,
	field: TerrainHeightField.TerrainHeightField,
}

local function createWorld(height: number, catalog: { BiomeTypes.BiomeDefinition }?): World
	local usedCatalog = catalog or BiomeCatalog.all
	local blocks = RoadBlocks.new()
	for _, segment in createRoad(height) do
		blocks.addSegment(segment)
	end
	local field = TerrainHeightField.new(SEED, usedCatalog, blocks)
	local builder = VoxelChunkBuilder.new({
		heightField = field,
		biomeMap = BiomeMap.new(SEED, usedCatalog),
		picker = BiomeBlend.newPicker(SEED, usedCatalog),
		catalog = usedCatalog,
	})
	return { builder = builder, field = field }
end

local function buildChunk(
	builder: VoxelChunkBuilder.VoxelChunkBuilder,
	chunkX: number,
	chunkZ: number,
	cover: VoxelChunkBuilder.VoxelRange?
)
	builder.begin(chunkX, chunkZ, cover)
	while builder.getRemainingSteps() > 0 do
		builder.runStep()
	end
	return builder.getResult()
end

-- La altura de la superficie que se ve en una columna: parte de la ocupación del vóxel más alto con terreno, más el
-- corrimiento medido en Studio.
local function readSurfaceHeight(result: VoxelChunkBuilder.ChunkVoxels, row: number, column: number): number
	for layer = result.sizeY, 1, -1 do
		local occupancy = result.occupancy[row][layer][column]
		if occupancy > 0 then
			local voxel = result.minVoxelY + layer - 1
			return voxel * VOXEL + occupancy * VOXEL + OFFSET
		end
	end
	return -math.huge
end

local function findTopLayer(result: VoxelChunkBuilder.ChunkVoxels, row: number, column: number): number
	for layer = result.sizeY, 1, -1 do
		if result.occupancy[row][layer][column] > 0 then
			return layer
		end
	end
	return 0
end

local function getColumnCenter(chunkX: number, chunkZ: number, row: number, column: number): (number, number)
	local chunk = WorldConfig.CHUNK_SIZE_STUDS
	return chunkX * chunk + (row - 0.5) * VOXEL, chunkZ * chunk + (column - 0.5) * VOXEL
end

Runner.test("the surface of the road columns lands on the height of the road, whatever the height", function()
	for _, height in { 50, 50.5, 53, 49.99, 48.01, 47.9, 0, -37.3, 151.7 } do
		local world = createWorld(height)
		local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
		for row = 1, CHUNK_VOXELS do
			for column = 1, NEAR_COLUMNS do
				Runner.expectNear(readSurfaceHeight(result, row, column), height, HEIGHT_TOLERANCE)
			end
		end
	end
end)

Runner.test("the occupancy of a road column is solid up to the surface voxel, partial in it and empty above", function()
	local world = createWorld(50.5)
	local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	-- (50,5 - 2) / 4 = 12,125: los vóxeles 0 a 11 llenos y el 12 al 12,5 por ciento.
	local topLayer = findTopLayer(result, 5, 1)
	Runner.expectEqual(result.minVoxelY + topLayer - 1, 12)
	Runner.expectNear(result.occupancy[5][topLayer][1], 0.125, TOLERANCE)
	Runner.expectEqual(result.occupancy[5][topLayer - 1][1], 1)
	Runner.expectEqual(result.occupancy[5][1][1], 1)
	Runner.expectEqual(result.occupancy[5][result.sizeY][1], 0)
	Runner.expectEqual(result.materials[5][result.sizeY][1], AIR)
end)

Runner.test(
	"a surface that falls exactly on a voxel border fills the voxel below and leaves the next one empty",
	function()
		local world = createWorld(50)
		local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
		-- (50 - 2) / 4 = 12: el vóxel 11 queda lleno y el 12 vacío.
		local topLayer = findTopLayer(result, 5, 1)
		Runner.expectEqual(result.minVoxelY + topLayer - 1, 11)
		Runner.expectEqual(result.occupancy[5][topLayer][1], 1)
		Runner.expectEqual(result.occupancy[5][topLayer + 1][1], 0)
	end
)

Runner.test(
	"the road has the road material and the shoulder the one of the biome, down to the top layer; deeper is the deep material, above is air",
	function()
		local world = createWorld(50.5, ROCKY)
		local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
		-- (50,5 - 2) / 4 = 12,125: la capa de superficie empieza en el vóxel 10.
		local firstTopLayer = TOP_FLOOR_VOXEL - result.minVoxelY + 1
		for row = 1, CHUNK_VOXELS do
			for column = 1, NEAR_COLUMNS do
				local topLayer = findTopLayer(result, row, column)
				local topMaterial = if column <= ROAD_COLUMNS then "Mud" else "Rock"
				for layer = firstTopLayer, topLayer do
					Runner.expectEqual(result.materials[row][layer][column], topMaterial)
				end
				for layer = 1, firstTopLayer - 1 do
					Runner.expectEqual(result.materials[row][layer][column], "Basalt")
				end
				for layer = topLayer + 1, result.sizeY do
					Runner.expectEqual(result.materials[row][layer][column], AIR)
				end
			end
		end
	end
)

Runner.test("outside the road the top is the surface material of the biome, never a road material", function()
	local world = createWorld(50.5, ROCKY)
	local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	local checked = 0
	for row = 1, CHUNK_VOXELS do
		for column = NEAR_COLUMNS + 2, CHUNK_VOXELS do
			Runner.expectEqual(result.materials[row][findTopLayer(result, row, column)][column], "Rock")
			checked += 1
		end
	end
	Runner.expectEqual(checked > 500, true)
end)

-- Cuenta los materiales de la superficie en tres chunks de la ruta y revisa, columna por columna, la regla de cada uno.
local function countForestSurface(catalog: { BiomeTypes.BiomeDefinition }, allowsMud: boolean): { [string]: number }
	local world = createWorld(50.5, catalog)
	local counts: { [string]: number } = {}
	for _, chunkZ in { 0, 1, -1 } do
		local result = buildChunk(world.builder, ROAD_CHUNK_X, chunkZ, nil)
		for row = 1, CHUNK_VOXELS do
			for column = 1, CHUNK_VOXELS do
				local top = result.materials[row][findTopLayer(result, row, column)][column]
				counts[top] = (counts[top] or 0) + 1
				local x, z = getColumnCenter(ROAD_CHUNK_X, chunkZ, row, column)
				local _, beyondShoulder, axisDistance = world.field.sampleColumn(x, z, { forest = 1 })
				if beyondShoulder == 0 then
					if axisDistance <= ROAD_HALF_WIDTH then
						Runner.expectEqual(top, "Mud")
					else
						Runner.expectEqual(top == "Grass" or top == "LeafyGrass", true)
					end
				elseif top == "Mud" then
					Runner.expectEqual(allowsMud, true)
					Runner.expectEqual(beyondShoulder > WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS, true)
				else
					Runner.expectEqual(top == "Grass" or top == "LeafyGrass", true)
				end
			end
		end
	end
	return counts
end

Runner.test("with the forest of the game the road is Mud and the rest, shoulder included, is only grass", function()
	local counts = countForestSurface(BiomeCatalog.all, false)
	Runner.expectEqual((counts.Grass or 0) > 500, true)
	Runner.expectEqual((counts.LeafyGrass or 0) > 100, true)
	-- Todo el Mud es el camino: el ancho de la ruta en columnas, por cada fila de x del chunk que la cruza.
	Runner.expectEqual(counts.Mud, ROAD_WIDTH_COLUMNS * CHUNK_VOXELS)
	Runner.expectEqual(counts.Ground, nil)
	Runner.expectEqual(counts.Limestone, nil)
end)

Runner.test("with a forest with mud patches there is mud also far from the shoulder, besides the road", function()
	local counts = countForestSurface(BiomeTestCatalog.muddyForestOnly, true)
	Runner.expectEqual((counts.Mud or 0) > ROAD_WIDTH_COLUMNS * CHUNK_VOXELS + 20, true)
	Runner.expectEqual((counts.Grass or 0) > 500, true)
	Runner.expectEqual((counts.LeafyGrass or 0) > 100, true)
	Runner.expectEqual(counts.Ground, nil)
end)

Runner.test(
	"every column is solid up to one voxel and empty above, and its surface is the height of the field",
	function()
		local world = createWorld(55)
		for _, chunkZ in { 0, -1, 1 } do
			local result = buildChunk(world.builder, ROAD_CHUNK_X, chunkZ, nil)
			for row = 1, CHUNK_VOXELS do
				for column = 1, CHUNK_VOXELS do
					local topLayer = findTopLayer(result, row, column)
					Runner.expectEqual(topLayer > 1 and topLayer < result.sizeY, true)
					for layer = 1, topLayer - 1 do
						Runner.expectEqual(result.occupancy[row][layer][column], 1)
					end
					for layer = topLayer + 1, result.sizeY do
						Runner.expectEqual(result.occupancy[row][layer][column], 0)
					end
					local x, z = getColumnCenter(ROAD_CHUNK_X, chunkZ, row, column)
					local height = world.field.sampleColumn(x, z, { forest = 1 })
					Runner.expectNear(readSurfaceHeight(result, row, column), height, HEIGHT_TOLERANCE)
				end
			end
		end
	end
)

Runner.test(
	"the vertical range is computed per chunk: it keeps depth under the lowest surface and an empty layer on top",
	function()
		local world = createWorld(55)
		local result = buildChunk(world.builder, ROAD_CHUNK_X, 1, nil)
		local lowest, highest = math.huge, -math.huge
		for row = 1, CHUNK_VOXELS do
			for column = 1, CHUNK_VOXELS do
				local height = readSurfaceHeight(result, row, column)
				lowest, highest = math.min(lowest, height), math.max(highest, height)
			end
		end
		local lowestVoxelStuds = result.minVoxelY * VOXEL
		Runner.expectEqual(lowest - OFFSET - lowestVoxelStuds >= WorldConfig.TERRAIN_DEPTH_STUDS, true)
		Runner.expectEqual(lowest - OFFSET - lowestVoxelStuds < WorldConfig.TERRAIN_DEPTH_STUDS + VOXEL, true)
		local topVoxel = result.minVoxelY + result.sizeY - 1
		Runner.expectEqual(topVoxel * VOXEL >= highest - OFFSET, true)
		Runner.expectEqual((topVoxel - 1) * VOXEL < highest - OFFSET, true)
		for row = 1, CHUNK_VOXELS do
			for column = 1, CHUNK_VOXELS do
				Runner.expectEqual(result.occupancy[row][1][column], 1)
				Runner.expectEqual(result.occupancy[row][result.sizeY][column], 0)
			end
		end
		Runner.expectEqual(result.minVoxelX, ROAD_CHUNK_X * CHUNK_VOXELS)
		Runner.expectEqual(result.minVoxelZ, CHUNK_VOXELS)
		Runner.expectEqual(result.sizeX, CHUNK_VOXELS)
		Runner.expectEqual(result.sizeZ, CHUNK_VOXELS)
		Runner.expectEqual(#result.materials, CHUNK_VOXELS)
		Runner.expectEqual(#result.occupancy[1], result.sizeY)
	end
)

Runner.test("a chunk far from the road is ambient height plus hills with no road material", function()
	local world = createWorld(50)
	local result = buildChunk(world.builder, ROAD_CHUNK_X, FAR_CHUNK_Z, nil)
	for row = 1, CHUNK_VOXELS, 4 do
		for column = 1, CHUNK_VOXELS, 4 do
			local top = result.materials[row][findTopLayer(result, row, column)][column]
			Runner.expectEqual(top ~= "Ground", true)
			local height = readSurfaceHeight(result, row, column)
			Runner.expectEqual(math.abs(height - WorldConfig.HILL_BASE_HEIGHT_STUDS) <= 16, true)
		end
	end
end)

Runner.test("covering a previous range makes the chunk reach it, with air where the old terrain was", function()
	local world = createWorld(50)
	local plain = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	-- El resultado es siempre la misma tabla: se copian los números antes de armar el siguiente.
	local plainMin, plainSize = plain.minVoxelY, plain.sizeY
	local plainMax = plainMin + plainSize - 1
	local covered = buildChunk(world.builder, ROAD_CHUNK_X, 0, { minVoxelY = plainMin - 6, maxVoxelY = plainMax + 9 })
	Runner.expectEqual(covered.minVoxelY, plainMin - 6)
	Runner.expectEqual(covered.sizeY, plainSize + 15)
	for row = 1, CHUNK_VOXELS, 3 do
		for column = 1, CHUNK_VOXELS, 3 do
			Runner.expectEqual(covered.occupancy[row][covered.sizeY][column], 0)
			Runner.expectEqual(covered.materials[row][covered.sizeY][column], AIR)
			Runner.expectEqual(covered.occupancy[row][covered.sizeY - 4][column], 0)
			Runner.expectEqual(covered.occupancy[row][1][column], 1)
		end
	end
	local inside = buildChunk(world.builder, ROAD_CHUNK_X, 0, { minVoxelY = plainMin + 2, maxVoxelY = plainMax - 2 })
	Runner.expectEqual(inside.minVoxelY, plainMin)
	Runner.expectEqual(inside.sizeY, plainSize)
end)

Runner.test("building the same chunk twice gives exactly the same tables", function()
	local world = createWorld(50)
	local first = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	local firstOccupancy, firstMaterials = table.clone(first.occupancy[7][3]), table.clone(first.materials[7][3])
	local firstSize = first.sizeY
	buildChunk(world.builder, ROAD_CHUNK_X + 1, 0, nil)
	local second = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	Runner.expectEqual(second.sizeY, firstSize)
	for column = 1, CHUNK_VOXELS do
		Runner.expectEqual(second.occupancy[7][3][column], firstOccupancy[column])
		Runner.expectEqual(second.materials[7][3][column], firstMaterials[column])
	end
end)

Runner.test("the tables are reused between chunks: the same outer tables come back", function()
	local world = createWorld(50)
	local first = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	local materials, occupancy = first.materials, first.occupancy
	local second = buildChunk(world.builder, ROAD_CHUNK_X, 5, nil)
	Runner.expectEqual(second.materials == materials, true)
	Runner.expectEqual(second.occupancy == occupancy, true)
	Runner.expectEqual(second == first, true)
end)

Runner.test("a chunk takes one preparation step, a step per row of columns and a step per row of voxels", function()
	local world = createWorld(50)
	Runner.expectEqual(world.builder.getRemainingSteps(), 0)
	world.builder.begin(ROAD_CHUNK_X, 0)
	Runner.expectEqual(world.builder.getRemainingSteps(), TOTAL_STEPS)
	for step = 1, TOTAL_STEPS do
		world.builder.runStep()
		Runner.expectEqual(world.builder.getRemainingSteps(), TOTAL_STEPS - step)
	end
	Runner.expectEqual(world.builder.getResult().chunkX, ROAD_CHUNK_X)
end)

Runner.test("steps and results need a started and finished chunk, and chunk coordinates are integers", function()
	local world = createWorld(50)
	Runner.expectError(function()
		world.builder.runStep()
	end)
	Runner.expectError(function()
		world.builder.getResult()
	end)
	world.builder.begin(ROAD_CHUNK_X, 0)
	world.builder.runStep()
	Runner.expectError(function()
		world.builder.getResult()
	end)
	Runner.expectError(function()
		world.builder.begin(1.5, 0)
	end)
	Runner.expectError(function()
		world.builder.begin(0, 0.25)
	end)
	for _ = 1, TOTAL_STEPS - 1 do
		world.builder.runStep()
	end
	Runner.expectError(function()
		world.builder.runStep()
	end)
end)

Runner.test("starting another chunk abandons the one being built", function()
	local world = createWorld(50)
	world.builder.begin(ROAD_CHUNK_X, 0)
	for _ = 1, 20 do
		world.builder.runStep()
	end
	local result = buildChunk(world.builder, ROAD_CHUNK_X + 1, -1, nil)
	Runner.expectEqual(result.chunkX, ROAD_CHUNK_X + 1)
	Runner.expectEqual(result.chunkZ, -1)
	Runner.expectNear(readSurfaceHeight(result, 3, CHUNK_VOXELS), 50, HEIGHT_TOLERANCE)
end)

Runner.test("the signature of a chunk is the one of the road around it", function()
	local world = createWorld(50)
	local result = buildChunk(world.builder, ROAD_CHUNK_X, 0, nil)
	local firstSignature = result.signature
	Runner.expectEqual(firstSignature ~= 0, true)
	local far = buildChunk(world.builder, ROAD_CHUNK_X, FAR_CHUNK_Z, nil)
	Runner.expectEqual(far.signature, 0)
end)

Runner.finish()
