--!strict
local LiveRoadRules = require("../../src/world/core/LiveRoadRules")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local CLEARANCE = WorldConfig.LIVE_CLEARANCE_STUDS
local NEAR_CLEARANCE = WorldConfig.LIVE_NEAR_CLEARANCE_STUDS
local NEIGHBOR_ARC = WorldConfig.LIVE_NEIGHBOR_ARC_STUDS
local NEAR_ARC = WorldConfig.LIVE_NEAR_ARC_STUDS
local HEIGHT_RADIUS = WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS
local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local ROAD_AND_SHOULDERS = WorldConfig.ROAD_WIDTH_STUDS + 2 * WorldConfig.SHOULDER_WIDTH_STUDS
local MAX_SLOPE_RISE = STEP_STUDS * math.tan(math.rad(WorldConfig.MAX_SLOPE_DEGREES))
local ROUNDING_STUDS = 0.01
local SAMPLE_STEPS = 400
-- Más lejos sobre el eje que los vecinos: piden la distancia libre larga.
local FAR_ARC = NEIGHBOR_ARC + 1
local JUST_INSIDE = 0.001

Runner.test("samples closer along the axis than the neighbor distance only need the near clearance", function()
	local distance = (NEAR_CLEARANCE + CLEARANCE) / 2
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, NEAR_ARC + 1, 0) >= 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, NEIGHBOR_ARC, 0) >= 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, FAR_ARC, 0) < 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(NEAR_CLEARANCE - JUST_INSIDE, NEAR_ARC + 1, 0) < 0, true)
end)

Runner.test("a sample closer than the required distance is a violation and one exactly at it is not", function()
	Runner.expectEqual(LiveRoadRules.getSafeSteps(CLEARANCE - JUST_INSIDE, FAR_ARC, 0) < 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(CLEARANCE, FAR_ARC, 0) >= 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(0, FAR_ARC, 0) < 0, true)
end)

Runner.test("inside the radius, a rise above what the terrain climbs is a violation, at the limit it is not", function()
	local slope = math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES - WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES)
	local distance = 90
	local allowed = math.tan(slope) * (distance - ROAD_AND_SHOULDERS)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, FAR_ARC, allowed - JUST_INSIDE) >= 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, FAR_ARC, allowed + JUST_INSIDE) < 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(distance, FAR_ARC, 0) > 0, true)
end)

Runner.test("from the radius on the height does not matter, however big the rise", function()
	Runner.expectEqual(LiveRoadRules.getSafeSteps(HEIGHT_RADIUS, FAR_ARC, 1e6) >= 0, true)
	Runner.expectEqual(LiveRoadRules.getSafeSteps(HEIGHT_RADIUS - 0.01, FAR_ARC, 1e6) < 0, true)
end)

Runner.test(
	"the more room there is, the more samples can be skipped and the count never grows past what is safe",
	function()
		local near = LiveRoadRules.getSafeSteps(CLEARANCE + 2 * STEP_STUDS, FAR_ARC, 0)
		local far = LiveRoadRules.getSafeSteps(HEIGHT_RADIUS + 20 * STEP_STUDS, FAR_ARC, 0)
		Runner.expectEqual(near >= 0 and near < 3, true)
		Runner.expectEqual(far > near, true)
		Runner.expectEqual(far <= 20, true)
		-- Dentro del radio, el margen de altura también limita.
		Runner.expectEqual(
			LiveRoadRules.getSafeSteps(90, FAR_ARC, 100) < LiveRoadRules.getSafeSteps(90, FAR_ARC, 0),
			true
		)
	end
)

Runner.test("walking the road away from a sample never breaks a rule before the safe count runs out", function()
	local random = SeededRandom.new(4)
	for _ = 1, SAMPLE_STEPS do
		local distance = CLEARANCE + random.nextNumber() * HEIGHT_RADIUS
		local rise = random.nextNumber() * 60
		local steps = math.floor(LiveRoadRules.getSafeSteps(distance, FAR_ARC, rise))
		if steps > 0 then
			-- Lo peor: la ruta se acerca lo más posible y sube lo más posible.
			local worstDistance = distance - steps * (STEP_STUDS + ROUNDING_STUDS)
			local worstRise = rise + steps * (MAX_SLOPE_RISE + ROUNDING_STUDS)
			Runner.expectEqual(LiveRoadRules.getSafeSteps(worstDistance, FAR_ARC, worstRise) >= 0, true)
		end
	end
end)

Runner.test("two samples a step apart on the plane and within the maximum slope are a continuous step", function()
	Runner.expectEqual(LiveRoadRules.isContinuousStep(STEP_STUDS ^ 2, MAX_SLOPE_RISE), true)
	Runner.expectEqual(LiveRoadRules.isContinuousStep((STEP_STUDS + ROUNDING_STUDS) ^ 2, 0), true)
	Runner.expectEqual(LiveRoadRules.isContinuousStep((STEP_STUDS + 2 * ROUNDING_STUDS) ^ 2, 0), false)
	Runner.expectEqual(LiveRoadRules.isContinuousStep(STEP_STUDS ^ 2, MAX_SLOPE_RISE + 2 * ROUNDING_STUDS), false)
	Runner.expectEqual(LiveRoadRules.isContinuousStep(0, 0), true)
end)

Runner.finish()
