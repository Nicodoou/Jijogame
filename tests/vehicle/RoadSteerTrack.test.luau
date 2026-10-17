--!strict
local Runner = require("../Runner")
local RoadSteerLimit = require("../../src/vehicle/core/RoadSteerLimit")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

Runner.test("track accepts continuous arc lengths and drops jumps", function()
	local accepted, last, rejected = RoadSteerLimit.track(nil, 0, 100)
	Runner.expectEqual(accepted, true)
	Runner.expectEqual(last, 100)
	accepted, last, rejected = RoadSteerLimit.track(last, rejected, 100 + VehicleConfig.ROAD_STEER_MAX_ARC_JUMP)
	Runner.expectEqual(accepted, true)
	accepted, last, rejected = RoadSteerLimit.track(100, 0, 100 + VehicleConfig.ROAD_STEER_MAX_ARC_JUMP + 1)
	Runner.expectEqual(accepted, false)
	Runner.expectEqual(last, 100)
	Runner.expectEqual(rejected, 1)
end)

Runner.test("track accepts the new point after many rejections in a row", function()
	local last: number? = 100
	local rejected = 0
	local accepted = false
	for _ = 1, 40 do
		accepted, last, rejected = RoadSteerLimit.track(last, rejected, 5000)
		if accepted then
			break
		end
	end
	Runner.expectEqual(accepted, true)
	Runner.expectEqual(last, 5000)
	Runner.expectEqual(rejected, 0)
	accepted, last, rejected = RoadSteerLimit.track(100, 0, 0 / 0)
	Runner.expectEqual(accepted, false)
end)

Runner.finish()
