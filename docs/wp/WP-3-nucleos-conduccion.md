# WP-3 — Núcleos de Conducción: auto, input y cámara

**Issue:** #7 (modelo de física), #8 (tipo de auto)
**Requerimientos:** CP-1, CP-2, CP-3, CP-4, CP-6, CP-7, CP-9, CP-10, CP-11 y CP-12, en su parte lógica. Prepara los datos de CP-13 a CP-16 (`VehicleFeedback`).
**Diseño:** `docs/disenos/auto.md` (aprobado), secciones "Decisión" y "Arquitectura"
**Responsable:** Agente A
**Depende de:** WP-1 (en `main`). No depende del Agente B: usa solo el tipo `SurfaceKind` del contrato #17.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (existente, del Agente B; se reutiliza)
- **Modelo:** Sonnet. El WP fija los módulos, las firmas, las fórmulas, los valores iniciales y las pruebas. Las dudas de diseño vuelven al orquestador.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, con los criterios de aceptación uno por uno y la salida de `scripts/check-all.sh`.
- **Orden de trabajo:** `input/core`, después `camera/core` y al final `vehicle/core`. Un commit por módulo con sus pruebas.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/auto.md`, secciones "Decisión" y "Arquitectura" (la investigación es contexto, no hace falta entera);
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5);
  - `docs/nombres.md`;
  - `src/shared/contracts/Surface.luau`;
  - `tests/Runner.luau` y, como ejemplo de estilo, `src/world/core/WorldConfig.luau` y `tests/world/SeededRandom.test.luau`;
  - `docs/guia-de-desarrollo.md` (cómo correr los chequeos).
- **Decisiones que aplican** (`docs/decisiones.md`):
  - "Auto: raycast con fuerzas, neumático con tope y AWD con sesgo trasero";
  - "Política de pruebas, cobertura y estructura de `src/`";
  - "Ruta de rally: trazado libre en un área acotada…" (el auto aparece cerca del origen: `vector` en float32 alcanza).
- **Supuestos vigentes:**
  - `vector` es `Vector3` en Roblox, con componentes en minúscula (`.x`) y precisión float32. Se usan `vector.create`, `vector.dot`, `vector.cross`, `vector.magnitude` y `vector.normalize`.
  - El núcleo no puede requerir el núcleo de otra área, y para `scripts/check-core.sh` `vehicle`, `input` y `camera` son áreas distintas. Por eso cada núcleo declara sus propios tipos de entrada; los tipos de Luau son estructurales y el arranque (WP-4) los conecta sin conversión.
  - Rokit está instalado: antes de cada comando, `export PATH="$HOME/.rokit/bin:$PATH"`, siempre desde la raíz del repo.
- **De la conversación con Nico:** quiere un auto **"arcade con peso"**: que derrape fácil y a propósito, pero que se sienta el peso al frenar, acelerar y doblar. Sin juego de referencia. Todo lo que sea sensación se ajusta después en las pruebas de juego, así que lo importante es que cada valor esté en la configuración y que nada sea inestable.
- **Contratos que usa o provee:** usa `SurfaceKind` (#17). No toca contratos.

**Dónde trabaja:** rama `a/7-nucleos-conduccion`, creada desde `main`, en un worktree aparte: `C:\Users\Nico\Documents\Rally-wp3`. No toca `C:\Users\Nico\Documents\Rally`. Al terminar, pushea la rama.

## Convenciones (valen para todo el WP)

- **Unidades:** studs, segundos, radianes (en la configuración, los ángulos van en grados con `_DEGREES` y el código los convierte) y masa en la unidad de Roblox. Las fuerzas son masa × studs/s².
- **Marco del chasis:** el de Roblox. En coordenadas locales, x es la derecha, y es arriba y **−z es adelante**. Las posiciones de las ruedas van en ese marco, así el adaptador hace `chassisCFrame * offset` sin traducir.
- **Signos:** dirección +1 = a la derecha. Un ángulo de dirección positivo gira las ruedas a la derecha. El ángulo de deriva (`driftAngle`) es positivo cuando la velocidad apunta a la derecha del frente del auto.
- **Pureza:** cada `step` recibe el estado anterior y devuelve uno nuevo. **No modifica sus argumentos.** Sin reloj, sin azar.
- **`dt`:** si no es un número finito o es ≤ 0, el `step` devuelve el estado sin cambios y fuerzas en cero. Si es mayor que `MAX_STEP_SECONDS` (de la configuración de cada núcleo), se usa ese máximo.
- **Filtros:** todo suavizado es `alpha = 1 − exp(−rate · dt)` con `rate` en 1/s, y `value += (target − value) · alpha`.

## Objetivo

Implementar, en Luau puro y probado en el CLI, toda la lógica de manejo: del input crudo a los controles suavizados, de los controles y el estado del chasis a la fuerza de cada rueda, y del estado del auto a la posición de la cámara.

## Entregables

Todo con `--!strict`. Pruebas en `tests/input/`, `tests/camera/` y `tests/vehicle/`.

### 1. `src/input/core/`

**`InputConfig.luau`** (solo datos):

| Valor | Inicial |
| --- | --- |
| `STEER_RISE_SECONDS` / `STEER_RETURN_SECONDS` | 0,25 / 0,15 (tiempo de 0 a 1 y de 1 a 0) |
| `THROTTLE_RISE_SECONDS` / `THROTTLE_RETURN_SECONDS` | 0,30 / 0,20 |
| `BRAKE_RISE_SECONDS` / `BRAKE_RETURN_SECONDS` | 0,15 / 0,10 |
| `GAMEPAD_DEADZONE` | 0,12 |
| `GAMEPAD_STEER_EXPONENT` / `GAMEPAD_PEDAL_EXPONENT` | 1,5 / 1,0 |
| `MAX_STEP_SECONDS` | 0,1 |

**`InputSmoother.luau`:**
- Tipos: `RawInput` = `{ isSteerLeftDown, isSteerRightDown, isThrottleDown, isBrakeDown, isHandbrakeDown, isLookBackDown: boolean, gamepadSteer: number, gamepadThrottle: number, gamepadBrake: number }` (los ejes del gamepad en [−1, 1] y [0, 1]; si no hay gamepad, 0). `SmoothedInput` = `{ steer: number, throttle: number, brake: number, isHandbrakeOn: boolean, isLookingBack: boolean }`. `InputState` = el último `SmoothedInput`.
- API: `newState(): InputState` (todo en cero) y `step(state, raw, dt): InputState`.
- **Por eje:**
  - El valor del gamepad pasa por la zona muerta (`signo · (|x| − zona) / (1 − zona)`, y 0 dentro de la zona) y después por la curva (`signo · |x|^exponente`).
  - Si el valor procesado del gamepad no es 0, gana el gamepad: la salida es ese valor, sin rampa.
  - Si no, el objetivo del teclado es 0 o 1 (en la dirección, `derecha − izquierda`) y la salida se mueve hacia él a velocidad constante: `1 / RISE` cuando se aleja de 0 y `1 / RETURN` cuando vuelve hacia 0. Si el objetivo tiene el signo opuesto, primero vuelve a 0 con `RETURN` y después sube con `RISE`.
  - Los valores entrados se recortan a su rango (un gamepad roto que da 1,3 no rompe nada).
- El freno de mano y mirar atrás son botones: pasan tal cual, sin rampa.

### 2. `src/camera/core/`

**`CameraConfig.luau`:**

| Valor | Inicial |
| --- | --- |
| `DISTANCE_STUDS` / `HEIGHT_STUDS` | 18 / 6 |
| `LOOK_AHEAD_STUDS` / `LOOK_HEIGHT_STUDS` | 6 / 2 (al punto al que mira, adelante y arriba del auto) |
| `YAW_FOLLOW_RATE` | 5 por segundo |
| `VELOCITY_HEADING_WEIGHT` | 0,6 (cuánto pesa la dirección de la velocidad contra la del auto al derrapar) |
| `MIN_SPEED_FOR_VELOCITY_HEADING` | 10 studs/s (debajo de esa velocidad, la cámara sigue la orientación del auto) |
| `POSITION_FOLLOW_RATE` | 12 por segundo (la altura y la posición, para absorber los saltos de la suspensión) |
| `MAX_STEP_SECONDS` | 0,1 |

**`ChaseCamera.luau`:**
- Tipos: `VehicleView` = `{ position: vector, forward: vector, linearVelocity: vector }`. `CameraState` = `{ yawRadians: number, focus: vector }`. `CameraPose` = `{ position: vector, lookAt: vector }`.
- API: `newState(view): CameraState` (arranca detrás del auto, sin suavizado) y `step(state, view, isLookingBack, dt): (CameraState, CameraPose)`.
- El yaw sale del plano horizontal (xz). El objetivo es el yaw del frente del auto mezclado con el de la velocidad según `VELOCITY_HEADING_WEIGHT`, solo por encima de `MIN_SPEED_FOR_VELOCITY_HEADING` y solo si la velocidad va hacia adelante (en reversa sigue la orientación). Se mezcla por el camino corto del ángulo (sin dar la vuelta por ±π). El yaw se suaviza con `YAW_FOLLOW_RATE` y `focus` (la posición seguida) con `POSITION_FOLLOW_RATE`.
- Con `isLookingBack`, la pose se calcula con el yaw + π y la cámara queda delante del auto mirando hacia atrás. **Cambia al instante**, sin suavizar, y al soltar vuelve al yaw que tenía.
- Si el frente del auto es casi vertical (proyección horizontal muy chica, por ejemplo con el auto volcado), mantiene el yaw anterior.

### 3. `src/vehicle/core/`

Los nombres y las responsabilidades son los de la tabla "Núcleo del auto" del diseño. Este WP fija las firmas y las fórmulas.

**`VehicleTypes.luau`** (solo tipos):
- `VehicleControls` = `{ steer: number, throttle: number, brake: number, isHandbrakeOn: boolean }`.
- `ChassisSample` = `{ position: vector, right: vector, up: vector, forward: vector, linearVelocity: vector, angularVelocity: vector, mass: number, gravity: number }`. `position` es el centro de masa; los ejes son unitarios en el mundo; `mass` y `gravity` los lee el adaptador del motor (`AssemblyMass`, `workspace.Gravity`), así la configuración no depende de la masa del modelo.
- `WheelContact` = `{ hasHit: boolean, distanceStuds: number, point: vector, surface: SurfaceKind? }`. `distanceStuds` se mide **desde el punto de montaje de la rueda** hacia abajo del chasis. Puede ser negativa si el suelo quedó por encima del montaje (el rayo sale desde arriba, #31).
- `WheelState` = `{ compressionStuds, compressionSpeed, gripMultiplier, rollingResistance: number, isGrounded: boolean }`.
- `VehicleState` = `{ wheels: { WheelState }, gear: number, shiftRemainingSeconds: number, engineRpm: number }`. `gear` va de 1 a N, y −1 es reversa.
- `WheelOutput` = `{ force: vector, isGrounded: boolean, steerAngleRadians: number, compressionStuds: number, spinRadiansPerSecond: number }`. `force` está en el mundo y se aplica en el punto de montaje de la rueda.
- `WheelFeedback` = `{ slipRatio: number, slipAngleRadians: number, isSliding: boolean, surface: SurfaceKind? }`.
- `VehicleFeedback` = `{ speedStudsPerSecond, forwardSpeedStudsPerSecond, engineRpm: number, gear: number, isShifting: boolean, driftAngleRadians: number, isDrifting: boolean, wheels: { WheelFeedback } }`.
- Las ruedas van siempre en el orden FL, FR, RL, RR.

**`VehicleConfig.luau`** (solo datos; valores iniciales, se ajustan en las pruebas de juego):

| Grupo | Valores |
| --- | --- |
| Ruedas | `WHEELS`: FL `(-2.5, -1, -4)`, FR `(2.5, -1, -4)`, RL `(-2.5, -1, 4)`, RR `(2.5, -1, 4)`, con `isFront` y `isLeft`. `WHEEL_RADIUS_STUDS` 1,2 |
| Suspensión | `SUSPENSION_FREQUENCY_HZ` 2,5 (**como máximo 4**, #32); `SUSPENSION_DAMPING_RATIO` 0,6; `SUSPENSION_REST_LENGTH_STUDS` 2,5; `SUSPENSION_MAX_COMPRESSION_STUDS` 2; `SUSPENSION_MAX_FORCE_PER_STATIC_LOAD` 4 (tope por rueda, en múltiplos de su carga estática); `BOTTOM_OUT_FRACTION` 0,8; `BOTTOM_OUT_MAX_MISSED_STEPS` 3; `COMPRESSION_SPEED_FILTER_RATE` 30 |
| Neumático | `TIRE_FRICTION` 1,0; `TIRE_CORNERING_STIFFNESS_PER_RADIAN` 8 (fuerza lateral por unidad de carga y por radián); `TIRE_SLIDE_FRICTION_RATIO` 1,0 (1 = sin caída después del pico); `LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND` 3 |
| Superficie | `SURFACE_GRIP`: Road 1,0, Shoulder 0,85, Grass 0,7, Mud 0,5. `SURFACE_ROLLING_RESISTANCE`: Road 0,015, Shoulder 0,03, Grass 0,06, Mud 0,12 (por unidad de carga). `SURFACE_BLEND_RATE` 8 |
| Motor | `TORQUE_CURVE`: puntos (rpm, fracción del pico) `(1000, 0.6)`, `(3000, 0.9)`, `(4500, 1.0)`, `(6500, 0.85)`, `(7000, 0.7)`; `IDLE_RPM` 1000; `REDLINE_RPM` 7000; `FIRST_GEAR_PEAK_ACCELERATION` 110 studs/s² (0,56 g: el acelerador tiene que poder soltar la cola en 1ra y 2da) |
| Caja | `GEAR_RATIOS` 3,5, 2,3, 1,65, 1,25, 1,0; `REVERSE_RATIO` 3,5; `FINAL_DRIVE` 5,9; `UPSHIFT_RPM` 6200; `DOWNSHIFT_RPM` 3000; `SHIFT_DURATION_SECONDS` 0,25; `SHIFT_TORQUE_FRACTION` 0; `REVERSE_ENGAGE_SPEED` 1 studs/s |
| Tracción | `REAR_BIAS` 0,7 |
| Frenos | `BRAKE_DECELERATION` 250 studs/s² (el neumático lo recorta); `BRAKE_FRONT_BIAS` 0,6; `HANDBRAKE_FORCE_PER_LOAD` 1,5; `BRAKE_REGULARIZATION_SPEED` 1 studs/s |
| Dirección | `STEER_MAX_LOW_SPEED_DEGREES` 32; `STEER_MAX_HIGH_SPEED_DEGREES` 8; `STEER_LOW_SPEED` 20 y `STEER_HIGH_SPEED` 120 studs/s |
| Asistencias | `COUNTER_STEER_STRENGTH` 0,3 (0 = apagado); `COUNTER_STEER_MAX_DEGREES` 15; `COUNTER_STEER_MIN_SPEED` 10 studs/s |
| Feedback | `DRIFT_ANGLE_THRESHOLD_DEGREES` 10; `DRIFT_MIN_SPEED` 15 studs/s |
| Paso | `MAX_STEP_SECONDS` 1/15 |

La velocidad máxima en la marcha más alta, al corte, da unos 150 studs/s. Hay una prueba que lo verifica, para que nadie cambie las relaciones sin darse cuenta.

**`Suspension.luau`:**
- `staticLoad(mass, gravity, wheelCount)`, `springRate(...)` y `damperRate(...)`: la carga estática es `masa · g / 4`. La rigidez es `(masa / 4) · (2π · f)²`. La amortiguación es `2 · ζ · √(rigidez · masa / 4)`.
- `step(wheel, contact, compressionSpeedRaw, ...)`: con contacto, `compresión = REST_LENGTH + RADIUS − distancia`, recortada a `[0, MAX_COMPRESSION]`. La velocidad de compresión es la de la rueda en el mundo proyectada sobre el "arriba" del contacto, con el signo cambiado; la calcula el simulador y llega filtrada con `COMPRESSION_SPEED_FILTER_RATE`. La fuerza es `rigidez · compresión + amortiguación · velocidad`, recortada a `[0, MAX_FORCE_PER_STATIC_LOAD · cargaEstática]`.
- **Suspensión a tope (#31):** si no hay contacto y la compresión anterior era ≥ `BOTTOM_OUT_FRACTION · MAX_COMPRESSION`, se toma compresión máxima y la rueda sigue apoyada, **como máximo durante `BOTTOM_OUT_MAX_MISSED_STEPS` pasos seguidos sin contacto** (el estado de la rueda lleva la cuenta). Pasados esos pasos, o si la compresión anterior era menor, la rueda está en el aire: compresión 0 y fuerza 0.
- Una distancia negativa o NaN cuenta como compresión máxima.

**`ContactPlane.luau`:**
- `upDirection(points: { vector }, chassisUp: vector): vector` con los puntos de contacto de las ruedas apoyadas, en el orden FL, FR, RL, RR (los que falten no están).
  - Con 4 puntos: `normalize(cross(FR − RL, FL − RR))` o el producto en el orden que dé "arriba".
  - Con 3: el producto de dos lados.
  - Con 2: el "arriba" del chasis sin su componente a lo largo de la línea entre los dos puntos.
  - Con menos de 2, o si el resultado es degenerado (magnitud < 1e-4): el "arriba" del chasis.
- **Siempre** se orienta hacia el mismo lado que el "arriba" del chasis (si el producto escalar da negativo, se invierte).

**`Tire.luau`:**
- `lateralForce(slipAngle, load, grip)`: lineal, `−CORNERING_STIFFNESS · load · slipAngle`, con tope `TIRE_FRICTION · grip · load`. Por encima del ángulo del pico, la fuerza baja linealmente hasta `SLIDE_FRICTION_RATIO · tope` cuando el ángulo llega a dos veces el del pico, y se queda ahí.
- `slipAngle(lateralSpeed, longitudinalSpeed)`: `atan2(lateral, max(|longitudinal|, LOW_SPEED_REGULARIZATION))`. A baja velocidad el neumático actúa como un amortiguador lateral en vez de temblar.
- `combine(longitudinal, lateral, load, grip)`: el **círculo de fricción**. Si `√(Fx² + Fy²)` supera `TIRE_FRICTION · grip · load`, escala las dos para quedar en el círculo. Devuelve también `slipRatio = pedida / disponible` (0 si la carga es 0). **"Pedida" es antes de cualquier tope:** la lateral es la lineal (`CORNERING_STIFFNESS · load · |slipAngle|`), así un derrape en curva pura da `slipRatio` > 1 e `isSliding = slipRatio > 1`.

**`SurfaceGrip.luau`:**
- `step(wheel, surface: SurfaceKind?, dt)`: lleva `gripMultiplier` y `rollingResistance` hacia los valores de la superficie con `SURFACE_BLEND_RATE`. Un `nil` mantiene los valores anteriores. El estado inicial es el de `Road`.

**`Drivetrain.luau`:**
- `torqueFraction(rpm)`: interpola linealmente la curva y recorta a sus extremos.
- `engineRpm(forwardSpeed, gear)`: `max(IDLE_RPM, |velocidad| / RADIUS · relación · FINAL_DRIVE · 60 / 2π)`, recortado a `REDLINE_RPM`.
- `nextGear(state, rpm, forwardSpeed, controls)`: sube si `rpm ≥ UPSHIFT_RPM` y no es la última marcha. Baja si `rpm ≤ DOWNSHIFT_RPM` y no es la primera. Las dos marchas nuevas arrancan un cambio de `SHIFT_DURATION_SECONDS`.
  - **Reversa (arcade):** con el freno apretado, sin acelerador y `|velocidad hacia adelante| < REVERSE_ENGAGE_SPEED`, pasa a −1. En reversa, el freno acelera hacia atrás y el acelerador frena. Vuelve a 1 con el acelerador y la misma condición de velocidad.
- `driveForce(state, controls, rpm, mass)`: `masa · FIRST_GEAR_PEAK_ACCELERATION · torqueFraction(rpm) · relación / relación de 1ra · pedal`. Durante un cambio se multiplica por `SHIFT_TORQUE_FRACTION`. Al corte, la fuerza es 0.
- `split(force)`: devuelve la fuerza por rueda (`(1 − REAR_BIAS) / 2` a cada delantera y `REAR_BIAS / 2` a cada trasera).
- `brakeForce(...)`: con regularización. La fuerza es `−clamp(velocidadLongitudinal / BRAKE_REGULARIZATION_SPEED, −1, 1) · fuerzaMáxima`, así no oscila cerca de 0. La fuerza máxima del freno sale de `masa · BRAKE_DECELERATION` repartida con `BRAKE_FRONT_BIAS`. El freno de mano actúa **solo atrás**, con `HANDBRAKE_FORCE_PER_LOAD · carga` por rueda.
- **Tope por paso (vale para toda fuerza que se opone al movimiento de la rueda: lateral, freno, freno de mano y resistencia al rodar):** su módulo no supera `(masa / 4) · |velocidad en ese eje| / dt`, así no puede invertir la velocidad en un solo paso. Las fuerzas quedan fijas durante el frame y, sin este tope, la ganancia del neumático y del freno a baja velocidad hace oscilar el auto (medido en la primera ejecución de este WP).
- **Sin inercia de rueda:** `spinRadiansPerSecond` es la velocidad longitudinal / `RADIUS`, solo para las ruedas visuales.

**`Steering.luau`:**
- `maxAngle(speed)`: interpola linealmente entre `STEER_MAX_LOW_SPEED` y `STEER_MAX_HIGH_SPEED` entre `STEER_LOW_SPEED` y `STEER_HIGH_SPEED`, y lo recorta fuera de ese rango.
- `angle(steerInput, speed)`: `steerInput · maxAngle(speed)`. Las dos ruedas delanteras giran igual (sin Ackermann).

**`Assists.luau`:**
- `counterSteer(driftAngle, forwardSpeed)`: `clamp(COUNTER_STEER_STRENGTH · driftAngle, ±COUNTER_STEER_MAX)`, solo si `forwardSpeed > COUNTER_STEER_MIN_SPEED`; si no, 0. Se suma al ángulo de dirección y el total se recorta a `maxAngle`.

**`VehicleSimulator.luau`:**
- API: `newState(): VehicleState` y `step(state, controls, chassis, contacts, dt): (VehicleState, { WheelOutput }, VehicleFeedback)`.
- Orden fijo, documentado en el módulo:
  1. recortar `dt` y las entradas;
  2. ángulo de deriva y dirección más contravolante;
  3. superficie y agarre por rueda;
  4. suspensión y carga (la carga es la fuerza de la suspensión);
  5. "arriba" del contacto (`ContactPlane`);
  6. caja y motor;
  7. por rueda: velocidad del punto de montaje (`v + ω × r`), ejes de la rueda en el plano del contacto (el frente del chasis girado por el ángulo de dirección alrededor del "arriba" y proyectado), deslizamiento, fuerza longitudinal (motor + freno + resistencia al rodar), fuerza lateral y círculo de fricción;
  8. fuerza total = suspensión · arriba + longitudinal · frente de la rueda + lateral · costado de la rueda (en el aire, 0);
  9. feedback.
- No implementa física propia: solo compone los otros módulos. Si una función pasa de 30 líneas, se divide en privadas.

### 4. Pruebas

En `tests/vehicle/`, `tests/input/` y `tests/camera/`, una por módulo, con bordes. Además, estas **pruebas de propiedades** sobre el simulador completo. Hace falta un "mundo de juguete" de prueba (`tests/vehicle/ToyWorld.luau`) que integre el chasis como cuerpo rígido con Euler semiimplícito a 240 Hz: posición, velocidad, orientación y velocidad angular, con un tensor de inercia de caja (6 × 2 × 10). Calcula los contactos contra un plano (con pendiente opcional) y la superficie por una función que se le pasa. **Solo es para las pruebas, no es parte del núcleo.** Cada propiedad corre el simulador a 30 FPS, con las fuerzas fijas entre frames como en Roblox:

1. **Reposo:** sobre un plano horizontal, sin input, 10 s, **también con una perturbación inicial** (0,3 studs/s de costado y 0,01 rad/s de giro). Asienta en menos de 2 s y después la deriva horizontal es < 0,05 studs y la velocidad < 0,05 studs/s.
2. **Estabilidad a 30 y 60 FPS:** con la suspensión entre 2 y 4 Hz y la amortiguación entre 0,45 y 1, el auto apoyado no diverge. A 60 FPS, también con amortiguación 0,3.
   - **Además:** una prueba de `VehicleConfig` exige que la compresión estática (`g / (2π · f)²`) no pase del 60% de `SUSPENSION_MAX_COMPRESSION_STUDS`, así una configuración que no sostiene el auto falla antes de probarla.
3. **Peso (CP-2):** al frenar fuerte, la carga de las delanteras sube por encima de la de las traseras. Al acelerar, al revés. En una curva, las ruedas de afuera cargan más.
4. **Freno de mano (CP-9):** a 60 studs/s, con la dirección a fondo y el freno de mano, la cola se suelta: el ángulo de deriva pasa los 20° en menos de 1,5 s. Sin freno de mano, la misma maniobra queda por debajo.
5. **`REAR_BIAS` (T1):** a la salida de una curva con el acelerador a fondo, con `REAR_BIAS` 1,0 el ángulo de deriva máximo es mayor que con 0,5, en 1ra o 2da marcha.
6. **Superficie (CP-3):** frenando en `Mud`, la distancia de frenado es mayor que en `Road`. Al cruzar un borde, el agarre no salta en un solo paso.
7. **Caja (CP-4):** acelerando a fondo desde 0, pasa por todas las marchas en orden y nunca hay dos cambios seguidos en menos de `SHIFT_DURATION_SECONDS`. La velocidad máxima da 150 ± 15 studs/s.
8. **Dirección (CP-10):** el ángulo máximo a 120 studs/s es menor que a 20 studs/s.
9. **Reversa:** detenido y con el freno apretado, el auto va marcha atrás. Con el acelerador vuelve a 1ra.
10. **Robustez:** con `dt` en 0, negativo, NaN, infinito, 1e-6 y 10, con contactos todos `nil`, con distancias negativas, con masa 0 y con controles fuera de rango, nada da NaN ni infinito, y las fuerzas quedan dentro del tope.
11. **Input (CP-7):** con el teclado, la dirección tarda `STEER_RISE_SECONDS` en llegar a 1 y `STEER_RETURN_SECONDS` en volver. El cambio de izquierda a derecha pasa por 0. La zona muerta y la curva del gamepad funcionan en sus bordes (0, la zona, 1 y −1). El gamepad gana sobre el teclado.
12. **Cámara (CP-11 y CP-12):** con el auto derrapando, el yaw de la cámara queda entre la orientación y la velocidad. Al pasar de 179° a −179°, el yaw toma el camino corto. Mirar atrás cambia al instante y al soltar vuelve. Con el auto volcado no da NaN.

### 5. `docs/nombres.md`

Agregar:
- controles (`VehicleControls`);
- muestra del chasis (`ChassisSample`);
- contacto de rueda (`WheelContact`);
- ángulo de deriva (`driftAngle`);
- deslizamiento (`slipRatio`, `slipAngle`);
- carga (`load`);
- reparto trasero (`REAR_BIAS`);
- y el orden de las ruedas (FL, FR, RL, RR).

## Cambios después de la primera ejecución

Los aprobó Nico el 2026-10-15, después del informe del subagente:
- **Tope por paso** de las fuerzas que se oponen al movimiento (en `Drivetrain` y en las fuerzas de cada rueda): resuelve el temblor lateral en reposo y la reversa a 60 FPS.
- **Rango de la propiedad 2:** de 2 a 4 Hz y amortiguación ≥ 0,45 a 30 FPS, más la prueba de compresión estática de `VehicleConfig`. 1,5 Hz con 2 studs de recorrido no sostiene el auto.
- **`FIRST_GEAR_PEAK_ACCELERATION`** de 60 a 110: con 0,3 g el motor nunca saturaba el neumático trasero y `REAR_BIAS` no cambiaba nada.
- **Resueltos por el orquestador, porque estaban en el WP:** `slipRatio` usa la fuerza pedida antes del tope, y la suspensión a tope dura como máximo `BOTTOM_OUT_MAX_MISSED_STEPS` pasos.
- **Aceptadas del informe:** configuración inyectable (`config?` como último parámetro), los módulos `VehicleMath` y `WheelForces`, `ContactPlane` antes de la suspensión y el filtro de la velocidad de compresión dentro de `Suspension.step`.

## Cambios después del experimento `exp/manejo`

Nico manejó el auto en un Baseplate con adaptadores descartables (rama `exp/manejo`, que no se mergea) y lo dejó "bastante bien" con estos cambios (2026-10-15). **Reemplazan** a los valores y fórmulas de arriba donde se contradigan:

**Valores de `VehicleConfig`:**

| Valor | Antes | Ahora |
| --- | --- | --- |
| `REAR_BIAS` | 0,7 | **1,0** (tracción trasera; ver `docs/decisiones.md`) |
| `FIRST_GEAR_PEAK_ACCELERATION` | 110 | **180** studs/s² |
| `COUNTER_STEER_STRENGTH` | 0,3 | **0** (apagado; el módulo `Assists` queda) |
| `STEER_MAX_HIGH_SPEED_DEGREES` | 8 | **18** |
| `TIRE_SLIDE_FRICTION_RATIO` | 1,0 | **0,75** |
| `BRAKE_DECELERATION` | 250 | **75** studs/s² |
| `HANDBRAKE_FORCE_PER_LOAD` | 1,5 | **0,25** |

**Mecánicas nuevas en el núcleo:**
1. **Contravolante sin recorte al derrapar** (en `VehicleSimulator`, donde se calcula el máximo de dirección): el límite efectivo es `max(Steering.maxAngle(speed), min(|driftAngle| + DRIFT_STEER_MARGIN, STEER_MAX_LOW_SPEED))`, con `DRIFT_STEER_MARGIN_DEGREES` = 5. CP-10 sigue valiendo en recta; al derrapar se puede contravolantear.
2. **Agarre por eje:** `FRONT_GRIP_MULTIPLIER` = 1,0 y `REAR_GRIP_MULTIPLIER` = 0,9 multiplican el agarre disponible (tope lateral y círculo) de cada rueda según su eje.
3. **El freno de mano suelta la cola en vez de frenar:** mientras está apretado, el agarre trasero se multiplica por `HANDBRAKE_REAR_GRIP_MULTIPLIER` = 0,5. Al soltarlo, el factor vuelve a 1 con `1 − exp(−HANDBRAKE_GRIP_RECOVERY_RATE · dt)`, con `HANDBRAKE_GRIP_RECOVERY_RATE` = 3 por segundo. Al apretarlo, baja de inmediato. El factor vive en `VehicleState.rearGripFactor`. La fuerza de freno del freno de mano (`HANDBRAKE_FORCE_PER_LOAD`) se mantiene, más chica.

**Pruebas que cambian:**
- Se ajustan a los valores nuevos las pruebas de `Tire` (caída 0,75), de `VehicleSimulator` (el tope de dirección ahora depende de la deriva) y la propiedad 6a (barro contra ruta).
- **Propiedad 4 (freno de mano):** a 60 studs/s, con dirección a fondo y freno de mano durante 0,3 s, la deriva pasa los 15° y **no hace trompo** (la deriva máxima queda por debajo de 90°).
- **Propiedad 5 (`REAR_BIAS`):** se mantiene, con la configuración inyectada (1,0 contra 0,5), en Road.
- **Propiedad nueva 13 (freno de mano que se recupera):** después de soltarlo, `rearGripFactor` vuelve a más de 0,95 en menos de 1,5 s y nunca pasa de 1.
- **Propiedad nueva 14 (contravolante):** con el auto derrapando a 30°, el ángulo de dirección permitido es mayor que `maxAngle(speed)`; en recta, a la misma velocidad, no.

Lo que no se pudo sostener en el experimento (un derrape largo a 60–80 studs/s con piloto automático) **no es una propiedad**: lo juzga una persona.

## Cambios después del experimento `exp/ajustes-manejo`

Nico manejó un segundo experimento (rama `exp/ajustes-manejo`, que no se mergea), después de un diagnóstico con inputs pregrabados en Studio, y dejó una configuración para derrapar que le gustó (2026-10-15). **Reemplaza** a los valores y fórmulas de arriba donde se contradigan.

**Valores de `VehicleConfig`:**

| Valor | Antes | Ahora |
| --- | --- | --- |
| `TIRE_FRICTION` | 1,0 | **0,7** |
| `TIRE_SLIDE_FRICTION_RATIO` | 0,75 | **0,9** |
| `SUSPENSION_DAMPING_RATIO` | 0,6 | **0,8** |
| `HANDBRAKE_REAR_GRIP_MULTIPLIER` | 0,5 | **0,85** |
| `FIRST_GEAR_PEAK_ACCELERATION` | 180 | **120** studs/s² |
| `REVERSE_RATIO` | 3,5 | **5** |
| `REAR_BIAS` | 1,0 | **0,5** (ver `docs/decisiones.md`) |
| `BRAKE_DECELERATION` | 75 | **55** studs/s² |
| `STEER_MAX_LOW_SPEED_DEGREES` | 32 | **36** |
| `STEER_MAX_HIGH_SPEED_DEGREES` | 18 | **24** |
| `STEER_LOW_SPEED` / `STEER_HIGH_SPEED` | 20 / 120 | **55 / 80** studs/s |
| `DRIFT_STEER_MARGIN_DEGREES` | 5 | **10** |

**Mecánicas nuevas en el núcleo** (las tres primeras ya se probaron en el experimento):
1. **Freno de mano progresivo:** al apretarlo, `rearGripFactor` baja hacia `HANDBRAKE_REAR_GRIP_MULTIPLIER` con `1 − exp(−HANDBRAKE_GRIP_DROP_RATE · dt)`, en vez de saltar. `HANDBRAKE_GRIP_DROP_RATE` = 8 por segundo.
2. **Reversa con empuje propio:** en marcha −1, la fuerza del motor se multiplica por `REVERSE_DRIVE_FRACTION` = 0,4. Con `REVERSE_RATIO` 5, la velocidad máxima atrás es de unos 30 studs/s.
3. **Corte de RPM suave:** entre `REDLINE_RPM − SOFT_LIMITER_RPM` y `REDLINE_RPM` la fuerza del motor baja linealmente hasta 0, en todas las marchas. `SOFT_LIMITER_RPM` = 400. Evita el prender y apagar del motor en el corte, que le sacaba agarre a la reversa.
4. **Dirección en reversa (nuevo, pedido por Nico):** en marcha −1, el ángulo máximo de dirección es `STEER_MAX_REVERSE_DEGREES` = 15, en vez del de `Steering.maxAngle`. Con 36° el auto giraba demasiado cerrado marcha atrás y patinaba.

**Pruebas que cambian:**
- Se ajustan a los valores nuevos las que dependan de ellos, y a la caída progresiva las de `rearGripFactor` (la 13 sigue: vuelve a más de 0,95 en menos de 1,5 s después de soltar).
- **Propiedad 4 (freno de mano):** con el agarre trasero al 85%, se mide igual que antes. Si ya no pasa los 15° con 0,3 s, el subagente **reporta los números** sin cambiar valores: el freno de mano ahora es más suave a propósito.
- **Propiedad 5 (`REAR_BIAS`):** se mantiene como comparación con la configuración inyectada (1,0 contra 0,5).
- **Propiedad nueva 15 (reversa):** desde quieto, con el freno a fondo y la dirección a fondo durante 6 s, el auto entra en marcha −1, la velocidad no pasa de 32 studs/s, el ángulo de dirección no pasa de `STEER_MAX_REVERSE_DEGREES` y el `slipRatio` trasero queda ≤ 1 en la mayor parte del círculo.
- **Propiedad nueva 16 (corte suave):** acelerando a fondo en cualquier marcha, cerca del corte la fuerza del motor baja de forma continua: entre dos pasos seguidos nunca cae de más del 20% del pico a 0.

## Cambios después del bug `2026-10-16-deslizamiento-pendiente`

Reemplazan lo anterior donde se contradigan (detalle en `docs/bugs/2026-10-16-deslizamiento-pendiente.md`):
- **Zona de adherencia:** la fricción (lateral, freno, freno de mano y resistencia al rodar) usa la velocidad de la rueda **prevista al final del cuadro**: `v + (g · eje) · dt`. En un plano horizontal es la velocidad actual.
- **Sin rampa de regularización:** el freno y la resistencia al rodar van contra `signo(v prevista)` y el tope por paso es lo que los limita cerca de 0. El tope de las fuerzas **longitudinales** (freno, freno de mano y resistencia al rodar) vale para la **suma de las cuatro ruedas**: `masa · |v prevista del chasis| / dt`, repartido en proporción a lo que pide cada rueda (`WheelFriction.longitudinalScale`, único lugar donde se calcula). `Drivetrain.brakeRequest` solo da lo que pide el freno de una rueda. `BRAKE_REGULARIZATION_SPEED` ya no existe.
- **Nuevas pruebas:** `tests/vehicle/SlopeHold.test.luau` (de costado sin input y con freno de mano a 5°, 10° y 15°, y freno de mano de frente y de espaldas a 3° y 5°: velocidad < 0,05 studs/s).
- **Pedido de cambio (no es parte del WP):** el freno de mano solo sostiene hasta unos 7°, sin input el auto rueda libre y el freno estando parado entra en reversa.

## Cambios después de manejar por las calles reales (2026-10-16)

Nico aprobó estos valores ("era muy patinoso, ahora está bien"; ver `docs/decisiones.md`). **Reemplazan** a los de las secciones anteriores:

| Valor | Antes | Ahora |
| --- | --- | --- |
| `FRONT_WEIGHT_FRACTION` | 0,5 | **0,7** |
| `CENTER_OF_MASS_HEIGHT_STUDS` | 1 | **0,6** |
| `TIRE_FRICTION` | 0,7 | **1** |
| `REAR_GRIP_MULTIPLIER` | 0,9 | **0,95** |
| `REAR_BIAS` | 0,5 | **0** (tracción delantera) |
| `STEER_MAX_HIGH_SPEED_DEGREES` | 24 | **18** |
| `COUNTER_STEER_STRENGTH` | 0 | **1** |

La propiedad 4 (freno de mano) queda descripta en el informe de esta tarea: con estos valores la maniobra sin freno de mano también pasa de 15° a 60 FPS y la prueba de contraste está pendiente de decisión.

## Fuera de alcance
- Todo lo que toca Roblox: adaptadores, `src/app/`, Rojo y las pruebas en Studio (son del WP-4).
- El reset (RC-12) y el uso de los contratos #35 y #36 (WP-4).
- Sonido, partículas, marcas y HUD (WPs de feedback). Este WP solo produce `VehicleFeedback`.
- Afinar la sensación. Los valores iniciales solo tienen que ser estables y cumplir las propiedades; se ajustan en la prueba de juego.

## Criterios de aceptación
- [ ] Están todos los entregables, con `--!strict` y sin globales de Roblox (pasa `scripts/check-core.sh`).
- [ ] `scripts/check-all.sh` pasa entero, con cobertura **≥ 87%** sobre `src/*/core/**`.
- [ ] Se cumplen las 12 propiedades de la sección 4.
- [ ] Ningún `step` modifica sus argumentos (hay una prueba que congela las entradas con `table.freeze` y llama a `step`).
- [ ] No hay números mágicos fuera de `VehicleConfig`, `InputConfig` y `CameraConfig` (salvo `math.pi` y conversiones de unidades con nombre).
- [ ] Ningún archivo pasa de 200 líneas ni de 7 funciones públicas, y ninguna función de 30 líneas. Si alguno se pasa, se justifica en el informe.
- [ ] El `ToyWorld` vive solo en `tests/` y ningún módulo de `src/` lo requiere.

## Pruebas manuales
- [ ] Intentar romperlo: correr las propiedades con valores de configuración extremos (frecuencia 4 Hz, amortiguación 0,3, `REAR_BIAS` 0 y 1, `TIRE_SLIDE_FRICTION_RATIO` 0,5) y confirmar que nada diverge. Lo que diverja se reporta, no se esconde.
- [ ] Revisión del orquestador: leer el `VehicleSimulator` de arriba abajo y comprobar que se entiende sin comentarios.
- Las pruebas en Studio (manejar, derrapar, 30 FPS y dueño de red) son del WP-4.
