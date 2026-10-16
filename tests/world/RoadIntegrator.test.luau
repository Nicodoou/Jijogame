--!strict
local HillProfile = require("../../src/world/core/HillProfile")
local RoadIntegrator = require("../../src/world/core/RoadIntegrator")
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local TOLERANCE = 1e-9
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local START_HEIGHT = 50

-- Un perfil sin cerros: la pendiente es siempre cero.
local function createFlatHill(): HillProfile.HillProfile
	return {
		getTargetHeight = function()
			return START_HEIGHT
		end,
		nextSlope = function()
			return 0
		end,
	}
end

-- Un perfil que sube siempre con la misma pendiente.
local function createRampHill(slope: number): HillProfile.HillProfile
	return {
		getTargetHeight = function()
			return START_HEIGHT
		end,
		nextSlope = function()
			return slope
		end,
	}
end

local function createState(heading: number): RoadIntegrator.IntegratorState
	return RoadIntegrator.createState(vector.create(100, START_HEIGHT, -200), heading)
end

Runner.test("a new state starts at the position, with the heading given and nothing else", function()
	local state = createState(0.5)
	Runner.expectEqual(state.x, 100)
	Runner.expectEqual(state.y, START_HEIGHT)
	Runner.expectEqual(state.z, -200)
	Runner.expectEqual(state.heading, 0.5)
	Runner.expectEqual(state.curvature, 0)
	Runner.expectEqual(state.slope, 0)
	Runner.expectEqual(state.sampleIndex, 0)
end)

Runner.test("with zero curvature the road goes straight one step at a time", function()
	local state = createState(0)
	local hill = createFlatHill()
	for step = 1, 50 do
		RoadIntegrator.step(state, 0, hill)
		Runner.expectNear(state.x, 100 + step * STEP_STUDS, TOLERANCE)
		Runner.expectNear(state.z, -200, TOLERANCE)
		Runner.expectEqual(state.y, START_HEIGHT)
	end
	Runner.expectEqual(state.sampleIndex, 50)
end)

Runner.test("a road heading to +z advances along z", function()
	local state = createState(math.pi / 2)
	RoadIntegrator.step(state, 0, createFlatHill())
	Runner.expectNear(state.x, 100, TOLERANCE)
	Runner.expectNear(state.z, -200 + STEP_STUDS, TOLERANCE)
end)

Runner.test("the heading changes by the mean of the curvatures of the step times the step", function()
	local state = createState(0)
	local hill = createFlatHill()
	RoadIntegrator.step(state, 0.01, hill)
	Runner.expectNear(state.heading, 0.5 * 0.01 * STEP_STUDS, TOLERANCE)
	Runner.expectEqual(state.curvature, 0.01)
	RoadIntegrator.step(state, 0.01, hill)
	Runner.expectNear(state.heading, 1.5 * 0.01 * STEP_STUDS, TOLERANCE)
end)

Runner.test("a constant curvature closes a circle of the radius of that curvature", function()
	local radius = WorldConfig.MIN_CURVE_RADIUS_STUDS
	local state = createState(0)
	local hill = createFlatHill()
	local stepsPerCircle = math.round(2 * math.pi * radius / STEP_STUDS)
	for _ = 1, stepsPerCircle do
		RoadIntegrator.step(state, 1 / radius, hill)
	end
	-- La curvatura sube de 0 en el primer paso, así que el círculo cierra con un error chico y no exacto.
	local distanceToStart = math.sqrt((state.x - 100) ^ 2 + (state.z + 200) ^ 2)
	Runner.expectEqual(distanceToStart < radius * 0.1, true)
end)

Runner.test("the height follows the slope of the hill with the tangent of the mean slope", function()
	local slope = math.rad(10)
	local state = createState(0)
	RoadIntegrator.step(state, 0, createRampHill(slope))
	Runner.expectNear(state.y, START_HEIGHT + STEP_STUDS * math.tan(0.5 * slope), TOLERANCE)
	Runner.expectEqual(state.slope, slope)
	RoadIntegrator.step(state, 0, createRampHill(slope))
	Runner.expectNear(
		state.y,
		START_HEIGHT + STEP_STUDS * math.tan(0.5 * slope) + STEP_STUDS * math.tan(slope),
		TOLERANCE
	)
end)

Runner.test("the hill receives the current height, slope and arc length", function()
	local received = {}
	local hill: HillProfile.HillProfile = {
		getTargetHeight = function()
			return 0
		end,
		nextSlope = function(height, slope, arcLength)
			table.insert(received, { height, slope, arcLength })
			return 0.01
		end,
	}
	local state = createState(0)
	RoadIntegrator.step(state, 0, hill)
	RoadIntegrator.step(state, 0, hill)
	Runner.expectEqual(received[1][1], START_HEIGHT)
	Runner.expectEqual(received[1][2], 0)
	Runner.expectEqual(received[1][3], 0)
	Runner.expectEqual(received[2][1], state.y - STEP_STUDS * math.tan(0.01))
	Runner.expectEqual(received[2][2], 0.01)
	Runner.expectEqual(received[2][3], STEP_STUDS)
end)

Runner.test("the sample copies the state and numbers the arc length by step", function()
	local state = createState(0.2)
	RoadIntegrator.step(state, 0.004, createFlatHill())
	local sample = RoadIntegrator.toSample(state)
	Runner.expectEqual(sample.position, vector.create(state.x, state.y, state.z))
	Runner.expectEqual(sample.heading, state.heading)
	Runner.expectEqual(sample.curvature, 0.004)
	Runner.expectEqual(sample.slope, 0)
	Runner.expectEqual(sample.arcLength, STEP_STUDS)
	RoadIntegrator.step(state, 0.004, createFlatHill())
	Runner.expectEqual(sample.arcLength, STEP_STUDS)
end)

Runner.test(
	"two states with the same inputs stay identical bit by bit, and a copy does not follow the original",
	function()
		local first, second = createState(0.1), createState(0.1)
		local hill = HillProfile.new(7)
		for step = 1, 300 do
			local curvature = math.sin(step / 7) / WorldConfig.MIN_CURVE_RADIUS_STUDS
			RoadIntegrator.step(first, curvature, hill)
			RoadIntegrator.step(second, curvature, hill)
		end
		Runner.expectEqual(RoadIntegrator.toSample(first).position, RoadIntegrator.toSample(second).position)
		Runner.expectEqual(first.heading, second.heading)
		Runner.expectEqual(first.y, second.y)
		local copy = table.clone(first)
		RoadIntegrator.step(first, 0, hill)
		Runner.expectEqual(copy.sampleIndex, 300)
		Runner.expectEqual(first.sampleIndex, 301)
	end
)

Runner.finish()
