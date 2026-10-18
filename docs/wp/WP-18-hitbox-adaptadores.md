# WP-18 — Hitbox en el auto: cajas, golpes, piezas que se caen

**Issue:** pedido de Nico (2026-10-18): "ponete con la hitbox".
**Requerimientos:** hitbox modular y daño por pieza en el MVP (decisión del 2026-10-16).
**Diseño:** `docs/disenos/hitbox-y-dano.md`, aprobado con D1, C1, P1, T1, A1, E1 y F1. Es el paso 3 del plan de trabajo. El núcleo ya está hecho (WP-15).
**Responsable:** Agente A
**Depende de:**
- el WP-15 (en `main`);
- el 147 nuevo guardado en `assets/vehicles/Fiat147.rbxm`, con su ficha. Hoy está en `exp/asistencia-curva` y entra a `main` con el WP-14.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` para los datos y la cuenta pura. Después, `programador-adaptador.md` para los adaptadores y Studio, en la misma rama.
- **Entrega:** sus informes, con mediciones **hechas con comandos y en Studio**.

## Contexto
- **Leer:**
  - `docs/disenos/hitbox-y-dano.md` entero, con los resultados de `exp/hitbox`;
  - `src/vehicle/core/damage/`;
  - `src/vehicle/core/VehicleModels.luau`;
  - `src/vehicle/server/VehicleModelBuilder.luau` y `VehicleVisualModel.luau`;
  - el informe `investigacion-hitbox-automatica.md`, que se copia a `docs/investigaciones/` en este WP.
- **De dónde salen las cajas (investigación del 2026-10-17):**
  - Las piezas del modelo no están rotadas, así que el tamaño y la posición de cada malla ya dan su caja exacta.
  - Si una pieza de daño tiene malla propia, su caja sale de esa malla.
  - El Chasis es una sola malla que envuelve todo y no sirve como caja de daño.
  - Las piezas sin malla propia (guardabarros, zócalos, vidrios y espejos sueltos) no tienen caja en este WP: las agrega el editor (WP-19) o una malla nueva que haga Nico en Blockbench.

**Dónde trabaja:** rama `a/hitbox-adaptadores`, en el worktree `C:\Users\Nico\Documents\Rally-wp18`.

## Entregables

### Núcleo (datos y cuenta pura)
1. **`VehicleModels`:** la ficha del 147 suma `damageMeshes`, que dice qué mallas forman cada pieza de daño.
   - Ejemplo: `hood = { "Capot", "Capot2" }`.
   - Las mallas que traen dos piezas se parten por la mitad en x (`side = "left"` / `"right"`).
2. **`src/vehicle/core/damage/HitboxLayout.luau`:** a partir de las cajas de las mallas (tamaño y posición en el marco del modelo) y de la colocación del modelo (`ModelPlacement`), devuelve `{ pieceId, offset en el marco del Body, size }` por pieza.
   - Une las cajas de varias mallas de una misma pieza.
   - Parte por la mitad las mallas compartidas.
   - Aplica un espesor mínimo de `HITBOX_MIN_THICKNESS` (0,2): la parrilla mide 0,06.
3. **`src/vehicle/core/damage/Fiat147Hitbox.luau`:** los datos generados, tamaño y posición de cada malla, con el script que los produjo comentado arriba. Son datos, no se calculan en el juego, porque leer mallas en el juego no está garantizado.
4. **Pruebas:**
   - cada `pieceId` existe en `DamageConfig`;
   - ninguna caja tiene tamaño 0 ni valores NaN;
   - las mitades no se superponen;
   - el espesor mínimo se respeta;
   - la unión de las cajas de una pieza contiene las cajas de sus mallas.

### Adaptadores
5. **`HitboxBuilder` (servidor):**
   - crea una `Part` por pieza, con `Massless`, `CanCollide` en true, `CanQuery` y `CanTouch` en false, invisible y soldada al `Body`;
   - todas van en el grupo de colisión `VehicleHitbox`: no chocan entre sí ni con el auto, y los rayos de las ruedas las ignoran;
   - verifica que la masa y el centro de masa no cambien;
   - el `Body` y las ruedas físicas dejan de chocar con el mundo solo si hace falta, y se mide en Studio.
6. **`CollisionReader` (cliente, dueño de red):**
   - `BindToCollisionSummaries` en cada caja;
   - convierte cada resumen en `(pieceId, impactSpeed)`, con la velocidad normal relativa;
   - ignora el piso: los golpes por debajo del umbral de la ficha y los de la cara de abajo contra el terreno a menos de `GROUND_IMPACT_SPEED`;
   - un mismo par de partes cuenta una vez cada `HIT_COOLDOWN_SECONDS`.
7. **`DamageController` (cliente):**
   - guarda el `DamageState`;
   - aplica `DamageModel.applyImpact`;
   - pasa `DamageEffects.apply` al simulador como su configuración;
   - emite los eventos.
8. **`DamageVisuals` (cliente):**
   - con el evento `detached`, oculta las mallas de la pieza (`LocalTransparencyModifier`) y suelta un clon visual sin colisión durante 0,2 s y apartado del auto (P1);
   - los clones se borran a los `DEBRIS_LIFETIME_SECONDS` o cuando se acumulan más de `DEBRIS_MAX`;
   - las texturas por estado (T1) quedan con un punto de extensión vacío hasta que Nico haga las texturas.
9. **`DamageReporter`:** manda el estado al servidor con un `RemoteEvent` limitado a 1 cada 2 s. El servidor valida los rangos y solo lo registra.
10. **Reset:** al volver a crear el auto, el daño vuelve a 0.

## Pruebas en Studio
- **Peso:** la masa y el centro de masa no cambian con la hitbox puesta.
- **Manejo:** igual que antes. El auto quieto no vibra a 60 y 30 FPS.
- **Golpe de frente contra un poste a 30, 60 y 120 studs/s:**
  - golpea la caja correcta;
  - el daño sigue la fórmula;
  - a 120 la parrilla o el paragolpes se caen, y el radiador y el motor reciben lo que les toca;
  - el auto pierde potencia.
- **Golpe de costado:** puerta, guardabarros si tiene caja, y la dirección tira para ese lado.
- **Rueda:** si se cae, el agarre de esa rueda baja a 0.
- **Piso y ripio:** andar 60 s sin chocar no deja daño.
- **Rendimiento:** costo por cuadro de las suscripciones y FPS con y sin hitbox.

## Fuera de alcance
- El plugin editor y el generador automático de cajas para cualquier auto: WP-19.
- Las texturas de daño: las hace Nico.
- La reparación y el desgaste en el juego: después del MVP.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos**.
- [ ] Nico lo prueba chocando.
