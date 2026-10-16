--!strict
-- Maneja un auto por el eje de la ruta de una semilla con el planificador real y el armador de chunks real, con un reloj
-- falso que hace que el trabajo vaya atrasado respecto del auto (lo que pasa en Studio con cuadros caros), y mide si la
-- altura escrita sobre el eje coincide con la altura del eje. No es una prueba: no termina en Runner.finish().

local ChunkGrid = require("../../src/world/core/ChunkGrid")
local RoadPath = require("../../src/world/core/RoadPath")
local VoxelChunkBuilder = require("../../src/world/core/VoxelChunkBuilder")
local WorkBudget = require("../../src/world/core/WorkBudget")
local WorldConfig = require("../../src/world/core/WorldConfig")
local WorldPlanner = require("../../src/world/core/WorldPlanner")

export type Options = {
	seed: number,
	-- Cuántos milisegundos del reloj falso cuesta cada paso del planificador: más alto, más atrasado va el trabajo.
	stepMs: number,
	startArcLength: number,
	endArcLength: number,
	speedStudsPerSecond: number,
}

export type Report = {
	-- Puntos del eje medidos (su chunk estaba escrito), y cuántos de esos el mundo daba por listos (IsWorldReadyAt).
	checkCount: number,
	readyCheckCount: number,
	-- Cuántos de los listos tienen una altura mala: esto es lo que no puede pasar. Los que no estaban listos son
	-- trabajo atrasado que el mundo avisa, y se cuentan aparte.
	badCount: number,
	notReadyBadCount: number,
	worstDifference: number,
	-- La primera diferencia mala, para el mensaje de la prueba.
	firstBad: string?,
}

local CHUNK_STUDS = WorldConfig.CHUNK_SIZE_STUDS
local VOXEL_STUDS = WorldConfig.TERRAIN_VOXEL_STUDS
local CHUNK_VOXELS = CHUNK_STUDS // VOXEL_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local SEGMENT_STUDS = WorldConfig.SEGMENT_LENGTH_STUDS
local FRAMES_PER_SECOND = 60
-- Cada cuántos cuadros se mide, y qué tramo de eje alrededor del auto se mide (atrás y adelante).
local FRAMES_PER_CHECK = 15
local CHECK_BEHIND_STUDS = 100
local CHECK_AHEAD_STUDS = 300
local CHECK_STRIDE_STUDS = 8
local CAR_HEIGHT_STUDS = 4
-- Tolerancia entre la altura escrita sobre el eje y la del eje (la que se pidió en el reporte del bug).
local TOLERANCE_STUDS = 0.5
-- Ruta de referencia generada de más, para tener el eje por delante del último chequeo.
local REFERENCE_EXTRA_STUDS = 3000
-- Cuántas muestras a cada lado del arcLength medido se miran para hallar el punto más cercano del eje.
local NEAR_AXIS_SAMPLES = 20

local TerrainDrive = {}

function TerrainDrive.run(options: Options): Report
	-- La ruta de referencia se genera entera y sin liberar nada: es el eje que el auto sigue y contra el que se compara.
	local reference = RoadPath.new(options.seed)
	local referenceSamples: { RoadPath.RoadSample } = {}
	repeat
		local segment = reference.generateNextSegment()
		for offset, sample in segment.samples do
			if segment.index == 0 or offset > 1 then
				table.insert(referenceSamples, sample)
			end
		end
	until (segment.index + 1) * SEGMENT_STUDS > options.endArcLength + REFERENCE_EXTRA_STUDS

	local function axisAt(arcLength: number): vector
		local fraction = arcLength / STEP_STUDS
		local index = math.floor(fraction)
		local start, finish = referenceSamples[index + 1].position, referenceSamples[index + 2].position
		return start + (finish - start) * (fraction - index)
	end

	-- Altura del eje en el punto más cercano a (x, z) entre las muestras cercanas a `nearArcLength`. Se mira solo ahí porque
	-- la ruta de referencia, entera, puede pasar por el mismo lugar mucho más atrás o más adelante (el anti-cruce solo rige
	-- en la ruta viva) y esa pasada no está en el mundo.
	local function getAxisHeightNear(x: number, z: number, nearArcLength: number): number
		local firstIndex = math.max(math.floor(nearArcLength / STEP_STUDS) - NEAR_AXIS_SAMPLES, 0)
		local bestSquared, bestHeight = math.huge, 0
		for index = firstIndex, firstIndex + 2 * NEAR_AXIS_SAMPLES do
			local start, finish = referenceSamples[index + 1].position, referenceSamples[index + 2].position
			local edgeX, edgeZ = finish.x - start.x, finish.z - start.z
			local fraction =
				math.clamp(((x - start.x) * edgeX + (z - start.z) * edgeZ) / (edgeX * edgeX + edgeZ * edgeZ), 0, 1)
			local offsetX, offsetZ = start.x + fraction * edgeX - x, start.z + fraction * edgeZ - z
			local squared = offsetX * offsetX + offsetZ * offsetZ
			if squared < bestSquared then
				bestSquared, bestHeight = squared, start.y + fraction * (finish.y - start.y)
			end
		end
		return bestHeight
	end

	-- Lo último escrito por chunk: la altura de cada columna, sacada de la ocupación.
	local writtenHeights: { [number]: { number } } = {}
	local sink: WorldPlanner.ChunkSink = {
		writeChunk = function(voxels: VoxelChunkBuilder.ChunkVoxels)
			local key = ChunkGrid.getKey(voxels.chunkX, voxels.chunkZ)
			local heights = writtenHeights[key] or table.create(CHUNK_VOXELS * CHUNK_VOXELS, 0)
			for row = 1, CHUNK_VOXELS do
				for column = 1, CHUNK_VOXELS do
					local filledVoxels = voxels.minVoxelY
					for layer = 1, voxels.sizeY do
						filledVoxels += voxels.occupancy[row][layer][column]
					end
					heights[(row - 1) * CHUNK_VOXELS + column] = filledVoxels * VOXEL_STUDS
						+ WorldConfig.TERRAIN_SURFACE_OFFSET_STUDS
				end
			end
			writtenHeights[key] = heights
		end,
		clearChunk = function(chunkX: number, chunkZ: number)
			writtenHeights[ChunkGrid.getKey(chunkX, chunkZ)] = nil
		end,
	}

	local planner = WorldPlanner.new({ seed = options.seed, sink = sink })
	local fakeNowMs = 0
	local budget = WorkBudget.new(function(): number
		return fakeNowMs
	end, WorldConfig.WORK_BUDGET_MS_PER_FRAME)
	local source: WorkBudget.WorkSource = {
		hasWork = planner.hasWork,
		runStep = function()
			planner.runStep()
			fakeNowMs += options.stepMs
		end,
	}

	local report: Report = {
		checkCount = 0,
		readyCheckCount = 0,
		badCount = 0,
		notReadyBadCount = 0,
		worstDifference = 0,
		firstBad = nil,
	}

	-- Mide los puntos del eje cuyo chunk ya está escrito: en el centro del vóxel que los contiene, la altura escrita
	-- tiene que ser la del eje en ese lugar siempre que el mundo se dé por listo ahí.
	local function checkAround(carArcLength: number)
		local firstArc = math.max(carArcLength - CHECK_BEHIND_STUDS, 0)
		for arcLength = firstArc, carArcLength + CHECK_AHEAD_STUDS, CHECK_STRIDE_STUDS do
			local axis = axisAt(arcLength)
			local chunkX, chunkZ = ChunkGrid.getCoordinate(axis.x), ChunkGrid.getCoordinate(axis.z)
			local heights = writtenHeights[ChunkGrid.getKey(chunkX, chunkZ)]
			if heights ~= nil then
				local row = math.floor((axis.x - chunkX * CHUNK_STUDS) / VOXEL_STUDS) + 1
				local column = math.floor((axis.z - chunkZ * CHUNK_STUDS) / VOXEL_STUDS) + 1
				local centerX = chunkX * CHUNK_STUDS + (row - 0.5) * VOXEL_STUDS
				local centerZ = chunkZ * CHUNK_STUDS + (column - 0.5) * VOXEL_STUDS
				local difference = heights[(row - 1) * CHUNK_VOXELS + column]
					- getAxisHeightNear(centerX, centerZ, arcLength)
				local isBad = math.abs(difference) > TOLERANCE_STUDS
				report.checkCount += 1
				if not planner.isWorldReadyAt(axis) then
					if isBad then
						report.notReadyBadCount += 1
					end
				else
					report.readyCheckCount += 1
					report.worstDifference = math.max(report.worstDifference, math.abs(difference))
					if isBad then
						report.badCount += 1
						report.firstBad = report.firstBad
							or `car at {math.floor(carArcLength)}, axis at {arcLength}: {difference} studs`
					end
				end
			end
		end
	end

	-- Calentamiento sin presupuesto: el mundo ya está listo cuando el auto empieza a moverse.
	local startPosition = axisAt(options.startArcLength) + vector.create(0, CAR_HEIGHT_STUDS, 0)
	planner.updatePlan(startPosition)
	while planner.hasWork() do
		planner.runStep()
	end

	local carArcLength = options.startArcLength
	local frame = 0
	while carArcLength < options.endArcLength do
		carArcLength += options.speedStudsPerSecond / FRAMES_PER_SECOND
		frame += 1
		planner.updatePlan(axisAt(carArcLength) + vector.create(0, CAR_HEIGHT_STUDS, 0))
		budget.advance(source)
		if frame % FRAMES_PER_CHECK == 0 then
			checkAround(carArcLength)
		end
	end
	return report
end

return TerrainDrive
