# WP-4 — Auto manejable: adaptadores y arranque con stubs

**Issue:** #7 (modelo de física), #8 (tipo de auto)
**Requerimientos:** RN-2. Hace jugables CP-1 a CP-4, CP-7, CP-9, CP-10, CP-11 y CP-12, que ya resuelve el núcleo del WP-3.
**Diseño:** `docs/disenos/auto.md` (aprobado), secciones "Arquitectura", "Adaptadores" y "Arranque"
**Responsable:** Agente A. Como crea `src/app/`, que es compartido, el Agente B revisa esa parte y Beni la aprueba.
**Depende de:** WP-3 (núcleos) mergeado en `main`. **No se empieza a implementar antes.**

Es la versión **mínima** que pidió Nico, para manejar cuanto antes en un Baseplate y ajustar la sensación sobre la marcha. Quedan para WPs posteriores el reset, los contratos reales del mundo, el feedback y la validación de lo que reporta el cliente.

## Subagente
- **Nombre:** `.claude/agents/programador-adaptador.md` (nuevo, en este mismo PR)
- **Modelo:** Sonnet. El WP fija los módulos, las instancias, las constantes y las pruebas.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep, y del MCP de Studio solo lo que lista su definición. Sin red.
- **Entrega:** el informe de su definición, con los criterios uno por uno y la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/auto.md`, secciones "Resultados del experimento `exp/auto-fisica` (#32)" y "Arquitectura";
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5);
  - `docs/nombres.md`;
  - `docs/wp/WP-3-nucleos-conduccion.md`, secciones "Convenciones" y "Entregables" (las firmas que vas a llamar);
  - todo `src/vehicle/core/`, `src/input/core/` y `src/camera/core/`, solo para leer;
  - `src/shared/contracts/` (`Surface`, `VehiclePosition`, `RoadPoint` y `WorldReady`);
  - `docs/guia-de-desarrollo.md`, secciones de Rojo y de chequeos de adaptadores.
- **Decisiones que aplican** (`docs/decisiones.md`):
  - "Auto: raycast con fuerzas, neumático con tope y AWD con sesgo trasero";
  - "Política de pruebas, cobertura y estructura de `src/`".
- **Supuestos vigentes** (medidos en #32):
  - `VectorForce` con `ApplyAtCenterOfMass = false` rige todos los pasos de física del frame.
  - **Sin un impulso mínimo por frame el chasis se "duerme" y la suspensión diverge.** Por eso, `ApplyImpulse(Vector3.new(0, 0.001, 0))` en cada frame.
  - Un rayo que arranca dentro del Terrain devuelve `nil`: el rayo sale desde arriba del chasis.
  - `PhysicsSteppingMethod` no se puede leer ni escribir desde un script.
- **Aprendido en el experimento `exp/manejo`** (rama descartable con adaptadores mínimos sobre el WP-3, 2026-10-15):
  - Con `StreamingEnabled` (viene activado en los Baseplate nuevos), el cliente no ve el auto y el script se cuelga en `WaitForChild`. Se resuelve con `ModelStreamingMode = Persistent` en el `Model` del auto y `player.ReplicationFocus = Body`, en el servidor.
  - **Rojo no cambia `Workspace.StreamingEnabled`** desde el project file.
  - La `SpawnLocation` por defecto del Baseplate está en el origen y cambia la altura de aparición: el auto aparece lejos de ella.
  - El auto quieto no se mueve a 60 ni a 30 FPS, y no diverge manejando.
  - Afinar en vivo con atributos de `Workspace` (`Cfg_<VALOR>`) fue lo que permitió encontrar la sensación (ver la sección 5).
- **De la conversación con Nico:** quiere probar el manejo ya, en un Baseplate, y ajustar valores a medida que maneja. Nunca se toca su juego "Juego de Papu" en Studio.
- **Contratos que usa o provee:**
  - **Provee** `GetVehiclePosition` (#22): la posición del chasis o, mientras el auto no existe, la del punto de aparición (acordado en #36).
  - **Usa, con stubs en el arranque:** `GetSurfaceAt` (#17) devuelve `"Road"`, `IsWorldReadyAt` (#36) devuelve `true` y `GetSpawnPoint` (#35) devuelve un `RoadPoint` fijo. Cambiar cada stub por el real es una línea en el arranque.

**Dónde trabaja:** rama `a/7-auto-manejable`, desde `main` (con el WP-3 ya mergeado), en el worktree `C:\Users\Nico\Documents\Rally-wp4`. En Studio, solo en un Baseplate abierto por Nico para pruebas, con `rojo serve` desde el worktree.

## Objetivo

Que Nico abra un Baseplate, conecte Rojo, le dé Play y maneje el auto de cajas con teclado o gamepad, con la cámara de persecución y mirar atrás.

## Entregables

### 1. Mapeo de Rojo (`default.project.json`)

- `ReplicatedStorage`: agregar `vehicle.shared` (si hace falta) y dejar los `core` como están.
- `ServerScriptService.app` ← `src/app/server` y `ServerScriptService.vehicle` ← `src/vehicle/server`.
- `StarterPlayer.StarterPlayerScripts.app` ← `src/app/client`, más `vehicle`, `input` y `camera` ← sus `client/`.
- `Players`: `CharacterAutoLoads = false` (no hay personaje; la cámara es del auto).
- `Workspace`: intentar `"PhysicsSteppingMethod": "Fixed"` en `$properties` (riesgo 1 del diseño). **Si `rojo build` o `rojo serve` lo rechazan, se saca** y se documenta en la guía cómo fijarlo a mano en las propiedades de `Workspace`.

### 2. Servidor: `src/vehicle/server/VehicleSpawner.luau`

- `new(getSpawnPoint: GetSpawnPoint, config)` y `spawnFor(player)`.
- Crea un `Model` `Vehicle_<UserId>` en `Workspace`, con el atributo `OwnerUserId`:
  - `Body`: `Part` de 6 × 2 × 10, gris, `CanCollide = true`. Es la `PrimaryPart` y la única con masa.
  - `WheelFL`, `WheelFR`, `WheelRL` y `WheelRR`: cilindros (`Part` con `Shape = Cylinder`) de diámetro `2 · WHEEL_RADIUS_STUDS`, negros, con `Massless = true`, `CanCollide = false`, `CanQuery = false` y `CanTouch = false`. Cada una va unida al `Body` con un `Motor6D` cuyo `C0` es la posición de la rueda en `VehicleConfig.WHEELS`. El cliente mueve el `Transform` para la compresión, la dirección y el giro.
  - Por rueda, un `Attachment` en el `Body`, en la posición de montaje, y un `VectorForce` con `RelativeTo = World`, `ApplyAtCenterOfMass = false` y `Force = 0`.
- El auto aparece **anclado**, apoyado en el punto de aparición: `CFrame.lookAt(position + up · altura, position + direction)`, donde la altura deja las ruedas a la compresión estática.
- Crea un `RemoteEvent` `VehicleReleaseRequest` en `ReplicatedStorage`. Cuando llega un pedido, lo valida:
  - que el jugador sea el dueño;
  - que el auto siga anclado (una sola vez por aparición);
  - límite de frecuencia: 1 pedido por segundo por jugador.

  Si es válido, desancla el auto y llama `Body:SetNetworkOwner(player)` (RN-2). Los pedidos inválidos se ignoran sin error.
- **Streaming:** `Model.ModelStreamingMode = Persistent` y `player.ReplicationFocus = Body`.
- Al salir el jugador, destruye su auto.

### 3. Cliente

**`src/input/client/InputReader.luau`:** `new()` y `read(): RawInput`, con `UserInputService` en cada frame. Las teclas van en una tabla de constantes al principio:

| Acción | Teclado | Gamepad |
| --- | --- | --- |
| Dirección | A / D y ← / → | stick izquierdo (x) |
| Acelerador | W y ↑ | R2 (`ButtonR2`, posición z) |
| Freno y reversa | S y ↓ | L2 |
| Freno de mano | Espacio | `ButtonX` |
| Mirar atrás | C | `ButtonY` |

Sin gamepad, los ejes del gamepad dan 0.

**`src/vehicle/client/VehicleController.luau`:**
- `new(deps)` recibe `getSurfaceAt`, `isWorldReadyAt`, `getSpawnPoint`, el simulador y la configuración.
- `start()` busca el auto propio por el atributo `OwnerUserId`.
- `step(controls, dt)` corre en `PreSimulation`:
  1. **Esperando:** mientras el auto esté anclado, consulta `isWorldReadyAt(posición)` en cada frame. Cuando da `true`, manda **un** `VehicleReleaseRequest`. Mientras tanto, no aplica fuerzas.
  2. **Manejando:**
     - Arma el `ChassisSample` desde el `Body`: `AssemblyCenterOfMass`, `RightVector`, `UpVector`, `LookVector`, `AssemblyLinearVelocity`, `AssemblyAngularVelocity`, `AssemblyMass` y `workspace.Gravity`, convertido a `vector`.
     - Lanza 4 rayos con `RaycastParams` que excluyen el auto. Cada uno sale desde `montaje + up · RAY_START_ABOVE_MOUNT_STUDS` hacia `−up`, con largo `RAY_START_ABOVE_MOUNT_STUDS + REST_LENGTH + RADIUS + RAY_EXTRA_STUDS`. La distancia que va al `WheelContact` es la del rayo menos `RAY_START_ABOVE_MOUNT_STUDS`. La superficie sale de `getSurfaceAt(punto)`.
     - Llama a `VehicleSimulator.step`, asigna cada `VectorForce.Force` y da el impulso despertador.
     - Guarda el estado y el último `VehicleFeedback`.
  3. **Ruedas visuales:** el `Transform` de cada `Motor6D` baja la rueda según la compresión, la gira con `steerAngleRadians` (las delanteras) y la hace rodar con `spinRadiansPerSecond · dt`.
- `getVehiclePosition()` devuelve la posición del `Body` o, si todavía no existe, `getSpawnPoint().position`.
- Constantes con nombre: `RAY_START_ABOVE_MOUNT_STUDS = 3` (queda por encima del techo del `Body`), `RAY_EXTRA_STUDS = 1` y `WAKE_IMPULSE = Vector3.new(0, 0.001, 0)`.

**`src/camera/client/ChaseCameraController.luau`:**
- `new(camera)` y `step(vehicleView, isLookingBack, dt)` en `PreRender`.
- Pone `CameraType = Scriptable` y asigna `CFrame.lookAt(pose.position, pose.lookAt)`.
- Hasta que exista el auto, no toca la cámara.

### 4. Arranque (`src/app/`)

- **`src/app/server/Main.server.luau`:**
  - define el stub de `GetSpawnPoint`: `RoadPoint` en `(0, 1, 60)` sobre el Baseplate, lejos de la `SpawnLocation`, mirando a −z;
  - crea `VehicleSpawner`;
  - llama `spawnFor` en `Players.PlayerAdded`, y también para los jugadores que ya estén conectados.
- **`src/app/client/Main.client.luau`:**
  - define los stubs de `GetSurfaceAt` y de `IsWorldReadyAt`, y el mismo stub de `GetSpawnPoint`, cada uno con un comentario `-- Stub hasta el adaptador del mundo (#17 / #35 / #36)`;
  - crea `InputReader`, `InputSmoother`, `VehicleController` y `ChaseCameraController`;
  - conecta `RunService.PreSimulation`: lee el input, lo suaviza y llama al controlador;
  - conecta `RunService.PreRender` para la cámara.
- **Los dos stubs de `GetSpawnPoint` tienen que dar el mismo punto.** Ponelo una sola vez en un módulo de `src/app/shared/`, mapeado a `ReplicatedStorage.app`.

### 5. Afinación en vivo (solo en Studio)

`src/vehicle/client/TuningOverrides.luau`: solo si `RunService:IsStudio()`, lee los atributos `Cfg_<NOMBRE>` de `Workspace` y arma una copia de `VehicleConfig` con esos valores, que el controlador pasa como `config` a `VehicleSimulator.step`. Se actualiza con `AttributeChanged`. Ignora los nombres que no existan en `VehicleConfig` y los valores que no sean del mismo tipo. Fuera de Studio no hace nada. Así Nico puede ajustar la sensación sin reiniciar, y lo que le guste se pasa a `VehicleConfig` por PR.

### 6. Guía

En `docs/guia-de-desarrollo.md`, una sección corta "Probar el manejo":
- abrir un Baseplate, nunca otro juego;
- `rojo serve` y Connect;
- Play;
- la tabla de controles;
- cómo fijar `PhysicsSteppingMethod = Fixed` a mano, si Rojo no puede;
- cómo afinar en vivo con `workspace:SetAttribute("Cfg_REAR_BIAS", 1)` y que lo que guste se pasa a `VehicleConfig` por PR.

## Fuera de alcance
- El reset (RC-12) y los adaptadores reales del mundo: van en un WP que se hace cuando el Agente B tenga sus adaptadores.
- Sonido, partículas, marcas y HUD (WPs de feedback).
- La validación en el servidor de lo que reporta el cliente sobre velocidades y posiciones (WP propio).
- El asset del auto: se pide a Nico con un issue `necesita-humano`. Mientras tanto, se usan las cajas.
- Cambios al núcleo. Si la sensación pide otros valores, se ajustan en la configuración del núcleo con un PR aparte, aprobado por Nico.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` pasa entero, incluido `scripts/analyze-adapters.sh` y `rojo build`.
- [ ] Los adaptadores no tienen lógica de juego: todo `if` que decide algo del manejo está en el núcleo.
- [ ] Sin números mágicos: las constantes del motor tienen nombre y los valores de ajuste vienen de las configuraciones del núcleo.
- [ ] El `RemoteEvent` valida dueño, estado y frecuencia.
- [ ] Ningún archivo pasa de 200 líneas ni ninguna función de 30.

## Pruebas manuales

**Las hace el subagente con el MCP, en el Baseplate:**
- [ ] En Play, el auto aparece anclado, se suelta y asienta sin saltar. El dueño de red es el jugador y no hay errores en la consola.
- [ ] Quieto 10 s: no se desliza ni tiembla. Medir la posición al principio y al final.
- [ ] Con el acelerador por teclado 3 s (`user_keyboard_input`), el auto avanza y cambia de marcha (leer el `VehicleFeedback`).
- [ ] Con el FPS limitado a 30 por una espera activa en `Heartbeat` (como en #32), el auto quieto no diverge y al acelerar tampoco.
- [ ] Mandar `VehicleReleaseRequest` desde otro jugador simulado, dos veces y en ráfaga: el servidor lo ignora.

**Las hace Nico:**
- [ ] Manejar 5 minutos con teclado: acelerar, frenar, reversa, curvas y freno de mano.
- [ ] Intentar derrapar a propósito (CP-1).
- [ ] Mirar atrás.
- [ ] Probar con gamepad, si tiene uno.
- [ ] Contar cómo se siente. Con eso se abre la prueba de juego (`prueba-de-juego`) y los ajustes de configuración.
- [ ] (Orquestador, con Nico) `Fixed` contra `Adaptive`: manejar con cada uno y comparar.
