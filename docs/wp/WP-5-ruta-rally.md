# WP-5 — Rediseño de la ruta de rally: guía grande, curvas locales, anti-cruce y perfil de cerros

**Issue:** #37
**Requerimientos:** RC-1, RC-4, RC-5, RC-6, RC-7 (sobre el núcleo del WP-2)
**Diseño:** `docs/disenos/ruta.md`, sección "Revisión de la arquitectura por la ruta de rally (#37), versión 2: guía grande"
**Responsable:** Agente B
**Depende de:** WP-2 (en `main`). Prototipo de referencia en la rama `exp/ruta-guia` (configuración G).

> **Versión 2.** La versión 1 de este WP no se implementó: su regla anti-cruce era imposible y su secuenciador se encerraba. Esta versión sigue el enfoque de la guía grande, probado en el prototipo con 0 encierros y 0 cruces en 200 semillas × 400 tramos.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (existente)
- **Modelo:** Sonnet. El diseño y el prototipo fijan el algoritmo, los valores y las pruebas.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, con los criterios uno por uno, la salida de `scripts/check-all.sh`, los tiempos y el hash nuevo.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/ruta.md` completo, sobre todo "Arquitectura" y la revisión versión 2;
  - el prototipo en la rama `exp/ruta-guia`: `exp/ruta-guia/guide.luau` y `LEEME.md`, con `git show origin/exp/ruta-guia:<ruta>`. Es de referencia: el código **no** se copia tal cual, se reescribe con las reglas del proyecto;
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5), `docs/nombres.md`, todo `src/world/core/`, `tests/world/` y `docs/guia-de-desarrollo.md`.
- **Decisiones que aplican** (`docs/decisiones.md`): "Ruta de rally: trazado libre en un área acotada, perfil de cerros y 16 studs de ancho", "Ruta y terreno: piezas con curvatura, todo Terrain, generado en el cliente" y "Política de pruebas, cobertura y estructura de `src/`". Si Beni aprueba el tamaño de las pruebas del CI, también esa decisión, que va en este mismo PR.
- **Supuestos vigentes:**
  - `math.noise`, `math.sin`, `math.cos` y `math.tan` dan lo mismo en el CLI y en Roblox.
  - `vector` es float32 y sus componentes van en minúscula.
  - Rokit: antes de cada comando, `export PATH="$HOME/.rokit/bin:$PATH"`, siempre desde la raíz del repo.
- **De la conversación con Beni:** quiere la ruta más de rally: que dé vueltas, cambie de dirección y sea sinuosa, con lomas marcadas y 16 studs de ancho. Eligió la guía grande.
- **Contratos que usa o provee:** usa `SurfaceKind` (#17). No cambia contratos. La API pública de `RoadPath`, `RoadQuery` y `SurfaceClassifier` no cambia.

## Objetivo

Que la ruta siga una guía grande sorteada con la semilla, que recorra el círculo de 8.000 studs dando vueltas. Que tenga carácter local (curvas cerradas, S y horquillas de a pares) y lomas pronunciadas. Que nunca se cruce ni se encierre, y que siga siendo determinista y continua.

## Entregables

Todo en `src/world/core/` y `tests/world/`, con `--!strict`, siguiendo la tabla "Módulos" de la versión 2.

1. **`WorldConfig`:** los valores de la tabla de la versión 2 y los `HILL_*`:
   - `HILL_BASE_HEIGHT_STUDS = 50`;
   - `HILL_AMPLITUDE_STUDS = 120`;
   - `HILL_WAVELENGTH_STUDS = 900`;
   - `HILL_OCTAVES = 3`;
   - `HILL_MIN_HEIGHT_STUDS = -150` y `HILL_MAX_HEIGHT_STUDS = 250`;
   - `HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP = 0.5`.

   Se borra lo que el diseño marca para borrar. Las relaciones entre valores van comentadas al lado (por ejemplo, `GUIDE_CLEARANCE ≥ LIVE_CLEARANCE + 2·LOCAL_DEVIATION_MAX + margen`).
2. **`RoadIntegrator`, `HillProfile`, `RoadGuide` y `LiveRoadIndex`:** como dice la tabla del diseño.
3. **`RoadPieceSequencer`:** las cuatro condiciones de aceptación, las alternativas en orden fijo, el retroceso de la ruta y el último recurso documentado. Lleva contadores de último recurso y de retrocesos, que exponen las pruebas.
4. **`RoadPieceCatalog`:** sin pendiente por pieza, con la horquilla doble (`hairpinPair`). Pesos iniciales: recta 2, curva abierta 4, curva cerrada 4, S 4 y horquilla doble 2.
5. **`RoadPath`:** buffer de piezas y publicación diferida, sin cambiar la API pública.
6. **Pruebas:** las del WP-2 que dependen de lo borrado se **reemplazan**. Las pruebas largas toman la cantidad de semillas de una constante, para que el CI corra 40 y la corrida a mano 200.
   - **Determinismo:** misma semilla da el mismo hash en 20 tramos, aunque se liberen tramos. Otra semilla da otro hash.
   - **Previsualización exacta:** `RoadIntegrator` en el secuenciador y en `RoadPath` dan lo mismo bit a bit.
   - **Propiedades sobre N semillas × 400 tramos** (N = 40 en el CI, 200 a mano):
     - curvatura ≤ 1/`MIN_CURVE_RADIUS_STUDS`;
     - pendiente ≤ `MAX_SLOPE_DEGREES`, y su cambio por paso ≤ el máximo;
     - altura dentro de la franja;
     - todo adentro del círculo;
     - **anti-cruce corregido: 0 violaciones**;
     - continuidad entre tramos;
     - **0 encierros**. Se informa cuántas veces se usó el último recurso y cuántos retrocesos hubo.
   - **Rally de verdad** (sobre las mismas semillas):
     - cada semilla tiene al menos una ventana de 2.000 studs con giro neto > 180°;
     - el rumbo pasa por los 4 cuadrantes;
     - hay más de 0,3 horquillas y más de 1 curva cerrada por km, en promedio;
     - en 2.000 studs la altura varía más de 60 studs en la mayoría de las ventanas.
   - **Casos borde** de `RoadGuide` (retroceso, borde del área), `LiveRoadIndex` (justo en la distancia libre, vecinas contra no vecinas), `HillProfile` (bordes de la franja) y el buffer de `RoadPath` (liberar tramos con piezas sin publicar).
   - Las pruebas de `RoadQuery` y `SurfaceClassifier` siguen pasando con el ancho nuevo.
7. **`docs/nombres.md`:** guía (`RoadGuide`), punto de paso (`waypoint`), perfil de cerros (`HillProfile`), ruta viva (`LiveRoadIndex`) y horquilla doble (`hairpinPair`).

## Fuera de alcance
- Terrain, adaptadores, Roblox y `src/app/`.
- La liberación y la reescritura de chunks (WP del terreno).
- Cambiar contratos.
- Ajustar valores a ojo: los iniciales son los del prototipo; Beni los afina jugando.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da "todo OK" y la cobertura de `src/world/core/**` es ≥ 87%.
- [ ] Las propiedades y el "rally de verdad" se cumplen con 40 semillas en el CI.
- [ ] La corrida completa de 200 × 400 se cumple, con la salida pegada en el informe.
- [ ] 0 violaciones del anti-cruce y 0 encierros en las dos corridas.
- [ ] La previsualización y `RoadPath` son idénticas bit a bit.
- [ ] La API pública de `RoadPath`, `RoadQuery` y `SurfaceClassifier` no cambió.
- [ ] Sin números mágicos fuera de `WorldConfig` y el catálogo. Ningún archivo pasa de 200 líneas ni de 7 funciones públicas (si pasa, se justifica).
- [ ] Se informan el tiempo de `scripts/test.sh` y el de la corrida completa. Si `test.sh` pasa de 60 s, se frena y se avisa.

## Pruebas manuales
- [ ] (Agente B, con el MCP en un lugar de prueba, nunca en "Juego de Papu") Medir el Terrain en rampas de 15° y 20° antes de subir `MAX_SLOPE_DEGREES` por encima de 12.
- [ ] (Agente B) Comparar el hash de 20 tramos con la semilla 12345 entre Studio y el CLI.
- [ ] (Beni) Recorrer varias semillas con la vista previa y confirmar que se siente de rally.
