--!nocheck
-- Barrido de semillas. luau exp86/sweep.luau -a <desde> <hasta> <tramos> [variante]
-- (o una lista de semillas separadas por coma en lugar de <desde>)
local a1, a2, a3, a4 = ...
local from, to, count = tonumber(a1), tonumber(a2), tonumber(a3) or 400
local seedList = nil
if from == nil then
	seedList = {}
	for n in string.gmatch(a1, "%d+") do table.insert(seedList, tonumber(n)) end
	from, to = 1, #seedList
end
require("./Variant").apply(a4)
local RoadPath = require("../src/world/core/RoadPath")
local Exp86 = require("../src/world/core/Exp86")
local thresholds = { 10, 30, 100, 300 }
local hist = { 0, 0, 0, 0 }
local globalMaxFail, globalMaxCount = 0, 0
local enclosed, exposure = 0, 0
local t0 = os.clock()
local worst, worstSeed = 0, 0
for seedIndex = from, to do
	local seed = if seedList then seedList[seedIndex] else seedIndex
	Exp86.stats.maxFail, Exp86.stats.maxCount = 0, 0
	local path = RoadPath.new(seed)
	for i = 1, count do
		local segment = nil
		local ok, err = pcall(function()
			while segment == nil do
				local s = os.clock()
				segment = path.generateStep()
				local dt = os.clock() - s
				if dt > worst then worst, worstSeed = dt, seed end
			end
		end)
		if not ok then
			enclosed += 1
			local kind = if string.find(tostring(err), "guide") then "GUIDE" else "SEQ"
			print(`ENCLOSED seed={seed} segment={i} kind={kind}`)
			Exp86.stats.maxFail = math.max(Exp86.stats.maxFail, 601)
			break
		end
		exposure += 1
	end
	for k, t in thresholds do
		if Exp86.stats.maxFail > t then hist[k] += 1 end
	end
	globalMaxFail = math.max(globalMaxFail, Exp86.stats.maxFail)
	globalMaxCount = math.max(globalMaxCount, Exp86.stats.maxCount)
end
print(`rerolls={Exp86.stats.rerolls} guideRescues={Exp86.stats.guideRescues} guideMaxFail={Exp86.stats.guideMaxFail}`)
print(`variant={a4} maxFailBeforeAdvance={globalMaxFail} maxRetractedAtOnce={globalMaxCount} seedsWithMaxFailOver10/30/100/300={table.concat(hist, "/")}`)
print(`range {from}-{to} segs={count} enclosed={enclosed} exposure={exposure} worstStepMs={string.format("%.2f", worst * 1000)}(seed {worstSeed}) time={string.format("%.1f", os.clock() - t0)}s`)
