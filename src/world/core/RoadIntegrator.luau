--!strict
-- Un paso de integración de la ruta. Lo comparten el secuenciador (para previsualizar una pieza) y RoadPath, así lo que
-- se previsualiza es, bit a bit, lo que después se publica.

local HillProfile = require("./HillProfile")
local WorldConfig = require("./WorldConfig")

-- Rumbo en radianes (crece hacia la derecha), curvatura en 1/stud, pendiente en radianes y arcLength en studs medidos
-- sobre el plano horizontal. Las muestras no se modifican después de crearse.
export type RoadSample = {
	position: vector,
	heading: number,
	curvature: number,
	slope: number,
	arcLength: number,
}

-- Posición en componentes sueltos (doubles): un `vector` guarda floats de 32 bits y sumar pasos de 2 studs sobre él
-- acumularía error.
export type IntegratorState = {
	x: number,
	y: number,
	z: number,
	heading: number,
	curvature: number,
	slope: number,
	sampleIndex: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local HALF = 0.5

local RoadIntegrator = {}

function RoadIntegrator.createState(position: vector, headingRadians: number): IntegratorState
	return {
		x = position.x,
		y = position.y,
		z = position.z,
		heading = headingRadians,
		curvature = 0,
		slope = 0,
		sampleIndex = 0,
	}
end

-- Avanza un paso y deja el estado en la muestra siguiente. La curvatura y la pendiente varían linealmente entre pasos,
-- así que el promedio de los extremos integra el rumbo y la altura sin error, y el rumbo medio da la dirección del paso.
function RoadIntegrator.step(state: IntegratorState, nextCurvature: number, hill: HillProfile.HillProfile)
	local nextSlope = hill.nextSlope(state.y, state.slope, state.sampleIndex * STEP_STUDS)
	local nextHeading = state.heading + HALF * (state.curvature + nextCurvature) * STEP_STUDS
	local stepHeading = HALF * (state.heading + nextHeading)
	state.x += STEP_STUDS * math.cos(stepHeading)
	state.z += STEP_STUDS * math.sin(stepHeading)
	state.y += STEP_STUDS * math.tan(HALF * (state.slope + nextSlope))
	state.heading = nextHeading
	state.curvature = nextCurvature
	state.slope = nextSlope
	state.sampleIndex += 1
end

function RoadIntegrator.toSample(state: IntegratorState): RoadSample
	return {
		position = vector.create(state.x, state.y, state.z),
		heading = state.heading,
		curvature = state.curvature,
		slope = state.slope,
		arcLength = state.sampleIndex * STEP_STUDS,
	}
end

return RoadIntegrator
