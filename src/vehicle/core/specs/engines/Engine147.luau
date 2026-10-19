--!strict
-- Ficha del motor del 147: curva de torque, régimen y freno motor. Solo datos.
local SpecTypes = require("../SpecTypes")

local engine: SpecTypes.EngineSpec = {
	-- En unidades de torque de juego. Se calcula para que la fuerza en la rueda sea la de siempre con el auto de 84:
	-- PEAK_TORQUE · relación · FINAL_DRIVE · DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS_STUDS = 84 · 120 · (relación / 3,5),
	-- o sea PEAK_TORQUE = 84 · 120 · 0,81 / (3,5 · 4 · 0,9) = 8164,8 / 12,6 = 648.
	PEAK_TORQUE = 648,
	-- (rpm, fracción del torque pico).
	TORQUE_CURVE = table.freeze({
		table.freeze({ rpm = 1000, fraction = 0.6 }),
		table.freeze({ rpm = 3000, fraction = 0.9 }),
		table.freeze({ rpm = 4500, fraction = 1.0 }),
		table.freeze({ rpm = 6500, fraction = 0.85 }),
		table.freeze({ rpm = 7000, fraction = 0.7 }),
	}),
	IDLE_RPM = 1000,
	REDLINE_RPM = 7000,
	-- Entre REDLINE_RPM − este valor y REDLINE_RPM la fuerza del motor baja linealmente hasta 0.
	SOFT_LIMITER_RPM = 400,
	-- Parte de los 84 del auto de hoy; el resto es del chasis.
	ENGINE_MASS = 14,

	-- Freno motor (WP-17): desaceleración (studs/s²) en 1ra al corte con el acelerador suelto. En otras marchas escala con
	-- la relación respecto de 1ra, y con las RPM entre el ralentí y el corte.
	ENGINE_BRAKE_DECELERATION = 8,
	-- Por debajo de estas RPM el embrague se abre y no hay freno motor.
	ENGINE_BRAKE_MIN_RPM = 1500,
}

return table.freeze(engine)
