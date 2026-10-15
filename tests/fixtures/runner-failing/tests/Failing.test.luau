--!strict
local Runner = require("../../../Runner")

Runner.test("sums two numbers", function()
	Runner.expectEqual(1 + 1, 3)
end)

Runner.finish()
