--!strict
local Runner = require("../Runner")
local Tire = require("../../src/vehicle/core/Tire")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

local LOAD = 50000
local GRIP = 1
local STIFFNESS = VehicleConfig.TIRE_CORNERING_STIFFNESS_PER_RADIAN
local PEAK_ANGLE = VehicleConfig.TIRE_FRICTION * GRIP / STIFFNESS
local PEAK_FORCE = VehicleConfig.TIRE_FRICTION * GRIP * LOAD
local REGULARIZATION = VehicleConfig.LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND

local function withSlideRatio(ratio: number): typeof(VehicleConfig)
	local settings = table.clone(VehicleConfig)
	settings.TIRE_SLIDE_FRICTION_RATIO = ratio
	return settings
end

Runner.test("the slip angle is zero when there is no lateral speed", function()
	Runner.expectEqual(Tire.slipAngle(0, 30), 0)
	Runner.expectEqual(Tire.slipAngle(0, 0), 0)
end)

Runner.test("the slip angle is the angle of the velocity at normal speed", function()
	Runner.expectNear(Tire.slipAngle(10, 30), math.atan2(10, 30), 1e-12)
	Runner.expectNear(Tire.slipAngle(-10, 30), -math.atan2(10, 30), 1e-12)
end)

Runner.test("the slip angle does not change sign with the direction of travel", function()
	Runner.expectNear(Tire.slipAngle(10, -30), Tire.slipAngle(10, 30), 1e-12)
end)

Runner.test("at low speed the slip angle uses the regularization instead of the speed", function()
	Runner.expectNear(Tire.slipAngle(1, 0), math.atan2(1, REGULARIZATION), 1e-12)
	Runner.expectNear(Tire.slipAngle(1, REGULARIZATION * 0.5), math.atan2(1, REGULARIZATION), 1e-12)
	Runner.expectNear(Tire.slipAngle(1, REGULARIZATION), math.atan2(1, REGULARIZATION), 1e-12)
end)

Runner.test("the lateral force is linear below the peak and opposes the slip", function()
	local angle = PEAK_ANGLE / 2
	Runner.expectNear(Tire.lateralForce(angle, LOAD, GRIP), -STIFFNESS * LOAD * angle, 1e-6)
	Runner.expectNear(Tire.lateralForce(-angle, LOAD, GRIP), STIFFNESS * LOAD * angle, 1e-6)
	Runner.expectEqual(Tire.lateralForce(0, LOAD, GRIP), 0)
end)

Runner.test("the lateral force reaches the friction limit at the peak angle", function()
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE, LOAD, GRIP), -PEAK_FORCE, 1e-6)
	Runner.expectNear(Tire.lateralForce(-PEAK_ANGLE, LOAD, GRIP), PEAK_FORCE, 1e-6)
end)

Runner.test("with no drop after the peak the force stays at the limit", function()
	local noDrop = withSlideRatio(1)
	for _, factor in { 1.5, 2, 5, 100 } do
		Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * factor, LOAD, GRIP, noDrop), -PEAK_FORCE, 1e-6)
	end
end)

Runner.test("with a drop the force falls linearly to the slide ratio at twice the peak angle", function()
	local settings = withSlideRatio(0.5)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE, LOAD, GRIP, settings), -PEAK_FORCE, 1e-6)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * 1.5, LOAD, GRIP, settings), -PEAK_FORCE * 0.75, 1e-6)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * 2, LOAD, GRIP, settings), -PEAK_FORCE * 0.5, 1e-6)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * 10, LOAD, GRIP, settings), -PEAK_FORCE * 0.5, 1e-6)
	Runner.expectNear(Tire.lateralForce(-PEAK_ANGLE * 10, LOAD, GRIP, settings), PEAK_FORCE * 0.5, 1e-6)
end)

Runner.test("the default configuration drops the force to 90% of the peak after twice the peak angle", function()
	Runner.expectEqual(VehicleConfig.TIRE_SLIDE_FRICTION_RATIO, 0.9)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * 2, LOAD, GRIP), -PEAK_FORCE * 0.9, 1e-6)
	Runner.expectNear(Tire.lateralForce(PEAK_ANGLE * 50, LOAD, GRIP), -PEAK_FORCE * 0.9, 1e-6)
end)

Runner.test("less grip lowers the limit and the angle of the peak", function()
	local grip = 0.5
	local noDrop = withSlideRatio(1)
	Runner.expectNear(
		Tire.lateralForce(PEAK_ANGLE, LOAD, grip, noDrop),
		-VehicleConfig.TIRE_FRICTION * grip * LOAD,
		1e-6
	)
	Runner.expectNear(
		Tire.lateralForce(PEAK_ANGLE * grip, LOAD, grip),
		-VehicleConfig.TIRE_FRICTION * grip * LOAD,
		1e-6
	)
end)

Runner.test("no load or no grip gives no lateral force", function()
	Runner.expectEqual(Tire.lateralForce(0.1, 0, GRIP), 0)
	Runner.expectEqual(Tire.lateralForce(0.1, LOAD, 0), 0)
	Runner.expectEqual(Tire.lateralForce(0, LOAD, 0), 0)
end)

Runner.test("the lateral force is odd in the slip angle", function()
	for angle = 1, 40 do
		local slip = angle * 0.01
		Runner.expectNear(Tire.lateralForce(slip, LOAD, GRIP), -Tire.lateralForce(-slip, LOAD, GRIP), 1e-9)
	end
end)

Runner.test("combine leaves the forces alone inside the friction circle", function()
	local longitudinal, lateral, slipRatio, isSliding = Tire.combine(0.3 * PEAK_FORCE, 0.4 * PEAK_FORCE, LOAD, GRIP)
	Runner.expectNear(longitudinal, 0.3 * PEAK_FORCE, 1e-9)
	Runner.expectNear(lateral, 0.4 * PEAK_FORCE, 1e-9)
	Runner.expectNear(slipRatio, 0.5, 1e-9)
	Runner.expectEqual(isSliding, false)
end)

Runner.test("combine scales both forces onto the circle when they ask for too much", function()
	local longitudinal, lateral, slipRatio, isSliding = Tire.combine(1.2 * PEAK_FORCE, 1.6 * PEAK_FORCE, LOAD, GRIP)
	Runner.expectNear(math.sqrt(longitudinal * longitudinal + lateral * lateral), PEAK_FORCE, 1e-6)
	Runner.expectNear(longitudinal / lateral, 0.75, 1e-9)
	Runner.expectNear(slipRatio, 2, 1e-9)
	Runner.expectEqual(isSliding, true)
end)

Runner.test("combine keeps the signs of both forces", function()
	local longitudinal, lateral = Tire.combine(-3 * PEAK_FORCE, 4 * PEAK_FORCE, LOAD, GRIP)
	Runner.expectEqual(longitudinal < 0, true)
	Runner.expectEqual(lateral > 0, true)
end)

Runner.test("combine at exactly the limit is not sliding", function()
	local _, _, slipRatio, isSliding = Tire.combine(PEAK_FORCE, 0, LOAD, GRIP)
	Runner.expectNear(slipRatio, 1, 1e-12)
	Runner.expectEqual(isSliding, false)
end)

Runner.test("combine with no load gives zeros and a ratio of zero", function()
	local longitudinal, lateral, slipRatio, isSliding = Tire.combine(1000, 1000, 0, GRIP)
	Runner.expectEqual(longitudinal, 0)
	Runner.expectEqual(lateral, 0)
	Runner.expectEqual(slipRatio, 0)
	Runner.expectEqual(isSliding, false)
	local _, _, noGripRatio = Tire.combine(1000, 1000, LOAD, 0)
	Runner.expectEqual(noGripRatio, 0)
end)

Runner.test("combine with no request gives zeros", function()
	local longitudinal, lateral, slipRatio, isSliding = Tire.combine(0, 0, LOAD, GRIP)
	Runner.expectEqual(longitudinal, 0)
	Runner.expectEqual(lateral, 0)
	Runner.expectEqual(slipRatio, 0)
	Runner.expectEqual(isSliding, false)
end)

Runner.test("the combined force never goes over the friction circle for many requests", function()
	for step = -10, 10 do
		for other = -10, 10 do
			local longitudinal, lateral = Tire.combine(step * 20000, other * 20000, LOAD, GRIP)
			local magnitude = math.sqrt(longitudinal * longitudinal + lateral * lateral)
			Runner.expectEqual(magnitude <= PEAK_FORCE * (1 + 1e-12), true)
		end
	end
end)

Runner.test("the linear lateral force has no limit and opposes the slip", function()
	Runner.expectNear(Tire.linearLateralForce(0.5, LOAD), -STIFFNESS * LOAD * 0.5, 1e-6)
	Runner.expectNear(Tire.linearLateralForce(-0.5, LOAD), STIFFNESS * LOAD * 0.5, 1e-6)
	Runner.expectEqual(Tire.linearLateralForce(0, LOAD), 0)
end)

Runner.test("combine measures the slip ratio with the requested lateral force before any cap", function()
	local _, lateral, slipRatio, isSliding = Tire.combine(0, 0.5 * PEAK_FORCE, LOAD, GRIP, 2 * PEAK_FORCE)
	Runner.expectNear(lateral, 0.5 * PEAK_FORCE, 1e-9)
	Runner.expectNear(slipRatio, 2, 1e-9)
	Runner.expectEqual(isSliding, true)
end)

Runner.test("a pure corner past the peak angle reports sliding even though the force dropped", function()
	local slip = PEAK_ANGLE * 3
	local capped = Tire.lateralForce(slip, LOAD, GRIP)
	local _, lateral, slipRatio, isSliding = Tire.combine(0, capped, LOAD, GRIP, Tire.linearLateralForce(slip, LOAD))
	Runner.expectNear(math.abs(lateral), PEAK_FORCE * VehicleConfig.TIRE_SLIDE_FRICTION_RATIO, 1e-6)
	Runner.expectNear(slipRatio, 3, 1e-9)
	Runner.expectEqual(isSliding, true)
end)

Runner.test("below the peak angle a corner is not sliding", function()
	local slip = PEAK_ANGLE * 0.5
	local _, _, slipRatio, isSliding =
		Tire.combine(0, Tire.lateralForce(slip, LOAD, GRIP), LOAD, GRIP, Tire.linearLateralForce(slip, LOAD))
	Runner.expectNear(slipRatio, 0.5, 1e-9)
	Runner.expectEqual(isSliding, false)
end)

Runner.finish()
