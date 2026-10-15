--!strict
local Runner = require("../../../Runner")

Runner.test("fails but nobody reports it", function()
	Runner.expectEqual(1, 2)
end)
