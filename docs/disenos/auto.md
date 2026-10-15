# Auto: modelo de física, neumático y tracción

**Issue:** #7 (modelo de física), #8 (tipo de auto)
**Requerimientos:** CP-1 a CP-16, RN-2
**Estado:** opciones presentadas

## Investigación

La hizo el subagente `investigador` el 2026-10-15. Las marcas significan: **[V]** verificado en una fuente primaria, **[S]** fuente secundaria y **[NC]** no confirmado. El orquestador volvió a verificar la frecuencia de la física, la recomendación de modo fijo para juegos de carreras y los datos de A-Chassis.

### Lo que condiciona el diseño

- **No hay un sistema de vehículos oficial de Roblox** vigente que reemplace al modelo propio [NC: no apareció en la búsqueda]. Lo que hay son `VehicleSeat`, los constraints y chasis de la comunidad, como [A-Chassis](https://github.com/lisphm/A-Chassis) (MPL-2.0, mantenido, sin documentar su modelo físico).
- **La física corre a 240 Hz por defecto**, con varios pasos por frame. La documentación recomienda `PhysicsSteppingMethod = Fixed` para juegos de carreras [V] ([adaptive timestepping](https://create.roblox.com/docs/physics/adaptive-timestepping)). El código Luau corre **una vez por frame**: a 30 FPS, una fuerza calculada por el script rige sobre unos 8 pasos de física. Es el riesgo central de un modelo propio.
- **Eventos:**
  - `RunService.PreSimulation` corre antes de la física y reemplaza a `Stepped`, que está deprecado. Ahí se calculan y aplican las fuerzas.
  - `PreRender` (cliente) reemplaza a `RenderStepped`, y sirve para la cámara [V] ([RunService](https://create.roblox.com/docs/en-us/reference/engine/classes/RunService.md)).
- **Rayos:**
  - `Raycast` devuelve `Position`, `Normal`, `Material` y `Distance`, y pega en Terrain.
  - `Spherecast` y `Blockcast` **no detectan lo que ya intersecta la forma al inicio** [V] ([WorldRoot](https://create.roblox.com/docs/en-us/reference/engine/classes/WorldRoot.md)).
- **Velocidades:** asignar `AssemblyLinearVelocity` directamente está desaconsejado. Las opciones son `VectorForce` o `ApplyImpulse` [V]. Si `VectorForce` persiste entre pasos de física, la documentación no lo dice [NC].
- **Dueño de red (RN-2):**
  - el servidor llama `SetNetworkOwner` y el cliente simula con respuesta inmediata;
  - Roblox no verifica la física del cliente;
  - todas las partes del vehículo deben tener el mismo dueño [V] ([network ownership](https://create.roblox.com/docs/physics/network-ownership)).
- **Antecedentes en el foro [S]:**
  - un chasis por raycast tiembla con FPS bajo, porque la suspensión se actualiza solo una vez por frame ([hilo](https://devforum.roblox.com/t/solvedproblem-with-raycasting-car-in-low-fps/3042743));
  - una suspensión hecha con scripts "takes a lot of time and experience".
- **Terreno** (`terreno.md`): la `Normal` del Terrain en rampas se desvía hasta la mitad de la pendiente (2,8° en una rampa de 5°). Si cada rueda usa su normal tal cual, la suspensión recibe ruido.
- **Input:**
  - el Input Action System (`InputContext`, `InputAction`, `InputBinding`) está vigente, pero no documenta una zona muerta [V];
  - `ContextActionService` y `UserInputService` siguen vigentes;
  - la zona muerta y las rampas conviene hacerlas en el núcleo, sea cual sea la API.

### Referencia de modelo de neumático

Marco Monster, [Car Physics for Games](https://www.asawicki.info/Mirror/Car%20Physics%20for%20Games/Car%20Physics%20for%20Games.html) (2003):
- **Ángulo de deslizamiento por rueda:** el ángulo entre hacia dónde apunta la rueda y hacia dónde se mueve.
- **Fuerza lateral:** proporcional al deslizamiento hasta un tope de `mu × carga`.
- **Transferencia de peso:** `Wf = (c/L)·W − (h/L)·M·a`.
- **Baja velocidad:** a poca velocidad se trata como cinemática.

En el foro se reporta inestabilidad a baja velocidad si el deslizamiento no se regulariza [S]. **No encontramos charlas ni postmortems de juegos arcade** [NC].

### Tracción

No hay fuentes de desarrolladores [NC]. Las guías de jugadores de Forza describen AWD con sesgo trasero (~70% a ~100%) como lo más fácil para derrapar, y un 50/50 como propenso al subviraje [S]. En cualquier modelo propio, el reparto es un parámetro (`rearBias`), así que se puede cambiar después sin rehacer el núcleo.

### Pendiente de confirmar con experimentos (`exp/auto-fisica`)

1. Si `VectorForce` persiste entre pasos de física, y cómo se compara con `ApplyImpulse` (auto en el aire, 30 y 60 FPS).
2. Rigidez y amortiguación máximas estables de una suspensión por raycast con **FPS limitado a 30**, con `Fixed` y con `Adaptive`.
3. Ruido de la `Normal` en rampas de Terrain: normal por rueda, normal suavizada o el eje "arriba" del chasis.
4. Qué pasa con `Raycast` si el origen está dentro del Terrain.
5. Costo en un celular de gama media.

## Opciones

Hay tres decisiones: **el modelo de física** (#7), **el modelo de neumático** y **el tipo de tracción** (#8).

### Decisión 1: modelo de física (#7)

#### Opción F1: constraints de Roblox

Las ruedas son partes reales, con `HingeConstraint` (motor y dirección) y `SpringConstraint` o `CylindricalConstraint` (suspensión). El agarre sale de la fricción de los materiales.

- **Bueno:** es lo más rápido de armar. El solver integra a 240 Hz sin importar el FPS del script, y las colisiones y el peso salen del motor.
- **Malo:**
  - el derrape depende de cómo el motor combina la fricción, y no hay curva que se pueda ajustar (CP-1);
  - el agarre por superficie obliga a cambiar propiedades de las ruedas por frame (CP-3);
  - **casi nada del manejo queda en `core/`**, así que el 87% de cobertura cubre poco.
- **Riesgoso:** un derrape poco controlable, que choca con "derrapar a propósito en menos de 5 minutos". Además, en el foro se reportan constraints inestables [S].
- **Funciona bien cuando:** se quiere un auto realista rápido, sin derrape por diseño.
- **Deja de funcionar cuando:** se exige un derrape controlable y afinable.

#### Opción F2: raycast por rueda y fuerzas sobre el chasis

El chasis es una parte real, con colisión. Cada rueda lanza un rayo hacia abajo:
- la compresión da la fuerza de suspensión;
- el núcleo calcula el agarre, el motor y los frenos;
- el adaptador aplica las fuerzas en `PreSimulation`.

Las ruedas son solo visuales.

- **Bueno:**
  - control total del derrape, el peso y el agarre por superficie (con `GetSurfaceAt` por rueda);
  - **casi todo el manejo queda en `core/`**, probado con `dt` y medido al 87%;
  - los choques los sigue resolviendo el motor (CP-5).
- **Malo:** hay que construir y afinar todo. Es la opción más costosa en tiempo.
- **Riesgoso:**
  - **estabilidad a 30 FPS:** las fuerzas se recalculan una vez por frame y la física da varios pasos. Se mitiga con una suspensión blanda y bien amortiguada, un tope de fuerza por rueda y `Fixed` a 240 Hz, pero no está medido (experimentos 1 y 2);
  - el ruido de la `Normal` en rampas (experimento 3).
- **Funciona bien cuando:** la suspensión es blanda y el FPS no baja de 30.
- **Deja de funcionar cuando:** se necesita una suspensión rígida o el FPS cae mucho más.

#### Opción F3: cuerpo propio integrado por el núcleo

El núcleo integra la posición y la velocidad con subpasos fijos, y el adaptador mueve el chasis.

- **Bueno:** es 100% testeable y no depende del FPS.
- **Malo:** se pierden las colisiones del motor. Hay que resolver los choques a mano con barridos.
- **Riesgoso:** justo los "bugs de física" que CP-5 quiere evitar. No hay antecedentes en Roblox [NC].
- **Funciona bien cuando:** no hay choques.
- **Deja de funcionar cuando:** hay árboles y rocas (RC-9).

**Recomendación del agente:** **F2**, condicionada a los experimentos 1 a 3. Es la única que deja el derrape, el peso y el agarre por superficie bajo control y medibles, y mantiene los choques en el motor. Si a 30 FPS no se logra estabilidad, la salida es una suspensión con `SpringConstraint` (lo mejor de F1), manteniendo en el núcleo el neumático, el motor y las asistencias, que son lo que define cómo se siente.

### Decisión 2: modelo de neumático

Aplica a F2 y F3.

#### Opción N1: lineal con tope y círculo de fricción

La fuerza lateral es proporcional al ángulo de deslizamiento, con un tope de `mu × carga`. Frenar o acelerar fuerte resta agarre lateral (círculo de fricción).

- **Bueno:**
  - es simple, estable y fácil de probar;
  - el círculo de fricción da justo lo que piden CP-1 y CP-9: el derrape se inicia frenando, acelerando o con el freno de mano.
- **Malo:** no tiene caída después del pico, así que el derrape no "suelta" solo y hay que ayudarlo con el freno de mano o una asistencia.
- **Riesgoso:** que se sienta plano si el tope es muy duro.

#### Opción N2: Pacejka simplificado

Una curva con pico y caída.

- **Bueno:** el derrape aparece al pasarse del pico y se puede sostener. Tiene más carácter.
- **Malo:** tiene más parámetros para afinar.
- **Riesgoso:** inestable a baja velocidad si no se regulariza [S].

#### Opción N3: arcade puro

Se amortigua la velocidad lateral con un factor de agarre y un estado de "derrape".

- **Bueno:** es lo más predecible y fácil de afinar.
- **Malo:** el peso hay que fingirlo, y choca con CP-2 ("se nota en el agarre, no solo visualmente").
- **Riesgoso:** que se sienta artificial.

**Recomendación del agente:** **N1, con una caída suave opcional después del pico**, que se activa con un parámetro. Arranca estable y probable. Si en las pruebas de juego falta carácter, se sube la caída sin cambiar la estructura. Junto con una **asistencia de contravolante suave**, también parametrizable, ayuda a cumplir "derrapar en menos de 5 minutos" sin volverlo un auto sobre rieles.

### Decisión 3: tracción (#8)

#### Opción T1: AWD con sesgo trasero (rally liviano)

Por ejemplo, 30% adelante y 70% atrás.

- **Bueno:** tracción en tierra y en la salida de las curvas, y perdona más al acelerar. Con el sesgo trasero, el acelerador todavía ayuda a soltar la cola.
- **Malo:** con un reparto parejo, subvira y no derrapa.
- **Riesgoso:** que se sienta "sobre rieles" si el sesgo es bajo.

#### Opción T2: RWD

- **Bueno:** el acelerador controla directamente la cola, así que el derrape es más fácil de provocar.
- **Malo:** es más difícil de controlar, y un jugador nuevo puede girar en trompo.
- **Riesgoso:** frustración temprana, que choca con el criterio de "15 minutos sin que se lo pidan".

**Recomendación del agente:** **T1, con 70% atrás como valor inicial.** Es un parámetro (`rearBias`): las pruebas de juego pueden moverlo hasta RWD (100%) sin tocar el código.

## Qué va al núcleo y qué al adaptador (con F2)

**Núcleo (`src/vehicle/core/`, Luau puro):** recibe el estado, el input y el `dt`, y devuelve el estado y las fuerzas.
- **Parámetros del auto** en un solo módulo (CP-6).
- **Input:** rampas de subida y de retorno por eje, zona muerta y curva de respuesta (CP-7). Dirección que se reduce con la velocidad (CP-10).
- **Por rueda:**
  - suspensión: resorte y amortiguador, con tope y velocidad de compresión filtrada;
  - carga por rueda (CP-2);
  - neumático: deslizamientos, curva, círculo de fricción y agarre por `SurfaceKind` (CP-3);
  - freno de mano trasero (CP-9).
- **Tren motriz:**
  - motor: curva de torque y RPM;
  - caja automática con histéresis y corte de torque al cambiar (CP-4);
  - reparto `rearBias`.
- **Asistencias** (contravolante).
- **Datos para la cámara** (CP-11): yaw objetivo entre la orientación y la velocidad, con suavizado `1 − exp(−k·dt)`.
- **Datos para el feedback** (CP-13 a CP-16): deslizamiento por rueda, RPM, marcha, cambio en curso y velocidad.

**Adaptadores (`src/vehicle/client/`, `src/input/client/`, `src/camera/client/`):**
- **Física:** rayos por rueda en `PreSimulation`; conversión entre `CFrame`/`Vector3` y `vector`; aplicar las fuerzas.
- **Visual:** ruedas, inclinación de la carrocería, sonido, partículas, marcas y HUD.
- **Input:** leer los valores crudos con la API elegida.
- **Cámara:** posicionarla en `PreRender` y mirar atrás (CP-12).
- **Reset:** RC-12, con el punto más cercano que provee Calles infinitas.
- **Contrato:** proveer `GetVehiclePosition` (#22) desde el adaptador del cliente.
- **Servidor** (`src/vehicle/server/`): asignar el dueño de red al jugador (RN-2).

## Decisión
Pendiente: decide Nico (área de Conducción).

## Arquitectura
Pendiente: se escribe con la decisión y los resultados de los experimentos.

## Aprobación
Pendiente.
