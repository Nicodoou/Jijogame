--!strict
local Runner = require("../Runner")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")
local WeightDistribution = require("../../src/vehicle/core/WeightDistribution")

type ChassisSample = VehicleTypes.ChassisSample

local TOLERANCE = 1e-6
local FRONT_Z = VehicleConfig.WHEELS[1].offset.z
local REAR_Z = VehicleConfig.WHEELS[3].offset.z
local RIGHT_X = VehicleConfig.WHEELS[2].offset.x
local LEFT_X = VehicleConfig.WHEELS[1].offset.x
-- Con ejes asimétricos (el 147), el punto medio entre los ejes no es z = 0.
local MIDDLE_Z = (FRONT_Z + REAR_Z) / 2

-- El centro de masa queda a `localOffset` del origen (x derecha, y arriba, z positivo atrás) con el chasis derecho.
local function chassisWithCenter(localOffset: vector): ChassisSample
	local frameOrigin = vector.create(10, 5, -20)
	return {
		origin = frameOrigin,
		position = frameOrigin + localOffset,
		right = vector.create(1, 0, 0),
		up = vector.create(0, 1, 0),
		forward = vector.create(0, 0, -1),
		linearVelocity = vector.create(0, 0, 0),
		angularVelocity = vector.create(0, 0, 0),
		mass = 1000,
		gravity = 196.2,
	}
end

local function total(shares: { number }): number
	return shares[1] + shares[2] + shares[3] + shares[4]
end

Runner.test("with the center of mass in the middle every wheel carries a quarter", function()
	local shares = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, MIDDLE_Z)))
	for _, share in shares do
		Runner.expectNear(share, 0.25, TOLERANCE)
	end
end)

Runner.test("the shares always add up to one", function()
	for _, x in { -2, -0.5, 0, 1, 2.4 } do
		for _, z in { -3.9, -1, 0, 0.7, 3.5 } do
			local shares = WeightDistribution.wheelShares(chassisWithCenter(vector.create(x, -0.3, z)))
			Runner.expectNear(total(shares), 1, TOLERANCE)
		end
	end
end)

Runner.test(
	"a center of mass 0.15 studs forward gives a front fraction of (rear - center) over the wheelbase",
	function()
		local shares = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, -0.15)))
		Runner.expectNear(shares[1] + shares[2], (REAR_Z + 0.15) / (REAR_Z - FRONT_Z), TOLERANCE)
		Runner.expectEqual(shares[1], shares[2])
		Runner.expectEqual(shares[1] + shares[2] > shares[3] + shares[4], true)
	end
)

Runner.test("moving the center of mass to the right loads the right side", function()
	local shares = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0.5, 0, 0)))
	Runner.expectNear(shares[2] + shares[4], (0.5 - LEFT_X) / (RIGHT_X - LEFT_X), TOLERANCE)
	Runner.expectEqual(shares[2] > shares[1], true)
end)

Runner.test("its height does not change the shares", function()
	local low = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, -1, 0)))
	local high = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 2, 0)))
	for index = 1, 4 do
		Runner.expectNear(low[index], high[index], TOLERANCE)
	end
end)

Runner.test("a center of mass outside the wheels is clamped to the fraction limits", function()
	local far = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, -100)))
	Runner.expectNear(far[1] + far[2], 0.95, TOLERANCE)
	local behind = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, 100)))
	Runner.expectNear(behind[1] + behind[2], 0.05, TOLERANCE)
	local sideways = WeightDistribution.wheelShares(chassisWithCenter(vector.create(-100, 0, 0)))
	Runner.expectNear(sideways[1] + sideways[3], 0.95, TOLERANCE)
	Runner.expectNear(total(far) + total(behind) + total(sideways), 3, TOLERANCE)
end)

Runner.test("the shares follow the orientation of the chassis", function()
	local chassis = chassisWithCenter(vector.create(0, 0, 0))
	chassis.right = vector.create(0, 0, 1)
	chassis.forward = vector.create(1, 0, 0)
	chassis.position = chassis.origin + vector.create(0.4, 0, 0)
	local shares = WeightDistribution.wheelShares(chassis)
	Runner.expectNear(shares[1] + shares[2], (REAR_Z + 0.4) / (REAR_Z - FRONT_Z), 1e-6)
end)

Runner.test("an origin that is not finite falls back to the center of mass", function()
	local nan = 0 / 0
	-- Sin origen válido el centro de masa pasa a ser el origen del marco: z = 0, que ya no es el punto medio de los ejes.
	local expected = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, 0)))
	for _, badOrigin in { vector.create(nan, 0, 0), vector.create(0, math.huge, 0), vector.create(0, 0, -math.huge) } do
		local chassis = chassisWithCenter(vector.create(0, 0, -0.5))
		chassis.origin = badOrigin
		Runner.expectEqual(WeightDistribution.frameOrigin(chassis), chassis.position)
		for index, share in WeightDistribution.wheelShares(chassis) do
			Runner.expectNear(share, expected[index], TOLERANCE)
		end
	end
end)

Runner.test("a finite origin is used as it is", function()
	local chassis = chassisWithCenter(vector.create(0, 0, 0))
	Runner.expectEqual(WeightDistribution.frameOrigin(chassis), chassis.origin)
end)

Runner.test("wheelShares does not modify the chassis", function()
	local chassis = chassisWithCenter(vector.create(0.2, 0.1, -0.3))
	table.freeze(chassis)
	Runner.expectNear(total(WeightDistribution.wheelShares(chassis)), 1, TOLERANCE)
end)

Runner.test("wheels that share the same line split the weight evenly instead of dividing by zero", function()
	local flat = table.clone(VehicleConfig)
	flat.WHEELS = table.freeze({
		{ name = "FL", offset = vector.create(-2.5, -1, 0), isFront = true, isLeft = true },
		{ name = "FR", offset = vector.create(2.5, -1, 0), isFront = true, isLeft = false },
		{ name = "RL", offset = vector.create(-2.5, -1, 0), isFront = false, isLeft = true },
		{ name = "RR", offset = vector.create(2.5, -1, 0), isFront = false, isLeft = false },
	})
	local shares = WeightDistribution.wheelShares(chassisWithCenter(vector.create(0, 0, -1)), flat)
	for _, share in shares do
		Runner.expectNear(share, 0.25, TOLERANCE)
	end
end)

Runner.finish()
