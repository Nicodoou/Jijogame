# WP-20a — Fichas de auto, motor y caja, y `VehicleBuild.assemble`, sin cambiar el manejo

**Issue:** pedido de Nico (2026-10-17), idea #63.
**Diseño:** `docs/disenos/motor-y-builder.md`, aprobado el 2026-10-18 con M1, U1, F1, E1 y la migración en 3 pasos. Este WP es el **paso 1**.
**Responsable:** Agente A
**Depende de:** nada, más allá de `main`. Choca con las ramas abiertas del WP-14 y del WP-18 solo en `VehicleConfig`: este WP lo reescribe como salida del builder, así que el que se mergee después resuelve el conflicto moviendo las claves nuevas a la ficha que corresponda.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (Sonnet). Es lógica pura del núcleo. La parte de Studio se limita a verificar que la masa no cambió.
- **Entrega:** su informe, con mediciones **hechas con comandos** y la salida de `scripts/check-all.sh`.

## Contexto para el subagente
- **Leer:**
  - `docs/disenos/motor-y-builder.md`;
  - `src/vehicle/core/VehicleConfig.luau`, `VehicleTypes.luau` y `Drivetrain.luau`;
  - `src/vehicle/server/VehicleModelBuilder.luau`, que es donde sale la masa física;
  - `src/vehicle/shared/TuningOverrides.luau`;
  - `tests/vehicle/`.
- **Cómo es hoy:**
  - La fuerza de tracción es `masa · FIRST_GEAR_PEAK_ACCELERATION · fracción(rpm) · (relación / relación de 1ra)`, en `Drivetrain.driveForce` y `gearForce`. `masa` es la masa del chasis que mide el adaptador (`AssemblyMass`, hoy 84).
  - Cualquier cambio de masa cambia la fuerza en la misma proporción, así que la aceleración es fija.

**Dónde trabaja:** rama `a/builder-fichas`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp20`.

## Entregables (núcleo)

### 1. Tipos (`src/vehicle/core/specs/SpecTypes.luau`)
- **`CarSpec`:**
  - ruedas, radio y suspensión;
  - neumático y agarre: `TIRE_*`, `FRONT/REAR_GRIP_MULTIPLIER` y `SURFACE_*`;
  - dirección y asistencias: `STEER_*`, `COUNTER_STEER_*` y `DRIFT_*`;
  - frenos y freno de mano;
  - aire;
  - reparto de peso y centro de masa;
  - `CHASSIS_MASS`, la masa del chasis en unidades de Roblox;
  - `ENGINE_POSITION_Z`, dónde va el motor, en el marco del Body.
- **`EngineSpec`:**
  - `PEAK_TORQUE`, en unidades de torque de juego;
  - `TORQUE_CURVE`, la forma de la curva en fracciones;
  - `IDLE_RPM`, `REDLINE_RPM` y `SOFT_LIMITER_RPM`;
  - `ENGINE_MASS`;
  - `ENGINE_BRAKE_DECELERATION` y `ENGINE_BRAKE_MIN_RPM`.
- **`GearboxSpec`:**
  - `kind = "automatic"` (el tipo admite `"manual"` para después, decisión M1);
  - `GEAR_RATIOS`, `REVERSE_RATIO`, `REVERSE_DRIVE_FRACTION`, `FINAL_DRIVE` y `DRIVETRAIN_EFFICIENCY`;
  - `REAR_BIAS`, el reparto de tracción;
  - umbrales de cambio, kickdown, tiempos y `SHIFT_TORQUE_FRACTION`.
- **`MAX_STEP_SECONDS` y `CONTACT_PLANE_DEGENERATE_THRESHOLD`** son del simulador, no de una ficha: quedan como constantes del builder.

### 2. Fichas (`src/vehicle/core/specs/`)
- `cars/Fiat147.luau`, `engines/Engine147.luau` y `gearboxes/Automatic5.luau`, con **exactamente los valores de hoy**, repartidos por ficha.
- **`PEAK_TORQUE`:** se calcula para que la fuerza en la rueda sea idéntica con la masa de hoy:
  `PEAK_TORQUE · relación · FINAL_DRIVE · DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS = 84 · FIRST_GEAR_PEAK_ACCELERATION · (relación / relación de 1ra)`,
  así que `PEAK_TORQUE = 84 · 120 · WHEEL_RADIUS / (3,5 · FINAL_DRIVE · DRIVETRAIN_EFFICIENCY)`.
  - El valor se escribe con la cuenta en un comentario.
  - `DRIVETRAIN_EFFICIENCY` = 0,9.
- **`CHASSIS_MASS + ENGINE_MASS` = 84**, la masa de hoy. El reparto entre chasis y motor lo propone el subagente (por ejemplo, 70 + 14) y lo justifica.

### 3. `src/vehicle/core/VehicleBuild.luau`
- **`assemble(car, engine, gearbox) → (VehicleSettings?, string?)`:** pura. Devuelve la configuración o un error con la razón.
- **Qué arma:**
  - todas las claves que hoy tiene `VehicleConfig` (las mismas, para que el simulador no cambie), salvo `FIRST_GEAR_PEAK_ACCELERATION`;
  - en su lugar, `WHEEL_FORCE_PER_TORQUE_RATIO`, o lo que haga falta para que `Drivetrain` calcule `F = PEAK_TORQUE · fracción · relación · FINAL_DRIVE · eficiencia / radio`;
  - `TOTAL_MASS = CHASSIS_MASS + ENGINE_MASS`;
  - `FRONT_WEIGHT_FRACTION`, que se corre por la masa del motor según `ENGINE_POSITION_Z`. Con la ficha del 147 tiene que dar exactamente el 0,7 de hoy: el valor de la ficha es el del chasis solo, recalculado para que la suma dé 0,7.
- **Validación**, con error y sin auto roto:
  - sin marchas o con relaciones ≤ 0;
  - curva vacía o sin orden de RPM;
  - masas ≤ 0;
  - eficiencia fuera de (0, 1];
  - corte ≤ ralentí.
- **Congela** la salida con `table.freeze`.
- **`powerHp(engine) → number`:** "HP de juego", el máximo de `torque(rpm) · rpm / GAME_HP_CONSTANT`. La constante se elige para que el motor del 147 dé 50 HP de juego (decisión U1). Solo informativo en este WP.

### 4. `VehicleConfig.luau`
- Pasa a ser `return VehicleBuild.assemble(Fiat147, Engine147, Automatic5)`, con error si la combinación es inválida.
- Todos los `require` siguen funcionando igual.

### 5. `Drivetrain`
- Calcula la fuerza desde el torque. **La masa deja de multiplicar la fuerza de tracción.**
- El freno y el freno motor siguen como hoy: son desaceleraciones por la masa, así que no cambian.

### 6. Adaptador de masa (`VehicleModelBuilder`)
- La masa física del auto armado tiene que ser `TOTAL_MASS`.
- Hoy da 84 por los tamaños de las partes. Si no coincide, se ajusta la densidad del lastre: no se cambian los tamaños, por el bug de vibración del WP-7.
- Se mide en Studio: `AssemblyMass` = 84,00 y el centro de masa igual al de hoy.

## Pruebas
- **Igualdad:**
  - para cada marcha y RPM de 1000 a 7000 cada 250, la fuerza de tracción nueva es la de hoy ±1% (con la fórmula vieja como referencia en la prueba);
  - todas las propiedades del simulador (`VehicleProperties` y el resto) pasan **sin tocarlas**;
  - la velocidad máxima en 5ta es la de hoy ±0,5%.
- **Builder:**
  - cada error de validación devuelve su razón;
  - la salida está congelada;
  - no modifica las fichas;
  - es determinista.
- **Peso:**
  - con un motor más pesado adelante, `FRONT_WEIGHT_FRACTION` sube;
  - con el del 147 da 0,7.
- **HP de juego:** `powerHp(Engine147)` = 50 ± 0,5.
- **`TuningOverrides`:** un `Cfg_` sigue pisando una clave de la salida (prueba existente o nueva).

## Fuera de alcance
- El segundo motor y las pruebas de combinaciones: WP-20b.
- El embrague con rampa: WP-20c.
- El garage y la caja manual (decisiones E1 y M1).

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] El manejo no cambia: igualdad de fuerza ±1% y todas las propiedades sin tocar.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos**.
- [ ] La masa en Studio es 84,00.
