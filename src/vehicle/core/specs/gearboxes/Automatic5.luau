--!strict
-- Ficha de la caja automática de 5 marchas del 147. Solo datos.
local SpecTypes = require("../SpecTypes")

local gearbox: SpecTypes.GearboxSpec = {
	kind = "automatic",
	GEAR_RATIOS = table.freeze({ 3.5, 2.3, 1.65, 1.25, 1.0 }),
	REVERSE_RATIO = 5,
	-- En reversa el empuje del motor se multiplica por esta fracción.
	REVERSE_DRIVE_FRACTION = 0.4,
	FINAL_DRIVE = 4.0,
	DRIVETRAIN_EFFICIENCY = 0.9,
	-- Tracción: fracción de la fuerza que va al eje trasero.
	REAR_BIAS = 0,
	UPSHIFT_RPM = 6200,
	DOWNSHIFT_RPM = 3000,
	-- Kickdown: con el acelerador a fondo y sin margen para acelerar con la carga, la caja baja a una marcha que empuje más.
	KICKDOWN_THROTTLE = 0.9,
	-- Aceleración (studs/s²) que tiene que dar la marcha de destino con la carga estimada, al bajar y al subir a fondo.
	KICKDOWN_ACCEL_MARGIN = 5,
	UPSHIFT_ACCEL_MARGIN = 2,
	-- RPM máximas que puede tener la marcha de abajo: lejos del corte, con recorrido para acelerar antes de volver a subir.
	KICKDOWN_MAX_RPM = 4800,
	-- Tasa del filtro de la inclinación del auto con la que se estima la carga (que el cabeceo no la mueva).
	LOAD_PITCH_FILTER_RATE = 8,
	-- Tiempo mínimo desde la última subida antes de que el kickdown pueda actuar (contra la caza de marchas).
	GEAR_HOLD_SECONDS = 1.0,
	SHIFT_DURATION_SECONDS = 0.25,
	SHIFT_TORQUE_FRACTION = 0,
	REVERSE_ENGAGE_SPEED = 1,
}

return table.freeze(gearbox)
