# WP-8 — Infraestructura de biomas (núcleo): catálogo, clima, pesos y mezcla

**Issue:** #56
**Requerimientos:** RC-6, RC-8 y CP-3 del MVP (bosque). Prepara los biomas múltiples de después del MVP.
**Diseño:** `docs/disenos/biomas.md` (aprobado), sección "Arquitectura"
**Responsable:** Agente B
**Depende de:** nada nuevo. Va **antes** de la implementación del WP-6, que lo consume.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (existente)
- **Modelo:** Sonnet.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, con los criterios uno por uno y la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/biomas.md` completo;
  - `docs/disenos/terreno.md`;
  - `docs/wp/WP-6-terreno.md` (quién va a consumir este WP);
  - `docs/reglas-de-trabajo.md` (secciones 3 a 5);
  - `docs/nombres.md`;
  - `src/world/core/`, en especial `WorldConfig`, `SeededRandom`, `HillProfile` y `SurfaceClassifier`;
  - `src/shared/contracts/Surface.luau`;
  - `docs/guia-de-desarrollo.md`.
- **Decisiones que aplican:** "Biomas: bosque en el MVP, infraestructura para N biomas" (`docs/decisiones.md`) y las de política de código.
- **Supuestos vigentes, medidos en el CLI y en Studio con resultados idénticos:**
  - `math.noise` tiene período 256 y valores entre −0,86 y +0,84. Los percentiles medidos están en la tabla del diseño.
  - Cuesta unos 0,04 µs por llamada.
  - Con coordenadas grandes no da 0.
  - Rokit: `export PATH="$HOME/.rokit/bin:$PATH"` antes de cada comando, desde la raíz del repo.
- **De la conversación con Beni y Nico:** el MVP usa solo bosque, pero esto tiene que quedar **modular**: sumar un bioma después es agregar una ficha de datos, sin tocar lógica.
- **Contratos:** usa `SurfaceKind` (#17). No lo cambia.

## Objetivo

Que exista, probado en el CLI, el sistema que dice cuánto pesa cada bioma en cada punto y cómo mezclar sus atributos. Tiene que andar con una ficha (bosque, MVP) y con N fichas (probado con fichas ficticias).

## Entregables

Todo en `src/world/core/`, con `--!strict`.

1. **`BiomeCatalog`:** fichas de bioma como datos, con el tipo `BiomeDefinition`:
   - `id`;
   - `climate`: rangos de relieve, humedad y temperatura en u ∈ [0, 1];
   - `terrain`: `hillAmplitudeScale` y `hillRoughness`;
   - `materials`: `surface` (lista de claves con proporciones), `transition` (material puente) y `deep`;
   - `surfaces`: `offroad` (`SurfaceKind`) y `patches` (por ejemplo, `Mud` con su escala de ruido, su umbral y su distancia mínima a la banquina);
   - `decoration`: lista de `{ kind, density, minSpacingStuds, collision }`, que todavía no consume nadie (es para el WP del decorado).

   Exporta **solo** la ficha `forest`, cuyos valores reproducen lo de hoy: superficie `Grass` y `LeafyGrass`, puente `Ground`, profundo `Ground`, fuera de ruta `Grass` y manchones de `Mud` con los parámetros que hoy tiene `WorldConfig`. Una función `validate(definitions)` comprueba que las fichas estén bien formadas.
2. **`ClimateField`:**
   - mapas de **relieve** y **humedad**, cada uno con N octavas de `math.noise`, `z` no entero propio, entrada envuelta con `% 256` y offsets de `SeededRandom`;
   - **temperatura** derivada: `ruido_temperatura − k · relieve`;
   - **normalización por cuantil** con una tabla constante (en `WorldConfig` o en un módulo de datos) que convierte el valor crudo de octavas sumadas en u ∈ [0, 1];
   - funciones `sample(x, z) -> ClimateSample` y `sampleGrid(chunkOriginX, chunkOriginZ, sizeStuds, stepStuds)`, que devuelve una grilla de muestras para interpolar los **parámetros**.
3. **`BiomeWeights`:** `compute(climate, catalog) -> { [id]: weight }`, con `w = max(0, 1 − d/R)^k`, donde `d` es la distancia del punto a la caja de la ficha. Corta los pesos chicos (menores a `BIOME_WEIGHT_CUTOFF`) y normaliza para que sumen 1. Si ninguna ficha alcanza, se queda con la más cercana. Con una ficha, siempre `{ forest = 1 }`.
4. **`BiomeBlend`:**
   - `blendNumber(weights, catalog, selector)`;
   - `pickMaterial(weights, catalog, x, z, seed)`: elección estocástica coherente con un ruido de `BIOME_MATERIAL_PATCH_STUDS` (12 a 24) y el material puente en las transiciones;
   - `pickOffroadSurface(weights, catalog, x, z, seed)`: devuelve un `SurfaceKind`, con los manchones de cada ficha.
5. **`WorldConfig`:** `BIOME_TRANSITION_RADIUS` (R en el espacio de u), `BIOME_TRANSITION_EXPONENT` (k), `BIOME_WEIGHT_CUTOFF`, `BIOME_MATERIAL_PATCH_STUDS`, `CLIMATE_*` (octavas, longitudes de onda y offsets) y la tabla de cuantiles.
6. **Pruebas** (`tests/world/`):
   - **Catálogo:** `forest` válido; una ficha mal formada falla en `validate`.
   - **`ClimateField`:**
     - determinista (misma semilla y posición, mismo resultado);
     - con 200.000 muestras, u queda casi uniforme: cada décimo entre 8% y 12%;
     - la grilla interpolada difiere del muestreo directo en menos de `CLIMATE_GRID_MAX_ERROR`.
   - **`BiomeWeights`** con un catálogo de **prueba** de 2 a 3 fichas ficticias (solo en las pruebas): los pesos suman 1, el interior de una caja es puro, la transición se ensancha con R y nada da NaN. Con `forest` solo, el peso es 1 en 10.000 puntos del círculo.
   - **`BiomeBlend`:**
     - `pickMaterial` respeta las proporciones de los pesos (estadístico, con tolerancia);
     - es coherente en el espacio: los vecinos a 4 studs coinciden en la gran mayoría de los casos (no sal y pimienta);
     - en una transición aparece el puente;
     - `pickOffroadSurface` con `forest` reproduce los manchones de `Mud` de hoy.
7. **`docs/nombres.md`:** bioma (`Biome`), ficha de bioma (`BiomeDefinition`), catálogo (`BiomeCatalog`), clima (`ClimateField`), peso de bioma (`BiomeWeight`) y mezcla (`BiomeBlend`).

## Fuera de alcance
- Conectar esto a `TerrainHeightField`, `VoxelChunkBuilder` y `SurfaceClassifier` (lo hace el WP-6 al implementarse).
- El decorado (WP aparte).
- Fichas de montaña, desierto y montaña con bosque.
- Cambiar el contrato de superficie.
- Arreglar el #57 (lomas que se repiten): va por su propio proceso de bug.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da "todo OK" y la cobertura de `src/world/core/**` es ≥ 87%.
- [ ] Todas las pruebas de arriba pasan, incluidas las de N fichas ficticias.
- [ ] Sumar una ficha nueva no requiere tocar ningún módulo salvo `BiomeCatalog`. Se demuestra con las fichas ficticias, pasadas como catálogo inyectado.
- [ ] Sin números mágicos fuera de `WorldConfig` y `BiomeCatalog`, y archivos dentro de los límites.
- [ ] El tiempo de `scripts/test.sh` sigue por debajo de 60 s. Si no, se frena y se avisa.

## Pruebas manuales
- [ ] (Agente B, con el MCP en "Experiencia sin título", nunca en "Juego de Papu") Correr `ClimateField` en Studio y comparar un hash de 1.000 muestras con el del CLI.
- [ ] (Agente B) Dibujar en Studio un mapa de colores de los pesos con un catálogo de prueba de 3 fichas, para ver que las transiciones son graduales y las zonas tienen formas naturales. Después, borrar todo.
