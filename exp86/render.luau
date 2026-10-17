--!nocheck
-- Dibuja la situación de un encierro en PNG (se imprime en hex entre marcas; ver exp86/render.sh).
local Png = require("./Png")
local Render = {}
local W = 1000
function Render.draw(d, Exp86, s, half)
	local scale = 2 * half / W
	local white, green, dkgreen, grey, blue, red, yellow, black, purple =
		{255,255,255}, {214,240,214}, {0,120,0}, {170,170,170}, {40,90,220}, {220,30,30}, {255,200,0}, {0,0,0}, {160,0,200}
	local px = table.create(W)
	for y = 1, W do px[y] = table.create(W, white) end
	local function toPx(x, z) return math.floor((x - (s.x - half)) / scale) + 1, math.floor((z - (s.z - half)) / scale) + 1 end
	local function disk(x, z, rStuds, color, only)
		local cx, cz = toPx(x, z)
		local r = math.max(1, math.floor(rStuds / scale + 0.5))
		for dy = -r, r do
			local yy = cz + dy
			if yy >= 1 and yy <= W then
				for dx = -r, r do
					local xx = cx + dx
					if xx >= 1 and xx <= W and dx * dx + dy * dy <= r * r then
						if only == nil or px[yy][xx] == only then px[yy][xx] = color end
					end
				end
			end
		end
	end
	local wps = d.guide.debugWaypoints()
	local tunnel = Exp86.tunnel or 170
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		for t = 0, 1, scale / 500 do disk(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, tunnel, green, white) end
	end
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		for t = 0, 1, scale / 500 do disk(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, 5, dkgreen) end
		disk(a.x, a.z, 25, black)
	end
	local liveMax = 0
	for i in Exp86.live do liveMax = math.max(liveMax, i) end
	for pass = 1, 3 do
		for i = 0, liveMax do
			local p = Exp86.live[i]
			if p then
				local back = (liveMax - i) * 2
				local band = if back <= 1000 then 3 elseif back <= 4000 then 2 else 1
				if band == pass then
					disk(p[1], p[2], 10, if band == 3 then red elseif band == 2 then blue else grey)
				end
			end
		end
	end
	-- cada 500 studs de arco, un punto morado (para leer el orden de la ruta)
	for i = 0, liveMax, 250 do
		local p = Exp86.live[i]
		if p then disk(p[1], p[2], 18, purple) end
	end
	disk(s.x, s.z, 30, yellow)
	disk(0, 0, 30, black)
	return Png.encode(W, W, px)
end
function Render.emit(name, png)
	print("PNGBEGIN " .. name)
	local parts = {}
	for i = 1, #png do parts[i] = string.format("%02x", string.byte(png, i)) end
	-- en líneas de 4000 caracteres
	local hex = table.concat(parts)
	for i = 1, #hex, 4000 do print(string.sub(hex, i, i + 3999)) end
	print("PNGEND")
end
return Render
