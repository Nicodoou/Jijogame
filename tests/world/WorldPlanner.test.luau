--!strict
local ChunkGrid = require("../../src/world/core/ChunkGrid")
local FastChunkBuilder = require("./FastChunkBuilder")
local PathHelpers = require("./PathHelpers")
local RoadPath = require("../../src/world/core/RoadPath")
local Runner = require("../Runner")
local SpawnPoint = require("../../src/world/core/SpawnPoint")
local SyntheticRoad = require("./SyntheticRoad")
local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local WorkBudget = require("../../src/world/core/WorkBudget")
local WorldConfig = require("../../src/world/core/WorldConfig")
local WorldPlanner = require("../../src/world/core/WorldPlanner")

local CHUNK = WorldConfig.CHUNK_SIZE_STUDS
local SAMPLE_STUDS = WorldConfig.TERRAIN_CORRIDOR_SAMPLE_STUDS
local WANTED_HALF = WorldConfig.TERRAIN_CORRIDOR_HALF_WIDTH_STUDS
local KEPT_HALF = WANTED_HALF + WorldConfig.TERRAIN_CORRIDOR_KEEP_EXTRA_STUDS
local BEHIND = WorldConfig.TERRAIN_BEHIND_STUDS
local KEPT_BEHIND = BEHIND + WorldConfig.TERRAIN_BEHIND_KEEP_EXTRA_STUDS
local MARGIN = WorldConfig.TERRAIN_FRONTIER_MARGIN_STUDS
local READY_RADIUS = WorldConfig.WORLD_READY_RADIUS_STUDS
local STRAIGHT_SEGMENTS = 40
local ROAD_HEIGHT = 50
local MOVE_STUDS = 100
local MAX_STEPS = 200000
local SEED = 5
-- Dentro de la ruta generada por delante del auto (ROUTE_AHEAD_STUDS): un salto más lejos no encuentra ruta.
local JUMP_ARC = 1800
local LAG_MOVE_STUDS = 80
local LAG_STEPS_PER_MOVE = 20
-- Adonde vuelve el auto al final, a menos de lo que recuerdan los bloques de ruta (TerrainWindow.BLOCK_MEMORY_STUDS).
local LAG_BACK_TO_X = 2000
-- Los chunks más atrás cambian de firma cuando los bloques viejos de la ruta se olvidan, sin que llegue ruta nueva: no es
-- lo que se mide acá.
local LAG_FIRST_COMPARED_CHUNK_X = 12

-- Un sumidero falso: anota qué chunks quedan escritos y cuántas veces se escribió cada uno sin borrarlo antes.
type FakeSink = {
	sink: WorldPlanner.ChunkSink,
	active: { [number]: boolean },
	writeCounts: { [number]: number },
	rewriteCount: () -> number,
	clearCount: () -> number,
	writeCount: () -> number,
	firstOf: { [number]: VoxelChunkBuilder.ChunkVoxels },
	lastOf: { [number]: VoxelChunkBuilder.ChunkVoxels },
	snapshots: { [number]: { { number } } },
}

local function createSnapshot(voxels: VoxelChunkBuilder.ChunkVoxels): VoxelChunkBuilder.ChunkVoxels
	return {
		chunkX = voxels.chunkX,
		chunkZ = voxels.chunkZ,
		minVoxelX = voxels.minVoxelX,
		minVoxelY = voxels.minVoxelY,
		minVoxelZ = voxels.minVoxelZ,
		sizeX = voxels.sizeX,
		sizeY = voxels.sizeY,
		sizeZ = voxels.sizeZ,
		materials = {},
		occupancy = {},
		signature = voxels.signature,
	}
end

local function createFakeSink(): FakeSink
	local fake = {} :: FakeSink
	local rewrites, clears, writes = 0, 0, 0
	fake.active, fake.writeCounts, fake.firstOf, fake.lastOf, fake.snapshots = {}, {}, {}, {}, {}
	fake.sink = {
		writeChunk = function(voxels: VoxelChunkBuilder.ChunkVoxels)
			local key = ChunkGrid.getKey(voxels.chunkX, voxels.chunkZ)
			if fake.active[key] then
				rewrites += 1
			end
			writes += 1
			fake.active[key] = true
			fake.writeCounts[key] = (fake.writeCounts[key] or 0) + 1
			local snapshot = createSnapshot(voxels)
			fake.firstOf[key] = fake.firstOf[key] or snapshot
			fake.lastOf[key] = snapshot
			-- Una fila de ocupación por chunk alcanza para ver si el contenido cambió entre escrituras.
			local row: { number } = {}
			for layer = 1, voxels.sizeY do
				table.insert(row, voxels.occupancy[CHUNK // WorldConfig.TERRAIN_VOXEL_STUDS // 2][layer][1])
			end
			fake.snapshots[key] = fake.snapshots[key] or {}
			table.insert(fake.snapshots[key], row)
		end,
		clearChunk = function(chunkX: number, chunkZ: number, _range: VoxelChunkBuilder.VoxelRange)
			clears += 1
			local key = ChunkGrid.getKey(chunkX, chunkZ)
			fake.active[key] = nil
			-- Lo que vale para comparar escrituras es lo que pasó desde que el chunk se escribió por última vez desde cero.
			fake.firstOf[key], fake.lastOf[key], fake.snapshots[key] = nil, nil, nil
		end,
	}
	fake.rewriteCount = function()
		return rewrites
	end
	fake.clearCount = function()
		return clears
	end
	fake.writeCount = function()
		return writes
	end
	return fake
end

local function createStraightRoute(): RoadPath.RoadPath
	return SyntheticRoad.createPath(SyntheticRoad.createSegments({
		segmentCount = STRAIGHT_SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return ROAD_HEIGHT
		end,
	}))
end

local OUTBOUND_STEPS = 1280
local TURN_RADIUS_STUDS = 100
local TURN_STEPS = math.floor(math.pi * TURN_RADIUS_STUDS / WorldConfig.INTEGRATION_STEP_STUDS)
local STADIUM_SEGMENTS = 22
local RETURN_RISE = 30

-- Va 2.560 studs hacia +x, da media vuelta de radio 100 hacia +z y vuelve por z = 200, más alta.
local function createStadiumRoute(): RoadPath.RoadPath
	return SyntheticRoad.createPath(SyntheticRoad.createSegments({
		segmentCount = STADIUM_SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function(step: number)
			return if step >= OUTBOUND_STEPS and step < OUTBOUND_STEPS + TURN_STEPS then 1 / TURN_RADIUS_STUDS else 0
		end,
		heightAt = function(step: number)
			return if step < OUTBOUND_STEPS + TURN_STEPS then ROAD_HEIGHT else ROAD_HEIGHT + RETURN_RISE
		end,
	}))
end

local function runUntilIdle(planner: WorldPlanner.WorldPlanner): number
	local steps = 0
	while planner.hasWork() do
		planner.runStep()
		steps += 1
		if steps > MAX_STEPS then
			error("the planner never goes idle", 2)
		end
	end
	return steps
end

local function pointOnStraight(arcLength: number): vector
	return vector.create(arcLength, ROAD_HEIGHT, 0)
end

-- Los chunks que toca un corredor alrededor de una ruta recta a lo largo de +x, calculados por fuerza bruta.
local function expectCorridor(fromArc: number, toArc: number, halfWidth: number): { [number]: boolean }
	local set: { [number]: boolean } = {}
	local firstPoint = math.ceil(math.max(fromArc, 0) / SAMPLE_STUDS)
	for point = firstPoint, math.floor(toArc / SAMPLE_STUDS) do
		local x = point * SAMPLE_STUDS
		for chunkX = ChunkGrid.getCoordinate(x - halfWidth), ChunkGrid.getCoordinate(x + halfWidth) do
			for chunkZ = ChunkGrid.getCoordinate(-halfWidth), ChunkGrid.getCoordinate(halfWidth) do
				if ChunkGrid.getDistanceToChunk(chunkX, chunkZ, x, 0) <= halfWidth then
					set[ChunkGrid.getKey(chunkX, chunkZ)] = true
				end
			end
		end
	end
	return set
end

local function expectWantedAndKept(
	planner: WorldPlanner.WorldPlanner,
	fake: FakeSink
): ({ [number]: boolean }, { [number]: boolean })
	local status = planner.getStatus()
	local lastWantedArc = status.generatedEndArcLength - MARGIN
	local wanted = expectCorridor(status.vehicleArcLength - BEHIND, lastWantedArc, WANTED_HALF)
	local kept = expectCorridor(status.vehicleArcLength - KEPT_BEHIND, lastWantedArc, KEPT_HALF)
	for key in wanted do
		Runner.expectEqual(fake.active[key], true)
	end
	for key in fake.active do
		Runner.expectEqual(kept[key], true)
	end
	return wanted, kept
end

local function createStraightPlanner(): (WorldPlanner.WorldPlanner, FakeSink)
	local fake = createFakeSink()
	return WorldPlanner.new({
		seed = SEED,
		sink = fake.sink,
		path = createStraightRoute(),
		createBuilder = FastChunkBuilder.create,
	}),
		fake
end

Runner.test("before any work nothing is written and the world is not ready at the spawn point", function()
	local planner, fake = createStraightPlanner()
	Runner.expectEqual(planner.isWorldReadyAt(planner.getSpawnPoint().position), false)
	Runner.expectEqual(fake.writeCount(), 0)
	Runner.expectEqual(planner.getStatus().writtenChunkCount, 0)
end)

Runner.test("the world is ready only once every chunk of the radius is written, and not a step before", function()
	local planner, fake = createStraightPlanner()
	local spawn = planner.getSpawnPoint().position
	planner.updatePlan(spawn)
	local firstReadyStep = 0
	local steps = 0
	while planner.hasWork() and firstReadyStep == 0 do
		planner.runStep()
		steps += 1
		-- Se mira desde afuera qué chunks del radio están escritos.
		local allWritten = true
		for chunkX = ChunkGrid.getCoordinate(spawn.x - READY_RADIUS), ChunkGrid.getCoordinate(spawn.x + READY_RADIUS) do
			for chunkZ = ChunkGrid.getCoordinate(spawn.z - READY_RADIUS), ChunkGrid.getCoordinate(spawn.z + READY_RADIUS) do
				if ChunkGrid.getDistanceToChunk(chunkX, chunkZ, spawn.x, spawn.z) <= READY_RADIUS then
					allWritten = allWritten and fake.active[ChunkGrid.getKey(chunkX, chunkZ)] == true
				end
			end
		end
		Runner.expectEqual(planner.isWorldReadyAt(spawn), allWritten)
		if allWritten then
			firstReadyStep = steps
		end
	end
	Runner.expectEqual(firstReadyStep > 0, true)
	-- Las ruedas del auto apoyan sobre varios chunks: el spawn está en el borde de dos o más.
	Runner.expectEqual(fake.writeCount() >= 2, true)
end)

Runner.test("a position outside every chunk of the world is never ready, even when everything is idle", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	Runner.expectEqual(planner.isWorldReadyAt(pointOnStraight(16)), true)
	Runner.expectEqual(planner.isWorldReadyAt(vector.create(1e6, 0, 1e6)), false)
	Runner.expectEqual(planner.isWorldReadyAt(vector.create(-5000, 0, 0)), false)
	Runner.expectEqual(planner.isWorldReadyAt(vector.create(16, 0, 3 * CHUNK)), false)
end)

Runner.test("a position at a chunk corner needs the four chunks around it", function()
	local planner, fake = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	local corner = vector.create(CHUNK * 3, 0, 0)
	Runner.expectEqual(planner.isWorldReadyAt(corner), true)
	fake.active[ChunkGrid.getKey(2, -1)] = nil
	for key in fake.active do
		Runner.expectEqual(key ~= nil, true)
	end
end)

Runner.test(
	"at rest it writes exactly the chunks of the corridor around the live route, up to the frontier margin",
	function()
		local planner, fake = createStraightPlanner()
		planner.updatePlan(pointOnStraight(16))
		runUntilIdle(planner)
		local status = planner.getStatus()
		local wanted =
			expectCorridor(status.vehicleArcLength - BEHIND, status.generatedEndArcLength - MARGIN, WANTED_HALF)
		local count = 0
		for key in wanted do
			Runner.expectEqual(fake.active[key], true)
			count += 1
		end
		for key in fake.active do
			Runner.expectEqual(wanted[key], true)
		end
		Runner.expectEqual(status.writtenChunkCount, count)
		Runner.expectEqual(fake.rewriteCount(), 0)
		Runner.expectEqual(status.generatedEndArcLength >= 16 + WorldConfig.ROUTE_AHEAD_STUDS, true)
		Runner.expectEqual(
			status.generatedEndArcLength < 16 + WorldConfig.ROUTE_AHEAD_STUDS + WorldConfig.SEGMENT_LENGTH_STUDS,
			true
		)
	end
)

Runner.test(
	"driving along a straight road it keeps the wanted chunks written and only the kept ones, never rewriting",
	function()
		local planner, fake = createStraightPlanner()
		for arcLength = 16, 4016, MOVE_STUDS do
			planner.updatePlan(pointOnStraight(arcLength))
			runUntilIdle(planner)
			expectWantedAndKept(planner, fake)
		end
		Runner.expectEqual(fake.rewriteCount(), 0)
		Runner.expectEqual(fake.clearCount() > 10, true)
		for _, count in fake.writeCounts do
			Runner.expectEqual(count, 1)
		end
	end
)

Runner.test(
	"a chunk behind the car stays while it is inside the kept corridor and is cleared once it leaves it",
	function()
		local planner, fake = createStraightPlanner()
		-- El chunk 10 (x de 1.280 a 1.408) deja de ser querido con el auto en 2.168 y deja de conservarse en 2.488.
		local chunkKey = ChunkGrid.getKey(10, 0)
		for arcLength = 16, 2616, MOVE_STUDS do
			planner.updatePlan(pointOnStraight(arcLength))
			runUntilIdle(planner)
			if arcLength == 2116 or arcLength == 2316 or arcLength == 2416 then
				Runner.expectEqual(fake.active[chunkKey], true)
			elseif arcLength == 2616 then
				Runner.expectEqual(fake.active[chunkKey], nil)
			end
		end
	end
)

Runner.test("the live route is released behind and the status follows the car", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	Runner.expectEqual(planner.getSurfaceAt(pointOnStraight(100)), "Road")
	for arcLength = 16, 6016, 500 do
		planner.updatePlan(pointOnStraight(arcLength))
		runUntilIdle(planner)
	end
	Runner.expectNear(planner.getStatus().vehicleArcLength, 6016, 1e-3)
	Runner.expectEqual(planner.getSurfaceAt(pointOnStraight(100)), nil)
	Runner.expectEqual(planner.getSurfaceAt(pointOnStraight(6016)), "Road")
end)

Runner.test(
	"when the road comes back near a written chunk it rewrites it, covering what was there, and goes idle",
	function()
		local fake = createFakeSink()
		local planner = WorldPlanner.new({
			seed = SEED,
			sink = fake.sink,
			path = createStadiumRoute(),
			createBuilder = FastChunkBuilder.create,
		})
		for arcLength = 16, OUTBOUND_STEPS * 2 + 400, 80 do
			planner.updatePlan(vector.create(math.min(arcLength, OUTBOUND_STEPS * 2), ROAD_HEIGHT, 0))
			runUntilIdle(planner)
		end
		Runner.expectEqual(fake.rewriteCount() > 0, true)
		local changed = 0
		for key, rows in fake.snapshots do
			if #rows > 1 and fake.active[key] then
				local first, last = fake.firstOf[key], fake.lastOf[key]
				Runner.expectEqual(last.signature ~= first.signature, true)
				local lowestFirst, lowestLast = first.minVoxelY, last.minVoxelY
				Runner.expectEqual(lowestLast <= lowestFirst, true)
				Runner.expectEqual(last.minVoxelY + last.sizeY >= first.minVoxelY + first.sizeY, true)
				local isDifferent = false
				local firstRow, lastRow = rows[1], rows[#rows]
				for layer = 1, math.max(#firstRow, #lastRow) do
					local before = firstRow[layer - (lowestFirst - lowestLast)] or 0
					isDifferent = isDifferent or math.abs(before - (lastRow[layer] or 0)) > 1e-9
				end
				if isDifferent then
					changed += 1
				end
			end
		end
		Runner.expectEqual(changed > 0, true)
		Runner.expectEqual(planner.hasWork(), false)
	end
)

Runner.test("when the car stops, the planner goes idle and does not start working again by itself", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(300))
	runUntilIdle(planner)
	Runner.expectEqual(planner.hasWork(), false)
	planner.updatePlan(pointOnStraight(300))
	Runner.expectEqual(planner.hasWork(), false)
	planner.updatePlan(pointOnStraight(300 + WorldConfig.TERRAIN_PLAN_REFRESH_STUDS * 2))
	Runner.expectEqual(planner.hasWork(), true)
end)

Runner.test("after a jump to another part of the route the new place is written and the old one is cleared", function()
	local planner, fake = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	planner.updatePlan(pointOnStraight(JUMP_ARC))
	runUntilIdle(planner)
	Runner.expectEqual(planner.isWorldReadyAt(pointOnStraight(JUMP_ARC)), true)
	Runner.expectEqual(planner.isWorldReadyAt(pointOnStraight(16)), false)
	expectWantedAndKept(planner, fake)
end)

Runner.test("a car far from the road does not move the plan", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(500))
	runUntilIdle(planner)
	local before = planner.getStatus()
	planner.updatePlan(vector.create(500, ROAD_HEIGHT, 9000))
	runUntilIdle(planner)
	local after = planner.getStatus()
	Runner.expectEqual(after.vehicleArcLength, before.vehicleArcLength)
	Runner.expectEqual(after.generatedEndArcLength, before.generatedEndArcLength)
end)

Runner.test("the contracts answer from the live route: surface, nearest road point and spawn point", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	Runner.expectEqual(planner.getSurfaceAt(vector.create(500, ROAD_HEIGHT, 3)), "Road")
	Runner.expectEqual(planner.getSurfaceAt(vector.create(500, ROAD_HEIGHT, -10)), "Shoulder")
	local off = planner.getSurfaceAt(vector.create(500, ROAD_HEIGHT, 80))
	Runner.expectEqual(off == "Grass" or off == "Mud", true)
	Runner.expectEqual(planner.getSurfaceAt(vector.create(500, ROAD_HEIGHT, 50000)), nil)
	local nearest = planner.getNearestRoadPoint(vector.create(500, 300, 120))
	Runner.expectEqual(nearest ~= nil, true)
	local point = nearest :: { position: vector, direction: vector, arcLength: number }
	Runner.expectNear(point.position.x, 500, 1e-3)
	Runner.expectNear(point.position.y, ROAD_HEIGHT, 1e-3)
	Runner.expectNear(point.position.z, 0, 1e-3)
	Runner.expectNear(point.direction.x, 1, 1e-6)
	Runner.expectNear(point.arcLength, 500, 1e-3)
	Runner.expectEqual(planner.getNearestRoadPoint(vector.create(500, ROAD_HEIGHT, 5000)), nil)
	local spawn = planner.getSpawnPoint()
	Runner.expectNear(spawn.position.x, WorldConfig.SPAWN_ARC_LENGTH_STUDS, 1e-3)
	Runner.expectEqual(spawn.arcLength, WorldConfig.SPAWN_ARC_LENGTH_STUDS)
end)

Runner.test("with the same seed the spawn point is the same in two planners and in the core alone", function()
	local first = WorldPlanner.new({ seed = 77, sink = createFakeSink().sink })
	local second = WorldPlanner.new({ seed = 77, sink = createFakeSink().sink })
	local alone = SpawnPoint.compute(77)
	Runner.expectEqual(first.getSpawnPoint().position, second.getSpawnPoint().position)
	Runner.expectEqual(first.getSpawnPoint().direction, second.getSpawnPoint().direction)
	Runner.expectEqual(first.getSpawnPoint().position, alone.position)
	Runner.expectEqual(first.getSpawnPoint().direction, alone.direction)
	Runner.expectEqual(first.getSpawnPoint().arcLength, alone.arcLength)
end)

Runner.test("on a real route the world gets ready at the spawn point and everything written is kept in step", function()
	local fake = createFakeSink()
	local planner = WorldPlanner.new({ seed = SEED, sink = fake.sink })
	local spawn = planner.getSpawnPoint().position
	planner.updatePlan(spawn)
	Runner.expectEqual(planner.isWorldReadyAt(spawn), false)
	runUntilIdle(planner)
	Runner.expectEqual(planner.isWorldReadyAt(spawn), true)
	Runner.expectEqual(planner.getStatus().writtenChunkCount > 20, true)
	Runner.expectEqual(planner.getSurfaceAt(spawn), "Road")
end)

Runner.test("with a frame budget and a clock the work always finishes and no frame passes the budget", function()
	local fake = createFakeSink()
	local planner = WorldPlanner.new({ seed = SEED, sink = fake.sink, path = createStraightRoute() })
	local now = 0
	local stepCostMs = 0.35
	local source: WorkBudget.WorkSource = {
		hasWork = planner.hasWork,
		runStep = function()
			planner.runStep()
			now += stepCostMs
		end,
	}
	local budget = WorkBudget.new(function(): number
		return now
	end, WorldConfig.WORK_BUDGET_MS_PER_FRAME)
	local frames = 0
	planner.updatePlan(pointOnStraight(16))
	while planner.hasWork() do
		local before = now
		budget.advance(source)
		Runner.expectEqual(now - before <= WorldConfig.WORK_BUDGET_MS_PER_FRAME + 1e-9, true)
		frames += 1
		Runner.expectEqual(frames < 5000, true)
	end
	Runner.expectEqual(planner.isWorldReadyAt(pointOnStraight(16)), true)
end)

Runner.test("running a step with nothing to do changes nothing", function()
	local planner = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	runUntilIdle(planner)
	local before = planner.getStatus()
	for _ = 1, 3 do
		planner.runStep()
	end
	local after = planner.getStatus()
	Runner.expectEqual(planner.hasWork(), false)
	Runner.expectEqual(after.writtenChunkCount, before.writtenChunkCount)
	Runner.expectEqual(after.generatedEndArcLength, before.generatedEndArcLength)
end)

Runner.test("a chunk being built when the car jumps away is abandoned and never written", function()
	local planner, fake = createStraightPlanner()
	planner.updatePlan(pointOnStraight(16))
	while not planner.getStatus().isBuildingChunk do
		planner.runStep()
	end
	local writesBefore = fake.writeCount()
	planner.updatePlan(pointOnStraight(JUMP_ARC))
	runUntilIdle(planner)
	Runner.expectEqual(fake.writeCount() > writesBefore, true)
	-- El chunk que se armaba primero era el más cercano al auto, al lado del punto de aparición.
	Runner.expectEqual(fake.writeCounts[ChunkGrid.getKey(0, -1)], nil)
	Runner.expectEqual(fake.writeCounts[ChunkGrid.getKey(0, 0)], nil)
	expectWantedAndKept(planner, fake)
end)

Runner.test(
	"a chunk that comes out of the builder already stale is rewritten once and then the planner settles",
	function()
		local fake = createFakeSink()
		local function createStaleOnce(
			dependencies: VoxelChunkBuilder.Dependencies
		): VoxelChunkBuilder.VoxelChunkBuilder
			local inner = FastChunkBuilder.create(dependencies)
			local builder = table.clone(inner)
			local results = 0
			builder.getResult = function(): VoxelChunkBuilder.ChunkVoxels
				local result = inner.getResult()
				results += 1
				if results == 1 then
					result.signature += 1
				end
				return result
			end
			return builder
		end
		local planner = WorldPlanner.new({
			seed = SEED,
			sink = fake.sink,
			path = createStraightRoute(),
			createBuilder = createStaleOnce,
		})
		planner.updatePlan(pointOnStraight(16))
		runUntilIdle(planner)
		Runner.expectEqual(fake.rewriteCount(), 1)
		local twice = 0
		for _, count in fake.writeCounts do
			if count == 2 then
				twice += 1
			end
		end
		Runner.expectEqual(twice, 1)
		Runner.expectEqual(planner.hasWork(), false)
	end
)

-- Una ruta real que cuenta las llamadas a la generación y se acuerda de los tramos que entregó, para compararlos.
type CountingPath = {
	path: RoadPath.RoadPath,
	stepCalls: () -> number,
	wholeSegmentCalls: () -> number,
	delivered: { RoadPath.Segment },
}

local function createCountingPath(seed: number): CountingPath
	local inner = RoadPath.new(seed)
	local counting = {} :: CountingPath
	local stepCalls, wholeSegmentCalls = 0, 0
	counting.delivered = {}
	counting.stepCalls = function()
		return stepCalls
	end
	counting.wholeSegmentCalls = function()
		return wholeSegmentCalls
	end
	local path = table.clone(inner)
	path.generateStep = function(): RoadPath.Segment?
		stepCalls += 1
		local segment = inner.generateStep()
		if segment ~= nil then
			table.insert(counting.delivered, segment)
		end
		return segment
	end
	path.generateNextSegment = function(): RoadPath.Segment
		wholeSegmentCalls += 1
		return inner.generateNextSegment()
	end
	counting.path = path
	return counting
end

-- Lleva al auto por la ruta que ya entregó el generador, hasta `targetArc`, y deja que el planificador termine.
local function driveTo(planner: WorldPlanner.WorldPlanner, counting: CountingPath, targetArc: number)
	local stepsPerSegment = SyntheticRoad.STEPS_PER_SEGMENT
	local segment = counting.delivered[math.min(#counting.delivered, targetArc // WorldConfig.SEGMENT_LENGTH_STUDS + 1)]
	local sample = segment.samples[math.min(#segment.samples, stepsPerSegment)]
	planner.updatePlan(sample.position)
end

Runner.test(
	"the planner generates the route one step per unit of work, with the same segments as generateNextSegment",
	function()
		local counting = createCountingPath(SEED)
		local fake = createFakeSink()
		local planner = WorldPlanner.new({
			seed = SEED,
			sink = fake.sink,
			path = counting.path,
			createBuilder = FastChunkBuilder.create,
		})
		local stepsAtConstruction = counting.stepCalls()
		local worstCallsPerUnit, units = 0, 0
		local function runUnit()
			local before = counting.stepCalls()
			planner.runStep()
			worstCallsPerUnit = math.max(worstCallsPerUnit, counting.stepCalls() - before)
			units += 1
			Runner.expectEqual(units < MAX_STEPS, true)
		end
		-- Con presupuesto y reloj falso, como en el juego: cada unidad cuesta lo mismo, así que cada cuadro corre varias.
		local now = 0
		local source: WorkBudget.WorkSource = {
			hasWork = planner.hasWork,
			runStep = function()
				runUnit()
				now += 0.3
			end,
		}
		local budget = WorkBudget.new(function(): number
			return now
		end, WorldConfig.WORK_BUDGET_MS_PER_FRAME)
		planner.updatePlan(planner.getSpawnPoint().position)
		for _ = 1, 3 do
			while planner.hasWork() do
				budget.advance(source)
			end
			driveTo(planner, counting, planner.getStatus().generatedEndArcLength - WorldConfig.ROUTE_AHEAD_STUDS / 2)
		end
		while planner.hasWork() do
			budget.advance(source)
		end
		Runner.expectEqual(worstCallsPerUnit, 1)
		Runner.expectEqual(counting.wholeSegmentCalls(), 0)
		-- Hubo más pasos que tramos: la generación de un tramo se repartió en varias unidades.
		Runner.expectEqual(counting.stepCalls() > #counting.delivered, true)
		Runner.expectEqual(counting.stepCalls() > stepsAtConstruction, true)
		Runner.expectEqual(#counting.delivered > 3, true)
		local reference = PathHelpers.generateSegments(RoadPath.new(SEED), #counting.delivered)
		Runner.expectEqual(PathHelpers.hashSegments(counting.delivered), PathHelpers.hashSegments(reference))
	end
)

Runner.test("a segment that takes several steps is generated across that many units of work", function()
	local fake = createFakeSink()
	local stepsPerSegment = 5
	local segments = SyntheticRoad.createSegments({
		segmentCount = STRAIGHT_SEGMENTS,
		startX = 0,
		startZ = 0,
		startHeadingRadians = 0,
		curvatureAt = function()
			return 0
		end,
		heightAt = function()
			return ROAD_HEIGHT
		end,
	})
	local planner = WorldPlanner.new({
		seed = SEED,
		sink = fake.sink,
		path = SyntheticRoad.createPath(segments, stepsPerSegment),
		createBuilder = FastChunkBuilder.create,
	})
	planner.updatePlan(pointOnStraight(16))
	local endBefore = planner.getStatus().generatedEndArcLength
	local unitsPerSegment = 0
	while planner.getStatus().generatedEndArcLength == endBefore do
		planner.runStep()
		unitsPerSegment += 1
		Runner.expectEqual(unitsPerSegment <= stepsPerSegment, true)
	end
	Runner.expectEqual(unitsPerSegment, stepsPerSegment)
	runUntilIdle(planner)
	Runner.expectEqual(planner.isWorldReadyAt(pointOnStraight(16)), true)
	expectWantedAndKept(planner, fake)
end)

-- Maneja el auto por la ruta del estadio dándole al planificador solo `stepsPerMove` pasos por cada avance, como pasa
-- en Studio con cuadros caros: el trabajo queda atrasado y se replanifica antes de vaciar la cola.
local function driveStadiumLagging(stepsPerMove: number?): (WorldPlanner.WorldPlanner, FakeSink)
	local fake = createFakeSink()
	local planner = WorldPlanner.new({
		seed = SEED,
		sink = fake.sink,
		path = createStadiumRoute(),
		createBuilder = FastChunkBuilder.create,
	})
	for arcLength = 16, OUTBOUND_STEPS * 2 + 400, LAG_MOVE_STUDS do
		planner.updatePlan(vector.create(math.min(arcLength, OUTBOUND_STEPS * 2), ROAD_HEIGHT, 0))
		if stepsPerMove == nil then
			runUntilIdle(planner)
		else
			for _ = 1, stepsPerMove do
				if planner.hasWork() then
					planner.runStep()
				end
			end
		end
	end
	runUntilIdle(planner)
	-- Un reinicio del auto un poco más atrás: los chunks que quedaron fuera de lo que se quería vuelven a ser querido.
	planner.updatePlan(vector.create(LAG_BACK_TO_X, ROAD_HEIGHT, 0))
	runUntilIdle(planner)
	return planner, fake
end

Runner.test(
	"a chunk that went stale while the work was lagging behind the car ends up with the same road as without lag",
	function()
		local _, lagging = driveStadiumLagging(LAG_STEPS_PER_MOVE)
		local _, reference = driveStadiumLagging(nil)
		local compared, rewritten = 0, 0
		for key, last in lagging.lastOf do
			local expected = reference.lastOf[key]
			if
				lagging.active[key]
				and reference.active[key]
				and expected ~= nil
				and last.chunkX >= LAG_FIRST_COMPARED_CHUNK_X
			then
				compared += 1
				Runner.expectEqual(last.signature, expected.signature)
				if (lagging.writeCounts[key] or 0) > 1 then
					rewritten += 1
				end
			end
		end
		Runner.expectEqual(compared > 10, true)
		Runner.expectEqual(rewritten > 0, true)
	end
)

Runner.finish()
