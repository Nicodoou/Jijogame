--!nocheck
-- Qué pasa en los pasos más lentos de una semilla. luau exp86/slowstep.luau -a <semilla> <tramos> [variante]
local a1, a2, a3 = ...
require("./Variant").apply(a3)
local RoadPath = require("../src/world/core/RoadPath")
local path, stats = RoadPath.newWithStatistics(tonumber(a1))
local slow = {}
for seg = 1, tonumber(a2) do
	local segment = nil
	while segment == nil do
		local s = stats()
		local before = { g = s.guide.backtrackCount, gd = s.guide.discardedWaypointCount, b = s.backtrackCount, lr = s.lastResortCount, p = s.pieceCount }
		local t = os.clock()
		segment = path.generateStep()
		local dt = (os.clock() - t) * 1000
		if dt > 15 then
			s = stats()
			table.insert(slow, string.format("seg=%d dt=%.1fms guideBacktracks+%d (descartados+%d) roadBacktracks+%d lastResort+%d", seg, dt, s.guide.backtrackCount - before.g, s.guide.discardedWaypointCount - before.gd, s.backtrackCount - before.b, s.lastResortCount - before.lr))
		end
	end
end
print(#slow .. " pasos > 15ms")
for i = 1, math.min(#slow, 25) do print(slow[i]) end
