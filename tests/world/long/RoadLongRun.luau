--!strict
-- Corrida completa de las propiedades de la ruta: 200 semillas × 400 tramos (~100 km cada una). Tarda varios minutos y
-- no es una prueba de scripts/test.sh (no termina en .test.luau): se corre a mano antes de cada PR que toque la ruta.
--   luau tests/world/long/RoadLongRun.luau
-- Opcional, para otra cantidad de semillas:  luau tests/world/long/RoadLongRun.luau -a 20
local RoadPropertySuite = require("../RoadPropertySuite")
local Runner = require("../../Runner")

local FULL_SEED_COUNT = 200

local seedCount = tonumber((...)) or FULL_SEED_COUNT
local report = RoadPropertySuite.defineTests(seedCount)

print(`semillas: {report.seedCount} x {RoadPropertySuite.segmentCount} tramos`)
print(`encierros: {report.enclosedSeedCount}`)
print(
	`violaciones del anti-cruce: {report.clearanceViolations} (distancia mínima entre no vecinas: {report.minimumClearance})`
)
print(
	`violaciones de la regla de altura: {report.heightViolations} (pendiente más empinada entre pasadas: {report.steepestSlopeDegrees}°)`
)
print(
	`último recurso: {report.lastResortCount}, retrocesos de la ruta: {report.backtrackCount} ({report.retractedPieceCount} piezas retiradas)`
)
print(`retrocesos de la guía: {report.guideBacktrackCount}`)
print(
	`semillas con giro neto > 180° en 2.000 studs: {report.seedsWithBigTurn}, con los 4 cuadrantes: {report.seedsWithAllQuadrants}`
)
print(`curvas cerradas por km: {report.sharpCurvesPerKm}, horquillas por km: {report.hairpinsPerKm}`)
print(`ventanas de 2.000 studs con más de 60 de desnivel: {report.hilliestWindowCount} de {report.heightWindowCount}`)
print(`ventanas de 2.000 studs con giro neto > 180°: {report.bigTurnWindowPercent}%`)
print(`vueltas en U por km: {report.uTurnsPerKm}`)
print(`recta más larga: {report.longestStraightStuds} studs, promedio: {report.meanStraightStuds}`)
print(
	`recorrido con pendiente > 10°: {report.steepPercent}%, largo medio de cada subida o bajada: {report.meanClimbStuds} studs`
)

Runner.finish()
