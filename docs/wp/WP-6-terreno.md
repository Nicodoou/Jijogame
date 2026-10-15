# WP-6 — Terreno: mundo vivo en el cliente, Terrain por chunks y proveedores de contratos

**Issue:** #10
**Requerimientos:** RC-2, RC-3, RC-6, RC-8, RC-11, RC-12 (proveedor), RN-1, y la tabla de rendimiento (sin tirones). Provee `GetSurfaceAt` (#17), `GetNearestRoadPoint` y `GetSpawnPoint` (#35), e `IsWorldReadyAt` (#36).
**Diseño:** `docs/disenos/ruta.md` ("Arquitectura" y la revisión versión 2) y `docs/disenos/terreno.md`
**Responsable:** Agente B
**Depende de:**
- **WP-5** (ruta de rally) en `main`: el núcleo de la ruta que usa este WP.
- **La implementación del WP-4** (A) en `main`: los archivos `src/app/` donde se cambian los stubs por el mundo real. Si todavía no está, el paso 10 de "Entregables" se hace en un PR aparte, cuando esté.

## Subagente
- **Núcleo:** `.claude/agents/programador-nucleo.md` (pasos 1 a 6).
- **Adaptadores y arranque:** `.claude/agents/programador-adaptador.md`, de A, reutilizado (pasos 7 a 10). Si hay que cambiarle algo, va por issue a A.
- **Modelo:** Sonnet para los dos.
- **Entrega:** el informe de cada definición. El de adaptadores incluye las pruebas automatizables en Studio con el MCP, en un Baseplate de prueba.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/terreno.md` y `docs/disenos/ruta.md` completos;
  - `docs/disenos/politica-de-codigo.md` ("Arquitectura");
  - `docs/disenos/auto.md` ("Arranque");
  - `docs/wp/WP-4-auto-manejable.md` (arranque, stubs y mapeo);
  - `src/shared/contracts/` (los cuatro contratos);
  - `src/world/core/`;
  - `docs/reglas-de-trabajo.md` y `docs/guia-de-desarrollo.md`.
- **Decisiones que aplican** (`docs/decisiones.md`):
  - "Ruta y terreno: piezas con curvatura, todo Terrain, generado en el cliente";
  - "Ruta de rally: trazado libre en un área acotada…";
  - "Ruta de rally con guía grande y tamaño de las pruebas largas";
  - las de política de código.
- **Supuestos vigentes (medidos en Studio):**
  - Escribir un chunk de 128×128 studs cuesta unos 3 ms en PC (armar las tablas más `WriteVoxels`).
  - La superficie del Terrain queda **2 studs más arriba** de la que dice la ocupación. Se calibra con `TERRAIN_SURFACE_OFFSET_STUDS = 2`.
  - Un `Raycast` que arranca adentro del Terrain da `nil`.
  - Las rampas no tienen escalones de vóxel, pero ondulan hasta 0,25 studs a 10°.
  - El Terrain se escribe sin problema lejos del origen.
  - El contenido creado en el cliente no sale por streaming.
  - `GetSurfaceAt` sin cursor cuesta unos 73 µs en el CLI; con cursor, unas 5 veces menos.
- **Acuerdos con A:**
  - mientras el auto no existe, `GetVehiclePosition` devuelve `GetSpawnPoint().position` (#36);
  - el auto aparece anclado y se suelta cuando `IsWorldReadyAt` da `true`;
  - el cambio de cada stub por el mundo real es una línea en `src/app/`.
- **De la conversación con Beni:** prioriza que no haya tirones y que la ruta se sienta de rally.
- **Contratos:** provee los cuatro de arriba, sin cambiar sus firmas.

## Objetivo

Que en el cliente exista el mundo vivo alrededor del auto:
- la ruta generada adelante y liberada atrás;
- el Terrain escrito por chunks dentro de un presupuesto por frame, plano y liso en la ruta y con lomas suaves alrededor;
- los cuatro contratos funcionando de verdad en vez de los stubs de A.

## Entregables

**Núcleo (`src/world/core/`, Luau puro, con pruebas en el CLI):**

1. **`TerrainHeightField`:** altura en (x, z) a partir del punto de ruta viva más cercano (con cursor).
   - Plana en todo el ancho de la ruta más la banquina, a la altura de la ruta.
   - A partir de ahí, mezcla suave (en `TERRAIN_BLEND_WIDTH_STUDS`) hacia colinas: ruido con semilla, relativo a la altura de la ruta, con `TERRAIN_HILL_*`. Así el terreno sigue a la ruta (RC-6).
   - Continua: sin saltos entre columnas vecinas mayores que lo que da la pendiente máxima del terreno.
2. **`VoxelChunkBuilder`:** para un chunk de `CHUNK_SIZE_STUDS` (128) arma las tablas de material y ocupación, **por filas**, así cada paso del presupuesto es chico.
   - El rango vertical se calcula por chunk.
   - La ocupación se calibra con `TERRAIN_SURFACE_OFFSET_STUDS`.
   - El material de arriba sale de la superficie de la columna (`SurfaceClassifier`, con cursor): `Road` y `Shoulder` → `"Ground"`, `Grass` → `"Grass"`, `Mud` → `"Mud"`. Debajo, `"Ground"`.
   - Las claves son propias (strings), nunca `Enum`. Las tablas se reutilizan entre chunks.
3. **`WorldPlanner`** (une el `ChunkPlanner` y la generación de tramos de la arquitectura):
   - con la posición del auto obtiene su `arcLength` (con cursor);
   - genera tramos de ruta hasta `ROUTE_AHEAD_STUDS` por delante, más el retraso del buffer del WP-5, y los libera más allá de `LIVE_LOOKBACK_STUDS` por detrás;
   - calcula los chunks queridos: los que tocan un corredor de `TERRAIN_CORRIDOR_HALF_WIDTH_STUDS` alrededor de la ruta viva;
   - arma la cola de trabajo, priorizada por cercanía al auto: escribir chunks queridos, borrar los que dejaron de serlo (con histéresis) y **reescribir** un chunk si la ruta vuelve por una zona vieja;
   - lleva el registro de chunks escritos, para `IsWorldReadyAt` (radio `WORLD_READY_RADIUS_STUDS` = 64).
4. **`WorkBudget`:** avanza la cola hasta gastar `WORK_BUDGET_MS_PER_FRAME`, con el reloj inyectado.
5. **`SpawnPoint`:** calcula el `RoadPoint` de aparición (inicio de la ruta, a `SPAWN_ARC_LENGTH_STUDS` del comienzo) **solo con la semilla y el núcleo**, así da lo mismo en el servidor y en el cliente.
6. **Pruebas en el CLI** (`tests/world/`):
   - la altura es plana en la ruta y continua, y en la banquina y la mezcla queda dentro de los límites;
   - las tablas de un chunk conocido tienen la ocupación y el material esperados, incluida la calibración;
   - el planificador quiere y libera los chunks correctos, hace histéresis y reescribe cuando la ruta vuelve, con una ruta de prueba que vuelva;
   - `WorkBudget` con un reloj falso nunca se pasa;
   - `IsWorldReadyAt` es falso hasta que todos los chunks del radio estén escritos;
   - el punto de aparición es el mismo en dos instancias con la misma semilla.

**Adaptadores y arranque:**

7. **`src/world/client/`:**
   - `TerrainWriter` (de las claves a `Enum.Material`, `WriteVoxels` y borrado con aire);
   - `WorldClient`, una fábrica que recibe la semilla, `getVehiclePosition` y el reloj, y devuelve `step()`, `getSurfaceAt`, `getNearestRoadPoint`, `getSpawnPoint` e `isWorldReadyAt`. Es lo que se conecta en `src/app/client/` en lugar de los stubs.
8. **`src/world/server/WorldSeedServer`:** elige la semilla (acá sí `Random`, porque es adaptador), la publica en el atributo `WorldSeed` de `ReplicatedStorage` y expone `getSpawnPoint` para el `VehicleSpawner` de A.
9. **Mapeo de Rojo:** `src/world/client` → `StarterPlayer.StarterPlayerScripts.world` y `src/world/server` → `ServerScriptService.world`.
10. **Arranque (`src/app/`):** cambiar los cuatro stubs por el mundo real (una línea cada uno). Si el código del WP-4 todavía no está en `main`, este paso queda para un PR aparte. El orden de arranque es obligatorio (revisión de A en el PR #49):
    - **Servidor:** `WorldSeedServer` elige y publica la semilla **antes** de crear el `VehicleSpawner` y de conectar `PlayerAdded`. Si no, el primer auto aparece con el stub o con `nil`.
    - **Cliente:** espera el atributo `WorldSeed`, arma `WorldClient` y **recién después** arma el `VehicleController` de A, pasándole los cierres del mundo. Así `getVehiclePosition()` puede devolver `getSpawnPoint().position` desde el primer frame.
    - El subagente de adaptadores usa **solo** el Baseplate de prueba que le indique el orquestador, nunca "Juego de Papu".

## Fuera de alcance
- Árboles y rocas (RC-9 y RC-10): van al WP del decorado.
- El final de etapa y la UI.
- Cambiar contratos o el núcleo de la ruta (WP-5).
- Optimizar en celular antes de medir. Primero se mide (ver las pruebas manuales).

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da "todo OK" y la cobertura de `src/world/core/**` es ≥ 87%.
- [ ] En Studio (PC), manejando o moviendo un objeto a 100 studs/s por la ruta durante 5 minutos, ningún frame gasta más de `WORK_BUDGET_MS_PER_FRAME` + 2 ms en el trabajo del mundo (medido con `debug.profilebegin` o con el tiempo del paso).
- [ ] La memoria de Terrain (`TerrainVoxels` y `GraphicsTerrain`) y la de Luau se mantienen estables en 10 minutos (RN-1): no crecen sin parar.
- [ ] La ruta se ve plana y lisa, y la superficie visual queda a ±0,5 studs de la altura que dice el núcleo (medido con rayos).
- [ ] `IsWorldReadyAt` en el punto de aparición pasa a `true` en menos de 2 s desde que llega la semilla.
- [ ] Los cuatro contratos responden de verdad, y `GetSpawnPoint` da lo mismo en el servidor y en el cliente.

## Pruebas manuales
- [ ] (Agente B, con el MCP en un Baseplate de prueba, nunca en "Juego de Papu") Medir las rampas de 15° y 20° si el WP-5 todavía no lo hizo.
- [ ] (Agente B) La medición de frames y de memoria de los criterios, y capturas desde arriba de una vuelta de la ruta sobre una zona vieja (que se reescriba bien).
- [ ] (Beni) Recorrer la ruta con el auto de A (o con la vista previa) y buscar tirones, bordes raros y lugares donde el terreno no siga a la ruta.
- [ ] (Pendiente, con un teléfono) Medir el presupuesto por frame en un celular de gama media.
