# WP-14 — Cámara en primera persona

**Issue:** pedido de Nico (2026-10-16). Decisión "Cámara en primera persona, la única del juego" en `docs/decisiones.md`.
**Requerimientos:**
- CP-12 (mirar atrás): se mantiene.
- CP-11 (cámara de persecución): **cambia**. La reemplaza la primera persona.
- CP-2 (peso perceptible): la cabeza se mueve con el auto.

**Diseño:**
- `docs/disenos/auto.md`, núcleo de la cámara.
- Este WP **reemplaza** `ChaseCamera` por `FirstPersonCamera`, con el mismo patrón: núcleo puro con `step`, adaptador delgado y configuración como datos.

**Responsable:** Agente A
**Depende de:** el WP-13 (el 147 y la posición de la cabeza del conductor en su ficha).

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (Sonnet) para el núcleo. Después, `programador-adaptador.md` para los adaptadores y Studio, en la misma rama.
- **Entrega:** sus informes, con mediciones **hechas con comandos**.

## Contexto para el subagente

- **Leer:**
  - `src/camera/core/` y `tests/camera/` (lo que se reemplaza);
  - `src/input/core/InputSmoother.luau`, `src/input/client/InputReader.luau` y `src/camera/client/ChaseCameraController.luau`;
  - `src/vehicle/core/VehicleModels.luau` (WP-13);
  - `docs/reglas-de-trabajo.md`.
- **Lo que decidió Nico:**
  - **Solo primera persona.** Se saca la de persecución, con su código y sus pruebas, y su configuración queda limpia.
  - **Mirar alrededor:** con el mouse o el stick derecho, dentro de un límite, y vuelve sola al frente al soltar.
  - **Mirar atrás:** C sigue mirando atrás (CP-12).
  - **La cabeza se mueve suave:** con las aceleraciones, las frenadas, las curvas y el ripio. No tiene que marear, y es configurable.
- **Contratos:** ninguno.

**Dónde trabaja:** rama `a/7-primera-persona`, desde `main` con el WP-13 ya mergeado, en el worktree `C:\Users\Nico\Documents\Rally-wp14`.

## Entregables

### Núcleo

1. **`src/input/core`:** `RawInput` suma `lookDeltaX` y `lookDeltaY`, el movimiento del mouse en el frame en píxeles, y `gamepadLookX` y `gamepadLookY`, el stick derecho en [−1, 1]. `SmoothedInput` suma `lookYawRate` y `lookPitchRate` en rad/s.
   - **Mouse:** `MOUSE_LOOK_RADIANS_PER_PIXEL`.
   - **Stick:** `GAMEPAD_LOOK_RADIANS_PER_SECOND`, con su zona muerta.
2. **`src/camera/core/FirstPersonCamera.luau`** (reemplaza a `ChaseCamera`):
   - **API:**
     - `newState()`;
     - `step(state, view, look, isLookingBack, dt) → (state, pose)`.
   - **Lo que recibe:**
     - `view`: orientación del auto (derecha, arriba y adelante), posición de la cabeza en el mundo, velocidad lineal y la aceleración que calcula el núcleo a partir de la velocidad;
     - `look`: las velocidades de giro del entrada.
   - **Mirar:**
     - el yaw y el pitch de la cabeza se acumulan y se recortan a `LOOK_MAX_YAW_DEGREES` (100) y `LOOK_MAX_PITCH_DEGREES` (35);
     - sin entrada, vuelven al frente con `LOOK_RETURN_RATE`;
     - `isLookingBack` gira 180° al instante, como hoy.
   - **Movimiento de la cabeza** (resorte con amortiguación, por eje):
     - la aceleración del auto en su propio marco empuja la cabeza al revés (frenar la tira hacia adelante) con `HEAD_SWAY_PER_ACCELERATION`, recortada a `HEAD_SWAY_MAX_STUDS`;
     - una inclinación (roll y pitch) proporcional a la aceleración lateral y longitudinal, con `HEAD_TILT_PER_ACCELERATION` y `HEAD_TILT_MAX_DEGREES`;
     - una vibración chica que depende de la velocidad, `HEAD_VIBRATION_*`. Es **determinista**: sale de la distancia recorrida, no de azar.
   - **Salida:** `CameraPose` con `position` (cabeza + balanceo) y una orientación que sale de la del auto, con la mirada y la inclinación.
   - **`dt` inválido:** el estado queda igual, como en el resto del núcleo.
3. **`CameraConfig`:** los valores de arriba, con unidades. Se sacan los de persecución.
4. **Pruebas** (sacá las de `ChaseCamera`):
   - **Mirar:** el yaw y el pitch se recortan al límite y vuelven al frente sin entrada (llegan al 95% en ≤ 1 s); mirar atrás es instantáneo.
   - **Balanceo:**
     - frenar a 1 g mueve la cabeza hacia adelante, nunca más que `HEAD_SWAY_MAX_STUDS`, y vuelve sin oscilar más de 2 veces;
     - en curva se inclina hacia afuera;
     - en reposo, quieta.
   - **Vibración:** 0 con el auto quieto, y acotada a velocidad.
   - **Robustez:** `dt` inválido, entradas NaN y el auto volcado no dan NaN.
   - **Argumentos:** no se modifican (`table.freeze`).

### Adaptadores
5. **`InputReader`:**
   - lee el movimiento del mouse (`UserInputService:GetMouseDelta()`) y el stick derecho;
   - mientras se maneja, pone `MouseBehavior = LockCenter`;
   - el mouse se libera con Esc, como es normal en Roblox.
6. **`FirstPersonCameraController`** (reemplaza a `ChaseCameraController`):
   - **Cuándo corre:** en `PreRender`.
   - **Qué arma:** la vista con la posición de la cabeza, que es la de la ficha del modelo pasada al marco del `Body`.
   - **Qué aplica:** la pose a `CurrentCamera`, con `CameraType = Scriptable`.
   - **Campo de visión:** `FieldOfView` desde la config (`FIELD_OF_VIEW_DEGREES`, inicial 80).
   - **Modelo propio:** el modelo del 147 queda visible (interior, volante y capó), y se ocultan solo las piezas que tapan la vista desde adentro, si hace falta. Medilo en Studio y reportalo.
7. **Arranque del cliente:** usa el controlador nuevo.

## Pruebas en Studio
- **Cámara:** desde el asiento del conductor, mirando adelante, con el capó y el interior visibles y nada atravesándola.
- **Mirar:** el mouse y el stick miran alrededor con su límite y vuelven al frente. C mira atrás.
- **Balanceo:** al frenar fuerte la cabeza va hacia adelante y vuelve, en curva se inclina, y en el ripio vibra apenas.
- **Rendimiento:** a 60 y 30 FPS, sin tirones de la cámara.

## Fuera de alcance
- Espejos funcionales. Los espejos del modelo son solo mallas.
- Sonido.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] No queda código ni configuración de la cámara de persecución.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos**.
- [ ] Nico lo prueba manejando.
