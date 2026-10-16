--!strict
-- Las medidas de la ventana de terreno alrededor del auto, derivadas de WorldConfig: hasta dónde se pide terreno, hasta
-- dónde se conserva (con histéresis) y cuánta ruta hace falta recordar para que los chunks conservados vean toda la
-- ruta que los influye.

local WorldConfig = require("./WorldConfig")

local CHUNK_DIAGONAL_STUDS = math.sqrt(2) * WorldConfig.CHUNK_SIZE_STUDS
local SHOULDER_EDGE_STUDS = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS

local wantedHalfWidthStuds = WorldConfig.TERRAIN_CORRIDOR_HALF_WIDTH_STUDS
local keptHalfWidthStuds = wantedHalfWidthStuds + WorldConfig.TERRAIN_CORRIDOR_KEEP_EXTRA_STUDS
local wantedBehindStuds = WorldConfig.TERRAIN_BEHIND_STUDS
local keptBehindStuds = wantedBehindStuds + WorldConfig.TERRAIN_BEHIND_KEEP_EXTRA_STUDS

local TerrainWindow = {}

-- Mitad del ancho del corredor de chunks que se piden, y del que se conserva.
TerrainWindow.WANTED_HALF_WIDTH_STUDS = wantedHalfWidthStuds
TerrainWindow.KEPT_HALF_WIDTH_STUDS = keptHalfWidthStuds
-- Cuánta ruta por detrás del auto se pide y cuánta se conserva.
TerrainWindow.WANTED_BEHIND_STUDS = wantedBehindStuds
TerrainWindow.KEPT_BEHIND_STUDS = keptBehindStuds
-- Cuánta ruta recuerdan los bloques del terreno por detrás del auto: lo que se conserva más lo que llega a influir en
-- el chunk conservado más lejano (su corredor, su diagonal, el alcance de la ruta y la banquina).
TerrainWindow.BLOCK_MEMORY_STUDS = keptBehindStuds
	+ keptHalfWidthStuds
	+ CHUNK_DIAGONAL_STUDS
	+ WorldConfig.TERRAIN_ROAD_REACH_STUDS
	+ SHOULDER_EDGE_STUDS

-- Entre el primer bloque que se recuerda y el último tramo generado no puede haber más de LIVE_LOOKBACK_STUDS: pasado
-- eso la ruta ya no garantiza que dos pasadas queden separadas y el terreno podría ver dos caminos cruzándose.
function TerrainWindow.fitsInLiveRoute(blockMemoryStuds: number, routeAheadStuds: number): boolean
	return blockMemoryStuds + routeAheadStuds + WorldConfig.SEGMENT_LENGTH_STUDS <= WorldConfig.LIVE_LOOKBACK_STUDS
end

return table.freeze(TerrainWindow)
