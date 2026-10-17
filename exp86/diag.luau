--!nocheck
-- Diagnóstico de encierros. luau exp86/diag.luau -a <semilla> [tramos] [plot]
local seedArg, segArg, plotArg, halfArg = ...
local seed, count = tonumber(seedArg), tonumber(segArg) or 400
local Exp86 = require("../src/world/core/Exp86")
Exp86.diag = true
Exp86.live = {}
local RoadPath = require("../src/world/core/RoadPath")
local function f(n) return string.format("%.0f", n) end

local function plot(d, centerX, centerZ, halfSize, cell, lastArcs)
	local cols = math.floor(2 * halfSize / cell)
	local grid = {}
	for r = 1, cols do grid[r] = table.create(cols, " ") end
	local function put(x, z, ch, force)
		local c = math.floor((x - (centerX - halfSize)) / cell) + 1
		local r = math.floor((z - (centerZ - halfSize)) / cell) + 1
		if c >= 1 and c <= cols and r >= 1 and r <= cols then
			if force or grid[r][c] == " " or grid[r][c] == "." then grid[r][c] = ch end
		end
	end
	local liveMax = 0
	for i in Exp86.live do liveMax = math.max(liveMax, i) end
	-- ruta viva: '.' vieja (más de lastArcs studs atrás) , dígito = décimas del tramo reciente
	for i = 0, liveMax do
		local p = Exp86.live[i]
		if p then
			local back = (liveMax - i) * 2
			local ch = if back <= 1000 then "#" elseif back <= 4000 then "o" else "."
			put(p[1], p[2], ch, ch == "#")
		end
	end
	local wps = d.guide.debugWaypoints()
	for i, w in wps do
		put(w.x, w.z, "G", true)
		if i < #wps then
			local n = wps[i + 1]
			for t = 1, 9 do put(w.x + (n.x - w.x) * t / 10, w.z + (n.z - w.z) * t / 10, "-", false) end
		end
	end
	put(d.state.x, d.state.z, "X", true)
	put(0, 0, "S", true)
	for r = 1, cols do print(table.concat(grid[r])) end
end

Exp86.onEnclosed = function(d)
	print(`=== seed {seed}: ENCLOSED. best arc={d.best} pieces alive={d.pieceCount} checkpoints={#d.checkpoints} failStreak(last stuck)={d.log[#d.log].fs}`)
	local s = d.state
	print(`state x={f(s.x)} z={f(s.z)} r={f(math.sqrt(s.x*s.x+s.z*s.z))} y={f(s.y)} heading={f(math.deg(s.heading))} sample={s.sampleIndex}`)
	local keys = {}
	for k, v in d.reasons do table.insert(keys, `{k}={v}`) end
	table.sort(keys)
	print("rechazos desde el último avance:", table.concat(keys, " "))
	local wps = d.guide.debugWaypoints()
	print(`guía: {#wps} puntos; últimos:`)
	for i = math.max(1, #wps - 14), #wps do print(`  wp{i} x={f(wps[i].x)} z={f(wps[i].z)} r={f(math.sqrt(wps[i].x^2+wps[i].z^2))}`) end
	-- tramos de ruta viva cercanos al estado, agrupados por rango de arco
	local liveMax = 0
	for i in Exp86.live do liveMax = math.max(liveMax, i) end
	local ranges, cur = {}, nil
	for i = 0, liveMax do
		local p = Exp86.live[i]
		if p and math.sqrt((p[1]-s.x)^2 + (p[2]-s.z)^2) < 300 then
			if cur and i - cur.to <= 5 then cur.to = i else cur = {from = i, to = i}; table.insert(ranges, cur) end
		end
	end
	local parts = {}
	for _, r in ranges do table.insert(parts, `{r.from*2}-{r.to*2}`) end
	print(`ruta viva (llega a arc {liveMax*2}); arcos a menos de 300 studs del estado: {table.concat(parts, ", ")}`)
	if plotArg == "png" then
		local Render = require("./render")
		Render.emit("seed" .. seed, Render.draw(d, Exp86, s, tonumber(halfArg) or 2000))
	elseif plotArg then
		-- ventana 3000 studs alrededor del estado, celda 40
		print("ASCII (celda 40 studs; # últimos 1000 studs, o 1000-4000 atrás, . más viejo; G guía, X estado, S origen)")
		plot(d, s.x, s.z, 2000, 40, 4000)
	end
	local from = math.max(1, #d.log - 12)
	for i = from, #d.log do
		local e = d.log[i]
		print(`{e.ev} {e.kind or ""} x={f(e.x)} z={f(e.z)} r={f(math.sqrt(e.x*e.x+e.z*e.z))} y={f(e.y)} h={f(math.deg(e.h))} off={f(e.off)} guideArc={f(e.arc)} arc={e.si*2} fs={e.fs or ""}`)
	end
end
local path = RoadPath.new(seed)
for i = 1, count do
	local ok, err = pcall(path.generateNextSegment)
	if not ok then print("error:", err, "en tramo", i) break end
end
