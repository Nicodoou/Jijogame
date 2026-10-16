--!strict
-- La ruta viva alrededor del auto: sigue su arcLength sobre la ruta, genera tramos hasta ROUTE_AHEAD_STUDS por delante
-- (sobre la ruta publicada: el buffer del secuenciador ya va más adelante y eso no cambia la cuenta) y libera los que
-- quedan más atrás de LIVE_LOOKBACK_STUDS. Los bloques que usa el terreno se guardan menos tiempo que la ruta, para que
-- dos pasadas que el terreno vea juntas nunca estén a más de LIVE_LOOKBACK_STUDS de arcLength (ahí rige el anti-cruce).

local RoadBlocks = require("./RoadBlocks")
local RoadFrame = require("./RoadFrame")
local RoadPath = require("./RoadPath")
local RoadQuery = require("./RoadQuery")
local WorldConfig = require("./WorldConfig")

export type RoadWindow = {
	query: RoadQuery.RoadQuery,
	blocks: RoadBlocks.RoadBlocks,
	-- Sigue al auto: guarda su arcLength si la posición cae sobre la ruta cargada. Devuelve el arcLength actual.
	trackVehicle: (position: vector) -> number,
	getVehicleArcLength: () -> number,
	-- arcLength hasta el que hay ruta publicada.
	getGeneratedEndArcLength: () -> number,
	needsExtension: () -> boolean,
	-- Genera un tramo más y lo devuelve.
	extend: () -> RoadPath.Segment,
	-- Libera la ruta y los bloques que quedaron muy atrás. Devuelve true si liberó algo.
	releaseOldSegments: () -> boolean,
	-- Llama a `visit(x, z, arcLength)` en los puntos del eje entre dos arcLength, cada `strideStuds`.
	forEachAxisPoint: (
		fromArcLength: number,
		toArcLength: number,
		strideStuds: number,
		visit: (number, number, number) -> ()
	) -> (),
}

local SEGMENT_STUDS = WorldConfig.SEGMENT_LENGTH_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()

local RoadWindowModule = {}

-- `blockMemoryStuds` es cuánto hacia atrás guardan los bloques del terreno.
function RoadWindowModule.new(path: RoadPath.RoadPath, aheadStuds: number, blockMemoryStuds: number): RoadWindow
	local query = RoadQuery.new(path)
	local blocks = RoadBlocks.new()
	local cursor: RoadQuery.RoadQueryResult? = nil
	local vehicleArcLength = 0
	local blocksFirstSegment = 0

	local function trackVehicle(position: vector): number
		cursor = query.findNearest(position, cursor)
		if cursor ~= nil then
			vehicleArcLength = cursor.arcLength
		end
		return vehicleArcLength
	end

	local function getVehicleArcLength(): number
		return vehicleArcLength
	end

	local function getGeneratedEndArcLength(): number
		local _, lastLoaded = path.getLoadedRange()
		return (lastLoaded + 1) * SEGMENT_STUDS
	end

	local function needsExtension(): boolean
		return getGeneratedEndArcLength() < vehicleArcLength + aheadStuds
	end

	local function extend(): RoadPath.Segment
		local segment = path.generateNextSegment()
		blocks.addSegment(segment)
		return segment
	end

	local function releaseOldSegments(): boolean
		local pathFirst = path.getLoadedRange()
		local keepFromSegment = math.floor((vehicleArcLength - WorldConfig.LIVE_LOOKBACK_STUDS) / SEGMENT_STUDS)
		local blocksFromSegment = math.floor((vehicleArcLength - blockMemoryStuds) / SEGMENT_STUDS)
		local hasReleased = keepFromSegment > pathFirst or blocksFromSegment > blocksFirstSegment
		if keepFromSegment > pathFirst then
			path.releaseSegmentsBefore(keepFromSegment)
		end
		if blocksFromSegment > blocksFirstSegment then
			blocks.forgetBefore(blocksFromSegment)
			blocksFirstSegment = blocksFromSegment
		end
		return hasReleased
	end

	local function forEachAxisPoint(
		fromArcLength: number,
		toArcLength: number,
		strideStuds: number,
		visit: (number, number, number) -> ()
	)
		local firstLoaded, lastLoaded = path.getLoadedRange()
		local stride = math.max(1, math.round(strideStuds / STEP_STUDS))
		local firstSample = math.max(math.ceil(fromArcLength / STEP_STUDS), firstLoaded * STEPS_PER_SEGMENT)
		local lastSample = math.min(math.floor(toArcLength / STEP_STUDS), (lastLoaded + 1) * STEPS_PER_SEGMENT)
		-- Alineados a múltiplos del paso, así los puntos no se corren cuando cambia la ventana.
		for sampleNumber = math.ceil(firstSample / stride) * stride, lastSample, stride do
			-- La última muestra de la ruta cargada es la última del último tramo.
			local segment = path.getSegment(sampleNumber // STEPS_PER_SEGMENT)
				or path.getSegment(sampleNumber // STEPS_PER_SEGMENT - 1)
			if segment ~= nil then
				local sample = segment.samples[sampleNumber - segment.index * STEPS_PER_SEGMENT + 1]
				visit(sample.position.x, sample.position.z, sample.arcLength)
			end
		end
	end

	return {
		query = query,
		blocks = blocks,
		trackVehicle = trackVehicle,
		getVehicleArcLength = getVehicleArcLength,
		getGeneratedEndArcLength = getGeneratedEndArcLength,
		needsExtension = needsExtension,
		extend = extend,
		releaseOldSegments = releaseOldSegments,
		forEachAxisPoint = forEachAxisPoint,
	}
end

return RoadWindowModule
