# Terreno: generación en tiempo de ejecución

**Issue:** #10
**Requerimientos:** RC-6, RC-8, RC-9, RC-10, RC-11, RN-1
**Estado:** arquitectura propuesta

## Investigación

La hizo el subagente `investigador` el 2026-10-14. Las marcas significan: **[V]** verificado en una fuente primaria, **[S]** fuente secundaria, **[A]** análisis propio, **[NC]** no confirmado y **[E]** medido por el Agente B en Studio (PC) con el MCP.

### Terrain de Roblox

- **API:** `WriteVoxels` y la familia `Fill*` son estables, pero corren en el hilo principal [V] ([Terrain](https://create.roblox.com/docs/reference/engine/classes/Terrain)).
  - Las tablas se pueden armar en Parallel Luau, pero la escritura va en el hilo principal.
  - No hay API de alturas.
  - Existe una familia `*Async_beta` sin documentación oficial; si se puede usar en un juego publicado está [NC].
- **Costo medido [E]:**

  | Pedazo | Armar las tablas | `WriteVoxels` |
  | --- | --- | --- |
  | 32×32 studs (8×16×8 vóxeles) | 0,3 ms | 4,2 ms (primera llamada, incluye el arranque) |
  | 64×64 studs (16×16×16) | 0,9 ms | 0,1 ms |
  | 128×128 studs (32×16×32) | 2,8 ms | 0,4 ms |

  Entra holgado en un presupuesto por frame. En el foro hay quejas de tirones con escrituras grandes [S]. En celular está [NC].
- **Planicidad [E]:** una franja escrita a una altura que no es múltiplo de 4 (21,3 studs) quedó **perfectamente plana** (441 rayos, variación 0). Quedó 2 studs más arriba de lo pedido, así que hay que calibrar la fórmula de ocupación.
- **Rampas [E]** (pedido de A en el PR #21): rampas de 2°, 5° y 10°, medidas con 301 rayos cada 0,4 studs a lo largo de 120 studs.

  | Pendiente | Ondulación de la altura | Desvío máximo de la normal | Salto máximo entre muestras vecinas |
  | --- | --- | --- | --- |
  | 2° | 0,06 studs | 1,7° | 0,012 studs |
  | 5° | 0,11 studs | 2,8° | 0,020 studs |
  | 10° | 0,25 studs | 5,8° | 0,043 studs |

  - **No hay escalones de vóxel:** la superficie es continua.
  - **Hay una ondulación suave:** la altura sube y baja hasta 0,25 studs y la normal se desvía hasta más o menos la mitad de la pendiente.
  - El corrimiento constante de unos 2 studs se repite (es el de la fórmula de ocupación, que se calibra).
  - **Consecuencia para el auto:** si la suspensión usa la normal de un solo rayo, la va a sentir. Hay dos mitigaciones posibles, que se acuerdan con A: promediar varios rayos por rueda, o que el mundo exponga la normal analítica de la ruta (sale de la poligonal del eje).
- **Resolución:** vóxeles de 4 studs [V]. La superficie es lisa, pero el borde entre materiales (por ejemplo, entre la ruta y el pasto) cae en la grilla de 4 studs.
- **Cliente o servidor:**
  - lo que escribe el servidor se replica [V];
  - lo que escribe el cliente queda local [S];
  - el contenido creado en el cliente no sale por streaming [V] ([streaming](https://create.roblox.com/docs/workspace/streaming)).
- **Materiales:** `Ground`, `Grass`, `LeafyGrass` y `Mud` existen [V]. Los `MaterialVariant` aplican al Terrain solo como reemplazo global del lugar [V] ([materiales](https://create.roblox.com/docs/parts/materials)).
- **RC-11:** el Terrain es una sola instancia, así que lo cumple sin esfuerzo.
- **Tope del mundo:** ±128.000 studs [V]. Ver "Riesgo: distancia al origen" en `ruta.md`.
- **Memoria:** se mide con las etiquetas `TerrainVoxels` y `GraphicsTerrain` de `Stats` [V]. Si al borrar un tramo (escribiendo aire) se devuelve memoria está [NC].
- **Lo nuevo de 2026** (Early Access de Terrain, path splines, SDF): no está disponible para jugadores fuera del programa [S], así que **no sirve para el MVP**.

### Mallas propias (`EditableMesh`)

- **Límites:** 60.000 vértices y 20.000 triángulos por malla [V]. La memoria del cliente tiene un presupuesto estricto [V], y se reporta un tope de 8 editables vivos [S]. Hay que activar las APIs de Mesh/Image para publicar [V]. Si además pide verificación de edad, está [NC].
- **Colisión:** hay que crear la pieza con `CreateMeshPartAsync` [V], que bloquea. Medido [E]: unos 14–15 ms con `Default` y hasta 32 ms con `PreciseConvexDecomposition`. Con `Box` cuesta 0,2 ms, pero `Box` no sirve como suelo.
- **Fidelidad:** la colisión `Default` es una descomposición convexa, imprecisa en ondulaciones [V] ([CollisionFidelity](https://create.roblox.com/docs/reference/engine/enums/CollisionFidelity)).
- **Replicación:** no se replica del servidor al cliente [S].

### Decorado (RC-9 y RC-10)

- SLIM y `StreamingMesh` no sirven para contenido generado en tiempo de ejecución [V] ([SLIM](https://create.roblox.com/docs/workspace/streaming/slim)).
- Para el decorado lejano: una sola malla subida y clonada (instancing), sin colisión, `CanQuery` y `CanTouch` en false, `CastShadow` en false. El borde se esconde con `Atmosphere` [V] ([mejorar rendimiento](https://create.roblox.com/docs/performance-optimization/improve)).
- Para la colisión por distancia de árboles y rocas: una pool que alterna `CanCollide` con histéresis, o un grupo chico de colisionadores invisibles que se mueven a los obstáculos cercanos [A]. Su costo está [NC] y se define en la arquitectura.

## Opciones

Se deciden junto con la malla de la ruta (#9), porque el terreno es lo que pisa el auto fuera de la ruta y, según la opción, también en la ruta.

### Opción T1: todo con Terrain (suelo y ruta)

El cliente escribe el suelo con `WriteVoxels`, por pedazos y con un presupuesto por frame. La ruta queda plana dentro del mismo Terrain, con material `Ground`. El pasto es `Grass` y el barro `Mud`.

- **Bueno:**
  - medido rápido (unos 3 ms por pedazo de 128×128 en PC) y plano;
  - la colisión viene incluida, sin `CreateMeshPartAsync`;
  - cumple RC-11 sin esfuerzo;
  - no hace falta activar APIs especiales.
- **Malo:** el borde de la ruta queda en la grilla de 4 studs, así que el borde visual entre tierra y pasto es serruchado. La superficie del contrato (#17) sigue siendo nítida, porque sale de los datos de la ruta y no del material.
- **Riesgoso:**
  - el costo en celular está [NC];
  - el tope de ±128.000 studs obliga a recentrar el mundo y reescribir el terreno cercano (ver `ruta.md`).
- **Funciona bien cuando:** el borde serruchado se tolera o se disimula (banquina de tierra suelta, que ya está en el contrato, más pasto alto).
- **Deja de funcionar cuando:** se quiere un borde de ruta prolijo, como de asfalto pintado.

### Opción T2: Terrain para el suelo + malla visual de la ruta sin colisión

Como T1, pero encima del Terrain plano va una malla (`EditableMesh`) que solo se ve: borde nítido, textura propia y UV continuas. La pieza se crea con colisión `Box` y `CanCollide=false`, que cuesta unos 0,2 ms [E]. El auto pisa el Terrain plano que queda debajo.

- **Bueno:**
  - borde de ruta nítido;
  - no paga el tirón de la colisión;
  - se puede sumar después de T1 sin rehacer nada.
- **Malo:**
  - hay que activar las APIs de Mesh/Image para publicar;
  - hay que respetar el presupuesto de editables (destruir o "hornear" cada malla después de crear la pieza).
- **Riesgoso:**
  - si la pieza sigue viva después de destruir el editable está [NC];
  - el posible requisito de verificación de edad o de identidad está [NC];
  - el render en algunos Android viejos [S].
- **Funciona bien cuando:** el borde serruchado de T1 molesta.
- **Deja de funcionar cuando:** el presupuesto de editables en celular es muy chico.

### Opción T3: todo con mallas propias (suelo y ruta)

- **Bueno:** libertad total de forma; no hay tope de 128.000 studs.
- **Malo:**
  - un tirón de 14 a 32 ms por pedazo [E];
  - colisión convexa imprecisa en las ondulaciones;
  - límites de memoria y de cantidad de editables en el cliente.
- **Riesgoso:** no cumple "sin tirones" (tabla de rendimiento de los requerimientos).
- **Funciona bien cuando:** Roblox permita crear la colisión sin bloquear (hoy no se puede).
- **Deja de funcionar cuando:** se exige 60 o 30 FPS estables.

### Opción T4: Terrain para el suelo + piezas de ruta prearmadas

Rectas y arcos modelados en Blender o Studio, clonados de una pool.

- **Bueno:** casi cero costo en ejecución y colisión precalculada.
- **Malo:**
  - hacen falta assets 3D (un pedido a Nico o a Beni);
  - la forma se limita a la biblioteca de piezas;
  - cada combinación de pendiente multiplica las variantes.
- **Riesgoso:** costuras entre piezas y saltos de cabeceo con pendientes.
- **Funciona bien cuando:** el trazado se arma con una biblioteca chica de piezas.
- **Deja de funcionar cuando:** se quieren pendientes y curvas variadas (RC-5 y RC-6).

**Recomendación del agente:** **T1 para arrancar**, con **T2 como mejora visual** si el borde serruchado molesta en las pruebas de juego. T1 es la única opción medida que es rápida, plana y sin APIs especiales. T2 se suma encima sin rehacer nada.

## Decisión
Beni eligió el 2026-10-14, en la sesión con el Agente B: **T1, todo con Terrain** (suelo y ruta), generado en el cliente (G1 de `ruta.md`). T2 (malla visual de la ruta encima) queda como mejora posible si el borde serruchado molesta en las pruebas de juego.

## Arquitectura
Está en `ruta.md`, sección Arquitectura, que cubre toda el área de Calles infinitas (ruta y terreno).

## Aprobación
Pendiente.
