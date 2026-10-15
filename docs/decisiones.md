# Decisiones

Registro de decisiones tomadas, la más nueva arriba. Formato en `docs/coordinacion-agentes.md`, sección 9.

Nada que esté en este registro se reabre sin un issue nuevo que explique por qué.

## 2026-10-15 — Auto: vuelve a AWD 50/50 y freno de mano suave
**Decidió:** Nico (después de manejar el experimento `exp/ajustes-manejo`)
**Issue:** #8 (cambia el valor de "Auto: tracción trasera y freno de mano que suelta la cola")
**Decisión:** `REAR_BIAS` pasa de 1,0 a 0,5, con menos agarre general (`TIRE_FRICTION` 0,7), un freno de mano que baja el agarre trasero solo al 85% y en forma progresiva, más dirección (36° y 24°) y menos empuje (120). La reversa tiene empuje, velocidad y ángulo de dirección propios.
**Por qué:** con esta combinación Nico logró derrapar a gusto. La tracción trasera con el freno de mano fuerte hacía trompo, y la reversa patinaba por exceso de empuje y de ángulo.
**Descartado:** mantener la tracción trasera con el freno de mano al 50–60% (trompo con la dirección sostenida, medido con inputs pregrabados).

## 2026-10-15 — Auto: modelo visual sin masa y centro de masa por configuración
**Decidió:** Nico
**Issue:** #7 (diseño: `docs/disenos/auto.md`, sección "Centro de masa y modelo del auto")
**Decisión:** el modelo del auto es solo visual (sin masa ni colisión). La física la dan el `Body` y un lastre invisible que el adaptador ubica según `FRONT_WEIGHT_FRACTION` y `CENTER_OF_MASS_HEIGHT_STUDS`. Roblox calcula el centro de masa y la inercia reales. El núcleo calcula el brazo de cada rueda desde el centro de masa real. No se simula un corrimiento del centro de masa al doblar: el traspaso de carga ya sale de la suspensión.
**Por qué:** cualquier modelo se puede usar sin cambiar el manejo, y el reparto de peso pasa a ser un valor ajustable (CP-6).
**Descartado:** dejar que la masa del modelo defina el centro de masa (cada modelo cambiaría el manejo); un corrimiento dinámico del centro de masa con un factor por motor (cuenta dos veces el traspaso de carga que ya da la suspensión).

## 2026-10-15 — Ruta de rally con guía grande y tamaño de las pruebas largas
**Decidió:** Beni
**Issue:** #37 (PR #46; experimento en la rama `exp/ruta-guia`)
**Decisión:** (1) la ruta de rally se arma con una guía grande (puntos de paso con retroceso) y piezas locales que la siguen dentro de un túnel, con rumbo relativo acotado, retroceso de la ruta, horquillas de a pares y un anti-cruce corregido (vecinas hasta 1.200 studs de arco, distancia libre de 200). (2) Las pruebas de propiedades de la ruta corren con 40 semillas × 400 tramos en el CI, y la corrida completa de 200 × 400 se hace a mano antes de cada PR que toque la ruta, con la salida pegada en el PR.
**Por qué:** la versión 1 (generar y probar pieza por pieza) tenía una regla anti-cruce imposible y se encerraba. La guía da 0 encierros y 0 cruces en 200 semillas × 400 tramos en el prototipo. Correr 200 × 400 en cada CI tardaría varios minutos.
**Descartado:** relajar la garantía con memoria corta; seguir explorando sin guía (mirar varias piezas adelante); correr siempre 200 semillas en el CI.

## 2026-10-15 — Auto: tracción trasera y freno de mano que suelta la cola
**Decidió:** Nico (después de manejar el experimento `exp/manejo`)
**Issue:** #8 (cambia el valor inicial de la decisión "Auto: raycast con fuerzas, neumático con tope y AWD con sesgo trasero")
**Decisión:** `REAR_BIAS` pasa de 0,7 a 1,0 (tracción trasera), con más empuje (`FIRST_GEAR_PEAK_ACCELERATION` 180) y sin asistencia de contravolante. El freno de mano baja el agarre trasero en vez de frenar, y al soltarlo el agarre vuelve en menos de un segundo. Al derrapar, la dirección permite contravolantear más allá del límite por velocidad. El modelo físico, el neumático y el resto de la decisión anterior no cambian.
**Por qué:** con AWD 70% y el empuje inicial no se podía derrapar: el agarre de la ruta le ganaba al motor y el freno de mano hacía trompo o frenaba en seco. Manejándolo, la combinación de arriba se sintió "bastante bien".
**Descartado:** temperatura de neumáticos y frenos (cambia en segundos o minutos y no resuelve el balance del derrape; queda como idea para después del MVP), y mantener AWD subiendo solo el empuje.

## 2026-10-15 — Ruta de rally: trazado libre en un área acotada, perfil de cerros y 16 studs de ancho
**Decidió:** Beni (después de probar la ruta del WP-2 en Studio)
**Issue:** #37 (reabre "El mundo arranca en −120.000 studs, sin recentrar" y retoma la idea de Nico del #23)
**Decisión:** la ruta va para cualquier lado dentro de un área acotada cerca del origen, da vueltas y cambia de dirección, sin que su parte viva pase cerca de sí misma. El contenido sale de la semilla y del progreso (`arcLength`), así que una zona vieja se reescribe si la ruta vuelve. La altura sigue un perfil de lomas y valles (ruido con semilla), con una pendiente máxima de 12° a 15° y dentro de una franja. El ancho de la ruta pasa a 16 studs.
**Por qué:** la ruta del WP-2 iba casi siempre hacia adelante y era muy plana: no se sentía de rally. Además, el auto queda siempre cerca del origen.
**Descartado:** abrir el corredor de rumbo a ±120° con horquillas (sigue avanzando en promedio); solo más curvas sin tocar el corredor; agrandar la pendiente por pieza sin perfil de cerros (la altura queda sin control); anchos de 10 y 24 studs.

## 2026-10-15 — Auto: raycast con fuerzas, neumático con tope y AWD con sesgo trasero
**Decidió:** Nico
**Issue:** #7, #8 (diseño: `docs/disenos/auto.md`)
**Decisión:** el auto usa un modelo propio, con un raycast por rueda y las fuerzas aplicadas al chasis en `PreSimulation`, y la lógica en `src/vehicle/core/`. Neumático lineal con tope y círculo de fricción, con caída opcional y contravolante suave. Tracción total con `rearBias` = 0,7, parametrizable. Queda condicionado al experimento de estabilidad a 30 FPS (`exp/auto-fisica`).
**Por qué:** es la única opción con el derrape, el peso y el agarre por superficie bajo control, testeables en el núcleo y afinables por parámetros.
**Descartado:** constraints de Roblox (el derrape casi no se puede afinar y casi no queda lógica testeable), cuerpo propio (choques a mano), Pacejka y arcade puro (para arrancar), y RWD (más difícil para un jugador nuevo; se puede llegar a eso con `rearBias` = 1).

## 2026-10-14 — El mundo arranca en −120.000 studs, sin recentrar
**Decidió:** Beni (lo había propuesto el Agente A en la revisión del PR #21)
**Issue:** #9, #10 (PR #21, `docs/disenos/ruta.md`, "Distancia al origen")
**Decisión:** la ruta arranca en x = −120.000 y avanza hacia +x. El mundo no se recentra. Si alguien llega cerca de +120.000, la etapa termina.
**Por qué:** el Terrain tiene un tope de ±128.000 studs. Arrancando en −120.000 hay 240.000 studs de margen (30 minutos a 100 studs/s son 180.000) y no hace falta un contrato con Conducción para mover el auto, la cámara y los efectos.
**Descartado:** recentrar el mundo cuando el auto se aleja del origen.

## 2026-10-14 — Ruta y terreno: piezas con curvatura, todo Terrain, generado en el cliente
**Decidió:** Beni
**Issue:** #9, #10 (PR #21; diseños `docs/disenos/ruta.md` y `docs/disenos/terreno.md`)
**Decisión:** el eje de la ruta se arma con piezas de curvatura definida (rectas, arcos y transiciones) sorteadas con la semilla, con el rumbo a menos de 90° de una dirección media. El suelo y la ruta se escriben en el Terrain de Roblox (la ruta plana, con material `Ground`). Todo se genera en el cliente a partir de la semilla.
**Por qué:** RC-4 y RC-5 se cumplen por construcción. El Terrain medido en Studio es rápido (unos 3 ms por pedazo de 128×128 studs), queda plano y trae la colisión sin el tirón de `CreateMeshPartAsync` (14 a 32 ms). En el cliente no hay replicación y queda junto a la física del auto (RN-2).
**Descartado:** spline Catmull-Rom; malla visual de la ruta encima del Terrain (queda como mejora futura); todo con mallas propias; piezas de ruta prearmadas; generación en el servidor.

## 2026-10-14 — Política de pruebas, cobertura y estructura de `src/`
**Decidió:** ambos
**Issue:** #6 (diseño: `docs/disenos/politica-de-codigo.md`)
**Decisión:** (1) la lógica pura vive en `src/<área>/core/`, se prueba con el CLI `luau` y se le exige el 87% de cobertura de líneas con `luau --coverage`; los adaptadores al motor son delgados y se prueban a mano en Studio. (2) `src/` se organiza primero por área (`world`, `vehicle`, `input`, `camera`, `shared/contracts`), con `server/`, `client/` y `shared/` dentro de cada área cuando hagan falta. (3) Las utilidades puras viven en el `core/` de cada área, no en una carpeta compartida. Herramientas base: Rokit, Rojo, StyLua, Selene, luau-lsp con `--!strict` y CI en GitHub Actions.
**Por qué:** dentro de Roblox no se puede medir cobertura; el CLI `luau` es lo único que la mide hoy, y solo sobre Luau puro.
**Descartado:** Jest dentro de Roblox (sin cobertura y con dependencia de Open Cloud), Lune con lune-test (sin cobertura hoy), la variante híbrida (dos frameworks), `src/` primero por lado y una carpeta compartida de utilidades.

## 2026-10-14 — Reparto de áreas: Conducción para A, Calles infinitas para B
**Decidió:** ambos
**Issue:** #5
**Decisión:** el Agente A (con Nico) toma Conducción (`src/vehicle/`, `src/input/`, `src/camera/`, CP-1 a CP-16) y el Agente B (con Beni) toma Calles infinitas (`src/world/`, RC-1 a RC-12). Los issues #7 y #8 pasan a `para-agente-a` y los #9 y #10 a `para-agente-b`. En la tabla de contratos, el que provee o usa cada contrato cambia con el área; las firmas no cambian.
**Por qué:** Nico prefiere hacer el auto y Beni estuvo de acuerdo.
**Descartado:** la propuesta inicial de la coordinación (Calles infinitas para A, Conducción para B).

## 2026-10-14 — Los agentes mergean con aprobación de su persona
**Decidió:** Nico (pendiente de que Beni lo vea en el PR #11)
**Issue:** #11 (PR de setup)
**Decisión:** los merges a `main` los hacen los agentes A y B, cada uno con la aprobación explícita de su persona; si el PR toca un contrato o el área del otro, con la aprobación de las dos. El agente deja en el PR un comentario con quién aprobó.
**Por qué:** que los humanos no tengan que hacer el merge a mano, sin perder el control sobre qué entra a `main`.
**Descartado:** que solo los humanos mergeen (regla original de la coordinación).
