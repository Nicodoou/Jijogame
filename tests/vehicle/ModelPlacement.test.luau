--!strict
local Runner = require("../Runner")
local ModelPlacement = require("../../src/vehicle/core/ModelPlacement")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleModels = require("../../src/vehicle/core/VehicleModels")

local GRAVITY = 196.2
local TOLERANCE = 1e-4
local SHEET = VehicleModels.Fiat147

Runner.test("the static compression is zero without gravity", function()
	Runner.expectNear(ModelPlacement.staticCompression(VehicleConfig, 0), 0, TOLERANCE)
end)

Runner.test("the ground is below the wheel mounts", function()
	Runner.expectEqual(ModelPlacement.groundHeight(VehicleConfig, GRAVITY) < VehicleConfig.WHEELS[1].offset.y, true)
end)

Runner.test("the pivot turns as much as the sheet says", function()
	local _, turnRadians = ModelPlacement.pivotOffset(SHEET, VehicleConfig, GRAVITY)
	Runner.expectNear(turnRadians, math.rad(SHEET.turnDegrees), TOLERANCE)
end)

Runner.test("the model origin lands at the pivot offset", function()
	local heightStuds = ModelPlacement.pivotOffset(SHEET, VehicleConfig, GRAVITY)
	local origin = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, vector.zero)
	Runner.expectNear(origin.x, 0, TOLERANCE)
	Runner.expectNear(origin.y, heightStuds, TOLERANCE)
	Runner.expectNear(origin.z, 0, TOLERANCE)
end)

Runner.test("a point at the front of the model ends up at the rear of the car when turned 180 degrees", function()
	local point = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, vector.create(0, 0, 10))
	Runner.expectNear(point.z, -10, TOLERANCE)
end)

Runner.test("the model wheel centers land on the physical wheel mounts", function()
	for _, wheel in VehicleConfig.WHEELS do
		local center = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, SHEET.wheelCenters[wheel.name])
		Runner.expectNear(center.x, wheel.offset.x, 0.05)
		Runner.expectNear(center.z, wheel.offset.z, 0.05)
	end
end)

Runner.test("the driver head sits on the left side and above the ground of the car", function()
	local head = ModelPlacement.headInBodyFrame(SHEET, VehicleConfig, GRAVITY)
	Runner.expectEqual(head.y > ModelPlacement.groundHeight(VehicleConfig, GRAVITY), true)
	Runner.expectEqual(math.abs(head.x) < math.abs(VehicleConfig.WHEELS[1].offset.x), true)
end)

Runner.test("the head in the body frame matches the rotation and drop of the sheet", function()
	local head = ModelPlacement.headInBodyFrame(SHEET, VehicleConfig, GRAVITY)
	local heightStuds = ModelPlacement.pivotOffset(SHEET, VehicleConfig, GRAVITY)
	Runner.expectNear(head.x, -SHEET.driverHead.x, TOLERANCE)
	Runner.expectNear(head.y, SHEET.driverHead.y + heightStuds, TOLERANCE)
	Runner.expectNear(head.z, -SHEET.driverHead.z, TOLERANCE)
end)

Runner.finish()
