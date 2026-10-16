--!strict
-- Revisiones muestra por muestra de una ruta ya generada: límites de curvatura, pendiente, altura y área, y continuidad
-- entre tramos. Cuentan las violaciones; no frenan en la primera. No es una prueba: no termina en Runner.finish().

local RoadPath = require("../../src/world/core/RoadPath")
local WorldConfig = require("../../src/world/core/WorldConfig")

export type Violations = {
	curvature: number,
	curvatureJump: number,
	slope: number,
	slopeChange: number,
	height: number,
	area: number,
	step: number,
	notFinite: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = WorldConfig.SEGMENT_LENGTH_STUDS // STEP_STUDS
local TOLERANCE = 1e-9
-- Un vector guarda floats de 32 bits: a 8.000 studs del origen cada coordenada se redondea a 0,001 studs.
local VECTOR_PRECISION_STUDS = 0.05
local MAX_CURVATURE = 1 / WorldConfig.MIN_CURVE_RADIUS_STUDS
local MAX_SLOPE_RADIANS = math.rad(WorldConfig.MAX_SLOPE_DEGREES)
local MAX_SLOPE_CHANGE_RADIANS = math.rad(WorldConfig.HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP)
-- La curvatura sube de a una rampa: la más corta que se confirma en la ruta es la del último recurso más breve.
local SHORTEST_COMMITTED_RAMP_STEPS = math.max(
	1,
	math.round(WorldConfig.TIGHT_TURN_RAMP_FRACTION * math.min(table.unpack(WorldConfig.LAST_RESORT_LOBE_STEPS)))
)
local MAX_CURVATURE_JUMP = MAX_CURVATURE / SHORTEST_COMMITTED_RAMP_STEPS
local AREA_SQUARED = (WorldConfig.AREA_RADIUS_STUDS + VECTOR_PRECISION_STUDS) ^ 2

local RoadSampleChecks = {}

RoadSampleChecks.vectorPrecisionStuds = VECTOR_PRECISION_STUDS

function RoadSampleChecks.createViolations(): Violations
	return {
		curvature = 0,
		curvatureJump = 0,
		slope = 0,
		slopeChange = 0,
		height = 0,
		area = 0,
		step = 0,
		notFinite = 0,
	}
end

local function isFinite(value: number): boolean
	return value == value and math.abs(value) ~= math.huge
end

local function countSampleLimits(sample: RoadPath.RoadSample, violations: Violations)
	local position = sample.position
	for _, value in { position.x, position.y, position.z, sample.heading, sample.curvature, sample.slope } do
		violations.notFinite += if isFinite(value) then 0 else 1
	end
	violations.curvature += if math.abs(sample.curvature) <= MAX_CURVATURE + TOLERANCE then 0 else 1
	violations.slope += if math.abs(sample.slope) <= MAX_SLOPE_RADIANS + TOLERANCE then 0 else 1
	local inBand = position.y >= WorldConfig.HILL_MIN_HEIGHT_STUDS - VECTOR_PRECISION_STUDS
		and position.y <= WorldConfig.HILL_MAX_HEIGHT_STUDS + VECTOR_PRECISION_STUDS
	violations.height += if inBand then 0 else 1
	violations.area += if position.x ^ 2 + position.z ^ 2 <= AREA_SQUARED then 0 else 1
end

local function countStepLimits(sample: RoadPath.RoadSample, previous: RoadPath.RoadSample, violations: Violations)
	local jump = math.abs(sample.curvature - previous.curvature)
	violations.curvatureJump += if jump <= MAX_CURVATURE_JUMP + TOLERANCE then 0 else 1
	local slopeChange = math.abs(sample.slope - previous.slope)
	violations.slopeChange += if slopeChange <= MAX_SLOPE_CHANGE_RADIANS + TOLERANCE then 0 else 1
	local groundDistance =
		math.sqrt((sample.position.x - previous.position.x) ^ 2 + (sample.position.z - previous.position.z) ^ 2)
	local isOneStep = sample.arcLength - previous.arcLength == STEP_STUDS
		and math.abs(groundDistance - STEP_STUDS) <= VECTOR_PRECISION_STUDS
	violations.step += if isOneStep then 0 else 1
end

-- Cuenta, sobre todas las muestras de la ruta, las que pasan de un límite.
function RoadSampleChecks.countViolations(road: { RoadPath.RoadSample }): Violations
	local violations = RoadSampleChecks.createViolations()
	local previous: RoadPath.RoadSample? = nil
	for _, sample in road do
		countSampleLimits(sample, violations)
		if previous ~= nil then
			countStepLimits(sample, previous, violations)
		end
		previous = sample
	end
	return violations
end

-- Cada tramo empieza donde terminó el anterior, muestra por muestra.
function RoadSampleChecks.countContinuityViolations(segments: { RoadPath.Segment }): number
	local violations = 0
	for index = 2, #segments do
		local last = segments[index - 1].samples[STEPS_PER_SEGMENT + 1]
		local first = segments[index].samples[1]
		local isSame = first.position == last.position
			and first.heading == last.heading
			and first.curvature == last.curvature
			and first.slope == last.slope
			and first.arcLength == last.arcLength
		violations += if isSame then 0 else 1
	end
	return violations
end

-- Todas las muestras de los tramos en orden, sin repetir la que comparten dos tramos seguidos.
function RoadSampleChecks.flatten(segments: { RoadPath.Segment }): { RoadPath.RoadSample }
	local road = {}
	for index, segment in segments do
		for offset, sample in segment.samples do
			if index == 1 or offset > 1 then
				table.insert(road, sample)
			end
		end
	end
	return road
end

return RoadSampleChecks
