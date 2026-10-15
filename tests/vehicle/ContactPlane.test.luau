--!strict
local Runner = require("../Runner")
local ContactPlane = require("../../src/vehicle/core/ContactPlane")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type WheelContact = VehicleTypes.WheelContact

local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

local TOLERANCE = 1e-6
local CHASSIS_UP = vector.create(0, 1, 0)

-- Puntos de las cuatro ruedas en el orden FL, FR, RL, RR sobre el plano y = slope * z.
local function wheelPoints(slope: number): { vector }
	local function at(x: number, z: number): vector
		return vector.create(x, slope * z, z)
	end
	return { at(-2.5, -4), at(2.5, -4), at(-2.5, 4), at(2.5, 4) }
end

local function expectVectorNear(actual: vector, expected: vector, tolerance: number)
	Runner.expectNear(actual.x, expected.x, tolerance)
	Runner.expectNear(actual.y, expected.y, tolerance)
	Runner.expectNear(actual.z, expected.z, tolerance)
end

Runner.test("four points on flat ground give straight up", function()
	expectVectorNear(ContactPlane.upDirection(wheelPoints(0), CHASSIS_UP), CHASSIS_UP, TOLERANCE)
end)

Runner.test("four points on a slope give the normal of that slope", function()
	local slope = 0.2
	local expected = vector.normalize(vector.create(0, 1, -slope))
	expectVectorNear(ContactPlane.upDirection(wheelPoints(slope), CHASSIS_UP), expected, TOLERANCE)
end)

Runner.test("the result is a unit vector", function()
	for _, slope in { 0, 0.1, -0.3, 1 } do
		local up = ContactPlane.upDirection(wheelPoints(slope), CHASSIS_UP)
		Runner.expectNear(vector.magnitude(up), 1, TOLERANCE)
	end
end)

Runner.test("three points give the plane through them", function()
	local points = wheelPoints(0.2)
	local three = { points[1], points[2], points[4] }
	local expected = vector.normalize(vector.create(0, 1, -0.2))
	expectVectorNear(ContactPlane.upDirection(three, CHASSIS_UP), expected, TOLERANCE)
end)

Runner.test("three points taken in the opposite winding are still oriented like the chassis", function()
	local points = wheelPoints(0)
	local three = { points[1], points[4], points[2] }
	local up = ContactPlane.upDirection(three, CHASSIS_UP)
	Runner.expectEqual(vector.dot(up, CHASSIS_UP) > 0, true)
	local flipped = ContactPlane.upDirection(three, vector.create(0, -1, 0))
	Runner.expectEqual(vector.dot(flipped, vector.create(0, -1, 0)) > 0, true)
end)

Runner.test("two points keep the chassis up without its part along the line", function()
	local points = wheelPoints(0)
	local leftSide = { points[1], points[3] }
	local tilted = vector.normalize(vector.create(0.3, 1, 0.4))
	local up = ContactPlane.upDirection(leftSide, tilted)
	Runner.expectNear(vector.dot(up, vector.create(0, 0, 1)), 0, TOLERANCE)
	Runner.expectNear(vector.magnitude(up), 1, TOLERANCE)
	Runner.expectEqual(vector.dot(up, tilted) > 0, true)
end)

Runner.test("two points along the chassis up are degenerate and fall back to the chassis up", function()
	local vertical = { vector.create(0, 0, 0), vector.create(0, 5, 0) }
	expectVectorNear(ContactPlane.upDirection(vertical, CHASSIS_UP), CHASSIS_UP, TOLERANCE)
end)

Runner.test("two identical points fall back to the chassis up", function()
	local same = { vector.create(1, 1, 1), vector.create(1, 1, 1) }
	expectVectorNear(ContactPlane.upDirection(same, CHASSIS_UP), CHASSIS_UP, TOLERANCE)
end)

Runner.test("fewer than two points fall back to the chassis up", function()
	local tilted = vector.normalize(vector.create(0.1, 1, 0))
	expectVectorNear(ContactPlane.upDirection({}, tilted), tilted, TOLERANCE)
	expectVectorNear(ContactPlane.upDirection({ vector.create(0, 0, 0) }, tilted), tilted, TOLERANCE)
end)

Runner.test("collinear points are degenerate and fall back to the chassis up", function()
	local line = { vector.create(0, 0, 0), vector.create(1, 0, 0), vector.create(2, 0, 0) }
	expectVectorNear(ContactPlane.upDirection(line, CHASSIS_UP), CHASSIS_UP, TOLERANCE)
	local four = { vector.create(0, 0, 0), vector.create(1, 0, 0), vector.create(2, 0, 0), vector.create(3, 0, 0) }
	expectVectorNear(ContactPlane.upDirection(four, CHASSIS_UP), CHASSIS_UP, TOLERANCE)
end)

Runner.test("NaN points fall back to the chassis up", function()
	local nan = 0 / 0
	local points = { vector.create(nan, 0, 0), vector.create(1, 0, 0), vector.create(0, 0, 1) }
	expectVectorNear(ContactPlane.upDirection(points, CHASSIS_UP), CHASSIS_UP, TOLERANCE)
end)

Runner.test("an upside down chassis gets an upside down result", function()
	local down = vector.create(0, -1, 0)
	local up = ContactPlane.upDirection(wheelPoints(0), down)
	expectVectorNear(up, down, TOLERANCE)
end)

Runner.test("upDirection does not modify its arguments", function()
	local points = wheelPoints(0.1)
	table.freeze(points)
	local up = ContactPlane.upDirection(points, CHASSIS_UP)
	Runner.expectEqual(up.y > 0, true)
end)

local function hitAt(point: vector): WheelContact
	return { hasHit = true, distanceStuds = 1, point = point, surface = "Road" }
end

Runner.test("hitPoints lists the points of the wheels whose ray hit, in wheel order", function()
	local first, third = vector.create(1, 0, 0), vector.create(3, 0, 0)
	local miss: WheelContact = { hasHit = false, distanceStuds = 0, point = vector.create(9, 9, 9), surface = nil }
	local points = ContactPlane.hitPoints({ hitAt(first), miss, hitAt(third), nil }, VehicleConfig)
	Runner.expectEqual(#points, 2)
	Runner.expectEqual(points[1], first)
	Runner.expectEqual(points[2], third)
end)

Runner.test("hitPoints skips points that are not finite and gives an empty list without contacts", function()
	local broken = hitAt(vector.create(0 / 0, 0, 0))
	Runner.expectEqual(#ContactPlane.hitPoints({ broken, nil, nil, nil }, VehicleConfig), 0)
	Runner.expectEqual(#ContactPlane.hitPoints({}, VehicleConfig), 0)
end)

Runner.finish()
