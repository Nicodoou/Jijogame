--!nocheck
-- Huella del camino publicado por semilla, para comparar variantes. luau exp86/hash.luau -a <desde> <hasta> <tramos> [variante]
local a1, a2, a3, a4 = ...
require("./Variant").apply(a4)
local RoadPath = require("../src/world/core/RoadPath")
for seed = tonumber(a1), tonumber(a2) do
	local path = RoadPath.new(seed)
	local h, n = 0, 0
	for i = 1, tonumber(a3) do
		local ok, seg = pcall(path.generateNextSegment)
		if not ok then break end
		n += 1
		for _, s in seg.samples do h = (h * 31 + math.floor(s.position.x * 8) + 7 * math.floor(s.position.z * 8) + 13 * math.floor(s.position.y * 8)) % 2147483647 end
	end
	print(`{seed} {n} {h}`)
end
