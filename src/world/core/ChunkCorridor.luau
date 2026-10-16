--!strict
-- Los chunks que toca un corredor alrededor de un tramo de la ruta viva: los que quedan a `halfWidthStuds` o menos de
-- algún punto del eje, tomado cada TERRAIN_CORRIDOR_SAMPLE_STUDS.

local ChunkGrid = require("./ChunkGrid")
local RoadWindow = require("./RoadWindow")
local WorldConfig = require("./WorldConfig")

export type ChunkCell = {
	chunkX: number,
	chunkZ: number,
	key: number,
}

local ChunkCorridor = {}

-- Chunks del corredor entre dos arcLength, por clave.
function ChunkCorridor.collect(
	window: RoadWindow.RoadWindow,
	fromArcLength: number,
	toArcLength: number,
	halfWidthStuds: number
): { [number]: ChunkCell }
	local cells: { [number]: ChunkCell } = {}
	window.forEachAxisPoint(fromArcLength, toArcLength, WorldConfig.TERRAIN_CORRIDOR_SAMPLE_STUDS, function(x, z)
		for chunkX = ChunkGrid.getCoordinate(x - halfWidthStuds), ChunkGrid.getCoordinate(x + halfWidthStuds) do
			for chunkZ = ChunkGrid.getCoordinate(z - halfWidthStuds), ChunkGrid.getCoordinate(z + halfWidthStuds) do
				local key = ChunkGrid.getKey(chunkX, chunkZ)
				if cells[key] == nil and ChunkGrid.getDistanceToChunk(chunkX, chunkZ, x, z) <= halfWidthStuds then
					cells[key] = { chunkX = chunkX, chunkZ = chunkZ, key = key }
				end
			end
		end
	end)
	return cells
end

return ChunkCorridor
