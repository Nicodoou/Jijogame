--!strict
local HillProfile = require("../../src/world/core/HillProfile")
local LiveRoadIndex = require("../../src/world/core/LiveRoadIndex")
local RoadFrame = require("../../src/world/core/RoadFrame")
local RoadGuide = require("../../src/world/core/RoadGuide")
local RoadIntegrator = require("../../src/world/core/RoadIntegrator")
local RoadPieceBuilder = require("../../src/world/core/RoadPieceBuilder")
local RoadPieceCatalog = require("../../src/world/core/RoadPieceCatalog")
local RoadPiecePreview = require("../../src/world/core/RoadPiecePreview")
local RoadPieceProfile = require("../../src/world/core/RoadPieceProfile")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

type RoadPiece = RoadPieceProfile.RoadPiece

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local GUIDE_SEED = 21
-- Con esta altura de partida, un perfil sin cerros queda plano.
local START_HEIGHT = WorldConfig.HILL_BASE_HEIGHT_STUDS
-- Mucho más que lo que el terreno salva entre dos pasadas a esa distancia.
local TALL_WALL_STUDS = 150
-- Un arcLength de partida lejano, para que lo ya recorrido pueda quedar como "no vecino" de lo que se previsualiza.
local FAR_START_STEPS = 1000
local OLD_ARC_STUDS = 0
-- El objetivo de la guía falsa: tan lejos hacia +x que el rumbo 0 apunta derecho a él.
local FAR_AHEAD_STUDS = 1e7

type World = {
	guide: RoadGuide.RoadGuide,
	index: LiveRoadIndex.LiveRoadIndex,
	hill: HillProfile.HillProfile,
	preview: RoadPiecePreview.RoadPiecePreview,
}

local function createFlatHill(): HillProfile.HillProfile
	local settings = table.clone(HillProfile.defaultSettings)
	settings.amplitudeStuds = 0
	return HillProfile.new(1, settings)
end

local function createWorld(): World
	local guide = RoadGuide.new(SeededRandom.new(GUIDE_SEED))
	guide.ensureCovers(WorldConfig.GUIDE_STEP_STUDS)
	local index = LiveRoadIndex.new()
	local hill = createFlatHill()
	return { guide = guide, index = index, hill = hill, preview = RoadPiecePreview.new(guide, index, hill) }
end

-- Parado sobre la guía, mirando a lo largo de ella más `offsetDegrees`.
local function createState(world: World, offsetDegrees: number): RoadIntegrator.IntegratorState
	local x, z = world.guide.getPointAt(0)
	local heading = world.guide.getSegmentHeading(1) + math.rad(offsetDegrees)
	return RoadIntegrator.createState(vector.create(x, START_HEIGHT, z), heading)
end

local function snapshot(state: RoadIntegrator.IntegratorState): string
	return `{state.x},{state.y},{state.z},{state.heading},{state.curvature},{state.slope},{state.sampleIndex}`
end

local function getDrawnPiece(kind: RoadPieceCatalog.PieceKind): RoadPiece
	local definition = RoadPieceCatalog.definitions[1]
	for _, candidate in RoadPieceCatalog.definitions do
		if candidate.kind == kind then
			definition = candidate
		end
	end
	return RoadPieceBuilder.draw(SeededRandom.new(5), definition)
end

local function expectRejected(world: World, state: RoadIntegrator.IntegratorState, piece: RoadPiece, reason: string)
	local result, why = world.preview.preview(state, piece, 1)
	Runner.expectEqual(result, nil)
	Runner.expectEqual(why, reason)
end

Runner.test("a straight piece along the guide is accepted with one sample per step", function()
	local world = createWorld()
	local piece = RoadPieceBuilder.createStraight(100)
	local result, why = world.preview.preview(createState(world, 0), piece, 1)
	local accepted = result :: RoadPiecePreview.PreviewResult
	Runner.expectEqual(why, nil)
	Runner.expectEqual(#accepted.samples, piece.totalSteps)
	Runner.expectEqual(accepted.samples[1].arcLength, STEP_STUDS)
	Runner.expectEqual(accepted.samples[piece.totalSteps].arcLength, piece.totalSteps * STEP_STUDS)
	Runner.expectEqual(accepted.endState.sampleIndex, piece.totalSteps)
	Runner.expectEqual(accepted.pieceKind, "straight")
end)

Runner.test("the preview does not change the state it starts from", function()
	local world = createWorld()
	local state = createState(world, 0)
	local before = snapshot(state)
	world.preview.preview(state, RoadPieceBuilder.createTightTurn(1, 40), 1)
	Runner.expectEqual(snapshot(state), before)
end)

Runner.test("the previewed samples are exactly what RoadIntegrator gives for the same curvatures", function()
	local world = createWorld()
	for _, kind in { "gentleCurve", "sCurve", "sharpCurve" } do
		local piece = getDrawnPiece(kind :: RoadPieceCatalog.PieceKind)
		local result = world.preview.preview(createState(world, 0), piece, 1)
		local accepted = result :: RoadPiecePreview.PreviewResult
		local replay = createState(world, 0)
		for step = 1, piece.totalSteps do
			RoadIntegrator.step(replay, RoadPieceProfile.getCurvatureAtStep(piece, step), world.hill)
			local expected = RoadIntegrator.toSample(replay)
			local sample = accepted.samples[step]
			Runner.expectEqual(sample.position, expected.position)
			Runner.expectEqual(sample.heading, expected.heading)
			Runner.expectEqual(sample.curvature, expected.curvature)
			Runner.expectEqual(sample.slope, expected.slope)
			Runner.expectEqual(sample.arcLength, expected.arcLength)
		end
		Runner.expectEqual(snapshot(accepted.endState), snapshot(replay))
	end
end)

-- Una guía que acepta cualquier lugar: deja solo al área como límite.
local function createBoundlessGuide(): RoadGuide.RoadGuide
	local guide = createWorld().guide
	return {
		ensureCovers = guide.ensureCovers,
		project = function()
			return 0, 0, 1
		end,
		getPointAt = function()
			return FAR_AHEAD_STUDS, 0
		end,
		getSegmentHeading = function()
			return 0
		end,
		getStatistics = guide.getStatistics,
	}
end

Runner.test("a piece that leaves the area is rejected for the area, whatever the guide says", function()
	local preview = RoadPiecePreview.new(createBoundlessGuide(), LiveRoadIndex.new(), createFlatHill())
	local radius = WorldConfig.AREA_RADIUS_STUDS
	local insideEnd = RoadIntegrator.createState(vector.create(radius - 100, START_HEIGHT, 0), 0)
	Runner.expectEqual(preview.preview(insideEnd, RoadPieceBuilder.createStraight(40), 1) ~= nil, true)
	local outsideEnd = RoadIntegrator.createState(vector.create(radius - 100, START_HEIGHT, 0), 0)
	local result, reason = preview.preview(outsideEnd, RoadPieceBuilder.createStraight(60), 1)
	Runner.expectEqual(result, nil)
	Runner.expectEqual(reason, "area")
	local negative = RoadIntegrator.createState(vector.create(0, START_HEIGHT, -radius + 10), -math.pi / 2)
	local _, negativeReason = preview.preview(negative, RoadPieceBuilder.createStraight(20), 1)
	Runner.expectEqual(negativeReason, "area")
end)

Runner.test("a piece that drifts out of the tunnel around the guide is rejected for the deviation", function()
	local world = createWorld()
	local longStraight = RoadPieceBuilder.createStraight(300)
	expectRejected(world, createState(world, 45), longStraight, "deviation")
	expectRejected(world, createState(world, -45), longStraight, "deviation")
	local shortStraight = RoadPieceBuilder.createStraight(100)
	Runner.expectEqual(world.preview.preview(createState(world, 45), shortStraight, 1) ~= nil, true)
end)

Runner.test("a piece that comes too close to a non neighbor part of the road is rejected for crowding", function()
	local world = createWorld()
	local state = createState(world, 0)
	state.sampleIndex = FAR_START_STEPS
	local aheadX = state.x + 100 * math.cos(state.heading)
	local aheadZ = state.z + 100 * math.sin(state.heading)
	world.index.add(aheadX, START_HEIGHT, aheadZ, OLD_ARC_STUDS)
	expectRejected(world, state, RoadPieceBuilder.createStraight(100), "crowded")
	local farAway = createWorld()
	farAway.index.add(aheadX, START_HEIGHT, aheadZ + 3 * WorldConfig.LIVE_CLEARANCE_STUDS, OLD_ARC_STUDS)
	Runner.expectEqual(farAway.preview.preview(state, RoadPieceBuilder.createStraight(100), 1) ~= nil, true)
end)

Runner.test(
	"a piece that passes close to an old part of the road at a very different height is rejected for crowding",
	function()
		local state = createState(createWorld(), 0)
		state.sampleIndex = FAR_START_STEPS
		local sideX, sideZ = -math.sin(state.heading), math.cos(state.heading)
		local distance = WorldConfig.LIVE_CLEARANCE_STUDS + 10
		local piece = RoadPieceBuilder.createStraight(100)
		local function createWorldWithOldPass(height: number): World
			local world = createWorld()
			local x, z = state.x + 100 * math.cos(state.heading), state.z + 100 * math.sin(state.heading)
			world.index.add(x + distance * sideX, height, z + distance * sideZ, OLD_ARC_STUDS)
			return world
		end
		Runner.expectEqual(createWorldWithOldPass(START_HEIGHT).preview.preview(state, piece, 1) ~= nil, true)
		expectRejected(createWorldWithOldPass(START_HEIGHT + TALL_WALL_STUDS), state, piece, "crowded")
		expectRejected(createWorldWithOldPass(START_HEIGHT - TALL_WALL_STUDS), state, piece, "crowded")
	end
)

Runner.test("a piece that turns away from the guide too much is rejected for the relative heading", function()
	local world = createWorld()
	local state = createState(world, 90)
	expectRejected(world, state, RoadPieceBuilder.createTightTurn(1, 60), "heading")
	local turnBack = world.preview.preview(state, RoadPieceBuilder.createTightTurn(-1, 60), 1)
	Runner.expectEqual(turnBack ~= nil, true)
end)

Runner.test("a piece that starts beyond the limit may not get further from the guide than it already was", function()
	local world = createWorld()
	local state = createState(world, WorldConfig.MAX_RELATIVE_HEADING_DEGREES + 20)
	Runner.expectEqual(world.preview.preview(state, RoadPieceBuilder.createTightTurn(-1, 20), 1) ~= nil, true)
	expectRejected(world, state, RoadPieceBuilder.createTightTurn(1, 20), "heading")
end)

Runner.test(
	"the hairpin pair is exempt from the relative heading limit and the same shape as another piece is not",
	function()
		local world = createWorld()
		local hairpin = getDrawnPiece("hairpinPair")
		local accepted = world.preview.preview(createState(world, 0), hairpin, 1)
		Runner.expectEqual(accepted ~= nil, true)
		local disguised: RoadPiece = { kind = "sCurve", parts = hairpin.parts, totalSteps = hairpin.totalSteps }
		expectRejected(world, createState(world, 0), disguised, "heading")
	end
)

Runner.test("a piece is rejected when no tight turn back toward the guide fits after it", function()
	local world = createWorld()
	local state = createState(world, 40)
	state.sampleIndex = FAR_START_STEPS
	local piece = RoadPieceBuilder.createStraight(100)
	local free = world.preview.preview(state, piece, 1) :: RoadPiecePreview.PreviewResult
	local finalState = free.endState
	local targetX, targetZ = world.guide.getPointAt(free.guideArcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
	local headingError =
		RoadFrame.wrapAngleRadians(math.atan2(targetZ - finalState.z, targetX - finalState.x) - finalState.heading)
	Runner.expectEqual(math.abs(headingError) > math.rad(WorldConfig.ESCAPE_MIN_HEADING_ERROR_DEGREES), true)
	local blockerDistance = WorldConfig.LIVE_CLEARANCE_STUDS + 15
	world.index.add(
		finalState.x + blockerDistance * math.cos(finalState.heading),
		START_HEIGHT,
		finalState.z + blockerDistance * math.sin(finalState.heading),
		OLD_ARC_STUDS
	)
	expectRejected(world, state, piece, "escape")
end)

Runner.test("a piece that ends facing the target needs no escape", function()
	local world = createWorld()
	local state = createState(world, 0)
	state.sampleIndex = FAR_START_STEPS
	local free = world.preview.preview(state, RoadPieceBuilder.createStraight(20), 1) :: RoadPiecePreview.PreviewResult
	local finalState = free.endState
	local targetX, targetZ = world.guide.getPointAt(free.guideArcLength + WorldConfig.GUIDE_TARGET_AHEAD_STUDS)
	local headingError =
		RoadFrame.wrapAngleRadians(math.atan2(targetZ - finalState.z, targetX - finalState.x) - finalState.heading)
	Runner.expectEqual(math.abs(headingError) <= math.rad(WorldConfig.ESCAPE_MIN_HEADING_ERROR_DEGREES), true)
	world.index.add(
		finalState.x + (WorldConfig.LIVE_CLEARANCE_STUDS + 15) * math.cos(finalState.heading),
		START_HEIGHT,
		finalState.z + (WorldConfig.LIVE_CLEARANCE_STUDS + 15) * math.sin(finalState.heading),
		OLD_ARC_STUDS
	)
	Runner.expectEqual(world.preview.preview(state, RoadPieceBuilder.createStraight(20), 1) ~= nil, true)
end)

-- El estado de createState corrido `offset` studs hacia la derecha de la guía.
local function createShiftedState(world: World, offsetDegrees: number, offset: number): RoadIntegrator.IntegratorState
	local state = createState(world, 0)
	local guideHeading = state.heading
	state.x -= math.sin(guideHeading) * offset
	state.z += math.cos(guideHeading) * offset
	state.heading += math.rad(offsetDegrees)
	return state
end

Runner.test("a hairpin pair may end beyond the tunnel, up to the extra allowance", function()
	local world = createWorld()
	local result =
		world.preview.preview(createState(world, 0), getDrawnPiece("hairpinPair"), 1) :: RoadPiecePreview.PreviewResult
	local endOffset = world.guide.project(result.endState.x, result.endState.z, result.guideSegment)
	Runner.expectEqual(math.abs(endOffset) > WorldConfig.LOCAL_DEVIATION_MAX_STUDS, true)
	Runner.expectEqual(
		math.abs(endOffset) <= WorldConfig.LOCAL_DEVIATION_MAX_STUDS + WorldConfig.TURN_BACK_EXTRA_DEVIATION_STUDS,
		true
	)
end)

Runner.test("a piece that starts outside the tunnel may stay there but not get further out", function()
	local world = createWorld()
	local outside = WorldConfig.LOCAL_DEVIATION_MAX_STUDS + 30
	Runner.expectEqual(
		world.preview.preview(createShiftedState(world, 0, outside), RoadPieceBuilder.createStraight(40), 1) ~= nil,
		true
	)
	expectRejected(world, createShiftedState(world, 10, outside), RoadPieceBuilder.createStraight(40), "deviation")
end)

Runner.finish()
