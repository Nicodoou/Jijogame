# Ruta: representación y malla

**Issue:** #9
**Requerimientos:** RC-1, RC-2, RC-3, RC-4, RC-5, RC-6, RC-7, RC-12
**Estado:** arquitectura propuesta

## Investigación

La hizo el subagente `investigador` el 2026-10-14. Las marcas significan: **[V]** verificado en una fuente primaria, **[S]** fuente secundaria (DevForum o blogs), **[A]** análisis propio sin fuente, **[NC]** no confirmado y **[E]** medido por el Agente B en Studio con el MCP.

El problema tiene tres capas, que se pueden decidir por separado:

1. **Eje:** la curva que sigue el centro de la ruta.
2. **Consultas:** responder rápido el punto más cercano y la distancia al eje. Las usan los contratos de superficie (#17) y de reset (RC-12).
3. **Malla y colisión:** lo que se ve y lo que pisa el auto.

### Eje

- **Splines (Catmull-Rom, Bézier, Hermite):**
  - dan continuidad C1 o G1 entre tramos;
  - la curvatura máxima no se conoce de antemano, así que para cumplir RC-5 hay que muestrear y corregir;
  - la longitud de arco no tiene fórmula y hay que armarla con una tabla.

  Fuentes: [Catmull-Rom centrípeta](https://en.wikipedia.org/wiki/Centripetal_Catmull%E2%80%93Rom_spline) [V], [Yuksel et al. 2011](https://cemyuksel.com/research/catmullrom_param/) [V], [Pomax](https://pomax.github.io/bezierinfo/) [S].
- **Rectas, arcos y clotoides** (como se diseñan las rutas reales):
  - la curvatura es un dato de diseño, así que RC-5 se cumple por construcción (radio mínimo, con aceleración lateral v²/R);
  - con clotoides la curvatura también es continua (G2) [V] ([clotoide](https://en.wikipedia.org/wiki/Euler_spiral)).

  Si se integran el rumbo y la pendiente en pasos fijos de 1 a 2 studs, el resultado es una **poligonal ya parametrizada por longitud de arco**, que sirve a la vez de eje, de base de la malla y de índice para las consultas [A].
- **Límite geométrico:** el semiancho de la ruta más la banquina tiene que ser menor que el radio mínimo. Si no, el borde interno de las curvas se pliega y "el punto más cercano" salta de lado [A].

### Trazado

- **Gramática de piezas** (recta, curva abierta, curva cerrada, S) con parámetros sorteados por un generador pseudoaleatorio propio. RC-5 se cumple por construcción. El riesgo es que se vea repetitivo [A].
- **Ruido sobre la curvatura o el rumbo** (`math.noise`): da un trazado más orgánico.
  - `math.noise` no tiene semilla, da 0 en coordenadas enteras y se repite cada 256 unidades [V] ([math](https://create.roblox.com/docs/reference/engine/libraries/math)). La semilla se usa como desplazamiento.
- **Para que no se cruce:** si el rumbo se mantiene a menos de 90° de una dirección media, la ruta es el gráfico de una función y no puede cruzarse ni volver sobre sí. No cuesta nada, pero no permite curvas de 180° [A]. La alternativa es comprobar contra una grilla de las muestras ya generadas y volver a sortear.
- **Determinismo de `sin` y `cos`** entre PC y celular: **[NC]**. Solo importa si la ruta se genera por separado en más de un lugar (por ejemplo, en el cliente y en el servidor).

### Consultas

- **Cursor con ventana:** se recuerda la última muestra más cercana y se busca en ±k muestras. Es tiempo constante y alcanza para la superficie por rueda y por frame. No sirve después de un teletransporte [A].
- **Grilla hash de muestras:** sirve para el reset (RC-12), cuando el auto puede estar lejos de la ruta. Hay que mantenerla al generar y liberar tramos [A].

### Malla y colisión

- **`EditableMesh`** ([clase](https://create.roblox.com/docs/reference/engine/classes/EditableMesh), [AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService)):
  - **Límites:** 60.000 vértices y 20.000 triángulos por malla [V].
  - **Memoria en el cliente:** tiene presupuesto estricto; si se agota, crear un editable devuelve `nil` [V]. Se reporta un tope de 8 editables vivos a la vez en el cliente [S].
  - **Requisito para publicar:** hay que activar las APIs de Mesh/Image en la configuración de la experiencia [V]. Si además pide verificación de edad, está [NC].
  - **Replicación:** no se replica del servidor al cliente [S].
- **La colisión no se actualiza al editar.** Hay que crear la pieza con `AssetService:CreateMeshPartAsync`, que bloquea y no se puede paralelizar [V]/[S]. Medición en Studio (PC) [E]:

  | Triángulos | `Box` | `Default` | `PreciseConvexDecomposition` |
  | --- | --- | --- | --- |
  | 504 | 0,2 ms | 14,0 ms | 15,2 ms |
  | 1016 | 0,2 ms | 14,7 ms | 32,1 ms |

  - Con colisión útil, crear la malla de un tramo cuesta casi un frame a 60 FPS (16,7 ms). En celular es [NC], pero seguro cuesta más.
  - `Box` es casi gratis, pero envuelve el tramo en una caja, así que no sirve para una ruta con curvas.
  - Un tramo de unos 2.560 studs de largo falló. Probable causa: el tamaño máximo de una pieza (2.048 studs) [NC].
- **`CreateDataModelContentAsync`** "hornea" la malla en contenido estático, que sale del presupuesto de editables. Lo creado en el servidor se replica [S] ([anuncio](https://devforum.roblox.com/t/4541898)).
- **Terrain para la ruta:** tiene celdas de 4 studs, así que los bordes de un ancho fijo quedan dentados. El mundo de Terrain tiene un tope de ±128.000 studs [V] ([Terrain](https://create.roblox.com/docs/reference/engine/classes/Terrain)).
- **Uniones sin costuras (RC-4):**
  - el anillo de vértices del borde se calcula una sola vez y se comparte entre los dos tramos;
  - las normales salen del marco del eje;
  - las UV usan la longitud de arco;
  - conviene un solape mínimo en la colisión [A].

### Riesgo nuevo: distancia al origen

La ruta es infinita hacia adelante, y en 30 minutos el auto puede alejarse cientos de miles de studs. El Terrain tiene un tope de ±128.000 studs [V]. La precisión de la física y del render lejos del origen está [NC]. Puede hacer falta recentrar el mundo.

## Opciones

Hay tres decisiones. La de la malla y la colisión de la ruta está en `terreno.md` (opciones T1 a T4), porque se decide junto con el terreno.

### Decisión 1: eje y trazado

#### Opción E1: piezas con curvatura definida (rectas, arcos y transiciones)

El generador sortea, con la semilla, piezas como recta, curva abierta, curva cerrada y S. Cada pieza tiene un largo y una curvatura que no supera el máximo. Se integran el rumbo y la pendiente en pasos fijos, y el resultado es una poligonal parametrizada por longitud de arco. El rumbo se mantiene a menos de 90° de una dirección media, así que la ruta no puede cruzarse.

- **Bueno:**
  - RC-5 se cumple por construcción (radio mínimo garantizado);
  - la continuidad (RC-4) se cumple porque cada pieza arranca con el rumbo, la curvatura y la altura de la anterior;
  - la poligonal sirve a la vez para la malla, la superficie (#17) y el reset (RC-12);
  - es fácil de probar en el CLI con semilla fija.
- **Malo:** sin curvas de 180° ni vueltas.
- **Riesgoso:** que se vea repetitivo si la tabla de piezas es corta. Se mitiga variando los parámetros con ruido.
- **Funciona bien cuando:** la ruta avanza "hacia adelante", como en un rally de etapa.
- **Deja de funcionar cuando:** se quieren horquillas cerradas que vuelven sobre sí.

#### Opción E2: spline (Catmull-Rom centrípeta) sobre puntos de control sorteados

- **Bueno:** trazado orgánico y la técnica más conocida.
- **Malo:**
  - la curvatura máxima no se conoce de antemano, así que hay que muestrear y corregir para cumplir RC-5;
  - la longitud de arco necesita una tabla aparte;
  - el punto más cercano es más caro.
- **Riesgoso:** que se cuelen curvas imposibles si el chequeo por muestreo falla.
- **Funciona bien cuando:** se acepta revisar cada tramo después de generarlo.
- **Deja de funcionar cuando:** se exige la garantía de RC-5 por construcción.

**Recomendación del agente:** **E1.** Garantiza RC-4 y RC-5 por construcción y da gratis lo que necesitan los dos contratos.

### Decisión 2: dónde se genera el mundo

#### Opción G1: todo en el cliente, a partir de la semilla
- **Bueno:**
  - sin replicación;
  - la física del auto ya corre en el cliente (RN-2);
  - el contrato de superficie se consulta en el cliente;
  - el contenido creado en el cliente no sale por streaming [V].
- **Malo:** el servidor no ve el terreno, así que nada que simule el servidor puede apoyarse en él.
- **Riesgoso:** para multijugador (afuera del MVP) habría que repensarlo.
- **Funciona bien cuando:** el juego es de un jugador, como el MVP.

#### Opción G2: en el servidor, replicado
- **Bueno:** una sola fuente de verdad.
- **Malo:**
  - replicación continua de terreno infinito;
  - el cliente espera los datos;
  - con mallas, no se replican.
- **Riesgoso:** latencia y tirones en la red.

**Recomendación del agente:** **G1.**

### Riesgo a resolver en la arquitectura: distancia al origen

Con E1 la ruta avanza siempre en una dirección. Ejemplo de cálculo [A]: a una velocidad media de 60 studs/s, en 30 minutos son unos 108.000 studs, cerca del tope de ±128.000 del Terrain. La arquitectura tiene que incluir un **recentrado del mundo** (mover el origen cuando el auto se aleja), o arrancar en −120.000 para tener 240.000 studs de margen. Se confirma con un experimento: precisión y tope lejos del origen.

## Decisión
Beni eligió el 2026-10-14, en la sesión con el Agente B, las tres recomendaciones:

1. **Eje y trazado: E1**, piezas con curvatura definida (rectas, arcos y transiciones), con el rumbo a menos de 90° de una dirección media.
2. **Dónde se genera: G1**, todo en el cliente a partir de la semilla.
3. **Malla y colisión de la ruta: T1** (ver `terreno.md`): la ruta va plana dentro del Terrain, sin malla propia.

No toca contratos: la superficie (#17) se sigue calculando con los datos de la ruta.

## Arquitectura

Cubre toda el área de Calles infinitas (`src/world/`): la ruta (#9) y el terreno (#10). `terreno.md` remite acá.

### Encaje con la regla "el servidor es la autoridad"

`docs/reglas-de-trabajo.md` (sección 3) pide que la generación del mundo se decida en el servidor. Con G1 se cumple así:

- **El servidor decide la semilla** y se la manda al cliente. El cliente nunca elige la semilla.
- **El núcleo es puro y lo pueden usar los dos lados** (`src/world/core/`, que Rojo mapea a `ReplicatedStorage`). Con la misma semilla, el servidor puede recalcular la ruta (sin terreno, que es caro) para validar que la posición que reporta el auto sea creíble. Esa validación es del área de Conducción o de una capa de servidor futura; acá solo se deja posible.
- **El cliente solo construye** lo visual y lo físico local: el Terrain, y más adelante el decorado.

### Capas

Sigue la arquitectura general de #6 (`politica-de-codigo.md`): contratos ← núcleo ← adaptadores ← arranque (`src/app/`). El núcleo no conoce a Roblox.

```
src/world/
  core/                 núcleo puro (CLI luau, 87% de cobertura): ruta, consultas, superficie y terreno
  client/               adaptadores a Roblox: Terrain, loop por frame y proveedores de contratos
  server/               adaptador: elige la semilla y la manda
tests/world/            pruebas del núcleo
```

Todo el núcleo va junto en `core/`, para que entre en la medición de `src/*/core/**`. Los módulos de terreno los usa solo el cliente, pero son puros igual.

#### Núcleo: ruta, consultas y superficie

| Módulo | Responsabilidad | No hace |
| --- | --- | --- |
| `SeededRandom` | Generador pseudoaleatorio propio (PCG32) con estado explícito. `nextNumber`, `nextInteger`. | No usa `Random` ni `math.random`. |
| `RoadPieceCatalog` | Datos de cada tipo de pieza (recta, curva abierta, curva cerrada, S): rangos de largo, curvatura y pendiente, y pesos. | No sortea. |
| `RoadPieceSequencer` | Sortea la próxima pieza con `SeededRandom` y el catálogo. Respeta la curvatura máxima, el corredor de rumbo (menos de 90° de la dirección media) y la pendiente máxima. | No integra geometría. |
| `RoadPath` | Integra las piezas en pasos fijos y produce **muestras** (posición `vector`, rumbo, curvatura, altura y `s`), agrupadas en **tramos** (`segment`) consecutivos. Agrega tramos adelante y descarta los de atrás. | No sabe de chunks ni de Terrain. |
| `RoadQuery` | Dada una posición, devuelve el punto más cercano, la dirección, la distancia lateral con signo y `s`. Usa un cursor con ventana (rápido, por frame) y una grilla hash de muestras (para el reset, RC-12). | No genera. |
| `SurfaceClassifier` | Implementa `GetSurfaceAt` (#17): con `RoadQuery`, decide `Road` y `Shoulder` por distancia lateral, y `Mud` por manchones de ruido con semilla. El resto es `Grass`. | No lee el Terrain. |
| `WorldConfig` | Todos los valores de ajuste con unidad: ancho de ruta, banquina, curvatura máxima, paso de integración, largo de tramo, etc. | Nada de lógica. |

#### Núcleo: terreno y planificación

| Módulo | Responsabilidad | No hace |
| --- | --- | --- |
| `TerrainHeightField` | Altura del suelo en (x, z): la de la ruta cerca del eje, mezclada con colinas de `math.noise` a medida que se aleja (RC-6, el terreno sigue a la ruta). | No escribe vóxeles. |
| `VoxelChunkBuilder` | Para un chunk (por ejemplo, 128×128 studs), arma las tablas de material y de ocupación con `TerrainHeightField` y `SurfaceClassifier`. Los materiales van como claves propias (`"Ground"`, `"Grass"`, `"Mud"`), no como `Enum`. Reutiliza tablas para no presionar al recolector de basura. | No llama a la API de Roblox. |
| `ChunkPlanner` | Con la posición del auto y `RoadPath`, decide qué chunks hay que generar adelante (RC-2) y cuáles liberar atrás (RC-3), con histéresis. Arma una cola de trabajo ordenada por prioridad. | No mide tiempo ni escribe. |
| `WorkBudget` | Avanza la cola por pasos hasta agotar un presupuesto de milisegundos por frame. Recibe la función de reloj inyectada, así que en las pruebas se usa un reloj falso. | No usa `task` ni `os.clock` directo. |
| `OriginShift` | Decide cuándo recentrar el mundo y en cuánto (ver "Distancia al origen"). | No mueve nada. |

#### Adaptadores del cliente (`src/world/client/`)

| Módulo | Responsabilidad |
| --- | --- |
| `TerrainWriter` | Traduce las claves de material a `Enum.Material` y llama a `WriteVoxels` y al borrado con aire. Es lo único que toca `workspace.Terrain`. |
| `WorldClient` | Fábrica del área: recibe la semilla y las dependencias (reloj, posición del auto) y devuelve el mundo armado, con su función `step` para cada frame. **No se arranca sola:** la llama el arranque compartido `src/app/client/`, que es el único punto de armado (#6) y engancha `step` a `RunService.Heartbeat`. |
| `SurfaceProvider` | Expone `GetSurfaceAt` (#17) a Conducción, conectado con `SurfaceClassifier`. |
| `RoadResetProvider` | Expone el contrato del punto más cercano de la ruta (RC-12), conectado con `RoadQuery`. El contrato todavía no existe y va por su issue `contrato`. |

#### Adaptador del servidor (`src/world/server/`)

| Módulo | Responsabilidad |
| --- | --- |
| `WorldSeedServer` | Elige la semilla al arrancar la partida y se la manda al cliente (un `RemoteEvent` o un atributo). Lo arma `src/app/server/`. |

### Cómo fluye un frame en el cliente

1. `WorldClient` lee la posición del auto con el contrato "posición del jugador o del auto" (lo provee A). Mientras no exista, usa un stub dentro de `src/world/`.
2. `ChunkPlanner` actualiza la cola: si hace falta, `RoadPath` agrega tramos adelante y marca chunks para liberar.
3. `WorkBudget` avanza la cola hasta gastar el presupuesto del frame (por ejemplo, 4 ms en PC y menos en celular, en `WorldConfig`). Cada paso es "armar un pedazo de chunk" (`VoxelChunkBuilder`) o "escribirlo" (`TerrainWriter`).
4. Conducción consulta `SurfaceProvider` por rueda cuando quiera, en tiempo constante.

### Patrones y por qué

- **Raíz de composición:** los módulos del área se crean y conectan en `WorldClient`, y a esa fábrica la llama `src/app/client/`, el único punto de armado del juego (#6). Cumple "sin estado global" y permite probar cada módulo con dependencias falsas.
- **Inyección de dependencias:** el reloj, el generador pseudoaleatorio y la posición del auto entran por parámetro. Así el núcleo se prueba en el CLI con semilla y tiempo fijos.
- **Cola de trabajo con presupuesto por frame:** resuelve "sin tirones" sin `task.wait` en el núcleo. El trabajo pesado se corta en pasos chicos.
- **Tabla de datos para las piezas (`RoadPieceCatalog`):** sumar o ajustar una pieza es cambiar datos, no código. Cumple "sin números mágicos".
- **Adaptador (`TerrainWriter`, proveedores de contratos):** aísla la API de Roblox en una capa delgada que se prueba a mano.

### Distancia al origen

Hay dos caminos, y el Agente A prefiere el segundo para el MVP (revisión del PR #21):

- **Recentrar:** `OriginShift` decide mover el origen cuando el auto pasa un umbral. Eso obliga a mover en el mismo frame el auto con su velocidad, la cámara, las marcas y las partículas. Toca el área de Conducción y necesita un contrato nuevo ("el origen se movió en tal vector").
- **Arrancar en −120.000 studs** y avanzar hacia +120.000: hay 240.000 studs de margen. A una velocidad media de 100 studs/s, 30 minutos son 180.000 studs. No hace falta ningún contrato.

**Pendiente de decisión de Beni.** En los dos casos, antes del WP correspondiente, un experimento confirma la precisión del render y **de la física del auto** lejos del origen (por ejemplo, a 100.000 studs), porque el temblor lo sentiría el jugador.

### Pruebas (núcleo, CLI)

- Con la misma semilla sale la misma ruta: hash de las muestras de los primeros N tramos.
- **Propiedades** sobre cientos de semillas: curvatura menor o igual al máximo, rumbo dentro del corredor, pendiente máxima, sin saltos entre tramos (RC-4), la ruta no se cruza.
- `RoadQuery` comparada contra una búsqueda por fuerza bruta.
- `SurfaceClassifier` en bordes conocidos.
- `WorkBudget` con un reloj falso: nunca se pasa del presupuesto.

### División en WPs (propuesta)

1. **WP de la ruta:** `SeededRandom`, catálogo, secuenciador, `RoadPath`, `RoadQuery`, `SurfaceClassifier` y `WorldConfig`. Todo núcleo, sin Roblox.
2. **WP del terreno:** `TerrainHeightField`, `VoxelChunkBuilder`, `ChunkPlanner`, `WorkBudget`, `TerrainWriter` y `WorldClient`, más `WorldSeedServer`.
3. **WP del decorado:** árboles y rocas (RC-9 y RC-10). Lleva un diseño corto aparte. Ya queda fijado un requisito, por pedido de A para CP-5 (choques sin frustración): **los colisionadores son formas simples**, un cilindro o una cápsula para el tronco y una esfera o una caja para la roca, nunca la colisión exacta de la malla, que engancha o despide al auto.
4. **WP del origen:** depende de la decisión de arriba (recentrar o arrancar en −120.000).

Cada WP depende del anterior. Los proveedores de contratos (`SurfaceProvider` y `RoadResetProvider`) entran en el WP 2.

## Aprobación
Pendiente.
