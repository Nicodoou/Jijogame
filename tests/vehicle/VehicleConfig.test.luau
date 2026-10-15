--!strict
local Runner = require("../Runner")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

local MAX_SUSPENSION_FREQUENCY_HZ = 4
local DEFAULT_GRAVITY = 196.2

Runner.test("the suspension frequency is not above the limit found in #32", function()
	Runner.expectEqual(VehicleConfig.SUSPENSION_FREQUENCY_HZ <= MAX_SUSPENSION_FREQUENCY_HZ, true)
end)

Runner.test("there are four wheels in the order FL, FR, RL, RR", function()
	Runner.expectEqual(#VehicleConfig.WHEELS, 4)
	local expected = { { true, true }, { true, false }, { false, true }, { false, false } }
	for index, flags in expected do
		Runner.expectEqual(VehicleConfig.WHEELS[index].isFront, flags[1])
		Runner.expectEqual(VehicleConfig.WHEELS[index].isLeft, flags[2])
	end
end)

Runner.test("the wheels are placed symmetrically and the front is toward -z", function()
	local wheels = VehicleConfig.WHEELS
	Runner.expectEqual(wheels[1].offset.x, -wheels[2].offset.x)
	Runner.expectEqual(wheels[3].offset.x, -wheels[4].offset.x)
	Runner.expectEqual(wheels[1].offset.z, wheels[2].offset.z)
	Runner.expectEqual(wheels[1].offset.z < wheels[3].offset.z, true)
	Runner.expectEqual(wheels[1].offset.x < 0, true)
end)

Runner.test("the torque curve is sorted by rpm and its fractions are between 0 and 1", function()
	for index, point in VehicleConfig.TORQUE_CURVE do
		Runner.expectEqual(point.fraction > 0 and point.fraction <= 1, true)
		if index > 1 then
			Runner.expectEqual(point.rpm > VehicleConfig.TORQUE_CURVE[index - 1].rpm, true)
		end
	end
end)

Runner.test("the rpm limits are in order", function()
	Runner.expectEqual(VehicleConfig.IDLE_RPM < VehicleConfig.DOWNSHIFT_RPM, true)
	Runner.expectEqual(VehicleConfig.DOWNSHIFT_RPM < VehicleConfig.UPSHIFT_RPM, true)
	Runner.expectEqual(VehicleConfig.UPSHIFT_RPM < VehicleConfig.REDLINE_RPM, true)
end)

Runner.test("the gear ratios go down from first to last", function()
	for index = 2, #VehicleConfig.GEAR_RATIOS do
		Runner.expectEqual(VehicleConfig.GEAR_RATIOS[index] < VehicleConfig.GEAR_RATIOS[index - 1], true)
	end
end)

Runner.test("the top speed in the last gear at the redline is about 150 studs per second", function()
	local lastRatio = VehicleConfig.GEAR_RATIOS[#VehicleConfig.GEAR_RATIOS]
	local wheelRevolutionsPerSecond = VehicleConfig.REDLINE_RPM / 60 / (lastRatio * VehicleConfig.FINAL_DRIVE)
	local topSpeed = wheelRevolutionsPerSecond * 2 * math.pi * VehicleConfig.WHEEL_RADIUS_STUDS
	Runner.expectNear(topSpeed, 150, 15)
end)

Runner.test("the static compression at the default gravity fits inside the suspension travel", function()
	local angularFrequency = 2 * math.pi * VehicleConfig.SUSPENSION_FREQUENCY_HZ
	local staticCompression = DEFAULT_GRAVITY / (angularFrequency * angularFrequency)
	Runner.expectEqual(staticCompression < VehicleConfig.SUSPENSION_MAX_COMPRESSION_STUDS, true)
	Runner.expectEqual(VehicleConfig.BOTTOM_OUT_FRACTION > 0 and VehicleConfig.BOTTOM_OUT_FRACTION < 1, true)
end)

Runner.test("the step limit is shorter than a frame at 15 FPS", function()
	Runner.expectEqual(VehicleConfig.MAX_STEP_SECONDS <= 1 / 15 + 1e-12, true)
end)

Runner.test("the configuration is read only", function()
	Runner.expectError(function()
		(VehicleConfig :: any).REAR_BIAS = 1
	end)
end)

Runner.finish()
