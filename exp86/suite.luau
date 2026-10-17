--!nocheck
-- Corrida 200 x 400 con las métricas del WP-5. luau exp86/suite.luau -a <semillas> [variante]
local a1, a2 = ...
require("./Variant").apply(a2)
local RoadPropertySuite = require("../tests/world/RoadPropertySuite")
local t0 = os.clock()
local r = RoadPropertySuite.measure(tonumber(a1) or 200)
local v = r.violations
local bad = 0
for _, n in v do bad += n end
local function f(x) return string.format("%.2f", x) end
print(`variante={a2 or "base"} semillas={r.seedCount} tiempo={f(os.clock() - t0)}s`)
print(`encierros={r.enclosedSeedCount} violAntiCruce={r.clearanceViolations} violAltura={r.heightViolations} violMuestras={bad} continuidad={r.continuityViolations}`)
print(`ultimoRecurso={r.lastResortCount} retrocesos={r.backtrackCount} piezasRetiradas={r.retractedPieceCount} retrocesosGuia={r.guideBacktrackCount}`)
print(`giroGrande>180(semillas)={r.seedsWithBigTurn}/{r.seedCount} cuadrantes={r.seedsWithAllQuadrants}/{r.seedCount} curvasCerradas/km={f(r.sharpCurvesPerKm)} (>1) horquillas/km={f(r.hairpinsPerKm)} (>0.3)`)
print(`ventanasGiro>180={f(r.bigTurnWindowPercent)}% (>=20) U/km={f(r.uTurnsPerKm)} (>=0.9) rectaMax={r.longestStraightStuds} (<=250) rectaMedia={f(r.meanStraightStuds)}`)
print(`pendiente>10°={f(r.steepPercent)}% (>=25) largoSubida={f(r.meanClimbStuds)} (<150) ventanasLomas>60={r.hilliestWindowCount}/{r.heightWindowCount}`)
print(`pendienteMax={r.steepestSlopeDegrees} distMinNoVecinas={f(r.minimumClearance)}`)
