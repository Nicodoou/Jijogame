# Auto: modelo de física, neumático y tracción

**Issue:** #7 (modelo de física), #8 (tipo de auto)
**Requerimientos:** CP-1 a CP-16, RN-2
**Estado:** arquitectura propuesta

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
3. ~~Ruido de la `Normal` en rampas.~~ **Medido [V]** por el Agente B con el MCP (revisión del PR #31). Promediar rayos cercanos **no sirve**, porque la ondulación del Terrain tiene un período de unos 4 studs (un vóxel):

   | Rampa | 1 rayo | 4 rayos a 1 stud | 9 rayos en 2×2 studs |
   | --- | --- | --- | --- |
   | 5° | 2,80° | 2,80° | 1,88° |
   | 10° | 5,82° | 5,82° | 5,82° |

   **Consecuencia:** la normal de cada rayo se ignora. La dirección de las fuerzas sale del **plano de los 4 puntos de contacto** de las ruedas (que están separados por más que el período de la ondulación) o del eje "arriba" del chasis. Si hiciera falta algo más limpio, el Agente B puede exponer la normal analítica de la ruta, pero eso sería un contrato nuevo y por ahora no hace falta.
4. ~~Rayo con origen dentro del Terrain.~~ **Medido [V]:** devuelve `nil`, hacia abajo y hacia arriba, aunque arranque a 1 stud de la superficie. **Consecuencias:**
   - el rayo arranca bien arriba (por ejemplo, desde el techo del chasis);
   - el núcleo trata un `nil` repentino con la rueda muy comprimida como "suspensión a tope", no como "rueda en el aire".

   **Además:** la superficie de un relleno de Terrain queda unos 2 studs por encima del límite pedido. El Agente B lo calibra en su WP del terreno. El auto toma la altura **del rayo**, nunca de los datos de la ruta.
5. Costo en un celular de gama media.

### Resultados del experimento `exp/auto-fisica` (#32)

Rama [`exp/auto-fisica`](https://github.com/Nicodoou/Jijogame/tree/exp/auto-fisica) (commit `72bf301`), corrida por el subagente `experimentador` en un Baseplate, en modo Play y del lado del servidor. Para simular 30 FPS se ocupó cada frame con una espera activa. El orquestador repitió dos casos clave y coinciden.

| Punto | Resultado |
| --- | --- |
| 1. `VectorForce` contra `ApplyImpulse` | **`VectorForce` rige todos los pasos de física del frame [V]:** Δv/(F/m·dt) = 1,00 a 60 y a 30 FPS. `ApplyImpulse(F·dt)` da lo mismo en una parte libre. |
| 2. Suspensión por raycast a 30 FPS | **Estable con `VectorForce` por rueda** (`ApplyAtCenterOfMass = false`, con un `Attachment` en cada rueda): las 9 combinaciones de 1,5, 2,5 y 4 Hz con amortiguación de 0,3, 0,6 y 1,0 quedan estables a 30 y a 60 FPS. La variación de altura en reposo es menor a 0,001 studs y asientan en menos de 1,4 s. **Con `ApplyImpulseAtPosition` no:** a 30 FPS ninguna pasa (deriva de 0,1 a 0,4 studs). |
| 2b. **Hallazgo crítico** | Con el chasis casi quieto, el motor congela su estado durante varios frames (probablemente el ensamble "se duerme") y la suspensión con `VectorForce` **diverge**: el auto sale disparado. Se resuelve con un **impulso mínimo por frame** (`ApplyImpulse(Vector3.new(0, 0.001, 0))`). El orquestador lo repitió: sin el impulso, deriva de 23 studs; con él, variación de 0,002 studs a 30 FPS. |
| 2c. Límite de rigidez a 30 FPS | Hasta **4 Hz** hay margen. 6 Hz asienta con amortiguación de 0,3 o 0,6; 8 Hz o más diverge. Más amortiguación no extiende el límite. |
| 2d. `Fixed` contra `Adaptive` | **No concluyente.** `PhysicsSteppingMethod` no se puede leer ni escribir desde un script, y no se sabe con qué modo corrieron las mediciones. Se cambia a mano en las propiedades de `Workspace`. |
| 3. Costo por frame (PC) | 65 a 85 µs típicos para 4 rayos con sus fuerzas: entre 0,4% y 0,7% de un frame. **En celular: pendiente** (prueba manual). |

**Consecuencias para la arquitectura:**
- las fuerzas se aplican con un `VectorForce` por rueda;
- el adaptador da un impulso mínimo por frame para que el chasis no se duerma;
- la suspensión se limita a **4 Hz** como máximo, por parámetro.

Queda pendiente probar:
- `Fixed` contra `Adaptive`, a mano;
- con el dueño de red en el cliente;
- sobre Terrain, con fuerzas laterales;
- en un celular.

Eso va como pruebas del WP del auto, no como experimento previo.

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
  - neumático: deslizamientos, curva, círculo de fricción y agarre por `SurfaceKind` (CP-3). `GetSurfaceAt` se consulta con el **punto de contacto** del rayo, no con el centro de la rueda. El agarre de cada rueda se filtra con `1 − exp(−k·dt)`, para que el borde nítido entre superficies no cambie el agarre de golpe (sugerencias del Agente B);
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

Decidió Nico el 2026-10-15, eligiendo las tres recomendaciones:

1. **Física: F2**, raycast por rueda y fuerzas sobre el chasis. Queda condicionada a los experimentos 1 a 3 de `exp/auto-fisica`. Si a 30 FPS no se logra estabilidad, la suspensión pasa a `SpringConstraint` y el resto del manejo queda en el núcleo.
2. **Neumático: N1**, lineal con tope y círculo de fricción, con caída opcional después del pico y un contravolante suave, los dos parametrizables.
3. **Tracción: T1**, AWD con sesgo trasero, con `rearBias` = 0,7 como valor inicial y parametrizable.

**Por qué:** es la combinación que deja el derrape, el peso y el agarre por superficie bajo control y medibles, y que se puede afinar con parámetros en las pruebas de juego.

## Arquitectura

Propuesta del Agente A, 2026-10-15. Sigue la arquitectura general de `docs/disenos/politica-de-codigo.md` (contratos ← núcleo ← adaptadores ← arranque). La aprueba Nico. Como crea `src/app/`, que es compartido, también hace falta la aprobación de Beni para esa parte.

### Visión general

Cada frame, el lado del cliente hace esto:

```
PreSimulation(dt)
  input/client  ──valores crudos──▶  input/core: InputSmoother ──▶ VehicleControls (dirección, acelerador, freno, freno de mano en [−1, 1] o [0, 1])
  vehicle/client: lee el chasis (CFrame, velocidades) y lanza 4 rayos ──▶ WheelContact ×4 (con GetSurfaceAt en el punto de contacto)
  vehicle/core: VehicleSimulator.step(state, controls, chassis, contacts, dt) ──▶ nuevo estado + fuerza por rueda (mundo) + datos de feedback
  vehicle/client: aplica la fuerza de cada rueda a su VectorForce + impulso mínimo (despertador)
PreRender(dt)
  camera/client ──▶ camera/core: ChaseCamera.step(cámara, datos del auto, mirarAtrás, dt) ──▶ CFrame objetivo ──▶ CurrentCamera
```

El núcleo es **una función de paso**: recibe el estado anterior, las entradas y `dt`, y devuelve el estado nuevo y las salidas. No guarda nada escondido, no lee el reloj ni usa azar. Así cada prueba arma un estado, llama a `step` y compara.

### Núcleo del auto (`src/vehicle/core/`)

| Módulo | Responsabilidad | Requerimientos |
| --- | --- | --- |
| `VehicleConfig` | **Todos los parámetros del auto en un solo lugar**, con nombre y unidad: masa, posición de las ruedas, suspensión (frecuencia en Hz, como máximo 4; amortiguación relativa; recorrido), neumático (`mu`, rigidez lateral, caída opcional después del pico), agarre por `SurfaceKind`, motor (curva de torque y corte), caja (relaciones, umbrales con histéresis, tiempo de cambio), `rearBias` (0,7), dirección (ángulo máximo contra velocidad), freno, freno de mano y asistencias. Es solo datos. | CP-6 |
| `VehicleTypes` | Los tipos compartidos del núcleo: `VehicleState`, `VehicleControls`, `ChassisSample` (orientación, velocidad lineal y angular, como `vector`), `WheelContact` (`hit`, distancia, punto, `SurfaceKind?`), `WheelOutput` y `VehicleFeedback`. | — |
| `Suspension` | Compresión, fuerza de resorte y amortiguador (con tope) y velocidad de compresión filtrada. Si el rayo no pega (`nil`) y la rueda venía muy comprimida, la trata como **suspensión a tope**, no como rueda en el aire (#31). | CP-2 |
| `ContactPlane` | El plano del suelo a partir de los puntos de contacto (de 2 a 4). Da la dirección "arriba" para las fuerzas. Ignora la `Normal` de cada rayo por la ondulación del Terrain (#31). Si hay menos de 2 contactos, usa el "arriba" del chasis. | — |
| `Tire` | Por rueda: ángulo de deslizamiento, fuerza lateral lineal con tope `mu × carga` y caída opcional, y círculo de fricción con la fuerza longitudinal. A baja velocidad, se regulariza para no temblar. | CP-1, CP-3 |
| `SurfaceGrip` | Del `SurfaceKind` al factor de agarre y a la resistencia al rodar. Filtra el cambio por rueda con `1 − exp(−k·dt)`, así un borde nítido no se siente como un golpe. Un `nil` mantiene el último valor. | CP-3 |
| `Drivetrain` | Curva de torque del motor, RPM desde la velocidad de las ruedas, caja automática con histéresis, corte de torque durante el cambio y reparto entre ejes según `rearBias`. **Sin inercia de rueda:** la fuerza longitudinal de cada rueda sale del torque y del freno, y el círculo de fricción la recorta. Es más simple y estable que integrar el giro de las ruedas, y alcanza para un auto arcade. | CP-4, CP-13 |
| `Steering` | El ángulo de dirección máximo baja con la velocidad. | CP-10 |
| `Assists` | Contravolante suave, parametrizable (con 0 se apaga). | CP-1 |
| `VehicleSimulator` | Orquesta un paso: dirección → suspensión y cargas → agarre → tren motriz → neumáticos → fuerzas por rueda en el plano del contacto → asistencias → feedback. **No implementa física propia:** solo compone los otros módulos. | — |

**Salidas por paso:**
- **`WheelOutput` ×4:** la fuerza total de cada rueda, en coordenadas del mundo (suspensión más neumático), y si la rueda toca el suelo.
- **`VehicleFeedback`:** velocidad, RPM, marcha, si está cambiando de marcha, deslizamiento por rueda, ángulo de deriva y si está derrapando. Es lo que usan el HUD, el sonido, las partículas, las marcas y la cámara.

### Núcleo del input (`src/input/core/`)

- `InputConfig`: rampas de subida y de retorno por eje, zona muerta del gamepad y curva de respuesta.
- `InputSmoother.step(state, rawInput, dt)`: devuelve `VehicleControls`. El teclado da 0 o 1 y pasa por las rampas; el gamepad da valores analógicos, pasa por la zona muerta y la curva, y no lleva rampa. El freno de mano es un botón, sin rampa. **CP-7.**

### Núcleo de la cámara (`src/camera/core/`)

- `CameraConfig`: distancia, altura, rigidez del seguimiento y peso de la dirección de la velocidad.
- Ni la cámara ni el auto suponen nada sobre el origen: el auto aparece a unos 120.000 studs de él.
- `ChaseCamera.step(state, vehicleView, isLookingBack, dt)`: calcula el yaw objetivo, que mezcla la orientación del auto con la dirección de su velocidad según el derrape, y lo suaviza con `1 − exp(−k·dt)`. Devuelve la posición y el punto al que mira, como `vector`. Si `isLookingBack` está activo, mira hacia atrás. **CP-11 y CP-12.**

### Adaptadores

| Módulo | Dónde | Qué hace |
| --- | --- | --- |
| `VehicleSpawner` | `src/vehicle/server/` | Crea el auto **anclado** en el punto de aparición (un modelo de cajas grises hasta que llegue el asset, ver más abajo). Cuando el cliente avisa que el mundo está listo, lo desancla y llama `SetNetworkOwner(player)` (RN-2). Valida el pedido: que venga del dueño del auto, una sola vez por aparición y con límite de frecuencia. |
| `VehicleController` | `src/vehicle/client/` | En `PreSimulation`: lee el chasis y lanza los 4 rayos. Cada rayo sale **desde arriba del chasis** (#31) y filtra el propio auto con `RaycastParams`. Consulta `GetSurfaceAt` en el punto de contacto, convierte `CFrame`/`Vector3` a `vector`, llama a `VehicleSimulator.step`, asigna cada `VectorForce.Force` y da el impulso mínimo despertador (#32). También publica `GetVehiclePosition` (#22) y mueve las ruedas visuales. |
| `InputReader` | `src/input/client/` | Lee el teclado y el gamepad en cada frame con `UserInputService` (`IsKeyDown`, `GetGamepadState`) y entrega valores crudos. Mapea las teclas y botones del juego, incluidos el freno de mano y mirar atrás. |
| `ChaseCameraController` | `src/camera/client/` | En `PreRender`: lee el auto, llama a `ChaseCamera.step` y posiciona la `CurrentCamera` (`CameraType = Scriptable`). |

Las constantes del motor van en constantes con nombre dentro de cada adaptador. Ejemplos: el valor del impulso despertador, cuánto arriba del chasis sale el rayo y la tecla de cada acción.

**Por qué `UserInputService` con lectura por frame** y no el Input Action System: es estable y conocido, y da exactamente lo que necesita el núcleo (valores crudos por frame). El Input Action System no documenta una zona muerta, y la zona muerta igual la hace el núcleo. Si más adelante conviene el Input Action System (por ejemplo, para reasignar controles), se cambia solo `InputReader`.

### Arranque (`src/app/`)

Se crea en este diseño:
- `src/app/client/Main.client.luau`: crea `InputReader`, `VehicleController` y `ChaseCameraController`, con sus núcleos y configuraciones, y les pasa `GetSurfaceAt` del mundo.
- `src/app/server/Main.server.luau`: crea `VehicleSpawner`.

**Orden de arranque** (acordado con el Agente B en la revisión del PR #34):
- Las funciones de los contratos se pasan como **cierres** (por ejemplo, `function(position) return world.getSurfaceAt(position) end`). El auto necesita `GetSurfaceAt` del mundo y el mundo necesita `GetVehiclePosition` del auto, y con cierres el orden de construcción no importa.
- **Punto de aparición:** el inicio de la ruta (cerca de x = −120.000), sacado del contrato "punto de ruta más cercano" que provee el Agente B. Ese contrato también sirve para el reset (RC-12) y tiene que poder usarse en el servidor. El issue `contrato` lo abre el Agente B.
- **El auto aparece anclado.** El servidor lo crea anclado en el punto de aparición. El arranque del cliente espera a que el mundo tenga escrito el Terrain alrededor de ese punto, con un contrato nuevo de "mundo listo en una posición" que provee el Agente B, también por issue `contrato`. Recién ahí el cliente le pide al servidor que lo suelte, con un `RemoteEvent` del área de Conducción validado y con límite de frecuencia. El servidor lo desancla y llama `SetNetworkOwner(player)`. Así el auto no se cae al vacío.
- Hasta que existan los adaptadores del mundo, el arranque usa **stubs**: `GetSurfaceAt` devuelve `"Road"`, el mundo está siempre listo y el punto de aparición es un valor fijo de configuración. Cambiar cada stub por el real es una línea en el arranque. El cambio al real es una línea en el arranque. Los dos agentes tocan `src/app/` **por acuerdo**: cada uno suma sus líneas en PRs revisados por el otro. Se agregan al mapeo de Rojo `src/app/`, `src/vehicle/{client,server}`, `src/input/client` y `src/camera/client`.

### Patrones y por qué

- **Núcleo funcional y cáscara imperativa:** el núcleo es una función `step` pura y los adaptadores hacen los efectos. Resuelve que todo el manejo se pueda probar con `dt` y estado fijos (87% de cobertura).
- **Composición en `VehicleSimulator` en vez de herencia:** cada parte de la física es un módulo chico que se prueba solo, y el simulador las encadena en un orden fijo y documentado.
- **Configuración como datos:** CP-6 pide ajustar sin tocar código. Toda constante de afinación vive en `VehicleConfig`, `InputConfig` o `CameraConfig`.
- **Puertos y adaptadores:** el núcleo nunca ve `Vector3` ni `Instance`, y el adaptador traduce.

### Lo que este diseño no cubre (WPs posteriores)

- **Feedback:** sonido del motor y de los neumáticos, polvo, marcas y HUD (CP-13 a CP-16). Usan `VehicleFeedback`, que ya define este diseño.
- **Reset (RC-12):** necesita el contrato "punto de ruta más cercano", que provee el Agente B y todavía no existe.
- **Validación en el servidor** de lo que reporta el cliente.
- **Asset del auto:** se pide a Nico con un issue `necesita-humano` (`asset-modelo`). Mientras tanto, se usan cajas grises con los nombres `Body`, `WheelFL`, `WheelFR`, `WheelRL` y `WheelRR`.

### Plan de WPs

1. **WP-3 (núcleos):** `vehicle/core`, `input/core` y `camera/core` con sus pruebas. Incluye las pruebas de propiedades:
   - el auto en reposo sobre suelo plano no se mueve;
   - con el freno de mano en una curva, la cola se suelta;
   - con más `rearBias`, más sobreviraje con acelerador;
   - nada da NaN con `dt` extremos.
   Es puro Luau y no necesita Studio.
2. **WP-4 (adaptadores y arranque):** el spawner, el controlador, el input, la cámara y `src/app/`.
   Pruebas manuales en Studio:
   - manejar;
   - derrapar;
   - 30 FPS con espera activa;
   - `Fixed` contra `Adaptive`;
   - el dueño de red en el cliente;
   - el Terrain del Agente B cuando esté.
   Pide a Nico la prueba de juego (`prueba-de-juego`).

### Riesgos que el WP-4 confirma primero

1. Si `PhysicsSteppingMethod` se puede fijar en `Fixed` desde `default.project.json` (`$properties` de `Workspace`). Si no se puede, se documenta cómo fijarlo a mano en el lugar.
2. Que la suspensión siga estable con el dueño de red en el cliente y con fuerzas laterales, no solo verticales (#32 midió en el servidor y solo con fuerzas verticales).
3. Cuánto cuesta en un celular de gama media: prueba manual.

## Aprobación
Pendiente.
