--!strict
local Runner = require("../Runner")
local Assists = require("../../src/vehicle/core/Assists")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")

local COUNTER_LIMIT = math.rad(VehicleConfig.COUNTER_STEER_MAX_DEGREES)
local ASSIST_STRENGTH = 0.3

-- El contravolante viene apagado en la configuración (decisión del experimento de manejo): se prueba encendido aparte.
local ASSISTED = table.clone(VehicleConfig)
ASSISTED.COUNTER_STEER_STRENGTH = ASSIST_STRENGTH

Runner.test("the counter steer is proportional to the drift angle", function()
	local drift = math.rad(10)
	Runner.expectNear(Assists.counterSteer(drift, 40, ASSISTED), ASSIST_STRENGTH * drift, 1e-12)
	Runner.expectNear(Assists.counterSteer(-drift, 40, ASSISTED), -ASSIST_STRENGTH * drift, 1e-12)
end)

Runner.test("the counter steer is capped", function()
	Runner.expectEqual(Assists.counterSteer(math.rad(80), 40, ASSISTED), COUNTER_LIMIT)
	Runner.expectEqual(Assists.counterSteer(-math.rad(80), 40, ASSISTED), -COUNTER_LIMIT)
end)

Runner.test("the counter steer only works above the minimum speed going forward", function()
	local drift = math.rad(10)
	Runner.expectEqual(Assists.counterSteer(drift, VehicleConfig.COUNTER_STEER_MIN_SPEED, ASSISTED), 0)
	Runner.expectEqual(Assists.counterSteer(drift, VehicleConfig.COUNTER_STEER_MIN_SPEED - 1, ASSISTED), 0)
	Runner.expectEqual(Assists.counterSteer(drift, 0, ASSISTED), 0)
	Runner.expectEqual(Assists.counterSteer(drift, -50, ASSISTED), 0)
	Runner.expectEqual(Assists.counterSteer(drift, VehicleConfig.COUNTER_STEER_MIN_SPEED + 0.001, ASSISTED) ~= 0, true)
end)

Runner.test("the counter steer is off in the default configuration", function()
	Runner.expectEqual(VehicleConfig.COUNTER_STEER_STRENGTH, 0)
	Runner.expectEqual(Assists.counterSteer(math.rad(30), 60), 0)
end)

Runner.test("with the strength at zero the counter steer is off", function()
	local off = table.clone(VehicleConfig)
	off.COUNTER_STEER_STRENGTH = 0
	Runner.expectEqual(Assists.counterSteer(math.rad(30), 60, off), 0)
end)

Runner.test("the counter steer is zero without drift", function()
	Runner.expectEqual(Assists.counterSteer(0, 60, ASSISTED), 0)
end)

Runner.finish()
