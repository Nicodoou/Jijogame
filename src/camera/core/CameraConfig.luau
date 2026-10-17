--!strict
-- Valores de ajuste de la cámara en primera persona. Solo datos: nada de lógica.
-- Los iniciales se ajustan después en las pruebas de juego. 1 g equivale a 196,2 studs/s².

return table.freeze({
	FIELD_OF_VIEW_DEGREES = 70,

	-- Horizonte: 1 = siempre a nivel (solo sigue el yaw del auto), 0 = pegado al chasis.
	HORIZON_LOCK = 1,
	-- Multiplicadores (0 a 1) del balanceo, la inclinación y la vibración de la cabeza.
	HEAD_SWAY = 0.5,
	HEAD_TILT = 0.5,
	HEAD_VIBRATION = 0.3,
	-- Mirar hacia donde va el auto: fracción (0 a 1) del ángulo entre el frente y la velocidad, con tope, por encima de
	-- una velocidad mínima (studs/s). LOOK_INTO_SMOOTH_RATE suaviza el giro (1/s).
	LOOK_INTO_VELOCITY = 0.3,
	LOOK_INTO_VELOCITY_MAX_DEGREES = 25,
	LOOK_INTO_VELOCITY_MIN_SPEED = 10,
	LOOK_INTO_SMOOTH_RATE = 5,
	-- Lo mismo hacia el punto del camino que viene.
	LOOK_INTO_CURVE = 0,
	LOOK_INTO_CURVE_MAX_DEGREES = 25,
	-- Suavizado del yaw de la cámara respecto del auto: frecuencia del resorte (1/s; 0 = sin suavizado, muy alta casi
	-- igual) y retraso máximo permitido en grados.
	CAMERA_YAW_SMOOTHING = 6,
	CAMERA_YAW_MAX_LAG_DEGREES = 15,

	-- Mirar alrededor: límites de la cabeza respecto del frente del auto.
	LOOK_MAX_YAW_DEGREES = 100,
	LOOK_MAX_PITCH_DEGREES = 35,
	-- Qué tan rápido vuelve al frente sin entrada (exponencial, 1/s): llega al 95% en unos 0,75 s.
	LOOK_RETURN_RATE = 4,

	-- Resorte de la cabeza (rad/s y razón de amortiguación). Casi crítico: vuelve sin rebotar de más.
	HEAD_SPRING_FREQUENCY = 8,
	HEAD_SPRING_DAMPING_RATIO = 0.85,
	-- Balanceo: studs de desplazamiento por stud/s² de aceleración, y su tope. A 1 g son unos 0,25 studs.
	HEAD_SWAY_PER_ACCELERATION = 0.0013,
	HEAD_SWAY_MAX_STUDS = 0.3,
	-- Inclinación (roll y pitch): grados por stud/s² de aceleración, y su tope. A 1 g son unos 3 grados.
	HEAD_TILT_PER_ACCELERATION = 0.015,
	HEAD_TILT_MAX_DEGREES = 5,
	-- Vibración vertical según la distancia recorrida: crece lineal con la velocidad hasta la de referencia.
	HEAD_VIBRATION_AMPLITUDE_STUDS = 0.015,
	HEAD_VIBRATION_FULL_SPEED = 100,
	HEAD_VIBRATION_RADIANS_PER_STUD = 1.1,
	-- Segunda onda de la vibración, a otra frecuencia, para que no se sienta como un zumbido puro.
	HEAD_VIBRATION_SECOND_WAVE_RATIO = 2.3,

	MAX_STEP_SECONDS = 0.1,
})
