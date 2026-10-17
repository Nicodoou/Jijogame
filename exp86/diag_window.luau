--!nocheck
-- Muestra cómo evoluciona la ventana de retroceso durante la racha de fallas. luau exp86/diag_window.luau -a <semilla> [variante]
local a1, a2 = ...
require("./Variant").apply(a2)
local Exp86 = require("../src/world/core/Exp86")
Exp86.diag = true
Exp86.onEnclosed = function(d)
	-- los eventos 'stuck' guardados (últimos 300 eventos)
	local line = {}
	for _, e in d.log do
		if e.ev == "stuck" then table.insert(line, `fs={e.fs}:cp={e.cp}`) end
	end
	print("racha(fs):piezas retrocedibles(cp) en cada falla (últimas):")
	print(table.concat(line, " "))
end
local RoadPath = require("../src/world/core/RoadPath")
local path = RoadPath.new(tonumber(a1))
for i = 1, 400 do
	local ok, err = pcall(path.generateNextSegment)
	if not ok then break end
end
