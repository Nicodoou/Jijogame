--!strict
local Runner = require("../Runner")
local Suspension = require("../../src/vehicle/core/Suspension")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type WheelState = VehicleTypes.WheelState
type WheelContact = VehicleTypes.WheelContact

local MASS = 1000
local GRAVITY = 196.2
local WHEEL_COUNT = 4
local FRAME_SECONDS = 1 / 30
local REACH = VehicleConfig.SUSPENSION_REST_LENGTH_STUDS + VehicleConfig.WHEEL_RADIUS_STUDS
local MAX_COMPRESSION = VehicleConfig.SUSPENSION_MAX_COMPRESSION_STUDS
local STATIC_LOAD = MASS * GRAVITY / WHEEL_COUNT
local SPRING_RATE = MASS / WHEEL_COUNT * (2 * math.pi * VehicleConfig.SUSPENSION_FREQUENCY_HZ) ^ 2

local function wheelWith(compression: number, compressionSpeed: number?): WheelState
	return {
		compressionStuds = compression,
		compressionSpeed = compressionSpeed or 0,
		gripMultiplier = 1,
		rollingResistance = 0.015,
		isGrounded = compression > 0,
	}
end

local function hitAt(distance: number): WheelContact
	return { hasHit = true, distanceStuds = distance, point = vector.create(0, 0, 0), surface = "Road" }
end

local function stepOnce(wheel: WheelState, contact: WheelContact?, speed: number): (WheelState, number)
	return Suspension.step(wheel, contact, speed, MASS, GRAVITY, FRAME_SECONDS)
end

Runner.test("the static load is a quarter of the weight", function()
	Runner.expectNear(Suspension.staticLoad(MASS, GRAVITY, WHEEL_COUNT), STATIC_LOAD, 1e-9)
	Runner.expectEqual(Suspension.staticLoad(0, GRAVITY, WHEEL_COUNT), 0)
end)

Runner.test("the spring rate gives the configured natural frequency", function()
	Runner.expectNear(Suspension.springRate(MASS, WHEEL_COUNT), SPRING_RATE, 1e-6)
	local frequency = math.sqrt(Suspension.springRate(MASS, WHEEL_COUNT) / (MASS / WHEEL_COUNT)) / (2 * math.pi)
	Runner.expectNear(frequency, VehicleConfig.SUSPENSION_FREQUENCY_HZ, 1e-9)
end)

Runner.test("the damper rate gives the configured damping ratio", function()
	local damper = Suspension.damperRate(MASS, WHEEL_COUNT)
	local critical = 2 * math.sqrt(SPRING_RATE * MASS / WHEEL_COUNT)
	Runner.expectNear(damper / critical, VehicleConfig.SUSPENSION_DAMPING_RATIO, 1e-9)
end)

Runner.test("the spring and damper rates scale with the mass", function()
	Runner.expectNear(Suspension.springRate(2 * MASS, WHEEL_COUNT), 2 * SPRING_RATE, 1e-6)
	Runner.expectEqual(Suspension.springRate(0, WHEEL_COUNT), 0)
	Runner.expectEqual(Suspension.damperRate(0, WHEEL_COUNT), 0)
end)

Runner.test("the compression is rest length plus radius minus the distance", function()
	local wheel, force = stepOnce(wheelWith(0), hitAt(REACH - 0.8), 0)
	Runner.expectNear(wheel.compressionStuds, 0.8, 1e-9)
	Runner.expectEqual(wheel.isGrounded, true)
	Runner.expectNear(force, SPRING_RATE * 0.8, 1e-6)
end)

Runner.test("a hit exactly at the reach has zero compression and zero force", function()
	local wheel, force = stepOnce(wheelWith(0), hitAt(REACH), 0)
	Runner.expectEqual(wheel.compressionStuds, 0)
	Runner.expectEqual(wheel.isGrounded, true)
	Runner.expectEqual(force, 0)
end)

Runner.test("the compression never goes above the maximum travel", function()
	local wheel = stepOnce(wheelWith(0), hitAt(REACH - MAX_COMPRESSION - 0.5), 0)
	Runner.expectEqual(wheel.compressionStuds, MAX_COMPRESSION)
	local exactly = stepOnce(wheelWith(0), hitAt(REACH - MAX_COMPRESSION), 0)
	Runner.expectEqual(exactly.compressionStuds, MAX_COMPRESSION)
end)

Runner.test("a negative or NaN distance counts as the maximum compression", function()
	for _, distance in { -0.001, -3, -1e9, 0 / 0 } do
		local wheel, force = stepOnce(wheelWith(0), hitAt(distance), 0)
		Runner.expectEqual(wheel.compressionStuds, MAX_COMPRESSION)
		Runner.expectEqual(wheel.isGrounded, true)
		Runner.expectEqual(force > 0, true)
	end
end)

Runner.test("a distance of exactly zero is a real hit with the maximum compression", function()
	local wheel = stepOnce(wheelWith(0), hitAt(0), 0)
	Runner.expectEqual(wheel.compressionStuds, MAX_COMPRESSION)
end)

Runner.test("the compression speed is filtered and damps the force", function()
	local wheel, force = stepOnce(wheelWith(0.8), hitAt(REACH - 0.8), 10)
	local alpha = 1 - math.exp(-VehicleConfig.COMPRESSION_SPEED_FILTER_RATE * FRAME_SECONDS)
	Runner.expectNear(wheel.compressionSpeed, 10 * alpha, 1e-9)
	local expected = SPRING_RATE * 0.8 + Suspension.damperRate(MASS, WHEEL_COUNT) * 10 * alpha
	Runner.expectNear(force, expected, 1e-6)
end)

Runner.test("the filtered speed approaches the raw speed over several steps", function()
	local wheel = wheelWith(0.8)
	for _ = 1, 30 do
		wheel = stepOnce(wheel, hitAt(REACH - 0.8), -3)
	end
	Runner.expectNear(wheel.compressionSpeed, -3, 1e-6)
end)

Runner.test("the force is never negative", function()
	local _, force = stepOnce(wheelWith(0.1, -50), hitAt(REACH - 0.1), -1e6)
	Runner.expectEqual(force, 0)
end)

Runner.test("the force is capped by the multiple of the static load", function()
	local cap = VehicleConfig.SUSPENSION_MAX_FORCE_PER_STATIC_LOAD * STATIC_LOAD
	local _, force = stepOnce(wheelWith(1), hitAt(REACH - 1), 1e9)
	Runner.expectEqual(force, cap)
	local _, withHuge = stepOnce(wheelWith(1), hitAt(REACH - 1), math.huge)
	Runner.expectEqual(withHuge <= cap and withHuge >= 0, true)
end)

Runner.test("a NaN raw speed is ignored", function()
	local wheel, force = stepOnce(wheelWith(0.8), hitAt(REACH - 0.8), 0 / 0)
	Runner.expectEqual(wheel.compressionSpeed, 0)
	Runner.expectNear(force, SPRING_RATE * 0.8, 1e-6)
end)

Runner.test("a wheel without contact that was not compressed enough is in the air", function()
	local previous = wheelWith(MAX_COMPRESSION * VehicleConfig.BOTTOM_OUT_FRACTION - 0.01, 3)
	local wheel, force = stepOnce(previous, nil, 5)
	Runner.expectEqual(wheel.isGrounded, false)
	Runner.expectEqual(wheel.compressionStuds, 0)
	Runner.expectEqual(wheel.compressionSpeed, 0)
	Runner.expectEqual(force, 0)
end)

Runner.test("a wheel without contact that was bottomed out stays on the ground", function()
	local previous = wheelWith(MAX_COMPRESSION * VehicleConfig.BOTTOM_OUT_FRACTION)
	local noHit: WheelContact = { hasHit = false, distanceStuds = 0, point = vector.create(0, 0, 0), surface = nil }
	local wheelWithoutContact, forceWithoutContact = stepOnce(previous, nil, 0)
	local wheelWithMiss, forceWithMiss = stepOnce(previous, noHit, 0)
	for _, wheel in { wheelWithoutContact, wheelWithMiss } do
		Runner.expectEqual(wheel.isGrounded, true)
		Runner.expectEqual(wheel.compressionStuds, MAX_COMPRESSION)
	end
	Runner.expectNear(forceWithoutContact, SPRING_RATE * MAX_COMPRESSION, 1e-6)
	Runner.expectNear(forceWithMiss, SPRING_RATE * MAX_COMPRESSION, 1e-6)
end)

Runner.test("an airborne wheel keeps its grip values", function()
	local previous = wheelWith(0)
	previous.gripMultiplier = 0.7
	previous.rollingResistance = 0.06
	local wheel = stepOnce(previous, nil, 0)
	Runner.expectEqual(wheel.gripMultiplier, 0.7)
	Runner.expectEqual(wheel.rollingResistance, 0.06)
end)

Runner.test("a mass of zero gives no force and no NaN", function()
	local wheel, force = Suspension.step(wheelWith(0.8), hitAt(REACH - 0.8), 5, 0, GRAVITY, FRAME_SECONDS)
	Runner.expectEqual(force, 0)
	Runner.expectNear(wheel.compressionStuds, 0.8, 1e-9)
end)

Runner.test("step returns a new wheel and does not touch the one it received", function()
	local previous = wheelWith(0.5, 1)
	table.freeze(previous)
	local contact = hitAt(REACH - 1)
	table.freeze(contact)
	local wheel = stepOnce(previous, contact, 2)
	Runner.expectEqual(wheel ~= previous, true)
	Runner.expectEqual(previous.compressionStuds, 0.5)
end)

Runner.test("a custom configuration changes the spring", function()
	local stiff = table.clone(VehicleConfig)
	stiff.SUSPENSION_FREQUENCY_HZ = 4
	local stiffRate = SPRING_RATE * (4 / 2.5) ^ 2
	Runner.expectNear(Suspension.springRate(MASS, WHEEL_COUNT, stiff), stiffRate, 1e-6)
	local _, force = Suspension.step(wheelWith(0.8), hitAt(REACH - 0.8), 0, MASS, GRAVITY, FRAME_SECONDS, stiff)
	Runner.expectNear(force, stiffRate * 0.8, 1e-6)
end)

Runner.finish()
