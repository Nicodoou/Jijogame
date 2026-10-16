--!strict
-- El mundo vivo alrededor del auto, sin tocar Roblox: sigue al auto sobre la ruta, genera ruta adelante y la libera
-- atrás, decide qué chunks de Terrain hacen falta (los que toca un corredor alrededor de la ruta viva) y arma la cola
-- de trabajo. Es una fuente de trabajo para WorkBudget: cada `runStep` hace una cosa chica (un tramo de ruta, replanificar,
-- una fila de un chunk, escribir un chunk). Lo que escribe en el Terrain sale por el `ChunkSink` que le pasa el
-- adaptador. Además provee los cuatro contratos del área.

local BiomeBlend = require("./BiomeBlend")
local BiomeCatalog = require("./BiomeCatalog")
local BiomeMap = require("./BiomeMap")
local BiomeTypes = require("./BiomeTypes")
local ChunkCorridor = require("./ChunkCorridor")
local ChunkPlan = require("./ChunkPlan")
local ChunkRegistry = require("./ChunkRegistry")
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

local PLAN_REFRESH_SQUARED_STUDS = WorldConfig.TERRAIN_PLAN_REFRESH_STUDS ^ 2
local FRONTIER_MARGIN_STUDS = WorldConfig.TERRAIN_FRONTIER_MARGIN_STUDS
local READY_RADIUS_STUDS = WorldConfig.WORLD_READY_RADIUS_STUDS

type PlannedWork = ChunkPlan.PlannedWork

-- Lo que se está haciendo ahora con un chunk: armarlo (y escribirlo) o borrarlo.
type CurrentWork = {
	plan: PlannedWork,
	isStarted: boolean,
}

local WorldPlannerModule = {}

function WorldPlannerModule.new(dependencies: Dependencies): WorldPlanner
	local seed, sink = dependencies.seed, dependencies.sink
	local catalog = dependencies.catalog or BiomeCatalog.all
	local path = dependencies.path or RoadPath.new(seed)

	local biomeMap = BiomeMap.new(seed, catalog)
	local picker = BiomeBlend.newPicker(seed, catalog)
	local window = RoadWindow.new(path, WorldConfig.ROUTE_AHEAD_STUDS, TerrainWindow.BLOCK_MEMORY_STUDS)
	local heightField = TerrainHeightField.new(seed, catalog, window.blocks)
	local registry = ChunkRegistry.new(window.blocks, heightField.getInfluenceStuds())
	local createBuilder = dependencies.createBuilder or VoxelChunkBuilder.new
	local builder = createBuilder({
		heightField = heightField,
		biomeMap = biomeMap,
		picker = picker,
		catalog = catalog,
	})

	local queue: { PlannedWork } = {}
	local queueHead = 1
	local current: CurrentWork? = nil
	local isPlanDirty = true
	local vehiclePosition = vector.zero
	local lastPlanPosition = vector.create(math.huge, 0, math.huge)

	window.extend()
	local spawnPoint = SpawnPoint.fromPath(path)

	local function replan()
		isPlanDirty = false
		lastPlanPosition = vehiclePosition
		window.releaseOldSegments()
		local arcLength = window.getVehicleArcLength()
		-- El borde de la ruta generada no se escribe: ahí todavía falta la ruta que entra en el alcance de la altura.
		local lastWantedArc = window.getGeneratedEndArcLength() - FRONTIER_MARGIN_STUDS
		local wanted = ChunkCorridor.collect(
			window,
			arcLength - TerrainWindow.WANTED_BEHIND_STUDS,
			lastWantedArc,
			TerrainWindow.WANTED_HALF_WIDTH_STUDS
		)
		local kept = ChunkCorridor.collect(
			window,
			arcLength - TerrainWindow.KEPT_BEHIND_STUDS,
			lastWantedArc,
			TerrainWindow.KEPT_HALF_WIDTH_STUDS
		)
		local building = current
		if building ~= nil and kept[building.plan.key] == nil then
			current, building = nil, nil
		end
		queue = ChunkPlan.build(
			wanted,
			kept,
			registry.getAll(),
			if building ~= nil then building.plan.key else nil,
			vehiclePosition.x,
			vehiclePosition.z,
			registry.isStale
		)
		queueHead = 1
		registry.clearNotes()
	end

	local function extendRoad()
		registry.noteNewSegment(window.extend())
		-- Con ruta nueva el auto puede haber quedado sobre ella: si no se lo vuelve a ubicar acá, la ruta de adelante
		-- se calcula desde un arcLength viejo hasta la próxima llamada de updatePlan.
		window.trackVehicle(vehiclePosition)
		isPlanDirty = true
	end

	local function commitBuiltChunk()
		local voxels = builder.getResult()
		sink.writeChunk(voxels)
		-- Si llegó ruta nueva mientras se armaba, el chunk ya salió viejo: se revisa en el próximo plan.
		if registry.record(voxels) then
			registry.flagAllForCheck()
			isPlanDirty = true
		end
	end

	local function clearChunk(plan: PlannedWork)
		local chunk = registry.get(plan.key)
		if chunk ~= nil then
			sink.clearChunk(plan.chunkX, plan.chunkZ, { minVoxelY = chunk.minVoxelY, maxVoxelY = chunk.maxVoxelY })
			registry.remove(plan.key)
		end
	end

	local function startBuilding(plan: PlannedWork)
		local chunk = registry.get(plan.key)
		local cover = if chunk ~= nil then { minVoxelY = chunk.minVoxelY, maxVoxelY = chunk.maxVoxelY } else nil
		builder.begin(plan.chunkX, plan.chunkZ, cover)
	end

	local function advanceCurrentWork(work: CurrentWork)
		local plan = work.plan
		if plan.kind == "clear" then
			clearChunk(plan)
			current = nil
			return
		end
		if not work.isStarted then
			startBuilding(plan)
			work.isStarted = true
		end
		if builder.getRemainingSteps() > 0 then
			builder.runStep()
		else
			commitBuiltChunk()
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
		window.trackVehicle(position)
		local movedX, movedZ = position.x - lastPlanPosition.x, position.z - lastPlanPosition.z
		if movedX * movedX + movedZ * movedZ >= PLAN_REFRESH_SQUARED_STUDS then
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
		return registry.isReadyAt(position, READY_RADIUS_STUDS)
	end

	local function getNearestRoadPoint(position: vector): RoadPoint.RoadPoint?
		local nearest = window.query.findNearest(position, nil)
		if nearest == nil then
			return nil
		end
		return { position = nearest.position, direction = nearest.direction, arcLength = nearest.arcLength }
	end

	local function getSpawnPoint(): RoadPoint.RoadPoint
		return { position = spawnPoint.position, direction = spawnPoint.direction, arcLength = spawnPoint.arcLength }
	end

	local function getStatus(): WorldStatus
		return {
			vehicleArcLength = window.getVehicleArcLength(),
			generatedEndArcLength = window.getGeneratedEndArcLength(),
			writtenChunkCount = registry.getCount(),
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
		getSpawnPoint = getSpawnPoint,
		isWorldReadyAt = isWorldReadyAt,
	}
end

return WorldPlannerModule
