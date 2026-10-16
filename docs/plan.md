# Plan del proyecto

Lo que está en curso, lo que sigue, lo que queda para después del MVP y las preguntas que todavía no tienen respuesta. Cada agente mantiene la sección de su área y la actualiza al cerrar cada sesión (`docs/reglas-de-trabajo.md`, "El plan y las preguntas abiertas"). Lo que ya se decidió está en `docs/decisiones.md`; esto es lo que todavía no.

## Conducción (Agente A, con Nico)

### En curso
- **Primera vuelta por las calles reales:** Nico maneja el auto sobre el terreno del Agente B (PR #70) para encontrar problemas de la combinación.
- **Modelo del auto (#48):** Nico lo modela en Blockbench. Falta que la importación respete las piezas y su posición, y decidir si la física se adapta a la geometría del modelo.

### Próximo
1. **Retención en pendiente:** sin input, el auto rueda cuesta abajo. La decisión de diseño está pendiente con Nico (auto hold, un freno de mano más fuerte o las dos).
2. **Freno motor en la automática:** aprobado por Nico. Es un WP chico.
3. **Hitbox modular para el MVP:**
   - piezas exteriores con colisión y piezas interiores que se dañan a través de ellas;
   - un editor en Studio para ubicarlas.

   Primero hay que cerrar con Nico la lista de piezas y qué hace el daño. Después va un diseño completo (investigación, opciones y arquitectura).
4. **Reset (RC-12):** devolver el auto a la ruta, con el último punto válido y `GetNearestRoadPoint` (#35).
5. **Feedback (CP-13 a CP-16):** sonido del motor y de los neumáticos, polvo, marcas y HUD (el HUD cuenta solo el avance continuo, sin atajos).
6. **Bug #64:** inestabilidad por debajo de unos 25 FPS.

### Después del MVP
- **Motor por potencia, embrague, caja manual y acelerador como mariposa (#63).**
- **Autos y piezas intercambiables:** el auto como composición de fichas de datos (`EngineSpec`, `GearboxSpec`, `TireSpec`, `SuspensionSpec`, `ChassisSpec`, modelo visual), con un ensamblador puro que valida y produce la configuración del simulador, y el builder del modelo de Roblox. **Las bases se dejan asentadas en el MVP:** la hitbox modular nace como `ChassisSpec`, y los WPs nuevos no mezclan valores de piezas distintas.
- **Temperatura de neumáticos y frenos:** idea de Nico, descartada para el MVP.

### Preguntas de investigación abiertas
- **`PhysicsSteppingMethod`:** ¿`Fixed` contra `Adaptive`? ¿Cuál se siente mejor y es más estable? Prueba manual en Studio. Todavía no se confirmó si el valor del repo se aplica en vivo.
- **Costo en un celular de gama media:** cuánto cuestan los 4 rayos y el núcleo por frame. Prueba manual con un teléfono.
- **Estabilidad con FPS bajos (#64):** ¿cómo mantener el auto estable por debajo de 25 FPS? Hay que comparar subpasos del núcleo, un tope que considere la inercia de giro y un límite de `dt`. Primero con el investigador; después, experimento en el CLI.
- **Daño y colisiones por pieza:** ¿cómo detecta Roblox qué pieza chocó y con qué fuerza (`Touched`, consultas espaciales o las fuerzas de contacto)? ¿Cuánto cuesta con 20 o más hitboxes por auto? Primero el investigador y después un experimento en Studio.
- **Importación desde Blockbench:** ¿qué formato y qué opciones de Import 3D conservan las piezas separadas con su posición, sin armar un rig? Experimento con el modelo de Nico.
- **Geometría del auto:** ¿la física se adapta al modelo (ejes a 5,9 y ruedas de 0,81) o el modelo a la física? Hay que medir cómo cambia el manejo con una distancia entre ejes más corta. Prueba de juego con `Cfg_`, cuando se puedan sobrescribir tablas.

## Calles infinitas (Agente B, con Beni)

### En curso
- **Terreno real (WP-6, PR #70):** el auto de A ya anda sobre nuestras rutas. Nico lo manejó y aprobó la prueba, y A aprobó lo técnico. Falta la aprobación de Beni para mergear. En Studio apareció un bug, la ruta quedaba enterrada bajo el terreno con frames caros; ya está arreglado y registrado en `docs/bugs/2026-10-16-ruta-enterrada.md`.
- **Camino de ripio claro (WP-11, #73, PR #74):** el camino casi no se distinguía del terreno, y Beni eligió `Limestone` para el camino y `Ground` para la banquina. El WP espera aprobación y el código va después del #70.

### Próximo
1. **Código del WP-11:** el material del camino y de la banquina en `VoxelChunkBuilder`.
2. **Lomas a ojo:** con el arreglo del #57 las lomas grandes salen menos seguido (las ventanas de 2 km con más de 60 studs de desnivel bajaron del 37 % al 7 %). Se ajusta `HILL_AMPLITUDE_STUDS` manejando con Beni, sin pasar los 20° de pendiente máxima.
3. **Deuda de documentación:** `terreno.md` y `ruta.md` todavía no describen el campo de alturas ni la ventana de ruta viva que salieron del WP-6.
4. **Decorado del bosque:** árboles y rocas al costado de la ruta. Va con diseño completo (investigación, opciones y arquitectura): instancing, colisión por distancia y costo por frame.
5. **Vista previa de la ruta (`VistaPreviaRuta`):** adaptarla o retirarla, ahora que el terreno real la reemplaza.

### Después del MVP
- **Varios biomas:** la infraestructura del WP-8 ya los soporta (catálogo, clima y mezcla). El MVP lleva solo el bosque (#56).
- **Malla visual de la ruta (opción T2 de `terreno.md`):** borde prolijo y textura propia encima del Terrain, si el borde serruchado de 4 studs molesta.
- **Saltos en la ruta (#37):** quedaron para que los decida Beni, junto con A (pendiente máxima y radio vertical de las crestas).

### Preguntas de investigación abiertas
- **Costo del terreno en un celular de gama media:** ¿cuánto cuestan `WriteVoxels` y la generación por frame, y cuánto congela el arranque síncrono de `WorldClient.new`? Prueba manual con un teléfono.
- **Tirones al generar:** en el CLI, el peor paso de `generateStep` está entre 2,9 y 3,7 ms, y en Studio se vio un pico de 46 ms sin causa clara. Se mide con el MicroProfiler (etiqueta `WorldClient.step`) manejando de verdad.
- **CI al límite:** `check-all` tarda unos 60 s y el WP pide menos de 60. ¿Se parten las pruebas largas o se paraleliza? Experimento en una rama `exp/`.
- **Legibilidad del camino:** ¿alcanza el ripio claro, o hace falta además una banquina más marcada o pasto alto en el borde? Prueba de juego después del WP-11.
- **Cuánta loma se siente rally:** amplitud y largo de subida que se disfruten sin que el auto se quede en las cuestas (ver el kickdown de A). Prueba de juego con Beni y Nico.
