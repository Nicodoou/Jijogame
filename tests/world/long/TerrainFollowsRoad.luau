--!strict
-- Recorrido largo del bug "la ruta queda enterrada bajo el terreno": la semilla del reporte, 55.000 studs a 80 studs/s,
-- con tres atrasos distintos del trabajo (el último es tan alto que el trabajo no alcanza: ahí el mundo tiene que dar
-- por no listo lo que quedó viejo). Tarda unos minutos y no es una prueba de scripts/test.sh (no termina en
-- .test.luau): se corre a mano antes de cada PR que toque el terreno.
--   luau tests/world/long/TerrainFollowsRoad.luau
-- Opcional, otro largo de recorrido en studs:  luau tests/world/long/TerrainFollowsRoad.luau -a 20000
local Runner = require("../../Runner")
local TerrainDrive = require("../TerrainDrive")

local REPORTED_SEED = 393026859
local DEFAULT_END_ARC_LENGTH = 55000
local SPEED_STUDS_PER_SECOND = 80
local STEP_COSTS_MS = { 0.5, 1, 2 }

local endArcLength = tonumber((...)) or DEFAULT_END_ARC_LENGTH

for _, stepMs in STEP_COSTS_MS do
	Runner.test(`the terrain follows the road axis with {stepMs} ms per step over {endArcLength} studs`, function()
		local report = TerrainDrive.run({
			seed = REPORTED_SEED,
			stepMs = stepMs,
			startArcLength = 0,
			endArcLength = endArcLength,
			speedStudsPerSecond = SPEED_STUDS_PER_SECOND,
		})
		print(
			`{stepMs} ms: {report.badCount} malos de {report.readyCheckCount} chequeos listos (peor diferencia {report.worstDifference} studs); `
				.. `{report.notReadyBadCount} malos más que el mundo no daba por listos, de {report.checkCount} escritos`
		)
		Runner.expectEqual(report.firstBad, nil)
		Runner.expectEqual(report.readyCheckCount > 0, true)
	end)
end

Runner.finish()
