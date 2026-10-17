--!nocheck
-- Una línea por semilla encerrada. luau exp86/diag_all.luau -a <lista de semillas>
local a1 = ...
local Exp86 = require("../src/world/core/Exp86")
Exp86.diag = true
local RoadPath = require("../src/world/core/RoadPath")
local function f(n) return string.format("%.0f", n) end
local seedNow
Exp86.onEnclosed = function(d)
	local s = d.state
	local live, liveMax = Exp86.live, 0
	for i in live do liveMax = math.max(liveMax, i) end
	local r = d.reasons
	local total = (r._crowded or 0) + (r._deviation or 0) + (r._escape or 0) + (r._heading or 0) + (r._area or 0)
	local maxOff, sumOff, n = 0, 0, 0
	for i = #d.log, 1, -1 do
		local e = d.log[i]
		if e.ev == "commit" and (liveMax * 2 - e.si * 2) < 1000 + 4000 then
			maxOff = math.max(maxOff, math.abs(e.off)); sumOff += math.abs(e.off); n += 1
		end
	end
	-- pasadas vecinas (rangos de arco a menos de 250 studs del estado)
	local passes, cur = 0, nil
	for i = 0, liveMax do
		local p = live[i]
		if p and math.sqrt((p[1]-s.x)^2 + (p[2]-s.z)^2) < 250 and i < liveMax - 300 then
			if cur and i - cur <= 5 then cur = i else cur = i; passes += 1 end
		end
	end
	local wps = d.guide.debugWaypoints()
	-- esquina de la guía más cercana al estado
	local bestI, bestD = 1, math.huge
	for i = 1, #wps do
		local dd = math.sqrt((wps[i].x - s.x)^2 + (wps[i].z - s.z)^2)
		if dd < bestD then bestD, bestI = dd, i end
	end
	local turnDeg = 0
	if bestI > 1 and bestI < #wps then
		local a, b, c = wps[bestI-1], wps[bestI], wps[bestI+1]
		local h1, h2 = math.atan2(b.z - a.z, b.x - a.x), math.atan2(c.z - b.z, c.x - b.x)
		turnDeg = math.deg(math.atan2(math.sin(h2 - h1), math.cos(h2 - h1)))
	end
	print(string.format("   esquina de guía más cercana: wp%d a %d studs, giro %d° (signo: %s)", bestI, bestD, turnDeg, if turnDeg > 0 then "derecha" else "izquierda"))
	print(string.format("seed=%d bestArc=%d liveArc=%d (retrocedido %d) rOrigen=%d | rechazos: crowded=%.0f%% deviation=%.0f%% escape=%.0f%% heading=%.0f%% | |off| últimos ~5000: max=%d media=%d | pasadas previas a <250: %d | guía: %d puntos",
		seedNow, d.best, liveMax * 2, d.best - liveMax * 2, math.sqrt(s.x*s.x+s.z*s.z),
		100*(r._crowded or 0)/total, 100*(r._deviation or 0)/total, 100*(r._escape or 0)/total, 100*(r._heading or 0)/total,
		maxOff, sumOff / math.max(1, n), passes, #wps))
end
for n in string.gmatch(a1, "%d+") do
	seedNow = tonumber(n)
	Exp86.live = {}
	local path = RoadPath.new(seedNow)
	for i = 1, 400 do
		local ok = pcall(path.generateNextSegment)
		if not ok then break end
	end
end
