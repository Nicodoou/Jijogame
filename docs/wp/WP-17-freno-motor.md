# WP-17 — Freno motor, resistencia del aire y freno de mano que sostiene

**Issue:** pedido de Nico (2026-10-17). Hoy, en una pendiente imposible, el auto rueda hacia atrás sin límite. Además, soltar el acelerador no frena nada.
**Requerimientos:**
- CP-2: peso perceptible.
- CP-4: la caja se siente.
- RC-6: pendientes.
**Diseño:** `docs/disenos/auto.md`, núcleo del auto. Agrega tres fuerzas que se oponen al movimiento, dentro del mecanismo que ya existe (`WheelFriction.longitudinalScale`, el tope común por paso). La arquitectura no cambia.
**Responsable:** Agente A
**Depende de:** nada, más allá de `main`.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (Sonnet). Lógica pura del núcleo. Después, una prueba de manejo de Nico en Studio.
- **Entrega:** su informe, con mediciones **hechas con comandos** y la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `src/vehicle/core/Drivetrain.luau`, `WheelFriction.luau`, `WheelForces.luau`, `Gearbox.luau`, `VehicleConfig.luau` y `VehicleSimulator.luau`;
  - `tests/vehicle/` (propiedades y `ToyWorld` con pendiente);
  - `docs/reglas-de-trabajo.md`.
- **Cómo es hoy:**
  - Las fuerzas que se oponen (freno, freno de mano y resistencia al rodar) se piden por rueda en `longitudinalRequest`.
  - Ese pedido se recorta entre todas las ruedas con el tope común `masa · |v prevista| / dt`.
  - Por ese tope, con el auto casi quieto actúan como fricción estática y no hacen oscilar al auto.

**Dónde trabaja:** rama `a/freno-motor`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp17`.

## Entregables (núcleo)

### 1. Freno motor
- **Cuándo actúa:** solo en las ruedas con tracción, con una marcha puesta y sin estar cambiando. Escala con `(1 − acelerador)`.
- **Fuerza:** `masa · ENGINE_BRAKE_DECELERATION · fracciónRpm · (relación de la marcha / relación de 1ra)`.
  - `fracciónRpm` es `(rpm − ralentí) / (corte − ralentí)`, recortada a [0, 1].
  - Con la relación de la marcha, frena más en las marchas cortas, como un auto real.
- **Por debajo de `ENGINE_BRAKE_MIN_RPM`** vale 0: el embrague se abre y el auto no se clava andando despacio.
- **Reparto:** como la tracción (`REAR_BIAS`). Entra en `longitudinalRequest`, así que respeta el tope común.
- **Valor inicial:** `ENGINE_BRAKE_DECELERATION` alrededor de 8 studs/s² en 1ra al corte. El subagente lo mide y lo reporta, y se ajusta con `Cfg_`.

### 2. Resistencia del aire
- **Fuerza:** `AIR_DRAG_PER_SPEED_SQUARED · v²`, contra la velocidad hacia adelante del chasis.
- **Reparto:** entre las ruedas apoyadas, en proporción a la carga.
- **Simplificación aceptada:** en el aire no actúa. Se anota en el diseño.
- **Calibración:** que la velocidad máxima en 5ta baje como mucho un 10% (de unos 148 a no menos de 133 studs/s), medido con el simulador en plano.

### 3. Freno de mano que sostiene
- **Cuándo se activa:** freno de mano puesto, velocidad del chasis < `HANDBRAKE_HOLD_SPEED` (unos 3 studs/s) y deriva < `HANDBRAKE_HOLD_MAX_DRIFT_DEGREES` (unos 10°).
- **Qué hace:** el freno de mano pasa a frenar las cuatro ruedas con `HANDBRAKE_HOLD_FORCE_PER_LOAD · carga`. Con eso alcanza para sostener la pendiente más empinada que el auto puede subir.
  - Sigue dentro del tope común: sostiene sin vibrar.
  - No cambia el agarre lateral: no agrega deriva estando quieto.
- **Se libera** al soltar el freno de mano. Por encima de la velocidad o derrapando, el freno de mano sigue como hoy (solo atrás, para derrapar).

### 4. `VehicleConfig`
- Las claves nuevas, con su unidad y un comentario.
- Las nuevas van **antes** de las del WP-15 (`WHEEL_GRIP_MULTIPLIERS` y `STEER_OFFSET_DEGREES`), para no chocar.

### 5. Pruebas
- **Freno motor:**
  - en plano, al soltar el acelerador a 60 studs/s en 3ra, el auto desacelera más que sin freno motor;
  - frena más en 2da que en 4ta a la misma velocidad;
  - es 0 por debajo de `ENGINE_BRAKE_MIN_RPM` y con el acelerador a fondo;
  - nunca empuja hacia adelante.
- **Aire:**
  - la velocidad máxima en 5ta baja como mucho un 10%;
  - es 0 con el auto quieto;
  - crece con v².
- **Freno de mano que sostiene:**
  - en la pendiente máxima del `ToyWorld`, con el auto quieto y el freno de mano puesto, el desplazamiento en 10 s es menor a 0,05 studs y no hay vibración (velocidad máxima menor a 0,01);
  - sin el freno de mano, rueda;
  - derrapando a 30 studs/s, el freno de mano sigue frenando solo atrás.
- **Pendiente imposible:** sin freno de mano, la velocidad hacia atrás queda acotada por el aire y el rodamiento, no crece sin límite en 20 s.
- **Robustez:** sin NaN. Las propiedades existentes siguen pasando; si alguna cambia, se reporta con números y no se relaja.

## Pruebas en Studio (las hace Nico manejando)
- Al soltar el acelerador, el auto frena perceptible pero suave. Al bajar una marcha a mano, el kickdown sigue funcionando.
- Velocidad máxima casi igual.
- En una cuesta, freno de mano casi quieto: el auto queda clavado. Al soltarlo, sale.
- El drift con freno de mano no cambia.

## Fuera de alcance
- El embrague, la curva de torque por motor y el builder de motores y autos: van en el próximo WP.
- El sonido.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos**.
- [ ] Nico lo prueba manejando.
