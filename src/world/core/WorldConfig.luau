--!strict
-- Valores de ajuste de la ruta y su superficie. Solo datos: nada de lógica.
-- Los iniciales se ajustan después en las pruebas de juego (WP-2).

return table.freeze({
	ROAD_WIDTH_STUDS = 24,
	SHOULDER_WIDTH_STUDS = 4,
	-- Tiene que ser mayor que la mitad del ancho más la banquina, o el eje cruzaría el borde de la propia curva.
	MIN_CURVE_RADIUS_STUDS = 60,
	MAX_SLOPE_DEGREES = 8,
	INTEGRATION_STEP_STUDS = 2,
	SEGMENT_LENGTH_STUDS = 256,

	-- El mundo arranca en -120.000 studs y no se recentra (docs/decisiones.md).
	START_POSITION = vector.create(-120000, 50, 0),
	MEAN_HEADING = vector.create(1, 0, 0),
	MAX_HEADING_DEVIATION_DEGREES = 60,
	MAX_LATERAL_DRIFT_STUDS = 2000,

	-- Reversión a la media del secuenciador.
	-- Desvío lateral al que el rumbo buscado llega a su máximo.
	STEERING_DRIFT_SCALE_STUDS = 800,
	-- Fracción del desvío máximo de rumbo que se busca cuando el desvío lateral es el máximo de la escala.
	STEERING_GOAL_HEADING_FRACTION = 0.6,
	-- Fracción del desvío máximo de rumbo a partir de la cual el empuje hacia la media es total.
	STEERING_ERROR_SCALE_FRACTION = 0.5,
	-- Qué tan sesgado puede quedar el sorteo del sentido de la curva (0 = parejo, 1 = siempre hacia la media).
	STEERING_STRENGTH = 0.85,
	-- Fracción del desvío lateral máximo desde la cual la curva siempre gira hacia la media.
	STEERING_FORCED_DRIFT_FRACTION = 0.3,
	-- Colchón para que el rumbo planeado nunca roce el límite por errores de redondeo.
	HEADING_PLANNING_MARGIN_DEGREES = 0.5,
	-- Si para respetar el corredor la curva quedaría con menos de esta fracción de su curvatura, se prueba el otro sentido.
	MIN_CAPPED_PEAK_FRACTION = 0.4,

	-- Manchones de barro: ruido con semilla, solo más allá de la banquina.
	MUD_NOISE_SCALE_PER_STUD = 0.01,
	MUD_NOISE_THRESHOLD = 0.2,
	MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS = 6,
	MUD_NOISE_OFFSET_RANGE = 10000,

	-- Consultas de la ruta (RoadQuery).
	ROAD_QUERY_GRID_CELL_STUDS = 64,
	ROAD_QUERY_GRID_KEY_STRIDE = 1048576,
	ROAD_QUERY_MAX_DISTANCE_STUDS = 1000,
	ROAD_QUERY_CURSOR_WINDOW_SAMPLES = 16,
})
