--!strict
-- Valores de ajuste de la ruta y su superficie. Solo datos: nada de lógica.
-- Los iniciales son los de la configuración G del prototipo (exp/ruta-guia) y se afinan jugando (WP-5).

return table.freeze({
	-- Ancho del camino (WP-16): 20 studs. El auto mide unos 6, así que quedan unos 7 por lado. La banquina suma 4 por lado.
	ROAD_WIDTH_STUDS = 20,
	SHOULDER_WIDTH_STUDS = 4,
	-- Color del camino (material Mud del Terrain, que el adaptador pinta): un marrón oscuro de tierra de rally.
	-- Se calibra a ojo en Studio.
	ROAD_COLOR_RGB = table.freeze({ 86, 64, 44 }),
	-- Tiene que ser mayor que la mitad del ancho más la banquina, o el eje cruzaría el borde de la propia curva.
	MIN_CURVE_RADIUS_STUDS = 60,
	-- Se confirma con el experimento de rampas de 15° y 20° antes de subirla más.
	MAX_SLOPE_DEGREES = 20,
	INTEGRATION_STEP_STUDS = 2,
	SEGMENT_LENGTH_STUDS = 256,

	START_POSITION = vector.create(0, 50, 0),
	START_HEADING_DEGREES = 0,
	-- La ruta nunca sale de este círculo alrededor del origen.
	AREA_RADIUS_STUDS = 8000,
	-- Desde este margen respecto del borde, la guía se inclina hacia el centro.
	AREA_STEERING_MARGIN_STUDS = 2000,

	-- Guía grande: puntos de paso sorteados con la semilla.
	GUIDE_STEP_STUDS = 500,
	GUIDE_MAX_TURN_DEGREES = 100,
	GUIDE_MIN_TURN_DEGREES = 50,
	GUIDE_TURN_PERSISTENCE = 0.97,
	-- Cambios de rumbo que se prueban, en orden fijo, cuando el sorteado no sirve (cada uno a la derecha y a la izquierda).
	-- Sin 120°: deja esquinas demasiado cerradas.
	GUIDE_ALTERNATIVE_TURNS_DEGREES = table.freeze({ 30, 60, 90 }),
	-- Tiene que ser >= LIVE_CLEARANCE_STUDS + 2 * LOCAL_DEVIATION_MAX_STUDS + un margen (200 + 700 + 100).
	GUIDE_CLEARANCE_STUDS = 400,
	-- A cuántos studs por delante de su posición sobre la guía apunta la ruta.
	GUIDE_TARGET_AHEAD_STUDS = 350,
	-- Un punto de paso nunca queda más cerca que esto del borde del área.
	GUIDE_EDGE_MARGIN_STUDS = 1000,
	-- Distancia más allá del margen de dirección en la que el tirón al centro llega al máximo.
	GUIDE_PULL_RANGE_STUDS = 1000,
	-- La guía va por lo menos tantos puntos delante de lo que usa la ruta, para que el retroceso no toque lo usado.
	GUIDE_AHEAD_WAYPOINTS = 4,
	-- Cada tantas fallas seguidas, la guía retrocede un punto más.
	GUIDE_BACKTRACK_FAILS_PER_EXTRA_WAYPOINT = 8,
	-- Tope de intentos sin avanzar antes de dar la guía por encerrada.
	GUIDE_FAIL_LIMIT = 600,

	-- Ruta local: el "túnel" alrededor de la guía y el rumbo relativo a ella.
	LOCAL_DEVIATION_MAX_STUDS = 170,
	TURN_BACK_EXTRA_DEVIATION_STUDS = 250,
	MAX_RELATIVE_HEADING_DEGREES = 120,

	-- Anti-cruce: dos muestras cuyo arcLength difiere en más de LIVE_NEIGHBOR_ARC_STUDS y hasta LIVE_LOOKBACK_STUDS
	-- tienen que estar a LIVE_CLEARANCE_STUDS o más en el plano. LIVE_CLEARANCE_STUDS tiene que ser mayor que el
	-- ancho total más las dos banquinas.
	LIVE_CLEARANCE_STUDS = 60,
	-- Mayor que lo más largo que se curva sobre sí mismo: una horquilla doble (~780 studs) y un círculo (~380).
	LIVE_NEIGHBOR_ARC_STUDS = 1200,
	-- Entre este largo (más que un círculo de radio mínimo, ~380) y LIVE_NEIGHBOR_ARC_STUDS la ruta no puede cruzarse: tiene
	-- que quedar a LIVE_NEAR_CLEARANCE_STUDS (más que el ancho con las dos banquinas) o más de sí misma.
	LIVE_NEAR_ARC_STUDS = 400,
	-- Tiene que ser mayor que ROAD_WIDTH_STUDS + 2 * SHOULDER_WIDTH_STUDS (hoy 20 + 8 = 28) y dejar entre banquinas el mismo
	-- margen de 6 studs que antes (con 16 de ancho eran 30 contra 24).
	LIVE_NEAR_CLEARANCE_STUDS = 34,
	-- El WP del terreno tiene que liberar todo lo que quede más atrás.
	LIVE_LOOKBACK_STUDS = 4000,
	-- Regla de altura (WP-9): dos pasadas no vecinas a menos de este radio (en el plano) no pueden estar a más altura de la que el
	-- terreno salva con TERRAIN_MAX_SLOPE_DEGREES en el espacio que queda entre sus banquinas. Igual que el alcance de la ruta sobre
	-- el terreno (TERRAIN_ROAD_REACH_STUDS, WP-6).
	LIVE_HEIGHT_RULE_RADIUS_STUDS = 136,
	-- Se exige una pendiente menor que la máxima en este margen: el terreno mezcla las alturas de varias pasadas y no es una rampa recta.
	LIVE_HEIGHT_RULE_MARGIN_DEGREES = 1,
	-- Pendiente máxima que se busca en el terreno entre pasadas (la usa la regla de altura; el WP-6 la usa para el terreno).
	TERRAIN_MAX_SLOPE_DEGREES = 62,
	-- Memoria extra para el retroceso. Tiene que ser >= ROAD_BACKTRACK_MAX_PIECES * la pieza más larga.
	LIVE_BACKTRACK_MEMORY_STUDS = 13000,

	-- Retroceso de la ruta.
	ROAD_BACKTRACK_MAX_PIECES = 16,
	-- Cada tantas fallas seguidas, la ruta retrocede una pieza más.
	ROAD_BACKTRACK_FAILS_PER_EXTRA_PIECE = 6,
	-- Tope de fallas seguidas (sin pasar del punto más lejano ya logrado) antes de dar la ruta por encerrada.
	ROAD_FAIL_LIMIT = 600,

	-- Cómo elige el secuenciador la próxima pieza.
	-- Si la guía queda a más de este ángulo del rumbo, solo se sortean curvas simples.
	SEQUENCER_CURVES_ONLY_ERROR_DEGREES = 45,
	-- Error de rumbo a partir del cual el sesgo hacia la guía es máximo.
	SEQUENCER_FULL_PULL_ERROR_DEGREES = 40,
	-- Probabilidad de girar hacia la guía con error cero, y cuánto sube con el error: 0,5 + 0,45 = 0,95 como máximo.
	SEQUENCER_TOWARD_BASE_PROBABILITY = 0.5,
	SEQUENCER_TOWARD_PULL_GAIN = 0.45,
	-- Con un error mayor que este ángulo, la pieza siempre gira hacia la guía.
	SEQUENCER_ALWAYS_TOWARD_ERROR_DEGREES = 90,
	-- Desde esta fracción del túnel, la probabilidad de girar hacia la guía sube al mínimo indicado.
	SEQUENCER_OFF_CENTER_FRACTION = 0.6,
	SEQUENCER_OFF_CENTER_MIN_PROBABILITY = 0.95,
	-- Las piezas que dan la vuelta (horquilla doble y U) solo se sortean mientras la ruta esté dentro de esta fracción del túnel.
	SEQUENCER_TURN_BACK_MAX_OFFSET_FRACTION = 0.8,
	-- Salida de emergencia: si el rumbo al objetivo difiere más que esto, tiene que caber un giro cerrado.
	ESCAPE_MIN_HEADING_ERROR_DEGREES = 3,
	-- Fracción de cada giro cerrado que se usa para subir la curvatura (y otra igual para bajarla).
	TIGHT_TURN_RAMP_FRACTION = 0.25,
	-- Recta corta de la última alternativa, en pasos de integración.
	EMERGENCY_STRAIGHT_STEPS = 20,
	-- Al acortar una pieza se queda con esta fracción de cada lóbulo, con un mínimo de pasos de integración.
	SHORTENED_PIECE_FRACTION = 0.5,
	MIN_SHORTENED_LOBE_STEPS = 4,
	-- Último recurso: giros de radio mínimo hacia la guía, del más largo al más corto, en pasos de integración.
	LAST_RESORT_LOBE_STEPS = table.freeze({ 60, 40, 24, 12 }),

	-- Perfil de cerros (HillProfile).
	HILL_BASE_HEIGHT_STUDS = 50,
	HILL_AMPLITUDE_STUDS = 50,
	HILL_WAVELENGTH_STUDS = 200,
	HILL_OCTAVES = 3,
	-- La ruta nunca sale de esta franja de alturas.
	HILL_MIN_HEIGHT_STUDS = -150,
	HILL_MAX_HEIGHT_STUDS = 250,
	HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP = 1.5,
	-- A cuántos studs por delante apunta la altura objetivo: cuanto más, más suave el seguimiento.
	HILL_LOOKAHEAD_STUDS = 50,
	-- Una octava tiene la amplitud y la longitud de onda de la anterior multiplicadas por estos factores.
	HILL_OCTAVE_AMPLITUDE_FACTOR = 0.5,
	HILL_OCTAVE_WAVELENGTH_FACTOR = 0.5,
	HILL_NOISE_OFFSET_RANGE = 10000,
	-- Dirección en que se recorre el plano (x, y) del ruido: math.noise repite cada 256 en cada eje, así que avanzar por un solo
	-- eje repetía el perfil cada 256 longitudes de onda (#57). En diagonal, la repetición exacta no existe (la tangente es irracional).
	HILL_NOISE_DIRECTION_DEGREES = 20,

	-- Manchones de barro: ruido con semilla, solo más allá de la banquina. Hoy ningún bioma los usa (el campo es solo pasto);
	-- se retoman con el issue #78 (barro en bordes y curvas).
	MUD_NOISE_SCALE_PER_STUD = 0.01,
	MUD_NOISE_THRESHOLD = 0.2,
	MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS = 6,
	MUD_NOISE_OFFSET_RANGE = 10000,

	-- Clima (ClimateField): relieve, humedad y ruido de temperatura, cada uno con octavas de math.noise.
	-- Si cambia algo de esta sección hay que volver a generar QuantileTables (tools/climate/GenerateQuantiles.luau).
	CLIMATE_OCTAVES = 3,
	CLIMATE_OCTAVE_AMPLITUDE_FACTOR = 0.5,
	CLIMATE_OCTAVE_WAVELENGTH_FACTOR = 0.5,
	-- Longitud de onda de la primera octava de cada mapa.
	CLIMATE_RELIEF_WAVELENGTH_STUDS = 4000,
	CLIMATE_HUMIDITY_WAVELENGTH_STUDS = 3500,
	CLIMATE_TEMPERATURE_WAVELENGTH_STUDS = 5000,
	-- El z de cada mapa no es entero: con z entero el ruido vale 0 en toda la grilla.
	CLIMATE_RELIEF_NOISE_Z = 0.31,
	CLIMATE_HUMIDITY_NOISE_Z = 0.57,
	CLIMATE_TEMPERATURE_NOISE_Z = 0.83,
	CLIMATE_NOISE_OFFSET_RANGE = 10000,
	-- Temperatura = ruido de temperatura - factor * relieve (crudos): lo alto es más frío.
	CLIMATE_TEMPERATURE_RELIEF_FACTOR = 0.5,
	CLIMATE_GRID_STEP_STUDS = 16,
	-- Diferencia máxima en u entre la grilla interpolada y el muestreo directo.
	CLIMATE_GRID_MAX_ERROR = 0.002,

	-- Pesos de bioma: w = max(0, 1 - d / R) ^ k, con d la distancia en u del clima a la caja de la ficha.
	BIOME_TRANSITION_RADIUS = 0.15,
	BIOME_TRANSITION_EXPONENT = 2,
	-- Los pesos menores a este se descartan antes de normalizar.
	BIOME_WEIGHT_CUTOFF = 0.05,
	-- Tamaño de los manchones con los que se alternan los materiales entre biomas (de 12 a 24 studs).
	BIOME_MATERIAL_PATCH_STUDS = 24,
	BIOME_PATCH_NOISE_OFFSET_RANGE = 10000,
	-- Fracción máxima de material puente, que se da con los dos biomas más pesados empatados.
	BIOME_BRIDGE_MAX_SHARE = 0.5,

	-- Terreno (TerrainHeightField y VoxelChunkBuilder).
	-- Un chunk son CHUNK_SIZE_STUDS / TERRAIN_VOXEL_STUDS vóxeles por lado.
	CHUNK_SIZE_STUDS = 128,
	-- Tamaño del vóxel del Terrain de Roblox (valor fijo del motor).
	TERRAIN_VOXEL_STUDS = 4,
	-- Medido en Studio: la superficie queda tantos studs más arriba de la que dice la ocupación.
	TERRAIN_SURFACE_OFFSET_STUDS = 2,
	-- Cuánto Terrain sólido queda bajo la superficie más baja de cada chunk.
	TERRAIN_DEPTH_STUDS = 12,
	-- Espesor de la capa de superficie: el material de la superficie ocupa también los vóxeles de abajo hasta esta
	-- profundidad. En pendiente el vóxel de arriba queda casi vacío en cada escalón y Roblox muestra el de abajo.
	TERRAIN_TOP_LAYER_STUDS = 8,
	-- Ancho en el que el terreno pasa de plano (al lado de la banquina) a las colinas completas.
	TERRAIN_BLEND_WIDTH_STUDS = 32,
	-- Colinas: dos octavas de math.noise relativas a la altura de la ruta. La amplitud y la rugosidad se multiplican por las de los biomas.
	TERRAIN_HILL_AMPLITUDE_STUDS = 12,
	TERRAIN_HILL_WAVELENGTH_STUDS = 160,
	TERRAIN_HILL_FINE_WAVELENGTH_STUDS = 48,
	-- Amplitud de la octava fina respecto de la gruesa, con rugosidad 1.
	TERRAIN_HILL_FINE_AMPLITUDE_RATIO = 0.25,
	TERRAIN_HILL_NOISE_OFFSET_RANGE = 10000,
	-- Se suma a la semilla para que el ruido de las colinas no repita el de la ruta ni el del clima.
	TERRAIN_NOISE_SEED_SALT = 7919,
	-- Alcance de cada pasada de la ruta sobre la altura del terreno: más allá no pesa.
	TERRAIN_ROAD_REACH_STUDS = 192,
	-- Desde esta distancia a la banquina la altura base se desvanece hacia la altura ambiente (HILL_BASE_HEIGHT_STUDS), hasta el alcance.
	TERRAIN_AMBIENT_FADE_START_STUDS = 60,
	-- Pasos de integración por bloque de ruta: el bloque es lo bastante corto (menos de 180 grados de arco) para que la
	-- distancia al eje tenga un único mínimo. Tiene que dividir los pasos por tramo.
	TERRAIN_ROAD_BLOCK_STEPS = 32,
	-- Más allá de este alcance sobre la banquina, la altura mide cada bloque contra su cuerda y no su arco, en este ancho de mezcla.
	TERRAIN_CHORD_SMOOTH_START_STUDS = 10,
	TERRAIN_CHORD_SMOOTH_SPAN_STUDS = 20,

	-- Planificación del mundo (WorldPlanner).
	ROUTE_AHEAD_STUDS = 2000,
	-- Corredor de terreno alrededor de la ruta viva, y cuánto más ancho es el que se conserva (histéresis).
	TERRAIN_CORRIDOR_HALF_WIDTH_STUDS = 160,
	TERRAIN_CORRIDOR_KEEP_EXTRA_STUDS = 64,
	-- Cada cuántos studs de ruta se toma un punto para trazar el corredor.
	TERRAIN_CORRIDOR_SAMPLE_STUDS = 32,
	-- Cuánto terreno se escribe por detrás del auto (la ruta viva llega más atrás: LIVE_LOOKBACK_STUDS), y su histéresis.
	TERRAIN_BEHIND_STUDS = 600,
	TERRAIN_BEHIND_KEEP_EXTRA_STUDS = 256,
	-- No se escribe terreno en los últimos studs de ruta generada: ahí todavía falta la ruta que entra en el alcance de la altura.
	TERRAIN_FRONTIER_MARGIN_STUDS = 512,
	-- Cuánto se mueve el auto antes de volver a planificar.
	TERRAIN_PLAN_REFRESH_STUDS = 32,
	TERRAIN_CHUNK_KEY_STRIDE = 1048576,
	WORLD_READY_RADIUS_STUDS = 64,
	-- Dónde aparece el auto sobre la ruta.
	SPAWN_ARC_LENGTH_STUDS = 16,

	-- Presupuesto de trabajo por frame (WorkBudget).
	WORK_BUDGET_MS_PER_FRAME = 4,
	-- En cada paso, la estimación del costo del paso más caro baja por este factor: un pico no frena el trabajo para siempre.
	WORK_BUDGET_STEP_ESTIMATE_DECAY = 0.98,
	-- Tope de pasos por llamada: si el reloj no avanza (o los pasos no cuestan nada) no se queda en el ciclo.
	WORK_BUDGET_MAX_STEPS_PER_FRAME = 512,

	-- Consultas de la ruta (RoadQuery).
	ROAD_QUERY_GRID_CELL_STUDS = 64,
	ROAD_QUERY_GRID_KEY_STRIDE = 1048576,
	ROAD_QUERY_MAX_DISTANCE_STUDS = 1000,
	ROAD_QUERY_CURSOR_WINDOW_SAMPLES = 16,
})
