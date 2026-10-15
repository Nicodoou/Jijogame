--!strict
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")

local SAMPLE_COUNT = 5000
local BUCKET_COUNT = 10
local BUCKET_TOLERANCE_FRACTION = 0.2
local UINT32_RANGE = 4294967296

local function collectNumbers(seed: number, count: number): { number }
	local random = SeededRandom.new(seed)
	local numbers = {}
	for index = 1, count do
		numbers[index] = random.nextNumber()
	end
	return numbers
end

Runner.test("nextNumber stays inside [0, 1) for many seeds", function()
	for seed = -50, 50 do
		for _, value in collectNumbers(seed, 200) do
			Runner.expectEqual(value >= 0 and value < 1, true)
		end
	end
end)

Runner.test("the same seed gives the same sequence", function()
	local first = collectNumbers(12345, 100)
	local second = collectNumbers(12345, 100)
	for index = 1, 100 do
		Runner.expectEqual(first[index], second[index])
	end
end)

Runner.test("different seeds give different sequences", function()
	local first = collectNumbers(1, 20)
	local second = collectNumbers(2, 20)
	local differences = 0
	for index = 1, 20 do
		if first[index] ~= second[index] then
			differences += 1
		end
	end
	Runner.expectEqual(differences, 20)
end)

Runner.test("numbers spread evenly over ten buckets", function()
	local counts = table.create(BUCKET_COUNT, 0)
	for _, value in collectNumbers(7, SAMPLE_COUNT) do
		local bucket = math.floor(value * BUCKET_COUNT) + 1
		counts[bucket] += 1
	end
	local expected = SAMPLE_COUNT / BUCKET_COUNT
	for _, count in counts do
		Runner.expectNear(count, expected, expected * BUCKET_TOLERANCE_FRACTION)
	end
end)

Runner.test("seed zero, negative, huge and fractional all work and differ", function()
	local seeds = { 0, -1, -0.5, 0.5, 1e15, -1e15, 1e300, 2 ^ 32, 2 ^ 32 + 1, 0.1, 0.2 }
	local firstValues = {}
	for _, seed in seeds do
		local value = SeededRandom.new(seed).nextNumber()
		Runner.expectEqual(value >= 0 and value < 1, true)
		Runner.expectEqual(firstValues[value], nil)
		firstValues[value] = true
	end
end)

Runner.test("a seed that is not finite is rejected", function()
	Runner.expectError(function()
		SeededRandom.new(0 / 0)
	end)
	Runner.expectError(function()
		SeededRandom.new(math.huge)
	end)
	Runner.expectError(function()
		SeededRandom.new(-math.huge)
	end)
end)

Runner.test("nextInteger covers both bounds and never leaves them", function()
	local random = SeededRandom.new(99)
	local seen = {}
	for _ = 1, 500 do
		local value = random.nextInteger(-2, 2)
		Runner.expectEqual(value == math.floor(value), true)
		Runner.expectEqual(value >= -2 and value <= 2, true)
		seen[value] = true
	end
	for value = -2, 2 do
		Runner.expectEqual(seen[value], true)
	end
end)

Runner.test("nextInteger with equal bounds returns that value", function()
	local random = SeededRandom.new(3)
	Runner.expectEqual(random.nextInteger(7, 7), 7)
	Runner.expectEqual(random.nextInteger(0, 0), 0)
end)

Runner.test("nextInteger works over the largest allowed range", function()
	local random = SeededRandom.new(4)
	for _ = 1, 100 do
		local value = random.nextInteger(0, UINT32_RANGE - 1)
		Runner.expectEqual(value >= 0 and value < UINT32_RANGE, true)
	end
end)

Runner.test("nextInteger rejects bad bounds", function()
	local random = SeededRandom.new(5)
	Runner.expectError(function()
		random.nextInteger(3, 2)
	end)
	Runner.expectError(function()
		random.nextInteger(0.5, 2)
	end)
	Runner.expectError(function()
		random.nextInteger(0, 2.5)
	end)
	Runner.expectError(function()
		random.nextInteger(0, UINT32_RANGE)
	end)
	Runner.expectError(function()
		random.nextInteger(0, math.huge)
	end)
	Runner.expectError(function()
		random.nextInteger(0 / 0, 1)
	end)
end)

Runner.test("a clone continues the same sequence as the original", function()
	local original = SeededRandom.new(21)
	for _ = 1, 10 do
		original.nextNumber()
	end
	local copy = original.clone()
	for _ = 1, 10 do
		Runner.expectEqual(copy.nextNumber(), original.nextNumber())
	end
end)

Runner.test("the sequence for seed 12345 never changes", function()
	local random = SeededRandom.new(12345)
	Runner.expectNear(random.nextNumber(), 0.3020892592612654, 1e-15)
	Runner.expectNear(random.nextNumber(), 0.085461309179663658, 1e-15)
	Runner.expectNear(random.nextNumber(), 0.55442637554369867, 1e-15)
	Runner.expectEqual(random.nextInteger(1, 100), 13)
end)

Runner.test("advancing a clone does not move the original", function()
	local original = SeededRandom.new(8)
	local copy = original.clone()
	for _ = 1, 50 do
		copy.nextNumber()
	end
	local reference = SeededRandom.new(8)
	Runner.expectEqual(original.nextNumber(), reference.nextNumber())
end)

Runner.finish()
