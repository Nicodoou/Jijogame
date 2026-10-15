--!strict
local Runner = require("../../../Runner")
local Standard = require("../src/a/core/Standard")

Runner.test("uses the standard library of Luau", function()
	local point = Standard.makePoint(1, 2, 3)
	Runner.expectEqual(point.x, 1)
	Runner.expectEqual(Standard.maskLowByte(0x1234), 0x34)
	Runner.expectEqual(buffer.len(Standard.encode(7)), 4)
	Runner.expectEqual(Standard.sampleNoise(0.5, 1.25), math.noise(0.5, 1.25))
	Runner.expectEqual(Standard.countSides({ sides = 3 }), 3)
end)

Runner.finish()
