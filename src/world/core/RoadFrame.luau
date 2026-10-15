--!strict
-- Marco de referencia de la ruta: rumbo medio, desvío lateral y pasos por tramo.

local WorldConfig = require("./WorldConfig")

local FULL_TURN_RADIANS = 2 * math.pi
local HALF_TURN_RADIANS = math.pi
local MEAN_HEADING_RADIANS = math.atan2(WorldConfig.MEAN_HEADING.z, WorldConfig.MEAN_HEADING.x)
-- Convención: el rumbo crece hacia la derecha del sentido de marcha, igual que el desvío lateral.
local MEAN_RIGHT_X = -math.sin(MEAN_HEADING_RADIANS)
local MEAN_RIGHT_Z = math.cos(MEAN_HEADING_RADIANS)
local STEPS_PER_SEGMENT = math.round(WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS)

local RoadFrame = {}

function RoadFrame.getStepsPerSegment(): number
	return STEPS_PER_SEGMENT
end

function RoadFrame.getMeanHeadingRadians(): number
	return MEAN_HEADING_RADIANS
end

-- Diferencia entre un rumbo y el medio, llevada a (-pi, pi].
function RoadFrame.getHeadingDeviationRadians(heading: number): number
	local wrapped = (heading - MEAN_HEADING_RADIANS + HALF_TURN_RADIANS) % FULL_TURN_RADIANS
	return wrapped - HALF_TURN_RADIANS
end

-- Distancia con signo (positiva a la derecha) entre una posición y la recta media que sale del punto de partida.
function RoadFrame.getLateralOffsetStuds(position: vector): number
	local start = WorldConfig.START_POSITION
	return (position.x - start.x) * MEAN_RIGHT_X + (position.z - start.z) * MEAN_RIGHT_Z
end

return RoadFrame
