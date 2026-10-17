--!nocheck
-- Escritor mínimo de PNG (RGB, deflate sin comprimir). Descartable.
local Png = {}
local crcTable = {}
for n = 0, 255 do
	local c = n
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1)) else c = bit32.rshift(c, 1) end
	end
	crcTable[n] = c
end
local function crc32(s)
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(crcTable[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end
local function be32(n) return string.char(bit32.rshift(n, 24) % 256, bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256) end
local function chunk(kind, data) return be32(#data) .. kind .. data .. be32(crc32(kind .. data)) end
local function adler(s)
	local a, b = 1, 0
	for i = 1, #s do a = (a + string.byte(s, i)) % 65521; b = (b + a) % 65521 end
	return b * 65536 + a
end
-- pixels[y][x] = {r,g,b}
function Png.encode(w, h, pixels)
	local rows = table.create(h)
	for y = 1, h do
		local row = table.create(w * 3 + 1)
		row[1] = string.char(0)
		local line = pixels[y]
		local parts = {}
		for x = 1, w do
			local p = line[x]
			parts[x] = string.char(p[1], p[2], p[3])
		end
		rows[y] = string.char(0) .. table.concat(parts)
	end
	local raw = table.concat(rows)
	local blocks = {}
	local pos = 1
	while pos <= #raw do
		local len = math.min(65535, #raw - pos + 1)
		local last = if pos + len > #raw then 1 else 0
		table.insert(blocks, string.char(last) .. string.char(len % 256, len // 256) .. string.char((65535 - len) % 256, (65535 - len) // 256) .. string.sub(raw, pos, pos + len - 1))
		pos += len
	end
	local z = string.char(0x78, 0x01) .. table.concat(blocks) .. be32(adler(raw))
	return "\137PNG\r\n\26\n" .. chunk("IHDR", be32(w) .. be32(h) .. string.char(8, 2, 0, 0, 0)) .. chunk("IDAT", z) .. chunk("IEND", "")
end
return Png
