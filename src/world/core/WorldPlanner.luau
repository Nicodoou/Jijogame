--!strict
-- El mundo vivo alrededor del auto, sin tocar Roblox: sigue al auto sobre la ruta, genera ruta adelante y la libera
-- atrás, decide qué chunks de Terrain hacen falta (los que toca un corredor alrededor de la ruta viva), arma la cola
-- de trabajo y lleva el registro de lo escrito. Es una fuente de trabajo para WorkBudget: cada `runStep` hace una cosa
-- chica (un tramo de ruta, replanificar, una fila de un chunk, escribir un chunk). Lo que escribe en el Terrain sale por
-- el `ChunkSink` que le pasa el adaptador. Además provee los cuatro contratos del área.

local BiomeBlend = require("./BiomeBlend")
local BiomeCatalog = require("./BiomeCatalog")
local BiomeMap = require("./BiomeMap")
local BiomeTypes = require("./BiomeTypes")
local ChunkCorridor = require("./ChunkCorridor")
local ChunkGrid = require("./ChunkGrid")
local ChunkPlan = require("./ChunkPlan")
local RoadPath = require("./RoadPath")
local RoadPoint = require("../../shared/contracts/RoadPoint")
local RoadWindow = require("./RoadWindow")
local SpawnPoint = require("./SpawnPoint")
local Surface = require("../../shared/contracts/Surface")
local SurfaceClassifier = require("./SurfaceClassifier")
local TerrainHeightField = require("./TerrainHeightField")
local TerrainWindow = require("./TerrainWindow")
local VoxelChunkBuilder = require("./VoxelChunkBuilder")
local WorkBudget = require("./WorkBudget")
local WorldConfig = require("./WorldConfig")
local WorldReady = require("../../shared/contracts/WorldReady")

-- El adaptador del Terrain. Las tablas de `writeChunk` se reutilizan: hay que usarlas ahí mismo y no guardarlas.
export type ChunkSink = {
	writeChunk: (voxels: VoxelChunkBuilder.ChunkVoxels) -> (),
	-- Borra con aire los vóxeles de un chunk en el tramo vertical dado.
	clearChunk: (chunkX: number, chunkZ: number, range: VoxelChunkBuilder.VoxelRange) -> (),
}

export type Dependencies = {
	seed: number,
	sink: ChunkSink,
	-- La ruta, para las pruebas. Por defecto se arma con la semilla.
	path: RoadPath.RoadPath?,
	-- Las fichas de bioma. Por defecto, las del juego.
	catalog: { BiomeTypes.BiomeDefinition }?,
	-- Cómo se arma cada chunk, para las pruebas del planificador. Por defecto, VoxelChunkBuilder.
	createBuilder: ((VoxelChunkBuilder.Dependencies) -> VoxelChunkBuilder.VoxelChunkBuilder)?,
}

export type WorldStatus = {
	vehicleArcLength: number,
	generatedEndArcLength: number,
	writtenChunkCount: number,
	queuedWorkCount: number,
	isBuildingChunk: boolean,
}

export type WorldPlanner = WorkBudget.WorkSource & {
	-- Avisa dónde está el auto. Es barato: el trabajo grande se hace en `runStep`.
	updatePlan: (vehiclePosition: vector) -> (),
	getStatus: () -> WorldStatus,
	getSurfaceAt: Surface.GetSurfaceAt,
	getNearestRoadPoint: RoadPoint.GetNearestRoadPoint,
	getSpawnPoint: RoadPoint.GetSpawnPoint,
	isWorldReadyAt: WorldReady.IsWorldReadyAt,
}

local CHUNK_STUDS = WorldConfig.CHUNK_SIZE_STUDS
local PLAN_REFRESH_STUDS = WorldConfig.TERRAIN_PLAN_REFRESH_STUDS
local FRONTIER_MARGIN_STUDS = WorldConfig.TERRAIN_FRONTIER_MARGIN_STUDS
local READY_RADIUS_STUDS = WorldConfig.WORLD_READY_RADIUS_STUDS

type PlannedWork = ChunkPlan.PlannedWork
type WrittenChunk = ChunkPlan.WrittenChunk

-- Lo que se está haciendo ahora con un chunk: armarlo (y escribirlo) o borrarlo.
type CurrentWork = {
	plan: PlannedWork,
	isStarted: boolean,
}

type Box = { minX: number, minZ: number, maxX: number, maxZ: number }

local WorldPlannerModule = {}

function WorldPlannerModule.new(dependencies: Dependencies): WorldPlanner
	local seed, sink = dependencies.seed, dependencies.sink
	local catalog = dependencies.catalog or BiomeCatalog.all
	local path = dependencies.path or RoadPath.new(seed)

	local biomeMap = BiomeMap.new(seed, catalog)
	local picker = BiomeBlend.newPicker(seed, catalog)
	local window = RoadWindow.new(path, WorldConfig.ROUTE_AHEAD_STUDS, TerrainWindow.BLOCK_MEMORY_STUDS)
	local heightField = TerrainHeightField.new(seed, catalog, window.blocks)
	local influenceStuds = heightField.getInfluenceStuds()
	local createBuilder = dependencies.createBuilder or VoxelChunkBuilder.new
	local builder = createBuilder({
		heightField = heightField,
		biomeMap = biomeMap,
		picker = picker,
		catalog = catalog,
	})

	local written: { [number]: WrittenChunk } = {}
	local writtenCount = 0
	local queue: { PlannedWork } = {}
	local queueHead = 1
	local current: CurrentWork? = nil
	local isPlanDirty = true
	local vehiclePosition = vector.zero
	local vehicleX, vehicleZ = 0, 0
	local lastPlanX, lastPlanZ = math.huge, math.huge
	-- Zonas donde llegó ruta nueva desde el último plan: los chunks escritos que las toquen pueden haber quedado viejos.
	local newRoadBoxes: { Box } = {}
	local checkAllChunks = false

	window.extend()
	local spawnPoint = SpawnPoint.fromPath(path)

	local function recordNewRoad(segment: RoadPath.Segment)
		local box: Box = { minX = math.huge, minZ = math.huge, maxX = -math.huge, maxZ = -math.huge }
		for _, sample in segment.samples do
			box.minX, box.maxX = math.min(box.minX, sample.position.x), math.max(box.maxX, sample.position.x)
			box.minZ, box.maxZ = math.min(box.minZ, sample.position.z), math.max(box.maxZ, sample.position.z)
		end
		table.insert(newRoadBoxes, box)
	end

	local function getSignatureOfChunk(chunkX: number, chunkZ: number): number
		local originX, originZ = ChunkGrid.getOriginStuds(chunkX), ChunkGrid.getOriginStuds(chunkZ)
		return window.blocks.getSignature(
			originX,
			originZ,
			originX + CHUNK_STUDS,
			originZ + CHUNK_STUDS,
			influenceStuds
		)
	end

	local function isTouchedByNewRoad(chunkX: number, chunkZ: number): boolean
		local originX, originZ = ChunkGrid.getOriginStuds(chunkX), ChunkGrid.getOriginStuds(chunkZ)
		for _, box in newRoadBoxes do
			local gapX = math.max(box.minX - (originX + CHUNK_STUDS), originX - box.maxX, 0)
			local gapZ = math.max(box.minZ - (originZ + CHUNK_STUDS), originZ - box.maxZ, 0)
			if gapX * gapX + gapZ * gapZ < influenceStuds * influenceStuds then
				return true
			end
		end
		return false
	end

	local function isStale(record: WrittenChunk): boolean
		if not (checkAllChunks or isTouchedByNewRoad(record.chunkX, record.chunkZ)) then
			return false
		end
		return getSignatureOfChunk(record.chunkX, record.chunkZ) ~= record.signature
	end

	local function replan()
		isPlanDirty = false
		lastPlanX, lastPlanZ = vehicleX, vehicleZ
		window.releaseOldSegments()
		local arcLength = window.getVehicleArcLength()
		local wantedFrom = arcLength - TerrainWindow.WANTED_BEHIND_STUDS
		local lastWantedArc = window.getGeneratedEndArcLength() - FRONTIER_MARGIN_STUDS
		local wanted = ChunkCorridor.collect(window, wantedFrom, lastWantedArc, TerrainWindow.WANTED_HALF_WIDTH_STUDS)
		local kept = ChunkCorridor.collect(
			window,
			arcLength - TerrainWindow.KEPT_BEHIND_STUDS,
			lastWantedArc,
			TerrainWindow.KEPT_HALF_WIDTH_STUDS
		)
		local busy = current
		if busy ~= nil and kept[busy.plan.key] == nil then
			current = nil
			busy = nil
		end
		queue = ChunkPlan.build(
			wanted,
			kept,
			written,
			if busy ~= nil then busy.plan.key else nil,
			vehicleX,
			vehicleZ,
			isStale
		)
		queueHead = 1
		newRoadBoxes, checkAllChunks = {}, false
	end

	local function extendRoad()
		recordNewRoad(window.extend())
		-- Con ruta nueva el auto puede haber quedado sobre ella: si no se lo vuelve a ubicar acá, la ruta de adelante
		-- se calcula desde un arcLength viejo hasta la próxima llamada de updatePlan.
		window.trackVehicle(vehiclePosition)
		isPlanDirty = true
	end

	local function commitBuiltChunk(plan: PlannedWork)
		local voxels = builder.getResult()
		sink.writeChunk(voxels)
		if written[plan.key] == nil then
			writtenCount += 1
		end
		written[plan.key] = {
			chunkX = plan.chunkX,
			chunkZ = plan.chunkZ,
			minVoxelY = voxels.minVoxelY,
			maxVoxelY = voxels.minVoxelY + voxels.sizeY - 1,
			signature = voxels.signature,
		}
		-- Si llegó ruta nueva mientras se armaba, el chunk ya salió viejo: se revisa en el próximo plan.
		if getSignatureOfChunk(plan.chunkX, plan.chunkZ) ~= voxels.signature then
			checkAllChunks, isPlanDirty = true, true
		end
	end

	local function clearChunk(plan: PlannedWork)
		local record = written[plan.key]
		if record ~= nil then
			sink.clearChunk(plan.chunkX, plan.chunkZ, { minVoxelY = record.minVoxelY, maxVoxelY = record.maxVoxelY })
			written[plan.key] = nil
			writtenCount -= 1
		end
	end

	local function advanceCurrentWork(work: CurrentWork)
		local plan = work.plan
		if plan.kind == "clear" then
			clearChunk(plan)
			current = nil
			return
		end
		if not work.isStarted then
			local record = written[plan.key]
			local cover = if record ~= nil then { minVoxelY = record.minVoxelY, maxVoxelY = record.maxVoxelY } else nil
			builder.begin(plan.chunkX, plan.chunkZ, cover)
			work.isStarted = true
		end
		if builder.getRemainingSteps() > 0 then
			builder.runStep()
		else
			commitBuiltChunk(plan)
			current = nil
		end
	end

	local function takeNextWork(): CurrentWork?
		local plan = queue[queueHead]
		if plan == nil then
			return nil
		end
		queueHead += 1
		return { plan = plan, isStarted = false }
	end

	local function updatePlan(position: vector)
		vehiclePosition = position
		vehicleX, vehicleZ = position.x, position.z
		window.trackVehicle(position)
		if (vehicleX - lastPlanX) ^ 2 + (vehicleZ - lastPlanZ) ^ 2 >= PLAN_REFRESH_STUDS ^ 2 then
			isPlanDirty = true
		end
	end

	local function hasWork(): boolean
		return window.needsExtension() or isPlanDirty or current ~= nil or queueHead <= #queue
	end

	local function runStep()
		if window.needsExtension() then
			extendRoad()
		elseif isPlanDirty then
			replan()
		else
			local work = current or takeNextWork()
			current = work
			if work ~= nil then
				advanceCurrentWork(work)
			end
		end
	end

	local function isWorldReadyAt(position: vector): boolean
		for chunkX = ChunkGrid.getCoordinate(position.x - READY_RADIUS_STUDS), ChunkGrid.getCoordinate(position.x + READY_RADIUS_STUDS) do
			for chunkZ = ChunkGrid.getCoordinate(position.z - READY_RADIUS_STUDS), ChunkGrid.getCoordinate(position.z + READY_RADIUS_STUDS) do
				local isInRadius = ChunkGrid.getDistanceToChunk(chunkX, chunkZ, position.x, position.z)
					<= READY_RADIUS_STUDS
				if isInRadius and written[ChunkGrid.getKey(chunkX, chunkZ)] == nil then
					return false
				end
			end
		end
		return true
	end

	local function getNearestRoadPoint(position: vector): RoadPoint.RoadPoint?
		local nearest = window.query.findNearest(position, nil)
		if nearest == nil then
			return nil
		end
		return { position = nearest.position, direction = nearest.direction, arcLength = nearest.arcLength }
	end

	local function getSpawnPointCopy(): RoadPoint.RoadPoint
		return { position = spawnPoint.position, direction = spawnPoint.direction, arcLength = spawnPoint.arcLength }
	end

	local function getStatus(): WorldStatus
		return {
			vehicleArcLength = window.getVehicleArcLength(),
			generatedEndArcLength = window.getGeneratedEndArcLength(),
			writtenChunkCount = writtenCount,
			queuedWorkCount = #queue - queueHead + 1 + (if current ~= nil then 1 else 0),
			isBuildingChunk = current ~= nil,
		}
	end

	return {
		updatePlan = updatePlan,
		hasWork = hasWork,
		runStep = runStep,
		getStatus = getStatus,
		getSurfaceAt = SurfaceClassifier.createGetSurfaceAt(window.query, picker, biomeMap),
		getNearestRoadPoint = getNearestRoadPoint,
		getSpawnPoint = getSpawnPointCopy,
		isWorldReadyAt = isWorldReadyAt,
	}
end

return WorldPlannerModule
