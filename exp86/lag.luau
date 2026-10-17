--!nocheck
-- Retraso de publicación (studs entre la punta generada y lo ya definitivo). luau exp86/lag.luau -a <semillas> <variante>
local a1, a2 = ...
require("./Variant").apply(a2)
local Seq = require("../src/world/core/RoadPieceSequencer")
local lags, maxLag = {}, 0
for seed = 1, tonumber(a1) do
	local s = Seq.new(seed)
	for _ = 1, 1500 do
		local ok, piece = pcall(s.generateNextPiece)
		if not ok then break end
		local last = piece.retractedAfterSampleNumber + #piece.samples
		local lag = (last - piece.finalizedSampleNumber) * 2
		table.insert(lags, lag)
		maxLag = math.max(maxLag, lag)
	end
end
table.sort(lags)
print(`variant={a2} pieces={#lags} lag p50={lags[#lags//2]} p99={lags[math.floor(#lags*0.99)]} max={maxLag}`)
