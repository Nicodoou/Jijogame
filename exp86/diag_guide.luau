--!nocheck
-- Diagnóstico de fallas de la guía. luau exp86/diag_guide.luau -a <semilla> [variante]
local a1, a2 = ...
require("./Variant").apply(a2)
local Exp86 = require("../src/world/core/Exp86")
Exp86.onGuideStuck = function(d)
	local w = d.waypoints
	print(`GUIDE STUCK: {#w} puntos, usados por la ruta (no se pueden descartar)={d.keptWaypointCount}, pedido descartar={d.requested}, posible={d.discarded}, failStreak={d.failStreak}`)
	for i = math.max(1, #w - 14), #w do
		print(string.format("  wp%d x=%.0f z=%.0f r=%.0f", i, w[i].x, w[i].z, math.sqrt(w[i].x^2 + w[i].z^2)))
	end
end
local RoadPath = require("../src/world/core/RoadPath")
local path = RoadPath.new(tonumber(a1))
for i = 1, 400 do
	local ok, err = pcall(path.generateNextSegment)
	if not ok then print("error:", err, "tramo", i) break end
end
