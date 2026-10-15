--!strict
-- Valores de ajuste del input. Solo datos: nada de lógica.
-- Los iniciales se ajustan después en las pruebas de juego (WP-3).

return table.freeze({
	-- Tiempo que tarda el teclado en llevar un eje de 0 a 1 (subida) y de 1 a 0 (retorno).
	STEER_RISE_SECONDS = 0.25,
	STEER_RETURN_SECONDS = 0.15,
	THROTTLE_RISE_SECONDS = 0.3,
	THROTTLE_RETURN_SECONDS = 0.2,
	BRAKE_RISE_SECONDS = 0.15,
	BRAKE_RETURN_SECONDS = 0.1,

	GAMEPAD_DEADZONE = 0.12,
	GAMEPAD_STEER_EXPONENT = 1.5,
	GAMEPAD_PEDAL_EXPONENT = 1.0,

	MAX_STEP_SECONDS = 0.1,
})
