--!strict
-- Valores de ajuste del auto. Solo datos: nada de lógica.
-- Los iniciales se ajustan después en las pruebas de juego (WP-3). Unidades: studs, segundos,
-- radianes (los ángulos van en grados con _DEGREES) y masa de Roblox. Las fuerzas son masa × studs/s².
-- Las posiciones de las ruedas están en el marco del chasis de Roblox: x a la derecha, y arriba y -z adelante.

return table.freeze({
	-- Orden fijo: FL, FR, RL, RR.
	WHEELS = table.freeze({
		table.freeze({ name = "FL", offset = vector.create(-2.5, -1, -4), isFront = true, isLeft = true }),
		table.freeze({ name = "FR", offset = vector.create(2.5, -1, -4), isFront = true, isLeft = false }),
		table.freeze({ name = "RL", offset = vector.create(-2.5, -1, 4), isFront = false, isLeft = true }),
		table.freeze({ name = "RR", offset = vector.create(2.5, -1, 4), isFront = false, isLeft = false }),
	}),
	WHEEL_RADIUS_STUDS = 1.2,

	-- Peso: solo los lee el adaptador para armar el lastre (CP-6); el núcleo saca el reparto del centro de masa real.
	-- Fracción del peso sobre el eje delantero.
	FRONT_WEIGHT_FRACTION = 0.7,
	-- Altura del centro de masa sobre el plano de montaje de las ruedas (y = −1 local).
	CENTER_OF_MASS_HEIGHT_STUDS = 0.6,
	-- Parte de la masa total que lleva el lastre invisible.
	BALLAST_MASS_FRACTION = 0.5,

	-- Suspensión.
	-- Como máximo 4 Hz (#32).
	SUSPENSION_FREQUENCY_HZ = 2.5,
	SUSPENSION_DAMPING_RATIO = 0.8,
	SUSPENSION_REST_LENGTH_STUDS = 2.5,
	SUSPENSION_MAX_COMPRESSION_STUDS = 2,
	-- Tope de la fuerza por rueda, en múltiplos de su carga estática.
	SUSPENSION_MAX_FORCE_PER_STATIC_LOAD = 4,
	-- Si la rueda venía comprimida más que esta fracción del recorrido y el rayo no pega, sigue apoyada (#31).
	BOTTOM_OUT_FRACTION = 0.8,
	-- Máximo de pasos seguidos sin contacto en los que la rueda se sigue considerando a tope.
	BOTTOM_OUT_MAX_MISSED_STEPS = 3,
	COMPRESSION_SPEED_FILTER_RATE = 30,

	-- Neumático.
	TIRE_FRICTION = 1.0,
	-- Fuerza lateral por unidad de carga y por radián.
	TIRE_CORNERING_STIFFNESS_PER_RADIAN = 8,
	-- 1 = sin caída de la fuerza lateral después del pico.
	TIRE_SLIDE_FRICTION_RATIO = 0.9,
	LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND = 3,
	-- Agarre por eje: multiplica el agarre disponible (tope lateral y círculo) de cada rueda.
	FRONT_GRIP_MULTIPLIER = 1.0,
	REAR_GRIP_MULTIPLIER = 0.95,
	-- Con el freno de mano apretado el agarre trasero baja a esta fracción; al soltarlo vuelve a 1 con esta tasa.
	HANDBRAKE_REAR_GRIP_MULTIPLIER = 0.85,
	-- Con el freno de mano apretado el factor baja hacia el multiplicador con esta tasa (por segundo).
	HANDBRAKE_GRIP_DROP_RATE = 8,
	HANDBRAKE_GRIP_RECOVERY_RATE = 3,

	-- Superficie.
	SURFACE_GRIP = table.freeze({ Road = 1.0, Shoulder = 0.85, Grass = 0.7, Mud = 0.5 }),
	-- Por unidad de carga.
	SURFACE_ROLLING_RESISTANCE = table.freeze({ Road = 0.015, Shoulder = 0.03, Grass = 0.06, Mud = 0.12 }),
	SURFACE_BLEND_RATE = 8,

	-- Motor: (rpm, fracción del torque pico).
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
	FIRST_GEAR_PEAK_ACCELERATION = 120,

	-- Caja.
	GEAR_RATIOS = table.freeze({ 3.5, 2.3, 1.65, 1.25, 1.0 }),
	REVERSE_RATIO = 5,
	-- En reversa el empuje del motor se multiplica por esta fracción.
	REVERSE_DRIVE_FRACTION = 0.4,
	FINAL_DRIVE = 5.9,
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

	-- Tracción: fracción de la fuerza que va al eje trasero.
	REAR_BIAS = 0,

	-- Frenos.
	-- El neumático la recorta.
	BRAKE_DECELERATION = 55,
	BRAKE_FRONT_BIAS = 0.6,
	HANDBRAKE_FORCE_PER_LOAD = 0.4,

	-- Dirección.
	STEER_MAX_LOW_SPEED_DEGREES = 36,
	STEER_MAX_HIGH_SPEED_DEGREES = 18,
	-- Al derrapar, la dirección permite este margen sobre el ángulo de deriva (hasta el máximo de baja velocidad).
	DRIFT_STEER_MARGIN_DEGREES = 10,
	STEER_LOW_SPEED = 55,
	STEER_HIGH_SPEED = 80,
	-- Ángulo máximo de dirección en marcha atrás.
	STEER_MAX_REVERSE_DEGREES = 15,

	-- Asistencias (COUNTER_STEER_STRENGTH en 0 apaga el contravolante).
	COUNTER_STEER_STRENGTH = 1,
	COUNTER_STEER_MAX_DEGREES = 15,
	COUNTER_STEER_MIN_SPEED = 10,

	-- Feedback.
	DRIFT_ANGLE_THRESHOLD_DEGREES = 10,
	DRIFT_MIN_SPEED = 15,

	-- Magnitud por debajo de la cual el producto vectorial que da el "arriba" del contacto es degenerado.
	CONTACT_PLANE_DEGENERATE_THRESHOLD = 1e-4,

	MAX_STEP_SECONDS = 1 / 15,
})
