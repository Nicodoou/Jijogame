# WP-15 — Núcleo del daño por pieza

**Issue:** diseño `docs/disenos/hitbox-y-dano.md` (aprobado), experimento #82
**Requerimientos:** CP-5 (ampliado con daño por pieza, decisión de Nico del 2026-10-16)
**Diseño:** `docs/disenos/hitbox-y-dano.md`, secciones "Las piezas", "Efecto de cada pieza", "Arquitectura" y "Resultados del experimento"
**Responsable:** Agente A
**Depende de:** nada; es núcleo puro. Puede ir en paralelo con los WP-13 y 14, porque toca archivos distintos.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` (Sonnet).
- **Entrega:** su informe, con las mediciones de tamaños **hechas con comandos** y los criterios uno por uno.

## Contexto para el subagente
- **Leer:**
  - el diseño entero;
  - `src/vehicle/core/VehicleConfig.luau`, `VehicleTypes.luau` y `VehicleSimulator.luau` (cómo se inyecta la configuración);
  - `src/vehicle/core/Drivetrain.luau` y `Gearbox.luau`;
  - `docs/reglas-de-trabajo.md`.
- **Decisiones que aplican:** "Hitbox modular y daño por pieza en el MVP" y las de política de código.
- **Lo que el núcleo NO hace:** detectar golpes (lo hace el adaptador, con `BindToCollisionSummaries`), ni texturas, ni piezas que caen. Solo recibe golpes `(pieza, velocidad de impacto)` y devuelve el estado y los efectos.
- **Contratos:** ninguno.

**Dónde trabaja:** rama `a/hitbox-nucleo`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp15`. Todo en `src/vehicle/core/damage/` y `tests/vehicle/damage/`.

## Entregables

1. **`DamageTypes.luau`:**
   - **`PieceKind`:** unión de cadenas con las piezas del diseño:
     - exteriores: `chassisBase`, `bonnet`, `trunk`, `roof`, `door`, `frontBumper`, `rearBumper`, `grille`, `fender`, `sideSkirt`, `windshield`, `rearWindow`, `window`, `mirror`, `light` y `wheel`;
     - interiores: `engine`, `radiator`, `gearbox`, `suspension`, `steering` y `fuelTank`.
   - **`PieceSpec`:** `{ id: string, kind: PieceKind, isExterior: boolean, damagePerImpact: number (K), impactThreshold: number (studs/s), wearPerDamage: number, protects: { { pieceId: string, factor: number } }, wheelIndex: number? }`.
   - **`PieceState`:** `{ damage: number, wear: number, isDetached: boolean }`.
   - **`DamageState`:** `{ pieces: { [string]: PieceState } }`.
   - **`DamageEvent`:** `{ pieceId: string, kind: "damaged" | "detached", damage: number }`.
2. **`DamageConfig.luau`:** una ficha de ejemplo para el 147, con las piezas que hoy tiene el modelo, y valores iniciales:
   - umbral: 15 studs/s;
   - K: 0,05 en piezas de chapa y 0,08 en vidrios y luces;
   - desgaste por daño: 0,1;
   - protección: parrilla y paragolpes delantero sobre el radiador (0,6); radiador sobre el motor (0,3); base del chasis sobre la suspensión de cada rueda y el tanque (0,4); guardabarros sobre su rueda y su suspensión (0,5).

   Es solo datos. La ficha vive aparte del manejo: es la base de `ChassisSpec`, para las piezas intercambiables de después del MVP.
3. **`DamageModel.luau`** (puro):
   - **`newState(specs)`:** todo en 0 y sin piezas caídas.
   - **`applyImpact(state, pieceId, impactSpeed, specs) → (state, { DamageEvent })`:**
     - el daño es `K · max(0, |v| − umbral)²`;
     - suma desgaste: `wearPerDamage · daño`;
     - pasa a las interiores que la pieza protege: `daño · factor`, recursivo y con un tope de profundidad para no ciclar;
     - con 100 o más, la pieza queda `isDetached`, emite el evento `detached` y deja de recibir daño;
     - una pieza caída **deja de proteger**: el golpe siguiente en esa zona va directo a lo que cubría.
   - **No modifica sus argumentos.** Ignora una pieza que no exista y los valores no finitos.
4. **`DamageEffects.luau`** (puro): `apply(settings, damageState, specs) → settings`. Devuelve una **copia** de la configuración del simulador con los efectos aplicados. Con vida = 1 − daño/100:
   - **`engine`:** `FIRST_GEAR_PEAK_ACCELERATION × vidaMotor`;
   - **`radiator`:** multiplica la potencia por `0,5 + 0,5 · vidaRadiador`;
   - **`gearbox`:** `SHIFT_DURATION_SECONDS × (1 + 2 · daño/100)`;
   - **`suspension` (por rueda):** baja el agarre de esa rueda (`(1 − 0,5 · daño/100)`) y agrega un desvío lateral de la dirección (`STEERING_PULL_DEGREES_PER_DAMAGE`, por lado);
   - **`steering`:** desvío fijo del volante proporcional al daño, con su valor en la config del daño;
   - **`wheel`:** agarre de esa rueda × vida; caída, agarre 0;
   - **el resto:** sin efecto en el manejo.

   **Lo que hay que sumarle al simulador:** las pruebas van a mostrar si el núcleo ya acepta "agarre por rueda" y "desvío de dirección". **Si no, sumá a `VehicleConfig` dos valores opcionales, `WHEEL_GRIP_MULTIPLIERS` (lista por rueda, 1 por defecto) y `STEER_OFFSET_DEGREES` (0 por defecto), y que el simulador los use.** Es el único cambio permitido fuera de `damage/`, con sus pruebas, y no puede cambiar ninguna propiedad con los valores por defecto.
5. **`docs/nombres.md`:** pieza (`PieceKind` y `PieceSpec`), daño, desgaste, golpe (`impactSpeed`) y pieza caída (`isDetached`).

## Pruebas (`tests/vehicle/damage/`)
- **Daño:**
  - por debajo del umbral es 0, y crece con el cuadrado;
  - el valor absoluto de la velocidad da lo mismo con cualquier signo;
  - NaN e infinito no dañan.
- **Pieza caída:** con 100 se cae, emite el evento una sola vez y no recibe más daño.
- **Protección:**
  - el radiador recibe el 60% de lo que entra por la parrilla;
  - con la parrilla caída, el golpe siguiente va directo al radiador;
  - no hay ciclos infinitos con una ficha mal hecha (A protege B y B protege A).
- **Desgaste:** sube con el daño y nunca baja (no hay reparación).
- **Efectos:**
  - con todo en 0, la configuración es idéntica a la original;
  - motor a 50 de daño, la mitad de empuje;
  - suspensión trasera derecha dañada, el agarre de esa rueda baja y la dirección se desvía;
  - rueda caída, agarre 0.
- **Propiedad del simulador con daño:**
  - con la suspensión delantera derecha al 80%, el auto en recta con el volante al centro se desvía (deriva lateral > X studs en 3 s);
  - con el motor al 50%, la velocidad a los 5 s es menor que sin daño.
- **Argumentos:** no se modifican (`table.freeze`).
- **Lo que ya pasaba:** todas las propiedades del manejo siguen pasando.

## Fuera de alcance
- Detectar golpes, las cajas, las texturas, las piezas que caen y el plugin del editor (otros WPs).
- Reparar (después del MVP).
- Combustible (decisión F1).

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Las pruebas de arriba pasan.
- [ ] Sin números mágicos: todo en la ficha o en la config del daño.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos y pegado en el informe**.
