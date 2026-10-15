# WP-5 — Rediseño de la ruta de rally: trazado libre en un área, anti-cruce y perfil de cerros

**Issue:** #37
**Requerimientos:** RC-1, RC-4, RC-5, RC-6, RC-7 (sobre el núcleo del WP-2)
**Diseño:** `docs/disenos/ruta.md`, sección "Revisión de la arquitectura por la ruta de rally (#37)"
**Responsable:** Agente B
**Depende de:** WP-2 (en `main`)

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (existente)
- **Modelo:** Sonnet. El WP fija los módulos, las garantías y las pruebas. Las dudas de diseño vuelven al orquestador.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, con los criterios de aceptación uno por uno y la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/ruta.md` completo, sobre todo "Arquitectura" y "Revisión de la arquitectura por la ruta de rally (#37)";
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5);
  - `docs/nombres.md`;
  - todo `src/world/core/` y `tests/world/` (es código del WP-2 que se modifica);
  - `docs/guia-de-desarrollo.md` (cómo correr los chequeos).
- **Decisiones que aplican** (`docs/decisiones.md`):
  - "Ruta de rally: trazado libre en un área acotada, perfil de cerros y 16 studs de ancho" (reemplaza a "El mundo arranca en −120.000 studs, sin recentrar");
  - "Ruta y terreno: piezas con curvatura, todo Terrain, generado en el cliente";
  - "Política de pruebas, cobertura y estructura de `src/`".
- **Supuestos vigentes:**
  - `math.noise`, `math.sin`, `math.cos` y `math.tan` dan lo mismo en el CLI y en Roblox (verificado con el hash del WP-2).
  - Los componentes de `vector` van en minúscula (`.x`), y `vector` es float32: cerca del origen la precisión sobra.
  - Rokit está instalado: antes de cada comando, `export PATH="$HOME/.rokit/bin:$PATH"`, siempre desde la raíz del repo.
- **De la conversación con Beni:** probó la ruta del WP-2 en Studio y la quiere "más de rally". Que dé vueltas, cambie de dirección y sea sinuosa, con subidas y bajadas más marcadas y una ruta más angosta (16 studs).
- **Contratos que usa o provee:** usa `SurfaceKind` (#17). No toca contratos. La API pública de `RoadPath`, `RoadQuery` y `SurfaceClassifier` no cambia.

## Objetivo

Que la ruta generada vague en cualquier dirección dentro de un círculo de 8.000 studs alrededor del origen, sin que su parte viva pase cerca de sí misma, con horquillas y lomas pronunciadas, y siga siendo determinista y continua.

## Entregables

Todo en `src/world/core/` y `tests/world/`, con `--!strict`, siguiendo la tabla "Módulos que cambian" del diseño.

1. **`WorldConfig`:** los valores nuevos y cambiados de la tabla del diseño, y los `HILL_*`:
   - `HILL_BASE_HEIGHT_STUDS = 50`;
   - `HILL_AMPLITUDE_STUDS = 120`;
   - `HILL_WAVELENGTH_STUDS = 900`;
   - `HILL_OCTAVES = 3`;
   - `HILL_MIN_HEIGHT_STUDS = -150` y `HILL_MAX_HEIGHT_STUDS = 250` (la franja);
   - `HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP = 0.5`.

   Se borra lo que el diseño marca para borrar. Hay que respetar dos invariantes: `MIN_CURVE_RADIUS_STUDS` tiene que ser mayor que la mitad del ancho más la banquina, y `LIVE_CLEARANCE_STUDS` tiene que ser mayor que el ancho total más dos veces la banquina.
2. **`RoadIntegrator`:** un paso de integración, compartido. `RoadPath` y la previsualización del secuenciador dan resultados idénticos bit a bit.
3. **`HillProfile`:**
   - `new(seed)`: el desplazamiento del ruido sale de `SeededRandom` y no es entero;
   - `getTargetHeight(arcLength)`;
   - `nextSlope(currentHeight, currentSlope, arcLength) -> slope`, que respeta `MAX_SLOPE_DEGREES`, el cambio máximo por paso y la franja de altura (cerca del borde de la franja, la pendiente apunta hacia adentro).
4. **`LiveRoadIndex`:** registra muestras con su `arcLength`, olvida las que quedaron a más de `LIVE_LOOKBACK_STUDS` y responde `isClear(position, arcLength) -> boolean`. Es falso si hay una muestra viva a menos de `LIVE_CLEARANCE_STUDS` en el plano horizontal cuyo `arcLength` difiera en más de `LIVE_CLEARANCE_STUDS`.
5. **`RoadPieceSequencer`:** sin corredor. Previsualiza con `RoadIntegrator` y acepta o rechaza con `LiveRoadIndex` y el círculo del área. Las alternativas van en el orden fijo del diseño y el tirón hacia el centro aplica cerca del borde. Hay un último recurso documentado (curva más cerrada hacia el lado libre), y un contador interno para que las pruebas sepan cuántas veces se usó.
6. **`RoadPieceCatalog`:** sin pendiente por pieza. Suma `hairpin` (un lóbulo, radio entre `MIN_CURVE_RADIUS_STUDS` y 1,4 veces ese valor, y giro total entre 120° y 180°). Los pesos iniciales son: recta 2, curva abierta 4, curva cerrada 4, S 4 y horquilla 2.
7. **`RoadFrame`** y **`RoadPath`:** como dice la tabla del diseño, sin cambiar la API pública de `RoadPath`.
8. **Pruebas** (las del WP-2 que ya no aplican se reemplazan, no se borran sin reemplazo):
   - **Determinismo:** misma semilla da el mismo hash en 20 tramos, aunque se liberen tramos. Otra semilla da otro hash.
   - **Propiedades sobre 200 semillas × 400 tramos:**
     - curvatura ≤ 1/`MIN_CURVE_RADIUS_STUDS`;
     - pendiente ≤ `MAX_SLOPE_DEGREES`;
     - cambio de pendiente por paso ≤ el máximo;
     - altura dentro de la franja (con la tolerancia de un paso);
     - todas las muestras dentro de `AREA_RADIUS_STUDS`;
     - **anti-cruce:** dos muestras con `arcLength` a menos de `LIVE_LOOKBACK_STUDS` y a más de `LIVE_CLEARANCE_STUDS` entre sí, sobre el eje, nunca están a menos de `LIVE_CLEARANCE_STUDS` en el plano;
     - continuidad entre tramos (posición, rumbo, curvatura y pendiente);
     - **el último recurso no se usa nunca**, o, si se usa, el resultado igual cumple todas las propiedades. El informe dice cuántas veces se usó.
   - **Que sea de rally de verdad:** sobre las 200 semillas, la ruta cambia de dirección. En cada semilla hay al menos un tramo de 2.000 studs donde el rumbo gira más de 180°, y el rumbo acumulado pasa por los cuatro cuadrantes. También se verifica que hay subidas y bajadas: la diferencia de altura en 2.000 studs supera los 60 studs en la mayoría de las ventanas.
   - `HillProfile`, `LiveRoadIndex` y `RoadIntegrator` con sus casos borde (en el límite de la franja, justo en la distancia libre, vecinas contra no vecinas).
   - Las pruebas de `RoadQuery` y `SurfaceClassifier` del WP-2 siguen pasando, con los anchos nuevos.
9. **`docs/nombres.md`:** suma perfil de cerros (`HillProfile`), ruta viva (`LiveRoadIndex`) y horquilla (`hairpin`).

## Fuera de alcance
- Terrain, adaptadores, Roblox y el arranque (`src/app/`).
- La liberación y la reescritura de chunks cuando la ruta vuelve (es del WP del terreno; acá solo se fija `LIVE_LOOKBACK_STUDS`).
- Cambiar contratos.
- Ajustar los valores "a ojo": los iniciales son los de este WP; Beni los afina después jugando.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da "todo OK" y la cobertura de `src/world/core/**` es ≥ 87%.
- [ ] Se cumplen todas las propiedades sobre 200 semillas × 400 tramos, incluido el anti-cruce y el área.
- [ ] Las pruebas de "rally de verdad" pasan (giro de más de 180° y lomas).
- [ ] La previsualización y `RoadPath` son idénticas bit a bit (prueba explícita).
- [ ] La API pública de `RoadPath`, `RoadQuery` y `SurfaceClassifier` no cambió.
- [ ] Sin números mágicos fuera de `WorldConfig` y el catálogo. Ningún archivo pasa de 200 líneas ni de 7 funciones públicas, y si alguno pasa, se justifica.
- [ ] El tiempo de `scripts/test.sh` queda informado. Si pasa de 60 s, se frena y se avisa.

## Pruebas manuales
- [ ] (Agente B, con el MCP en un lugar de prueba, nunca en "Juego de Papu") Medir el Terrain en rampas de 15° y 20° antes de subir `MAX_SLOPE_DEGREES` por encima de 12.
- [ ] (Agente B) Comparar el hash de 20 tramos con la semilla 12345 entre Studio y el CLI.
- [ ] (Beni) Recorrer varias semillas con la vista previa (`VistaPreviaRuta`, con el atributo `Seed`) y confirmar que se siente de rally: vueltas, cambios de dirección y lomas.
