--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DebrisPolicy = require("../../../src/vehicle/core/damage/DebrisPolicy")

local LIFETIME = DamageConfig.DEBRIS.LIFETIME_SECONDS
local MAX_COUNT = DamageConfig.DEBRIS.MAX_COUNT

Runner.test("with no debris nothing is removed", function()
	Runner.expectEqual(#DebrisPolicy.selectToRemove({}, 100), 0)
end)

Runner.test("a piece is removed exactly when it reaches its lifetime", function()
	Runner.expectEqual(#DebrisPolicy.selectToRemove({ 0 }, LIFETIME - 0.01), 0)
	Runner.expectEqual(#DebrisPolicy.selectToRemove({ 0 }, LIFETIME), 1)
end)

Runner.test("the expired positions come from the highest to the lowest", function()
	local result = DebrisPolicy.selectToRemove({ 0, 1, 2, 100 }, LIFETIME + 5)
	Runner.expectEqual(table.concat(result, ","), "3,2,1")
end)

Runner.test("with more than the maximum the oldest ones are removed", function()
	local born = {}
	for index = 1, MAX_COUNT + 3 do
		born[index] = index * 0.01
	end
	Runner.expectEqual(table.concat(DebrisPolicy.selectToRemove(born, 1), ","), "3,2,1")
end)

Runner.test("exactly the maximum removes nothing", function()
	local born = {}
	for index = 1, MAX_COUNT do
		born[index] = 0
	end
	Runner.expectEqual(#DebrisPolicy.selectToRemove(born, 1), 0)
end)

Runner.test("the expired ones count first and only then the excess", function()
	local born = { 0 }
	for index = 1, MAX_COUNT do
		born[index + 1] = 50 + index
	end
	Runner.expectEqual(table.concat(DebrisPolicy.selectToRemove(born, 50 + LIFETIME - 1), ","), "1")
end)

Runner.finish()
