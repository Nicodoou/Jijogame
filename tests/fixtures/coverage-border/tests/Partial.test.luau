--!strict
local Runner = require("../../../Runner")
local Partial = require("../src/a/core/Partial")

Runner.test("covers every line except the false branch", function()
	Runner.expectEqual(Partial.pick(true), 1)
	Runner.expectEqual(Partial.other(), 3)
end)

Runner.finish()
