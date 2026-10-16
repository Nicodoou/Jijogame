--!strict
local Runner = require("../Runner")
local VehicleMath = require("../../src/vehicle/core/VehicleMath")

Runner.test("isFinite accepts normal numbers and rejects NaN and infinities", function()
	Runner.expectEqual(VehicleMath.isFinite(0), true)
	Runner.expectEqual(VehicleMath.isFinite(-1e300), true)
	Runner.expectEqual(VehicleMath.isFinite(0 / 0), false)
	Runner.expectEqual(VehicleMath.isFinite(math.huge), false)
	Runner.expectEqual(VehicleMath.isFinite(-math.huge), false)
end)

Runner.test("finiteOr keeps finite values and replaces the rest", function()
	Runner.expectEqual(VehicleMath.finiteOr(3, 7), 3)
	Runner.expectEqual(VehicleMath.finiteOr(0 / 0, 7), 7)
	Runner.expectEqual(VehicleMath.finiteOr(math.huge, 7), 7)
end)

Runner.test("isFiniteVector checks every component", function()
	Runner.expectEqual(VehicleMath.isFiniteVector(vector.create(1, 2, 3)), true)
	Runner.expectEqual(VehicleMath.isFiniteVector(vector.create(0 / 0, 2, 3)), false)
	Runner.expectEqual(VehicleMath.isFiniteVector(vector.create(1, math.huge, 3)), false)
	Runner.expectEqual(VehicleMath.isFiniteVector(vector.create(1, 2, -math.huge)), false)
end)

Runner.test("isUsableStep needs a finite number greater than zero", function()
	Runner.expectEqual(VehicleMath.isUsableStep(1 / 30), true)
	Runner.expectEqual(VehicleMath.isUsableStep(1e-9), true)
	Runner.expectEqual(VehicleMath.isUsableStep(0), false)
	Runner.expectEqual(VehicleMath.isUsableStep(-1), false)
	Runner.expectEqual(VehicleMath.isUsableStep(0 / 0), false)
	Runner.expectEqual(VehicleMath.isUsableStep(math.huge), false)
end)

Runner.test("smoothingAlpha is between zero and one and grows with the rate and the step", function()
	Runner.expectEqual(VehicleMath.smoothingAlpha(10, 0), 0)
	Runner.expectNear(VehicleMath.smoothingAlpha(10, 0.1), 1 - math.exp(-1), 1e-12)
	Runner.expectEqual(VehicleMath.smoothingAlpha(10, 1e6) <= 1, true)
	Runner.expectEqual(VehicleMath.smoothingAlpha(20, 0.1) > VehicleMath.smoothingAlpha(10, 0.1), true)
end)

Runner.test("opposingForceLimit is the force that stops the share of the mass in one step", function()
	Runner.expectNear(VehicleMath.opposingForceLimit(1000, 0.25, 2, 0.1), 5000, 1e-9)
	Runner.expectEqual(
		VehicleMath.opposingForceLimit(1000, 0.25, -2, 0.1),
		VehicleMath.opposingForceLimit(1000, 0.25, 2, 0.1)
	)
	Runner.expectEqual(VehicleMath.opposingForceLimit(1000, 0.25, 0, 0.1), 0)
	Runner.expectEqual(VehicleMath.opposingForceLimit(0, 0.25, 50, 0.1), 0)
end)

Runner.finish()
