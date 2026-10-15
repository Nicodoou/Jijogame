--!strict
-- Geometría plana entre puntos y segmentos. Las usa la guía para medir distancias de segmento a segmento.

local SegmentGeometry = {}

-- Distancia de un punto al segmento (a, b). Un segmento de largo cero vale como un punto.
function SegmentGeometry.getPointToSegmentDistance(
	pointX: number,
	pointZ: number,
	startX: number,
	startZ: number,
	endX: number,
	endZ: number
): number
	local edgeX, edgeZ = endX - startX, endZ - startZ
	local lengthSquared = edgeX * edgeX + edgeZ * edgeZ
	local fraction = 0
	if lengthSquared > 0 then
		fraction = math.clamp(((pointX - startX) * edgeX + (pointZ - startZ) * edgeZ) / lengthSquared, 0, 1)
	end
	local offsetX, offsetZ = pointX - (startX + edgeX * fraction), pointZ - (startZ + edgeZ * fraction)
	return math.sqrt(offsetX * offsetX + offsetZ * offsetZ)
end

local function getOrientation(ax: number, az: number, bx: number, bz: number, cx: number, cz: number): number
	return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
end

-- Dos segmentos se cruzan cuando cada uno deja los extremos del otro a lados opuestos.
local function doSegmentsCross(a: vector, b: vector, c: vector, d: vector): boolean
	local abToC = getOrientation(a.x, a.z, b.x, b.z, c.x, c.z)
	local abToD = getOrientation(a.x, a.z, b.x, b.z, d.x, d.z)
	local cdToA = getOrientation(c.x, c.z, d.x, d.z, a.x, a.z)
	local cdToB = getOrientation(c.x, c.z, d.x, d.z, b.x, b.z)
	return (abToC > 0) ~= (abToD > 0) and (cdToA > 0) ~= (cdToB > 0)
end

-- Distancia mínima entre los segmentos (a, b) y (c, d): cero si se cruzan, y si no, la menor entre un extremo y el otro
-- segmento. Los puntos usan `x` y `z`; la altura no cuenta.
function SegmentGeometry.getSegmentToSegmentDistance(a: vector, b: vector, c: vector, d: vector): number
	if doSegmentsCross(a, b, c, d) then
		return 0
	end
	return math.min(
		SegmentGeometry.getPointToSegmentDistance(a.x, a.z, c.x, c.z, d.x, d.z),
		SegmentGeometry.getPointToSegmentDistance(b.x, b.z, c.x, c.z, d.x, d.z),
		SegmentGeometry.getPointToSegmentDistance(c.x, c.z, a.x, a.z, b.x, b.z),
		SegmentGeometry.getPointToSegmentDistance(d.x, d.z, a.x, a.z, b.x, b.z)
	)
end

return SegmentGeometry
