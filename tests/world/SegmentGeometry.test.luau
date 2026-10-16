--!strict
local Runner = require("../Runner")
local SegmentGeometry = require("../../src/world/core/SegmentGeometry")

local TOLERANCE = 1e-9
-- La altura no cuenta: se pone cualquiera.
local ANY_HEIGHT = 99

local function point(x: number, z: number): vector
	return vector.create(x, ANY_HEIGHT, z)
end

local function measure(a: vector, b: vector, c: vector, d: vector): number
	return SegmentGeometry.getSegmentToSegmentDistance(a, b, c, d)
end

Runner.test("a point beside a segment is at the perpendicular distance", function()
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(5, 3, 0, 0, 10, 0), 3, TOLERANCE)
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(5, -3, 0, 0, 10, 0), 3, TOLERANCE)
end)

Runner.test("a point beyond an end is at the distance to that end", function()
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(-3, 4, 0, 0, 10, 0), 5, TOLERANCE)
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(13, 4, 0, 0, 10, 0), 5, TOLERANCE)
end)

Runner.test("a point on the segment, on an end or beside a degenerate segment has the right distance", function()
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(4, 0, 0, 0, 10, 0), 0, TOLERANCE)
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(10, 0, 0, 0, 10, 0), 0, TOLERANCE)
	Runner.expectNear(SegmentGeometry.getPointToSegmentDistance(3, 4, 0, 0, 0, 0), 5, TOLERANCE)
end)

Runner.test("segments that cross have distance zero", function()
	Runner.expectEqual(measure(point(-5, 0), point(5, 0), point(0, -5), point(0, 5)), 0)
	Runner.expectEqual(measure(point(0, 0), point(10, 10), point(0, 10), point(10, 0)), 0)
end)

Runner.test("parallel segments are at their separation, and the height does not count", function()
	Runner.expectNear(measure(point(0, 0), point(10, 0), point(0, 7), point(10, 7)), 7, TOLERANCE)
	local raised = measure(
		vector.create(0, 500, 0),
		vector.create(10, 500, 0),
		vector.create(0, -500, 7),
		vector.create(10, -500, 7)
	)
	Runner.expectNear(raised, 7, TOLERANCE)
end)

Runner.test("segments that do not cross are at the distance between their closest points", function()
	Runner.expectNear(measure(point(0, 0), point(10, 0), point(13, 4), point(20, 9)), 5, TOLERANCE)
	Runner.expectNear(measure(point(0, 0), point(10, 0), point(5, 6), point(5, 20)), 6, TOLERANCE)
end)

Runner.test("segments that touch at an end or overlap have distance zero", function()
	Runner.expectEqual(measure(point(0, 0), point(10, 0), point(10, 0), point(10, 8)), 0)
	Runner.expectEqual(measure(point(0, 0), point(10, 0), point(4, 0), point(20, 0)), 0)
end)

Runner.test("the distance does not depend on the order or the direction of the segments", function()
	local a, b, c, d = point(0, 0), point(10, 3), point(14, -8), point(12, 6)
	local reference = measure(a, b, c, d)
	Runner.expectNear(measure(c, d, a, b), reference, TOLERANCE)
	Runner.expectNear(measure(b, a, d, c), reference, TOLERANCE)
end)

Runner.finish()
