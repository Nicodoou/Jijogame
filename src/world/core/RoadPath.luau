--!strict
-- Ruta infinita con semilla: integra las piezas en pasos fijos y las agrupa en tramos que se generan adelante y se
-- liberan atrás. Cada tramo depende solo de la semilla, aunque se hayan liberado los anteriores.

local RoadFrame = require("./RoadFrame")
local RoadPieceProfile = require("./RoadPieceProfile")
local RoadPieceSequencer = require("./RoadPieceSequencer")
local SeededRandom = require("./SeededRandom")
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

-- Las muestras incluyen la última del tramo anterior como primera, así los tramos se tocan.
export type Segment = {
	index: number,
	samples: { RoadSample },
}

export type RoadPath = {
	generateNextSegment: () -> Segment,
	releaseSegmentsBefore: (index: number) -> (),
	getSegment: (index: number) -> Segment?,
	getLoadedRange: () -> (number, number),
}

type PathState = {
	x: number,
	y: number,
	z: number,
	heading: number,
	slope: number,
	sampleIndex: number,
	piece: RoadPieceProfile.RoadPiece?,
	pieceStep: number,
	pieceStartSlope: number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local STEPS_PER_SEGMENT = RoadFrame.getStepsPerSegment()
local HALF = 0.5

local function createInitialState(): PathState
	local start = WorldConfig.START_POSITION
	return {
		x = start.x,
		y = start.y,
		z = start.z,
		heading = RoadFrame.getMeanHeadingRadians(),
		slope = 0,
		sampleIndex = 0,
		piece = nil,
		pieceStep = 0,
		pieceStartSlope = 0,
	}
end

local function createSample(state: PathState, curvature: number): RoadSample
	return {
		position = vector.create(state.x, state.y, state.z),
		heading = state.heading,
		curvature = curvature,
		slope = state.slope,
		arcLength = state.sampleIndex * STEP_STUDS,
	}
end

local function chooseNextPiece(state: PathState, random: SeededRandom.SeededRandom): RoadPieceProfile.RoadPiece
	local position = vector.create(state.x, state.y, state.z)
	return RoadPieceSequencer.chooseNextPiece(random, {
		headingDeviationRadians = RoadFrame.getHeadingDeviationRadians(state.heading),
		lateralOffsetStuds = RoadFrame.getLateralOffsetStuds(position),
	})
end

-- La pieza en curso, o una nueva si la anterior terminó (o todavía no hubo ninguna).
local function getCurrentPiece(state: PathState, random: SeededRandom.SeededRandom): RoadPieceProfile.RoadPiece
	local piece = state.piece
	if piece ~= nil and state.pieceStep < RoadPieceProfile.getTotalSteps(piece) then
		return piece
	end
	local nextPiece = chooseNextPiece(state, random)
	state.piece = nextPiece
	state.pieceStep = 0
	state.pieceStartSlope = state.slope
	return nextPiece
end

-- Avanza un paso. La curvatura y la pendiente varían linealmente entre pasos, así que el promedio de los extremos
-- integra el rumbo y la altura sin error, y el rumbo medio da la dirección del paso.
local function advanceOneStep(
	state: PathState,
	random: SeededRandom.SeededRandom,
	previousCurvature: number
): RoadSample
	local piece = getCurrentPiece(state, random)
	local nextStep = state.pieceStep + 1
	local progress = nextStep / RoadPieceProfile.getTotalSteps(piece)
	local nextCurvature = RoadPieceProfile.getCurvatureAtStep(piece, nextStep)
	local nextSlope = state.pieceStartSlope + (piece.endSlopeRadians - state.pieceStartSlope) * progress
	local nextHeading = state.heading + HALF * (previousCurvature + nextCurvature) * STEP_STUDS
	local stepHeading = HALF * (state.heading + nextHeading)
	state.x += STEP_STUDS * math.cos(stepHeading)
	state.z += STEP_STUDS * math.sin(stepHeading)
	state.y += STEP_STUDS * math.tan(HALF * (state.slope + nextSlope))
	state.heading = nextHeading
	state.slope = nextSlope
	state.pieceStep = nextStep
	state.sampleIndex += 1
	return createSample(state, nextCurvature)
end

local function assertIsInteger(value: number)
	if math.floor(value) ~= value then
		error("the segment index has to be an integer", 3)
	end
end

local RoadPathModule = {}

function RoadPathModule.new(seed: number): RoadPath
	local random = SeededRandom.new(seed)
	local state = createInitialState()
	local lastSample = createSample(state, 0)
	local segments: { [number]: Segment } = {}
	local firstIndex = 0
	local lastIndex = -1

	local function generateNextSegment(): Segment
		local samples = table.create(STEPS_PER_SEGMENT + 1, lastSample)
		for step = 1, STEPS_PER_SEGMENT do
			lastSample = advanceOneStep(state, random, lastSample.curvature)
			samples[step + 1] = lastSample
		end
		lastIndex += 1
		local segment = { index = lastIndex, samples = samples }
		segments[lastIndex] = segment
		return segment
	end

	local function releaseSegmentsBefore(index: number)
		assertIsInteger(index)
		local releaseUpTo = math.min(index, lastIndex + 1)
		for released = firstIndex, releaseUpTo - 1 do
			segments[released] = nil
		end
		firstIndex = math.max(firstIndex, releaseUpTo)
	end

	local function getSegment(index: number): Segment?
		return segments[index]
	end

	-- Si no hay tramos cargados, el último índice es menor que el primero.
	local function getLoadedRange(): (number, number)
		return firstIndex, lastIndex
	end

	return {
		generateNextSegment = generateNextSegment,
		releaseSegmentsBefore = releaseSegmentsBefore,
		getSegment = getSegment,
		getLoadedRange = getLoadedRange,
	}
end

return RoadPathModule
