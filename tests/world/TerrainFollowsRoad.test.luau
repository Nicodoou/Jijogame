--!strict
local Runner = require("../Runner")
local TerrainDrive = require("./TerrainDrive")

-- La semilla del reporte del bug "la ruta queda enterrada bajo el terreno" (2026-10-16).
local REPORTED_SEED = 393026859
-- Cerca de la velocidad máxima: el auto se adelanta al trabajo y alcanza para ver el bug en pocos studs.
local SPEED_STUDS_PER_SECOND = 150
-- Pasos caros del reloj falso: el trabajo va atrasado respecto del auto, como en Studio con cuadros caros.
local STEP_MS = 1
-- Con esta semilla, esta velocidad y este atraso el terreno ya quedaba mal desde los 2.140 studs.
local END_ARC_LENGTH = 2400
local MIN_READY_CHECKS = 1000

Runner.test(
	"at speed with the work lagging, the terrain on the road axis matches the axis wherever the world is ready (ruta enterrada)",
	function()
		local report = TerrainDrive.run({
			seed = REPORTED_SEED,
			stepMs = STEP_MS,
			startArcLength = 0,
			endArcLength = END_ARC_LENGTH,
			speedStudsPerSecond = SPEED_STUDS_PER_SECOND,
		})
		Runner.expectEqual(report.readyCheckCount > MIN_READY_CHECKS, true)
		Runner.expectEqual(report.firstBad, nil)
		Runner.expectEqual(report.badCount, 0)
	end
)

Runner.finish()
