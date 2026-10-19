--!strict
-- Ficha del Fiat 147: lo que es del auto y no del motor ni de la caja. Solo datos.
-- Los valores iniciales se ajustan después en las pruebas de juego (WP-3).
local SpecTypes = require("../SpecTypes")

local car: SpecTypes.CarSpec = {
	-- Orden fijo: FL, FR, RL, RR.
	WHEELS = table.freeze({
		table.freeze({ name = "FL", offset = vector.create(-2.34, -1, -2.88), isFront = true, isLeft = true }),
		table.freeze({ name = "FR", offset = vector.create(2.34, -1, -2.88), isFront = true, isLeft = false }),
		table.freeze({ name = "RL", offset = vector.create(-2.34, -1, 3.06), isFront = false, isLeft = true }),
		table.freeze({ name = "RR", offset = vector.create(2.34, -1, 3.06), isFront = false, isLeft = false }),
	}),
	WHEEL_RADIUS_STUDS = 0.81,

	-- Peso. El auto armado pesa 84, como hoy: 70 de chasis y 14 de motor (el 17 % del total, lo habitual en un auto
	-- chico).
	CHASSIS_MASS = 70,
	-- Sobre el eje delantero (z = −2,88), un poco adelante, donde va el motor de un 147.
	ENGINE_POSITION_Z = -3,
	-- Del chasis solo. Con el motor de 14 en z = −3 el auto armado da 0,7 (CP-6): el centro de masa del conjunto cae en
	-- z = 3,06 − 0,7 · 5,94 = −1,098, el del chasis solo en (84 · −1,098 + 14 · 3) / 70 = −0,7176, y eso es
	-- (3,06 + 0,7176) / 5,94 = 0,63595959… del paso entre ejes.
	FRONT_WEIGHT_FRACTION = 0.6359595959596,
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

	-- Resistencia del aire: desaceleración = esto · v² (studs/s² por (studs/s)²).
	AIR_DRAG_PER_SPEED_SQUARED = 0.001,

	-- Frenos.
	-- El neumático la recorta.
	BRAKE_DECELERATION = 55,
	BRAKE_FRONT_BIAS = 0.6,
	HANDBRAKE_FORCE_PER_LOAD = 0.4,
	-- Freno de mano que sostiene (WP-17): casi quieto y sin derrapar frena las cuatro ruedas con esta fuerza por unidad
	-- de carga (alcanza para la pendiente más empinada que el auto sube) y se libera al soltar el freno de mano.
	HANDBRAKE_HOLD_FORCE_PER_LOAD = 0.6,
	-- Velocidad del chasis (studs/s) y deriva máxima (grados) por debajo de las cuales el freno de mano sostiene.
	HANDBRAKE_HOLD_SPEED = 3,
	HANDBRAKE_HOLD_MAX_DRIFT_DEGREES = 10,

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

	-- Daño (WP-15): `DamageEffects` los cambia; con los valores por defecto no tienen ningún efecto.
	-- Multiplicador del agarre de cada rueda, en el orden FL, FR, RL, RR.
	WHEEL_GRIP_MULTIPLIERS = table.freeze({ 1, 1, 1, 1 }),
	-- Desvío fijo de la dirección, en grados (positivo a la derecha).
	STEER_OFFSET_DEGREES = 0,
}

return table.freeze(car)
