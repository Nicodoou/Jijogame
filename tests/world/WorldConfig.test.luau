--!strict
local Runner = require("../Runner")
local WorldConfig = require("../../src/world/core/WorldConfig")

local WIDTH_SIDES = 2

Runner.test("the minimum curve radius is bigger than half the road plus the shoulder", function()
	local halfRoadWithShoulder = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.MIN_CURVE_RADIUS_STUDS > halfRoadWithShoulder, true)
end)

Runner.test("a segment is a whole number of integration steps", function()
	local steps = WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS
	Runner.expectEqual(steps, math.floor(steps))
end)

Runner.test("the road is 16 studs wide and the world starts at the origin heading to +x", function()
	Runner.expectEqual(WorldConfig.ROAD_WIDTH_STUDS, 16)
	Runner.expectEqual(WorldConfig.START_POSITION.x, 0)
	Runner.expectEqual(WorldConfig.START_POSITION.z, 0)
	Runner.expectEqual(WorldConfig.START_HEADING_DEGREES, 0)
end)

Runner.test("the live clearance is bigger than the full width of the road with both shoulders", function()
	local fullWidth = WorldConfig.ROAD_WIDTH_STUDS + WIDTH_SIDES * WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.LIVE_CLEARANCE_STUDS > fullWidth, true)
end)

Runner.test("the guide clearance leaves room for the live clearance and the tunnel on both sides", function()
	local needed = WorldConfig.LIVE_CLEARANCE_STUDS + WIDTH_SIDES * WorldConfig.LOCAL_DEVIATION_MAX_STUDS
	Runner.expectEqual(WorldConfig.GUIDE_CLEARANCE_STUDS >= needed, true)
end)

Runner.test(
	"the guide step is longer than its clearance and the neighbor distance is shorter than the lookback",
	function()
		Runner.expectEqual(WorldConfig.GUIDE_STEP_STUDS > WorldConfig.GUIDE_CLEARANCE_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEIGHBOR_ARC_STUDS < WorldConfig.LIVE_LOOKBACK_STUDS, true)
	end
)

Runner.test("a full circle of the minimum radius fits inside the neighbor distance", function()
	Runner.expectEqual(WorldConfig.LIVE_NEIGHBOR_ARC_STUDS > 2 * math.pi * WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
end)

Runner.test("the area margins fit inside the area and the start is inside it", function()
	Runner.expectEqual(WorldConfig.AREA_STEERING_MARGIN_STUDS >= WorldConfig.GUIDE_EDGE_MARGIN_STUDS, true)
	Runner.expectEqual(WorldConfig.AREA_STEERING_MARGIN_STUDS < WorldConfig.AREA_RADIUS_STUDS, true)
	local start = WorldConfig.START_POSITION
	Runner.expectEqual(math.sqrt(start.x ^ 2 + start.z ^ 2) < WorldConfig.AREA_RADIUS_STUDS, true)
end)

Runner.test("the local tunnel and the target distance fit inside one guide step", function()
	Runner.expectEqual(WorldConfig.LOCAL_DEVIATION_MAX_STUDS < WorldConfig.GUIDE_STEP_STUDS, true)
	Runner.expectEqual(WorldConfig.GUIDE_TARGET_AHEAD_STUDS < WorldConfig.GUIDE_STEP_STUDS, true)
end)

Runner.test("the start height is inside the hill band and the maximum slope is a real incline", function()
	Runner.expectEqual(WorldConfig.START_POSITION.y >= WorldConfig.HILL_MIN_HEIGHT_STUDS, true)
	Runner.expectEqual(WorldConfig.START_POSITION.y <= WorldConfig.HILL_MAX_HEIGHT_STUDS, true)
	Runner.expectEqual(WorldConfig.MAX_SLOPE_DEGREES > 0 and WorldConfig.MAX_SLOPE_DEGREES < 90, true)
end)

Runner.test("the flat start fits in the straight first segment of the guide, and starts at the base height", function()
	Runner.expectEqual(WorldConfig.START_FLAT_STUDS > 0, true)
	Runner.expectEqual(WorldConfig.START_FLAT_STUDS < WorldConfig.GUIDE_STEP_STUDS, true)
	Runner.expectEqual(WorldConfig.START_HILL_FADE_STUDS > 0, true)
	Runner.expectEqual(WorldConfig.START_POSITION.y, WorldConfig.HILL_BASE_HEIGHT_STUDS)
end)

Runner.test(
	"the terrain border rises between the shoulder blend and the corridor, at a slope the terrain can have",
	function()
		local shoulderEdge = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
		local width = WorldConfig.TERRAIN_BORDER_END_STUDS - WorldConfig.TERRAIN_BORDER_START_STUDS
		Runner.expectEqual(
			WorldConfig.TERRAIN_BORDER_START_STUDS > shoulderEdge + WorldConfig.TERRAIN_BLEND_WIDTH_STUDS,
			true
		)
		Runner.expectEqual(width > 0, true)
		Runner.expectEqual(WorldConfig.TERRAIN_BORDER_END_STUDS <= WorldConfig.TERRAIN_CORRIDOR_HALF_WIDTH_STUDS, true)
		Runner.expectEqual(
			WorldConfig.TERRAIN_BORDER_END_STUDS <= shoulderEdge + WorldConfig.TERRAIN_ROAD_REACH_STUDS,
			true
		)
		-- La pendiente máxima de un smoothstep es 1,5 veces el alto sobre el ancho.
		local steepestDegrees = math.deg(math.atan(1.5 * WorldConfig.TERRAIN_BORDER_HEIGHT_STUDS / width))
		Runner.expectEqual(steepestDegrees >= 45 and steepestDegrees <= WorldConfig.TERRAIN_MAX_SLOPE_DEGREES, true)
	end
)

Runner.test("the alternative guide turns are growing angles of at most a right angle", function()
	local previous = 0
	for _, degrees in WorldConfig.GUIDE_ALTERNATIVE_TURNS_DEGREES do
		Runner.expectEqual(degrees > previous and degrees <= 90, true)
		previous = degrees
	end
end)

Runner.test("the configuration is read only", function()
	Runner.expectError(function()
		(WorldConfig :: any).ROAD_WIDTH_STUDS = 1
	end)
	Runner.expectError(function()
		(WorldConfig.LAST_RESORT_LOBE_STEPS :: any)[1] = 1
	end)
end)

Runner.test(
	"the near distance is longer than a full circle, and the near clearance covers the width of the road",
	function()
		local fullWidth = WorldConfig.ROAD_WIDTH_STUDS + WIDTH_SIDES * WorldConfig.SHOULDER_WIDTH_STUDS
		Runner.expectEqual(WorldConfig.LIVE_NEAR_ARC_STUDS > 2 * math.pi * WorldConfig.MIN_CURVE_RADIUS_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_ARC_STUDS < WorldConfig.LIVE_NEIGHBOR_ARC_STUDS, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_CLEARANCE_STUDS > fullWidth, true)
		Runner.expectEqual(WorldConfig.LIVE_NEAR_CLEARANCE_STUDS <= WorldConfig.LIVE_CLEARANCE_STUDS, true)
	end
)

Runner.test("the biome transition settings make sense: positive radius and exponent, small cutoff", function()
	Runner.expectEqual(WorldConfig.BIOME_TRANSITION_RADIUS > 0 and WorldConfig.BIOME_TRANSITION_RADIUS <= 1, true)
	Runner.expectEqual(WorldConfig.BIOME_TRANSITION_EXPONENT >= 1, true)
	Runner.expectEqual(WorldConfig.BIOME_WEIGHT_CUTOFF >= 0 and WorldConfig.BIOME_WEIGHT_CUTOFF < 1, true)
	Runner.expectEqual(WorldConfig.BIOME_BRIDGE_MAX_SHARE >= 0 and WorldConfig.BIOME_BRIDGE_MAX_SHARE <= 1, true)
end)

Runner.test("the material patches are between 12 and 24 studs", function()
	Runner.expectEqual(WorldConfig.BIOME_MATERIAL_PATCH_STUDS >= 12, true)
	Runner.expectEqual(WorldConfig.BIOME_MATERIAL_PATCH_STUDS <= 24, true)
end)

Runner.test("the climate noise z values are not whole numbers and different from each other", function()
	local zValues = {
		WorldConfig.CLIMATE_RELIEF_NOISE_Z,
		WorldConfig.CLIMATE_HUMIDITY_NOISE_Z,
		WorldConfig.CLIMATE_TEMPERATURE_NOISE_Z,
	}
	for index, noiseZ in zValues do
		Runner.expectEqual(noiseZ % 1 ~= 0, true)
		for other = index + 1, #zValues do
			Runner.expectEqual(noiseZ ~= zValues[other], true)
		end
	end
end)

Runner.test(
	"the climate octaves shrink, the grid step is finer than the shortest wavelength and the error is small",
	function()
		Runner.expectEqual(WorldConfig.CLIMATE_OCTAVES >= 1, true)
		Runner.expectEqual(
			WorldConfig.CLIMATE_OCTAVE_AMPLITUDE_FACTOR > 0 and WorldConfig.CLIMATE_OCTAVE_AMPLITUDE_FACTOR < 1,
			true
		)
		Runner.expectEqual(
			WorldConfig.CLIMATE_OCTAVE_WAVELENGTH_FACTOR > 0 and WorldConfig.CLIMATE_OCTAVE_WAVELENGTH_FACTOR < 1,
			true
		)
		local shortest = WorldConfig.CLIMATE_HUMIDITY_WAVELENGTH_STUDS
			* WorldConfig.CLIMATE_OCTAVE_WAVELENGTH_FACTOR ^ (WorldConfig.CLIMATE_OCTAVES - 1)
		Runner.expectEqual(WorldConfig.CLIMATE_GRID_STEP_STUDS < shortest, true)
		Runner.expectEqual(WorldConfig.CLIMATE_GRID_MAX_ERROR > 0 and WorldConfig.CLIMATE_GRID_MAX_ERROR < 0.1, true)
	end
)

local SHOULDER_EDGE = WorldConfig.ROAD_WIDTH_STUDS / 2 + WorldConfig.SHOULDER_WIDTH_STUDS
-- Hasta dónde llega la ruta sobre las columnas de un chunk: el alcance de las pasadas más la banquina.
local ROAD_INFLUENCE = WorldConfig.TERRAIN_ROAD_REACH_STUDS + SHOULDER_EDGE

Runner.test("a chunk is a whole number of voxels and a segment is a whole number of terrain road blocks", function()
	Runner.expectEqual(WorldConfig.CHUNK_SIZE_STUDS % WorldConfig.TERRAIN_VOXEL_STUDS, 0)
	local stepsPerSegment = WorldConfig.SEGMENT_LENGTH_STUDS / WorldConfig.INTEGRATION_STEP_STUDS
	Runner.expectEqual(stepsPerSegment % WorldConfig.TERRAIN_ROAD_BLOCK_STEPS, 0)
end)

Runner.test("a terrain road block is a short arc: under 180 degrees at the minimum curve radius", function()
	local arcStuds = WorldConfig.TERRAIN_ROAD_BLOCK_STEPS * WorldConfig.INTEGRATION_STEP_STUDS
	Runner.expectEqual(arcStuds / WorldConfig.MIN_CURVE_RADIUS_STUDS < math.pi, true)
end)

Runner.test(
	"the frontier margin covers the corridor, a chunk and the reach of the road, so a straight road never rewrites",
	function()
		local needed = WorldConfig.TERRAIN_CORRIDOR_HALF_WIDTH_STUDS + WorldConfig.CHUNK_SIZE_STUDS + ROAD_INFLUENCE
		Runner.expectEqual(WorldConfig.TERRAIN_FRONTIER_MARGIN_STUDS >= needed, true)
		Runner.expectEqual(WorldConfig.TERRAIN_FRONTIER_MARGIN_STUDS < WorldConfig.ROUTE_AHEAD_STUDS, true)
	end
)

Runner.test(
	"the terrain fades and smooths inside the reach of the road, and the kept corridor is wider than the wanted one",
	function()
		Runner.expectEqual(WorldConfig.TERRAIN_AMBIENT_FADE_START_STUDS < WorldConfig.TERRAIN_ROAD_REACH_STUDS, true)
		local smoothEnd = WorldConfig.TERRAIN_CHORD_SMOOTH_START_STUDS + WorldConfig.TERRAIN_CHORD_SMOOTH_SPAN_STUDS
		Runner.expectEqual(smoothEnd < WorldConfig.TERRAIN_ROAD_REACH_STUDS, true)
		Runner.expectEqual(WorldConfig.TERRAIN_CORRIDOR_KEEP_EXTRA_STUDS > 0, true)
		Runner.expectEqual(WorldConfig.TERRAIN_BEHIND_KEEP_EXTRA_STUDS > 0, true)
		Runner.expectEqual(WorldConfig.TERRAIN_CORRIDOR_SAMPLE_STUDS <= WorldConfig.CHUNK_SIZE_STUDS / 2, true)
	end
)

Runner.test("the world is ready in a radius that fits in one chunk and the surface offset is under a voxel", function()
	Runner.expectEqual(WorldConfig.WORLD_READY_RADIUS_STUDS <= WorldConfig.CHUNK_SIZE_STUDS, true)
	Runner.expectEqual(WorldConfig.TERRAIN_SURFACE_OFFSET_STUDS < WorldConfig.TERRAIN_VOXEL_STUDS, true)
	Runner.expectEqual(WorldConfig.SPAWN_ARC_LENGTH_STUDS > 0, true)
end)

Runner.test("the work budget decays slowly and a frame budget is a few milliseconds", function()
	Runner.expectEqual(
		WorldConfig.WORK_BUDGET_STEP_ESTIMATE_DECAY > 0 and WorldConfig.WORK_BUDGET_STEP_ESTIMATE_DECAY < 1,
		true
	)
	Runner.expectEqual(WorldConfig.WORK_BUDGET_MS_PER_FRAME > 0 and WorldConfig.WORK_BUDGET_MS_PER_FRAME < 16, true)
end)

Runner.test("the height rule reaches as far as the tallest hills can make two passes differ", function()
	local fullWidth = WorldConfig.ROAD_WIDTH_STUDS + WIDTH_SIDES * WorldConfig.SHOULDER_WIDTH_STUDS
	Runner.expectEqual(WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS > WorldConfig.LIVE_CLEARANCE_STUDS, true)
	local factor = WorldConfig.HILL_OCTAVE_AMPLITUDE_FACTOR
	local amplitudeSum = 0
	for octave = 0, WorldConfig.HILL_OCTAVES - 1 do
		amplitudeSum += WorldConfig.HILL_AMPLITUDE_STUDS * factor ^ octave
	end
	local largestRise =
		math.min(WIDTH_SIDES * amplitudeSum, WorldConfig.HILL_MAX_HEIGHT_STUDS - WorldConfig.HILL_MIN_HEIGHT_STUDS)
	local ruleSlope = math.rad(WorldConfig.TERRAIN_MAX_SLOPE_DEGREES - WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES)
	Runner.expectEqual(WorldConfig.LIVE_HEIGHT_RULE_RADIUS_STUDS >= fullWidth + largestRise / math.tan(ruleSlope), true)
end)

Runner.test("the margin of the height rule leaves a positive slope", function()
	Runner.expectEqual(WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES >= 0, true)
	Runner.expectEqual(WorldConfig.LIVE_HEIGHT_RULE_MARGIN_DEGREES < WorldConfig.TERRAIN_MAX_SLOPE_DEGREES, true)
end)

Runner.finish()
