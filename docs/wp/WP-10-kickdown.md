# WP-10 — Caja automática con kickdown

**Issue:** #8 (tipo de auto). Lo pidió Nico después de manejar por las calles del Agente B: "le cuesta mucho subir cuestas altas, por las marchas".
**Requerimientos:** CP-4 (caja automática que se siente), RC-6 (pendientes que el auto puede subir).
**Diseño:** `docs/disenos/auto.md`, tabla del núcleo, fila `Drivetrain` (caja automática con histéresis). Este WP agrega una regla de cambio sin cambiar la arquitectura.
**Responsable:** Agente A
**Depende de:** los valores nuevos de Nico en `main` (PR de `a/7-valores-nico-2`).

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (Sonnet). Es lógica pura del núcleo, sin Studio.
- **Entrega:** el informe de su definición, con los criterios uno por uno y la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `src/vehicle/core/Drivetrain.luau`, `VehicleConfig.luau` y `VehicleSimulator.luau`;
  - `tests/vehicle/` (propiedad 7, de la caja, y `ToyWorld` con pendiente);
  - `docs/reglas-de-trabajo.md` (secciones 3 a 5).
- **El problema, con números:**
  - Con `FIRST_GEAR_PEAK_ACCELERATION` = 120, el empuje máximo por marcha es de 120, 79, 57, 43 y 34 studs/s² (1ra a 5ta).
  - Una cuesta de 15° pide 51 studs/s² solo para mantener la velocidad.
  - Hoy la caja solo baja de marcha con las RPM ≤ `DOWNSHIFT_RPM` (3000). Así, en una cuesta el auto se frena en 4ta o 5ta y baja recién cuando ya perdió mucha velocidad.
- **Decisión de Nico (2026-10-16):** kickdown, como el de una automática real. Se descartó acortar las marchas, porque baja la velocidad máxima o pone nervioso al auto en plano.

**Dónde trabaja:** rama `a/8-kickdown`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp10`.

## Objetivo

Que con el acelerador a fondo la caja elija la marcha que más empuja (dentro del margen del corte), así el auto sube las cuestas sin quedarse en una marcha larga. Con el acelerador suave se comporta como hoy.

## Entregables

1. **`Drivetrain.gearForce(gear, forwardSpeed, config?)`** (pública, pura): la fracción de empuje que daría esa marcha a esa velocidad. Es `torqueFraction(rpm) · relación / relación de 1ra · factor del corte suave`, con las RPM que tendría el motor en esa marcha. Devuelve 0 si las RPM pasan `REDLINE_RPM`. La usan `driveForce` y la regla de cambio, así la fórmula está en un solo lugar.
2. **Regla de kickdown en `Drivetrain.nextGear`.** Se suma a las de hoy, después de la reversa y del bloqueo por cambio en curso:
   - **Bajar:**
     - si `throttle ≥ KICKDOWN_THROTTLE`;
     - y la marcha de abajo tendría RPM ≤ `REDLINE_RPM − SOFT_LIMITER_RPM − KICKDOWN_RPM_MARGIN`;
     - y `gearForce(abajo) > gearForce(actual) · (1 + KICKDOWN_FORCE_MARGIN)`;

     entonces baja **una** marcha, con su `SHIFT_DURATION_SECONDS`. Si en el paso siguiente sigue conviniendo, baja otra cuando termine el cambio.
   - **Subir con el acelerador a fondo:** no sube mientras la marcha de arriba empuje menos que la actual, salvo que la actual ya esté en el corte suave (RPM ≥ `REDLINE_RPM − SOFT_LIMITER_RPM`). Así no sube para volver a bajar.
   - **Con el acelerador por debajo de `KICKDOWN_THROTTLE`:** las reglas de hoy (`UPSHIFT_RPM` y `DOWNSHIFT_RPM`), sin cambios.
3. **`VehicleConfig`:**
   - `KICKDOWN_THROTTLE` = 0,9;
   - `KICKDOWN_FORCE_MARGIN` = 0,1, la histéresis: hace falta un 10% más de empuje para bajar;
   - `KICKDOWN_RPM_MARGIN` = 300.
4. **`docs/nombres.md`:** kickdown (`KICKDOWN_*`) y empuje relativo de una marcha (`gearForce`).

## Pruebas (`tests/vehicle/`, con `ToyWorld` donde haga falta)
- **Unitarias de `gearForce`:** coincide con la fuerza de `driveForce` dividida por masa · pico; es 0 por encima del corte; es monótona en la velocidad dentro de cada tramo de la curva.
- **Unitarias de `nextGear`:**
  - a fondo, en 5ta a 40 studs/s, baja;
  - a fondo, en 2da cerca del corte, sube;
  - con el acelerador en 0,5, no hay kickdown;
  - durante un cambio, no cambia;
  - en la marcha más baja no baja más, y en la más alta no sube más.
- **Propiedad 18 (subida):** sobre una pendiente de 15°, llegando a 80 studs/s en 5ta con el acelerador a fondo:
  - el auto baja de marcha antes de que la velocidad caiga 15 studs/s;
  - termina subiendo a una velocidad estable de al menos 35 studs/s;
  - con la regla anterior, la misma maniobra queda por debajo (comparación con `config` inyectada o con `KICKDOWN_THROTTLE` = 2, que la apaga).
- **Propiedad 19 (sin "caza" de marchas):** en una pendiente constante de 10° y 15° con el acelerador a fondo, una vez estable no hay dos cambios seguidos en sentidos opuestos en menos de 1 s, a 30 y a 60 FPS.
- **Propiedad 7 (caja en plano):** sigue pasando: pasa por todas las marchas en orden y la velocidad máxima es 150 ± 15.
- **Todas las demás propiedades** y `RestAfterDriving`, `SlopeHold` y `LongitudinalLimit` siguen pasando.

## Fuera de alcance
- Mapas de cambio que dependan del acelerador para subir antes con el pedal suave.
- Freno motor (WP propio, ya aprobado).
- La caja manual (después del MVP, #63).

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Pasan las propiedades 18 y 19, y siguen pasando todas las demás.
- [ ] La fórmula del empuje por marcha está en un solo lugar (`gearForce`).
- [ ] Sin números mágicos; archivos ≤ 200 líneas y funciones ≤ 30.

## Pruebas manuales
- [ ] (Nico, en Studio) Subir las cuestas más empinadas de la ruta del Agente B a fondo, y fijarse que la caja baje a tiempo y no "cace" marchas.
- [ ] (Nico) En plano, pisar a fondo desde 5ta a velocidad media: tiene que bajar una o dos marchas y acelerar.
