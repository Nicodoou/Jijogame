--!nocheck
-- Tiempo de generateStep (ms), en un proceso solo y con la máquina quieta. luau exp86/timing.luau -a <lista de semillas|N> <tramos> [variante]
local a1, a2, a3 = ...
require("./Variant").apply(a3)
local RoadPath = require("../src/world/core/RoadPath")
local seeds = {}
if tonumber(a1) then
	for s = 1, tonumber(a1) do table.insert(seeds, s) end
else
	for n in string.gmatch(a1, "%d+") do table.insert(seeds, tonumber(n)) end
end
local times, worst, worstSeed, total, steps, enclosed = {}, 0, 0, 0, 0, 0
for _, seed in seeds do
	local path = RoadPath.new(seed)
	local ok = pcall(function()
		for _ = 1, tonumber(a2) do
			local segment = nil
			while segment == nil do
				local t = os.clock()
				segment = path.generateStep()
				local dt = (os.clock() - t) * 1000
				table.insert(times, dt)
				total += dt
				steps += 1
				if dt > worst then worst, worstSeed = dt, seed end
			end
		end
	end)
	if not ok then enclosed += 1 end
end
table.sort(times)
local function pct(p) return times[math.max(1, math.floor(#times * p))] end
print(string.format("variante=%s semillas=%d encerradas=%d pasos=%d media=%.3fms p99=%.2fms p99.99=%.2fms peor=%.2fms (semilla %d) total=%.1fs",
	a3 or "base", #seeds, enclosed, steps, total / steps, pct(0.99), pct(0.9999), worst, worstSeed, total / 1000))
