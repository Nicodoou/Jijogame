# Nombres del proyecto

Un concepto, un nombre. Se consulta antes de nombrar algo nuevo y se agrega acá cuando aparece un concepto nuevo.

| Concepto (español) | Nombre en código | Definición |
| --- | --- | --- |
| Tramo | `segment` | Porción de ruta generada como unidad, que se crea delante del auto y se libera detrás. |
| Superficie | `SurfaceKind` | Tipo de suelo en una posición del mundo; define cómo agarra el auto. Contrato en `src/shared/contracts/Surface.luau` (#17). |
| Ruta (superficie) | `"Road"` | Tierra compactada que ocupa todo el ancho de la ruta. |
| Banquina | `"Shoulder"` | Franja angosta de tierra suelta a cada lado de la ruta. |
| Pasto | `"Grass"` | Terreno al costado de la ruta. |
| Barro | `"Mud"` | Manchones fuera de la ruta, ubicados a partir de la semilla. |
| Muestra | `RoadSample` | Punto del eje de la ruta que produce la integración en pasos fijos: posición, rumbo, curvatura, pendiente y `arcLength`. Los tramos son listas de muestras. |
| Pieza | `RoadPiece` | Trozo de ruta con un perfil de curvatura definido (`straight`, `gentleCurve`, `sharpCurve`, `sCurve` o `hairpinPair`). El `RoadPieceSequencer` las sortea una detrás de otra. |
| Guía | `RoadGuide` | Secuencia de puntos de paso, sorteada con la semilla, que recorre el área dando vueltas. La ruta local la sigue dentro de un túnel de `LOCAL_DEVIATION_MAX_STUDS`. |
| Punto de paso | `waypoint` | Cada punto de la guía, separado `GUIDE_STEP_STUDS` del anterior. |
| Perfil de cerros | `HillProfile` | Altura de la ruta en función de su `arcLength`: ruido con semilla dentro de una franja, con la pendiente y su cambio acotados. |
| Ruta viva | `LiveRoadIndex` | Las muestras de la ruta de los últimos `LIVE_LOOKBACK_STUDS` studs, en una grilla, para el anti-cruce. |
| Regla de altura | `LIVE_HEIGHT_RULE_RADIUS_STUDS` | Parte del anti-cruce de `LiveRoadIndex`: dos pasadas no vecinas cercanas no pueden diferir en altura más de lo que el terreno salva con su pendiente máxima entre las dos banquinas. |
| Paso de generación | `generateStep` | Avance acotado de la ruta (sortear una pieza, probar una alternativa o retroceder). `RoadPath.generateStep` devuelve el tramo cuando se completa y `nil` mientras tanto. |
| Horquilla doble | `hairpinPair` | Pieza de dos horquillas para lados opuestos (de 120° a 180° cada una), unidas por una recta corta: el rumbo neto es cero. |
| Longitud recorrida sobre el eje | `arcLength` | Distancia en studs, medida sobre el plano horizontal, desde el punto de partida de la ruta hasta una muestra o un punto del eje. |
| Desvío lateral | `lateralOffset` | Distancia con signo entre una posición y el punto más cercano del eje: positiva a la derecha del sentido de marcha, negativa a la izquierda. Es la que usa `RoadQuery`. |
| Posición del auto | `GetVehiclePosition` | Función que devuelve la posición actual del auto del jugador local. Contrato en `src/shared/contracts/VehiclePosition.luau` (#22). |
| Controles | `VehicleControls` | Dirección (−1 izquierda, +1 derecha), acelerador y freno (0 a 1) y freno de mano, ya suavizados. Los produce `InputSmoother` y los consume `VehicleSimulator`. |
| Muestra del chasis | `ChassisSample` | Lo que el núcleo del auto lee del chasis en cada paso: centro de masa, ejes unitarios en el mundo, velocidades, masa y gravedad. |
| Contacto de rueda | `WheelContact` | Resultado del rayo de una rueda: si pegó, la distancia desde el punto de montaje, el punto y la superficie. |
| Ángulo de deriva | `driftAngle` | Ángulo entre el frente del auto y su velocidad. Es positivo cuando la velocidad apunta a la derecha del frente. |
| Deslizamiento | `slipRatio`, `slipAngle` | `slipAngle` es el ángulo entre la rueda y su velocidad (positivo a la derecha). `slipRatio` es la fuerza pedida sobre el agarre disponible; por encima de 1 el neumático desliza. |
| Carga | `load` | Fuerza vertical que la suspensión hace sobre una rueda. Es el límite de agarre del neumático. |
| Reparto trasero | `REAR_BIAS` | Fracción de la fuerza del motor que va al eje trasero (0,7 inicial). |
| Orden de las ruedas | FL, FR, RL, RR | Delantera izquierda, delantera derecha, trasera izquierda y trasera derecha. Es el orden de todas las listas de ruedas del núcleo del auto. |
| Punto de ruta | `RoadPoint` | Punto sobre el eje de la ruta, a la altura de la superficie, con su dirección hacia adelante y su `arcLength`. Contrato en `src/shared/contracts/RoadPoint.luau` (#35). |
| Punto más cercano de la ruta | `GetNearestRoadPoint` | Función que devuelve el `RoadPoint` del eje más cercano a una posición, ignorando la altura. Se usa para el reset (RC-12). |
| Punto de aparición | `GetSpawnPoint` | Función que devuelve el inicio de la ruta, donde aparece el auto. |
| Mundo listo | `IsWorldReadyAt` | Función que dice si el Terrain alrededor de una posición ya está escrito. Contrato en `src/shared/contracts/WorldReady.luau` (#36). |
| Bioma | `Biome` | Tipo de lugar (bosque, montaña...) con su clima, terreno, materiales, superficies y decorado. El MVP tiene uno solo: `forest`. Diseño en `docs/disenos/biomas.md`. |
| Ficha de bioma | `BiomeDefinition` | Los datos de un bioma: `id`, caja de clima, `terrain`, `materials`, `surfaces` y `decoration`. Sumar un bioma es agregar una ficha. |
| Catálogo de biomas | `BiomeCatalog` | Módulo con las fichas del juego (`forest`), la lista `all` en orden fijo y `validate`. Las funciones de biomas reciben el catálogo por parámetro. |
| Clima | `ClimateField` | Campo de relieve, humedad y temperatura de cada punto, normalizado por cuantil a `u` en [0, 1]. La temperatura sale del ruido propio menos un factor del relieve. |
| Peso de bioma | `BiomeWeight` | Cuánto pesa cada bioma en un punto (`BiomeWeights.compute`): `max(0, 1 - d / R) ^ k`, normalizado para sumar 1. Los consumidores leen pesos, no preguntan "qué bioma es". |
| Mezcla de biomas | `BiomeBlend` | Ayudas que combinan los pesos: `blendNumber`, `pickMaterial`, `pickOffroadSurface`, `pickDeepMaterial` y `newPicker` (las mismas elecciones con los desplazamientos del ruido calculados una sola vez). |
| Mapa de biomas | `BiomeMap` | Los pesos de bioma de cada punto: del clima (`ClimateField`) a los pesos (`BiomeWeights`), exactos en un punto o con el clima interpolado de la grilla de un chunk. |
| Chunk | `chunk` | Cuadrado de `CHUNK_SIZE_STUDS` (128) de lado en el plano, con coordenadas enteras (`ChunkGrid`). El Terrain se escribe de a un chunk. |
| Vóxel | `voxel` | Celda de `TERRAIN_VOXEL_STUDS` (4) del Terrain. En el núcleo se indica con índices enteros: el vóxel `i` cubre de `4 * i` a `4 * i + 4` studs. |
| Campo de alturas | `TerrainHeightField` | Altura del terreno en (x, z): plana en la ruta y la banquina, y fuera de ella una base que mezcla las pasadas cercanas más las colinas. |
| Bloque de ruta | `RoadBlock` | Arco corto del eje (`TERRAIN_ROAD_BLOCK_STEPS` pasos, 64 studs) con sus coordenadas en listas de números. Es lo que recorre el campo de alturas (`RoadBlocks`). |
| Armador de chunks | `VoxelChunkBuilder` | Arma las tablas de material y de ocupación de un chunk, de a pasos chicos (preparación, una fila de columnas, una fila de vóxeles). |
| Presupuesto de trabajo | `WorkBudget` | Avanza una fuente de trabajo hasta gastar `WORK_BUDGET_MS_PER_FRAME`, con el reloj inyectado. |
| Planificador del mundo | `WorldPlanner` | Sigue al auto sobre la ruta, genera y libera ruta, decide qué chunks hacen falta y lleva el registro de los escritos. Provee los cuatro contratos del área. |
| Sumidero de chunks | `ChunkSink` | Lo que el adaptador le da al planificador para escribir un chunk en el Terrain (`writeChunk`) o borrarlo con aire (`clearChunk`). |
| Ventana de terreno | `TerrainWindow` | Cuánto terreno se pide y se conserva alrededor del auto (corredor y ruta de atrás) y cuánta ruta recuerdan los bloques. |
| Kickdown | `KICKDOWN_THROTTLE`, `KICKDOWN_FORCE_MARGIN`, `KICKDOWN_RPM_MARGIN` | Con el acelerador a fondo (desde `KICKDOWN_THROTTLE`) la caja baja a la marcha que más empuja, si empuja al menos `KICKDOWN_FORCE_MARGIN` más y queda `KICKDOWN_RPM_MARGIN` por debajo del corte suave. |
| Empuje relativo de una marcha | `gearForce` | Fracción del empuje de la primera marcha a pleno pedal que daría una marcha a una velocidad: curva de torque, relación y corte suave. |
