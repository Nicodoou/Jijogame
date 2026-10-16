--!strict
-- Referencias comunes de la ruta: pasos por tramo, rumbo inicial y envoltura de ángulos.

local WorldConfig = require("./WorldConfig")

local FULL_TURN_RADIANS = 2 * math.pi
local HALF_TURN_RADIANS = math.pi
local START_HEADING_RADIANS = math.rad(WorldConfig.START_HEADING_DEGREES)
local STEPS_PER_SEGMENT = math.round(WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS)

local RoadFrame = {}

function RoadFrame.getStepsPerSegment(): number
	return STEPS_PER_SEGMENT
end

function RoadFrame.getStartHeadingRadians(): number
	return START_HEADING_RADIANS
end

-- Lleva un ángulo a [-pi, pi). El rumbo crece hacia la derecha del sentido de marcha.
function RoadFrame.wrapAngleRadians(angle: number): number
	return (angle + HALF_TURN_RADIANS) % FULL_TURN_RADIANS - HALF_TURN_RADIANS
end

return RoadFrame
