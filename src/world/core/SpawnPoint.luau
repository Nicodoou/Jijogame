--!strict
-- Punto de aparición del auto (contrato #35, GetSpawnPoint): el comienzo de la ruta, a SPAWN_ARC_LENGTH_STUDS del inicio.
-- Sale solo de la semilla y del núcleo, sin esperar al Terrain, así el servidor y el cliente dan exactamente lo mismo.

local RoadPath = require("./RoadPath")
local RoadPoint = require("../../shared/contracts/RoadPoint")
local WorldConfig = require("./WorldConfig")

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local SPAWN_ARC_STUDS = WorldConfig.SPAWN_ARC_LENGTH_STUDS

local SpawnPoint = {}

-- Punto de aparición sobre una ruta que todavía conserva su primer tramo.
function SpawnPoint.fromPath(path: RoadPath.RoadPath): RoadPoint.RoadPoint
	local firstLoaded, lastLoaded = path.getLoadedRange()
	if lastLoaded < firstLoaded then
		path.generateNextSegment()
	end
	local segment = path.getSegment(0)
	if segment == nil then
		error("the spawn point needs the first segment of the route", 2)
	end
	local sampleNumber = math.floor(SPAWN_ARC_STUDS / STEP_STUDS)
	local fraction = SPAWN_ARC_STUDS / STEP_STUDS - sampleNumber
	local from = segment.samples[sampleNumber + 1]
	local to = segment.samples[sampleNumber + 2]
	return {
		position = from.position + (to.position - from.position) * fraction,
		-- Es la dirección de la arista, la misma que da RoadQuery en ese punto.
		direction = vector.normalize(to.position - from.position),
		arcLength = SPAWN_ARC_STUDS,
	}
end

-- Punto de aparición de una semilla: arma la ruta solo para esto.
function SpawnPoint.compute(seed: number): RoadPoint.RoadPoint
	return SpawnPoint.fromPath(RoadPath.new(seed))
end

return SpawnPoint
