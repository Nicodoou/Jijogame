--!strict
-- Valores de ajuste de la cámara de seguimiento. Solo datos: nada de lógica.
-- Los iniciales se ajustan después en las pruebas de juego (WP-3).

return table.freeze({
	-- Dónde se para la cámara respecto del punto que sigue, detrás y arriba del auto.
	DISTANCE_STUDS = 18,
	HEIGHT_STUDS = 6,
	-- Punto al que mira, adelante y arriba del auto.
	LOOK_AHEAD_STUDS = 6,
	LOOK_HEIGHT_STUDS = 2,

	YAW_FOLLOW_RATE = 5,
	-- Cuánto pesa la dirección de la velocidad contra la del frente del auto al derrapar.
	VELOCITY_HEADING_WEIGHT = 0.6,
	-- Debajo de esta velocidad horizontal la cámara sigue la orientación del auto.
	MIN_SPEED_FOR_VELOCITY_HEADING = 10,
	-- Seguimiento de la posición: absorbe los saltos de la suspensión.
	POSITION_FOLLOW_RATE = 12,
	-- Proyección horizontal del frente por debajo de la cual el auto se considera vertical (volcado).
	MIN_HORIZONTAL_FORWARD = 1e-3,

	MAX_STEP_SECONDS = 0.1,
})
