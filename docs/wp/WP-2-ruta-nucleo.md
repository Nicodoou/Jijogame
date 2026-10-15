# WP-2 — Núcleo de la ruta: generación, consultas y superficie

**Issue:** #9
**Requerimientos:** RC-1, RC-4, RC-5, RC-6, RC-7. Prepara RC-2, RC-3 y RC-12 (los usa el WP del terreno) y provee la lógica de `GetSurfaceAt` (#17, CP-3).
**Diseño:** `docs/disenos/ruta.md` (aprobado), arquitectura en la sección "Arquitectura"
**Responsable:** Agente B
**Depende de:** el WP de configuración de #6 (Rokit, `tests/Runner.luau`, `scripts/test.sh`, `scripts/coverage.sh`, `scripts/check-core.sh`, `selene-core.toml` y `stylua.toml`). **No se empieza a implementar hasta que ese WP esté en `main`.**

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (nuevo, en este mismo PR)
- **Modelo:** Sonnet. El WP fija la geometría, las firmas y los valores, así que el trabajo es implementar y probar. Las dudas de diseño vuelven al orquestador.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin acceso a la red ni a Studio.
- **Entrega:** el informe de su definición, con los chequeos corridos y los criterios de aceptación uno por uno.

## Contexto para el subagente

- **Leer:**
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5);
  - `docs/disenos/ruta.md` (secciones "Arquitectura" y "Distancia al origen");
  - `docs/disenos/politica-de-codigo.md` (sección "Arquitectura");
  - `docs/nombres.md`;
  - `src/shared/contracts/Surface.luau`;
  - `tests/Runner.luau` y los `scripts/` del WP de configuración.
- **Decisiones que aplican** (`docs/decisiones.md`):
  - "Política de pruebas, cobertura y estructura de `src/`";
  - "Ruta y terreno: piezas con curvatura, todo Terrain, generado en el cliente";
  - "El mundo arranca en −120.000 studs, sin recentrar".
- **Supuestos vigentes:**
  - `math.noise` da los mismos valores en el CLI y en Roblox (verificado en #16).
  - `vector` es `Vector3` en Roblox (verificado en #15).
  - `require("./X")` y `require("../../X")` funcionan en los dos lados (#16 y PR #20).
  - Si `math.sin` y `math.cos` dan los mismos bits en PC y en celular está sin confirmar. Por eso la generación nunca depende de comparar flotantes por igualdad.
- **De la conversación con Beni:** prioriza que nunca salga una curva imposible (RC-5) y que no haya tirones. El auto es "arcade con peso", así que la ruta tiene que tener curvas con carácter, no solo curvas suaves.
- **Contratos que usa o provee:**
  - Usa el tipo `SurfaceKind` de `src/shared/contracts/Surface.luau`.
  - Provee la función que cumple `GetSurfaceAt`. El adaptador que la expone a Conducción (`SurfaceProvider`) **no** es de este WP.

## Objetivo

Implementar, en Luau puro y probado en el CLI, la ruta infinita con semilla: generar tramos hacia adelante, liberar los de atrás, responder el punto más cercano y la superficie en una posición.

## Entregables

Todo en `src/world/core/`, con `--!strict`. Los nombres son los de la arquitectura.

1. **`WorldConfig.luau`:** tabla de solo datos, con unidad en cada nombre. Valores iniciales (se ajustan después en las pruebas de juego):

   | Valor | Inicial |
   | --- | --- |
   | `ROAD_WIDTH_STUDS` | 24 |
   | `SHOULDER_WIDTH_STUDS` | 4 |
   | `MIN_CURVE_RADIUS_STUDS` | 60 (tiene que ser mayor que la mitad del ancho más la banquina) |
   | `MAX_SLOPE_DEGREES` | 8 |
   | `INTEGRATION_STEP_STUDS` | 2 |
   | `SEGMENT_LENGTH_STUDS` | 256 |
   | `START_POSITION` | `vector.create(-120000, 50, 0)` |
   | `MEAN_HEADING` | +x |
   | `MAX_HEADING_DEVIATION_DEGREES` | 60 |
   | `MAX_LATERAL_DRIFT_STUDS` | 2000 |

   También los parámetros de los manchones de barro (escala del ruido, umbral, distancia mínima al borde).
2. **`SeededRandom.luau`:**
   - generador de 32 bits hecho **solo con `bit32` y aritmética entera exacta** (por ejemplo, xoshiro128** o mulberry32). No PCG de 64 bits, porque los números de Luau son dobles;
   - funciones: `new(seed: number)`, `nextNumber()` en [0, 1) y `nextInteger(min, max)`;
   - el estado es explícito y se puede copiar (`clone`).
3. **`RoadPieceCatalog.luau`:** datos de las piezas (`straight`, `gentleCurve`, `sharpCurve`, `sCurve`), cada una con rangos de largo, curvatura (o radio), pendiente y peso. Las curvas incluyen transiciones de curvatura lineal al entrar y al salir, así la curvatura es continua.
4. **`RoadPieceSequencer.luau`:** sortea la próxima pieza con `SeededRandom` y el catálogo.
   - **Invariantes:** |curvatura| ≤ 1 / `MIN_CURVE_RADIUS_STUDS`; el desvío del rumbo respecto de `MEAN_HEADING` es ≤ `MAX_HEADING_DEVIATION_DEGREES`; el desvío lateral acumulado es ≤ `MAX_LATERAL_DRIFT_STUDS`; la pendiente es ≤ `MAX_SLOPE_DEGREES`.
   - Para no chocar con los límites, atrae el rumbo y la posición lateral hacia la media (reversión a la media) y elige el sentido de cada curva en consecuencia.
5. **`RoadPath.luau`:**
   - integra las piezas en pasos de `INTEGRATION_STEP_STUDS` y produce **muestras** (`RoadSample`: `position: vector`, `heading`, `curvature`, `slope`, `arcLength`);
   - las agrupa en **tramos** (`segment`) de `SEGMENT_LENGTH_STUDS`, numerados desde 0;
   - API pública: `new(seed)`, `generateNextSegment()`, `releaseSegmentsBefore(index)`, `getSegment(index)` y `getLoadedRange()`;
   - **determinismo:** el tramo k depende solo de la semilla, aunque se hayan liberado tramos anteriores.
6. **`RoadQuery.luau`:** dada una posición, devuelve `{ position, direction, lateralOffset, arcLength, segmentIndex }` del punto más cercano del eje, o `nil` si cae fuera de los tramos cargados.
   - Usa una grilla hash de muestras, que se actualiza al generar y al liberar tramos.
   - Acepta un cursor opcional (el resultado anterior) para buscar solo en una ventana de ±k muestras.
   - Con cursor, cada consulta revisa un número acotado de muestras, que no crece con la cantidad de tramos.
7. **`SurfaceClassifier.luau`:** una función con la firma `GetSurfaceAt` del contrato.
   - Con `RoadQuery` decide: `Road` si |lateral| ≤ ancho / 2; `Shoulder` hasta la banquina; `Mud` donde un ruido con semilla (`math.noise`, con la semilla convertida en desplazamiento no entero) supera el umbral y la posición está más allá de la banquina más la distancia mínima; `Grass` en el resto; `nil` fuera de los tramos cargados.
   - Ignora la altura.
8. **Pruebas** en `tests/world/`, con `tests/Runner.luau`:
   - **Determinismo:** dos `RoadPath` con la misma semilla dan muestras idénticas en los primeros 20 tramos (hash). Con otra semilla, el resultado es distinto. Lo mismo pasa si se liberan tramos en el medio.
   - **Propiedades sobre 200 semillas** y 40 tramos cada una:
     - curvatura dentro del límite;
     - rumbo dentro del corredor;
     - desvío lateral dentro del límite;
     - pendiente dentro del límite;
     - continuidad entre tramos: el primer punto de un tramo es el último del anterior, con el mismo rumbo, y sin saltos de altura ni de curvatura mayores a lo que permite un paso;
     - la ruta no se cruza (x siempre crece).
   - **`SeededRandom`:** rango de `nextNumber` y `nextInteger` en sus bordes, misma secuencia con la misma semilla y `clone` independiente.
   - **`RoadQuery`** contra una búsqueda por fuerza bruta, en 1.000 posiciones al azar con semilla fija, incluidas posiciones sobre el eje, en el borde, lejos y fuera de los tramos cargados. Con cursor, se verifica que la cantidad de muestras revisadas no supere el límite.
   - **`SurfaceClassifier`:** posiciones justo antes y justo después de cada borde (ruta, banquina), `Mud` solo fuera de la banquina, y `nil` antes del primer tramo cargado y después del último.
9. **`docs/nombres.md`:** agregar muestra (`RoadSample`), pieza (`RoadPiece`), longitud recorrida sobre el eje (`arcLength`) y desvío lateral (`lateralOffset`).

## Fuera de alcance
- Todo lo que toca Roblox: Terrain, adaptadores (`SurfaceProvider`, `RoadResetProvider`, `TerrainWriter`) y el arranque en `src/app/`.
- El terreno (`TerrainHeightField`, `VoxelChunkBuilder`), la planificación de chunks y el presupuesto por frame (son del WP del terreno).
- El contrato del punto más cercano para el reset (va por su issue `contrato`). `RoadQuery` ya deja lista la lógica.
- El decorado, la normal analítica para el auto (se acuerda con A si la pide) y el final de etapa cerca de +120.000.

## Criterios de aceptación
- [ ] Están todos los entregables, con `--!strict` y sin globales de Roblox (pasa `scripts/check-core.sh`).
- [ ] `scripts/test.sh` pasa y `scripts/coverage.sh` da **≥ 87%** sobre `src/world/core/**`.
- [ ] `stylua --check`, `selene --config selene-core.toml` y `luau-lsp analyze --platform=standard` dan 0 problemas.
- [ ] La misma semilla genera la misma ruta, aunque se liberen tramos (prueba de hash).
- [ ] Las propiedades de 200 semillas se cumplen (curvatura, corredor, desvío lateral, pendiente, continuidad, no se cruza).
- [ ] `RoadQuery` coincide con la fuerza bruta en las 1.000 posiciones (tolerancia de 0,01 studs) y, con cursor, la cantidad de muestras revisadas es acotada.
- [ ] `SurfaceClassifier` cumple el contrato (#17): bordes nítidos, `nil` fuera de la zona generada y la altura no influye.
- [ ] No hay números mágicos fuera de `WorldConfig` y `RoadPieceCatalog`.
- [ ] Ningún archivo pasa de 200 líneas ni de 7 funciones públicas. Si alguno se pasa, se justifica en el PR.

## Pruebas manuales
- [ ] (Agente B, con el MCP en un Baseplate de prueba, **nunca en "Juego de Papu"**) Cargar los módulos de `src/world/core/` en Studio y comparar el hash de los primeros 20 tramos con la semilla 12345 contra el del CLI. Tiene que dar igual. Así se confirma el determinismo de `sin` y `cos` entre el CLI y Roblox en PC.
- [ ] (Agente B) Dibujar en el Baseplate de prueba la poligonal de 20 tramos con Parts temporales, sacar una captura con el MCP y mirarla buscando curvas raras, zigzags o rectas eternas. Después, borrar todo.
- [ ] Intentar romperlo: semillas 0, negativas, enormes y no enteras; liberar todos los tramos y seguir generando; consultar posiciones con NaN o infinito (no tiene que colgarse).
