--!nocheck
-- Qué piezas y qué desvíos hay en los ~4000 studs previos al encierro. luau exp86/diag_kinds.luau -a <semillas>
local a1 = ...
local Exp86 = require("../src/world/core/Exp86")
Exp86.diag = true
local RoadPath = require("../src/world/core/RoadPath")
local seedNow
local totalTurnBack, totalPieces, withTurnBack = 0, 0, 0
local seeds = 0
Exp86.onEnclosed = function(d)
	local liveArc = d.state.sampleIndex * 2
	local counts, maxOffTurnBack, maxOffOther = {}, 0, 0
	local seenSi = {}
	local lastCommits = {}
	for i = #d.log, 1, -1 do
		local e = d.log[i]
		if e.ev == "commit" and not seenSi[e.si] and e.si * 2 <= liveArc and e.si * 2 > liveArc - 4000 then
			seenSi[e.si] = true
			counts[e.kind] = (counts[e.kind] or 0) + 1
		end
	end
	local parts = {}
	for k, v in counts do table.insert(parts, `{k}={v}`) end
	table.sort(parts)
	local tb = (counts.hairpinPair or 0) + (counts.uTurn or 0)
	seeds += 1
	if tb > 0 then withTurnBack += 1 end
	print(`seed={seedNow} últimos 4000 studs: {table.concat(parts, " ")} | giran-hacia-atrás={tb}`)
end
for n in string.gmatch(a1, "%d+") do
	seedNow = tonumber(n)
	local path = RoadPath.new(seedNow)
	for i = 1, 400 do
		if not pcall(path.generateNextSegment) then break end
	end
end
print(`semillas encerradas con al menos una horquilla/U en los últimos 4000 studs: {withTurnBack}/{seeds}`)
