--!strict
-- Implementa GetSurfaceAt (contrato #17): decide la superficie de una posición con el punto más cercano del eje.

local RoadQuery = require("./RoadQuery")
local SeededRandom = require("./SeededRandom")
local Surface = require("../../shared/contracts/Surface")
local WorldConfig = require("./WorldConfig")

local ROAD_HALF_WIDTH_STUDS = WorldConfig.ROAD_WIDTH_STUDS / 2
local SHOULDER_EDGE_STUDS = ROAD_HALF_WIDTH_STUDS + WorldConfig.SHOULDER_WIDTH_STUDS
local MUD_MIN_LATERAL_STUDS = SHOULDER_EDGE_STUDS + WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS
-- Un desplazamiento entero pondría los puntos del ruido sobre la grilla de la función, donde vale siempre 0.
local NON_INTEGER_OFFSET = 0.5

local SurfaceClassifier = {}

function SurfaceClassifier.createGetSurfaceAt(query: RoadQuery.RoadQuery, seed: number): Surface.GetSurfaceAt
	local random = SeededRandom.new(seed)
	local offsetX = math.floor(random.nextNumber() * WorldConfig.MUD_NOISE_OFFSET_RANGE) + NON_INTEGER_OFFSET
	local offsetZ = math.floor(random.nextNumber() * WorldConfig.MUD_NOISE_OFFSET_RANGE) + NON_INTEGER_OFFSET

	local function isMudNoiseHigh(position: vector): boolean
		local noise = math.noise(
			position.x * WorldConfig.MUD_NOISE_SCALE_PER_STUD + offsetX,
			position.z * WorldConfig.MUD_NOISE_SCALE_PER_STUD + offsetZ
		)
		return noise > WorldConfig.MUD_NOISE_THRESHOLD
	end

	return function(position: vector): Surface.SurfaceKind?
		local nearest = query.findNearest(position, nil)
		if nearest == nil then
			return nil
		end
		local lateralStuds = math.abs(nearest.lateralOffset)
		if lateralStuds <= ROAD_HALF_WIDTH_STUDS then
			return "Road"
		elseif lateralStuds <= SHOULDER_EDGE_STUDS then
			return "Shoulder"
		elseif lateralStuds > MUD_MIN_LATERAL_STUDS and isMudNoiseHigh(position) then
			return "Mud"
		end
		return "Grass"
	end
end

return SurfaceClassifier
