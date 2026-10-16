# Biomas alrededor de la ruta

**Issue:** #56
**Requerimientos:** RC-6, RC-8, RC-9, RC-10 y CP-3 del MVP. Prepara S3, S4, S7 y S9 de los requerimientos generales (biomas múltiples, después del MVP).
**Estado:** aprobado

## Alcance

- **El MVP sale con un solo bioma: bosque.** Lo eligió Beni. Nico pidió en #56 que sea un solo bioma, pero que todo quede listo para sumar N biomas sin rehacer nada.
- Por eso este diseño arma **toda la infraestructura de biomas** (clima, pesos, catálogo y mezcla) y la prueba con un catálogo de una sola ficha. Sumar un bioma después es agregar una ficha y, si hace falta, ampliar el contrato de superficie con A.

## Investigación

Punto de partida: la preinvestigación de Nico (adjunta en #56). La investigación la hizo el subagente `investigador` el 2026-10-16, con mediciones del Agente B. Las marcas son las de siempre: [V], [S], [A], [NC] y [E].

### `math.noise`, medido [E] (idéntico en el CLI y en Studio, 200.000 muestras)

| Medida | 2D | 3D |
| --- | --- | --- |
| Mínimo / máximo | −0,855 / 0,807 | −0,794 / 0,835 |
| Percentiles 1 y 99 | −0,553 / 0,556 | −0,588 / 0,590 |
| Percentiles 5 y 95 | −0,431 / 0,428 | −0,453 / 0,444 |
| Cuartiles | −0,182 / 0,179 | −0,196 / 0,200 |

- **Período 256 confirmado:** `noise(300.37, 12.5) == noise(44.37, 12.5)`.
- **Coordenadas grandes:** no da 0 con 2¹⁹ ni con 2²³. La corrección de precisión está activa en los dos lados, así que el riesgo de la preinvestigación no aplica, y además el mundo vive en un círculo de 8.000 studs.
- **Costo:** unos 0,04 µs por llamada. Tres mapas × tres octavas × 1.024 columnas de un chunk dan menos de 0,5 ms.
- **Normalización:** ni ±0,5 ni ±1 sirven como rango. Se convierte a cuantil (u ∈ [0,1], casi uniforme) con una tabla de la distribución medida. Así los umbrales de la tabla de biomas pasan a ser proporciones de área.

### Cómo lo hacen otros [S]

- **Minecraft 1.18+:** el bioma sale de mapas continuos (temperatura, humedad, continentalidad, erosión y "rareza") y gana el más cercano. La coherencia sale de que el terreno y el bioma comparten los mismos mapas ([wiki](https://minecraft.wiki/w/World_generation)).
- **Red Blob Games:** dos mapas (elevación y humedad) con una tabla tipo Whittaker, y la temperatura derivada de la elevación ([artículo](https://www.redblobgames.com/maps/terrain-from-noise/)).
- **Mezcla en fronteras:** hay que mezclar **parámetros y pesos**, no IDs de bioma; si no, quedan bordes de acantilado ([KdotJPG](https://noiseposti.ng/posts/2021-03-13-Fast-Biome-Blending-Without-Squareness.html)).

### Terrain y materiales [V]

- Materiales de Terrain útiles: Grass, LeafyGrass, Ground, Mud, Sand, Sandstone, Rock, Slate, Basalt, Snow, Salt, Limestone y Cobblestone. **No existe "grava" para Terrain**: se imita con Ground, Cobblestone o Limestone.
- Las `MaterialVariant` y `SetMaterialColor` son **globales por lugar**: no se puede teñir el pasto distinto por bioma. La diferencia entre biomas sale de **materiales base distintos**.
- Un vóxel tiene un solo material. El borde entre materiales se disimula alternándolos con ruido de baja frecuencia (manchones de 12 a 24 studs) y con un material "puente" en la transición.

### Objetos (para el WP del decorado) [A]

- La distribución de cada chunk no puede depender del orden de carga: candidatos por celda con prioridad por hash, comparando solo con las celdas vecinas. Cada celda sale de `hash(semilla, celda)`.
- Tiene que haber zona de exclusión en la ruta y la banquina, y paso mínimo entre obstáculos para el auto (6 studs de ancho).

## Opciones

### Decisión 1: cómo se elige el bioma de un punto

- **B1. Clima → bioma (Whittaker), con pesos suaves (recomendado).** Mapas de **relieve** y **humedad** normalizados por cuantil, con la **temperatura** derivada del relieve y de un ruido propio. Cada ficha declara una caja de clima. El peso de cada bioma es `max(0, 1 − d/R)^k`, con `d` la distancia del punto a la caja, normalizado para que sumen 1.
  - **Bueno:** coherencia por construcción y transiciones graduales solas.
  - **Malo:** hay que afinar R y k jugando.
- **B2. Regiones (Voronoi) con bioma asignado.** Garantiza variedad, pero pierde la coherencia climática y los bordes rectos se notan.
- **B3. Bioma por `arcLength` de la ruta.** Controla el ritmo, pero no son lugares reales: si la ruta vuelve, el lugar cambió.

### Decisión 2: relación con la ruta

- **R1. La ruta no se toca. El bioma escala el relieve, los materiales y el decorado alrededor de la ruta (recomendado).** No reabre el WP-5. La montaña sería "colinas más altas al costado" más un decorado lejano.
- **R2. La ruta lee un mapa de macro-altura.** La ruta subiría y bajaría con el bioma, pero toca el generador de ruta (WP-5) y su perfil de lomas.

### Decisión 3: variedad a lo largo de la ruta (después del MVP)

Con un solo bioma no aplica. Para cuando haya N: **V1, campo espacial con una escala elegida por un experimento en el CLI** (distancia entre cambios de bioma sobre 200 semillas de ruta, con longitudes de onda de 2.000 a 6.000 studs), más una garantía de cobertura: se elige un desplazamiento de semilla para el que cada bioma ocupe al menos un 10% del círculo.

**Recomendación del agente:** B1 + R1, con V1 para después del MVP.

## Decisión

Beni, 2026-10-16: bosque para el MVP con la infraestructura de N biomas (respuesta de Nico en #56), **B1 + R1** y los patrones de abajo.

## Arquitectura

Todo el cálculo vive en `src/world/core/` (Luau puro, probado en el CLI) y lo consumen los módulos del WP-6.

### Módulos

| Módulo | Qué hace | Qué no hace |
| --- | --- | --- |
| `BiomeCatalog` | **Fichas de bioma como datos** (patrón *Type Object*). Cada ficha tiene: `id`; caja de clima (relieve, humedad y temperatura); `terrain` (escala de amplitud y rugosidad de las colinas); `materials` (superficie arriba, puente de transición y profundo, como claves propias); `surfaces` (qué `SurfaceKind` da fuera de la ruta y los manchones, por ejemplo de barro); `decoration` (lista de objetos con densidad, distancia mínima y forma de colisión, para el WP del decorado). **MVP: una sola ficha, `forest`.** | No tiene lógica. |
| `ClimateField` | Mapas de relieve y humedad: varias octavas de `math.noise` con `z` no entero propio, entrada envuelta `% 256` y normalización por la tabla de cuantiles medida. La temperatura sale derivada del relieve y de un ruido. Se evalúa en una grilla de 16 studs por chunk con interpolación bilineal **de los parámetros** (no de los pesos). | No elige biomas. |
| `BiomeWeights` | Del clima de un punto a los pesos de cada bioma (B1). Corta los pesos chicos y normaliza para que sumen 1. Con una sola ficha devuelve `{ forest = 1 }`. | No sabe de terreno ni de materiales. |
| `BiomeBlend` | Ayudas para los consumidores: `blendNumber(pesos, campo)` (por ejemplo, la amplitud de las colinas), `pickMaterial(pesos, x, z)` (elección estocástica coherente con ruido de 12 a 24 studs más el material puente) y `pickOffroadSurface(pesos, x, z)`. | No escribe nada. |

**Quién lo usa (cambios sobre el WP-6, sin cambiar su API):**
- `TerrainHeightField`: la amplitud y la rugosidad de las colinas salen de `BiomeBlend.blendNumber`. La ruta y la banquina siguen planas (R1).
- `VoxelChunkBuilder`: el material de cada columna sale de `BiomeBlend.pickMaterial`. En la ruta y la banquina, fijo: `Limestone` en el camino y `Ground` en la banquina (WP-11).
- `SurfaceClassifier`: fuera de la ruta, la superficie la da `BiomeBlend.pickOffroadSurface` (bosque: `Grass` y manchones de `Mud`). **El contrato #17 no cambia en el MVP.**
- WP del decorado: densidades y listas de objetos por peso de bioma.

### Patrones y por qué

- **Fichas de datos (*Type Object*):** sumar un bioma es agregar datos. Es lo que pide Nico para que el diseño sea modular.
- **Los consumidores solo leen pesos:** el terreno, los materiales, la superficie y el decorado nunca preguntan "¿qué bioma es?", piden pesos y mezclan. Así funcionan igual con 1 o con N biomas y no hay casos especiales por par de biomas.
- **Clima → bioma (función pura):** la misma semilla y la misma posición dan los mismos pesos, sin importar el orden de carga de los chunks.
- **Grilla interpolada:** el costo baja 12 veces y, al interpolar parámetros y no pesos, no quedan pliegues en la grilla.

### Después del MVP (fuera de alcance ahora)

- Sumar las fichas de montaña, montaña con bosque y desierto.
- Ampliar el contrato de superficie con A (roca, arena y una "grava" imitada).
- Hacer el experimento de variedad (V1).
- El relieve lejano de las montañas como decorado.

### Pruebas (núcleo, CLI)

- Los pesos suman 1, el interior de una caja es puro y la transición se ensancha con R.
- Con una sola ficha, el peso es 1 en todo el círculo.
- `ClimateField` es determinista y su tabla de cuantiles da u ≈ uniforme sobre 200.000 muestras.
- `BiomeBlend.pickMaterial` es coherente en el espacio (manchones, no sal y pimienta) y respeta las proporciones de los pesos.
- **Catálogo de prueba con 2 fichas ficticias:** valida que la mezcla, los materiales y la superficie funcionan con N > 1, aunque el MVP use 1.

### WP

**WP-8, infraestructura de biomas (núcleo):** `BiomeCatalog` (con `forest` y las fichas ficticias solo en las pruebas), `ClimateField`, `BiomeWeights` y `BiomeBlend`, con sus pruebas. Va **antes** del WP-6, que pasa a consumirlo con los cambios de "Quién lo usa".

## Aprobación
Aprobó Beni el 2026-10-16 ([#56](https://github.com/Nicodoou/Jijogame/issues/56#issuecomment-6205547410)). Nico definió el alcance en #56.
