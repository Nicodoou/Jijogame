--!strict
local Runner = require("../Runner")
local SurfaceGrip = require("../../src/vehicle/core/SurfaceGrip")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

local FRAME_SECONDS = 1 / 30
local SURFACES: { VehicleTypes.SurfaceKind } = { "Road", "Shoulder", "Grass", "Mud" }

Runner.test("a new wheel starts with the values of the road", function()
	local wheel = SurfaceGrip.newWheelState()
	Runner.expectEqual(wheel.gripMultiplier, VehicleConfig.SURFACE_GRIP.Road)
	Runner.expectEqual(wheel.rollingResistance, VehicleConfig.SURFACE_ROLLING_RESISTANCE.Road)
	Runner.expectEqual(wheel.compressionStuds, 0)
	Runner.expectEqual(wheel.compressionSpeed, 0)
	Runner.expectEqual(wheel.isGrounded, false)
end)

Runner.test("every surface has a grip and a rolling resistance", function()
	for _, surface: VehicleTypes.SurfaceKind in SURFACES do
		Runner.expectEqual(VehicleConfig.SURFACE_GRIP[surface] > 0, true)
		Runner.expectEqual(VehicleConfig.SURFACE_ROLLING_RESISTANCE[surface] > 0, true)
	end
end)

Runner.test("a rougher surface has less grip and more rolling resistance", function()
	local order: { VehicleTypes.SurfaceKind } = { "Road", "Shoulder", "Grass", "Mud" }
	for index = 2, #order do
		Runner.expectEqual(
			VehicleConfig.SURFACE_GRIP[order[index]] < VehicleConfig.SURFACE_GRIP[order[index - 1]],
			true
		)
		local current = VehicleConfig.SURFACE_ROLLING_RESISTANCE[order[index]]
		Runner.expectEqual(current > VehicleConfig.SURFACE_ROLLING_RESISTANCE[order[index - 1]], true)
	end
end)

Runner.test("one step moves the values toward the surface with the blend rate", function()
	local wheel = SurfaceGrip.newWheelState()
	local alpha = 1 - math.exp(-VehicleConfig.SURFACE_BLEND_RATE * FRAME_SECONDS)
	local moved = SurfaceGrip.step(wheel, "Mud", FRAME_SECONDS)
	Runner.expectNear(moved.gripMultiplier, 1 + (0.5 - 1) * alpha, 1e-12)
	Runner.expectNear(moved.rollingResistance, 0.015 + (0.12 - 0.015) * alpha, 1e-12)
	Runner.expectEqual(moved.gripMultiplier < 1 and moved.gripMultiplier > 0.5, true)
end)

Runner.test("the grip never jumps in a single step when crossing an edge", function()
	local wheel = SurfaceGrip.newWheelState()
	local after = SurfaceGrip.step(wheel, "Mud", FRAME_SECONDS)
	local jump = math.abs(after.gripMultiplier - wheel.gripMultiplier)
	Runner.expectEqual(jump < 0.5 * math.abs(VehicleConfig.SURFACE_GRIP.Mud - VehicleConfig.SURFACE_GRIP.Road), true)
end)

Runner.test("after enough steps the values reach the surface", function()
	for _, surface: VehicleTypes.SurfaceKind in SURFACES do
		local wheel = SurfaceGrip.newWheelState()
		for _ = 1, 120 do
			wheel = SurfaceGrip.step(wheel, surface, FRAME_SECONDS)
		end
		Runner.expectNear(wheel.gripMultiplier, VehicleConfig.SURFACE_GRIP[surface], 1e-9)
		Runner.expectNear(wheel.rollingResistance, VehicleConfig.SURFACE_ROLLING_RESISTANCE[surface], 1e-9)
	end
end)

Runner.test("the values always stay between the old and the new surface", function()
	local wheel = SurfaceGrip.newWheelState()
	for _ = 1, 60 do
		wheel = SurfaceGrip.step(wheel, "Mud", FRAME_SECONDS)
		Runner.expectEqual(wheel.gripMultiplier >= 0.5 and wheel.gripMultiplier <= 1, true)
	end
end)

Runner.test("a nil surface keeps the previous values", function()
	local wheel = SurfaceGrip.step(SurfaceGrip.newWheelState(), "Grass", FRAME_SECONDS)
	local kept = SurfaceGrip.step(wheel, nil, FRAME_SECONDS)
	Runner.expectEqual(kept.gripMultiplier, wheel.gripMultiplier)
	Runner.expectEqual(kept.rollingResistance, wheel.rollingResistance)
end)

Runner.test("the other wheel fields are kept", function()
	local wheel = SurfaceGrip.newWheelState()
	wheel.compressionStuds = 1.2
	wheel.compressionSpeed = -3
	wheel.isGrounded = true
	local moved = SurfaceGrip.step(wheel, "Grass", FRAME_SECONDS)
	Runner.expectEqual(moved.compressionStuds, 1.2)
	Runner.expectEqual(moved.compressionSpeed, -3)
	Runner.expectEqual(moved.isGrounded, true)
end)

Runner.test("step does not modify the wheel it receives", function()
	local wheel = SurfaceGrip.newWheelState()
	table.freeze(wheel)
	local moved = SurfaceGrip.step(wheel, "Mud", FRAME_SECONDS)
	Runner.expectEqual(moved ~= wheel, true)
	Runner.expectEqual(wheel.gripMultiplier, 1)
	local kept = SurfaceGrip.step(wheel, nil, FRAME_SECONDS)
	Runner.expectEqual(kept ~= wheel, true)
end)

Runner.finish()
