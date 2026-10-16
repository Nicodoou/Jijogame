--!strict
local PatchNoise = require("../../src/world/core/PatchNoise")
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorldConfig = require("../../src/world/core/WorldConfig")

local DECILE_COUNT = 10
local SAMPLE_COUNT = 100000
local AREA_STUDS = 6000
local MIN_DECILE_SHARE = 0.08
local MAX_DECILE_SHARE = 0.12
local OFFSET_SEEDS = 25
local FAR_COORDINATE_STUDS = 2 ^ 22
local TOLERANCE = 1e-12

Runner.test("the mud offsets are the first two numbers of the stream, as SurfaceClassifier draws them", function()
	for _, seed in { 0, 1, -3, 0.75, 12345, 1e12 } do
		local random = SeededRandom.new(seed)
		local expectedX = math.floor(random.nextNumber() * WorldConfig.MUD_NOISE_OFFSET_RANGE) + 0.5
		local expectedZ = math.floor(random.nextNumber() * WorldConfig.MUD_NOISE_OFFSET_RANGE) + 0.5
		local offsets = PatchNoise.createOffsets(seed)
		Runner.expectEqual(offsets.mud.x, expectedX)
		Runner.expectEqual(offsets.mud.z, expectedZ)
	end
end)

Runner.test("the offsets are never whole numbers and depend only on the seed", function()
	for seed = 1, OFFSET_SEEDS do
		local offsets = PatchNoise.createOffsets(seed)
		local again = PatchNoise.createOffsets(seed)
		for _, name in { "mud", "biome", "material", "bridge" } do
			local offset = (offsets :: any)[name]
			Runner.expectEqual(offset.x % 1, 0.5)
			Runner.expectEqual(offset.z % 1, 0.5)
			Runner.expectEqual(offset.x, (again :: any)[name].x)
			Runner.expectEqual(offset.z, (again :: any)[name].z)
		end
	end
end)

Runner.test("the three patch fields are different from each other", function()
	local offsets = PatchNoise.createOffsets(7)
	Runner.expectEqual(offsets.biome.x ~= offsets.material.x or offsets.biome.z ~= offsets.material.z, true)
	Runner.expectEqual(offsets.material.x ~= offsets.bridge.x or offsets.material.z ~= offsets.bridge.z, true)
end)

Runner.test("the patch value is in [0, 1] and almost uniform: every tenth holds 8% to 12%", function()
	local random = SeededRandom.new(1)
	local counts = table.create(DECILE_COUNT, 0)
	for seed = 1, OFFSET_SEEDS do
		local offset = PatchNoise.createOffsets(seed + 1000).biome
		for _ = 1, SAMPLE_COUNT // OFFSET_SEEDS do
			local value = PatchNoise.sampleUnit(
				offset,
				(random.nextNumber() - 0.5) * AREA_STUDS,
				(random.nextNumber() - 0.5) * AREA_STUDS
			)
			Runner.expectEqual(value >= 0 and value <= 1, true)
			local decile = math.min(DECILE_COUNT, math.floor(value * DECILE_COUNT) + 1)
			counts[decile] += 1
		end
	end
	for decile = 1, DECILE_COUNT do
		local share = counts[decile] / SAMPLE_COUNT
		Runner.expectEqual(share >= MIN_DECILE_SHARE and share <= MAX_DECILE_SHARE, true)
	end
end)

Runner.test("the patch value changes slowly: it is almost the same one stud away", function()
	local offset = PatchNoise.createOffsets(3).material
	local random = SeededRandom.new(2)
	local biggest = 0
	for _ = 1, 2000 do
		local x, z = (random.nextNumber() - 0.5) * AREA_STUDS, (random.nextNumber() - 0.5) * AREA_STUDS
		biggest =
			math.max(biggest, math.abs(PatchNoise.sampleUnit(offset, x, z) - PatchNoise.sampleUnit(offset, x + 1, z)))
	end
	Runner.expectEqual(biggest < 0.3, true)
end)

Runner.test("the patch value repeats every 256 patches, because the input wraps with % 256", function()
	local offset = PatchNoise.createOffsets(4).bridge
	local period = 256 * WorldConfig.BIOME_MATERIAL_PATCH_STUDS
	Runner.expectNear(
		PatchNoise.sampleUnit(offset, 10.5 + period, -7.25),
		PatchNoise.sampleUnit(offset, 10.5, -7.25),
		1e-6
	)
end)

Runner.test("far away and at negative positions the values are still numbers in range", function()
	local offset = PatchNoise.createOffsets(5).biome
	for _, coordinate in { -FAR_COORDINATE_STUDS, -1, 0, FAR_COORDINATE_STUDS } do
		local value = PatchNoise.sampleUnit(offset, coordinate, -coordinate)
		Runner.expectEqual(value >= 0 and value <= 1, true)
	end
end)

Runner.test("the mud noise is the same account that SurfaceClassifier made", function()
	local offset = PatchNoise.createOffsets(9).mud
	local scale = WorldConfig.MUD_NOISE_SCALE_PER_STUD
	Runner.expectNear(
		PatchNoise.sampleMud(offset, 123.5, -456.25, scale),
		math.noise(123.5 * scale + offset.x, -456.25 * scale + offset.z),
		TOLERANCE
	)
end)

Runner.finish()
