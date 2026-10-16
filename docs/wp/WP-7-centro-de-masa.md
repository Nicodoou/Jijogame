# WP-7 — Centro de masa real y lastre por configuración

**Issue:** #7 (modelo de física). Prepara #48 (modelo del auto).
**Requerimientos:** CP-2 y CP-6.
**Diseño:** `docs/disenos/auto.md`, sección "Centro de masa y modelo del auto" (aprobada en el PR #47)
**Responsable:** Agente A
**Depende de:** el código del WP-4 (PR #52) en `main`. **No se empieza antes.**

## Subagentes
Son dos, uno por capa, en orden:
1. **Núcleo:** `.claude/agents/programador-nucleo.md` (Sonnet), entregables 1 a 5.
2. **Adaptadores:** `.claude/agents/programador-adaptador.md` (Sonnet), entregables 6 y 7, con el núcleo ya terminado en la misma rama.

- **Herramientas:** las de cada definición. Studio, solo en el Baseplate de prueba que indique el orquestador.
- **Entrega:** el informe de cada definición, con la salida de `scripts/check-all.sh`.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/auto.md`, secciones "Arquitectura" y "Centro de masa y modelo del auto";
  - `docs/wp/WP-3-nucleos-conduccion.md`, secciones "Convenciones" y "Entregables";
  - `docs/wp/WP-4-auto-manejable.md`;
  - `src/vehicle/core/` (sobre todo `VehicleTypes`, `WheelForces`, `Suspension` y `VehicleSimulator`);
  - `src/vehicle/client/VehicleController.luau` y `src/vehicle/server/VehicleModelBuilder.luau`;
  - `tests/vehicle/ToyWorld.luau`;
  - `docs/reglas-de-trabajo.md` (secciones 3 a 5).
- **Decisiones que aplican:** "Auto: modelo visual sin masa y centro de masa por configuración" y las de política de código (`docs/decisiones.md`).
- **Supuestos vigentes:**
  - Roblox calcula el centro de masa (`AssemblyCenterOfMass`) y la inercia de un ensamble a partir de la masa de sus piezas. Las piezas con `Massless = true` no cuentan.
  - `AssemblyLinearVelocity` es la velocidad del centro de masa.
  - La masa de una pieza es su densidad (`CustomPhysicalProperties`) por su volumen.
- **El problema que resuelve:**
  - Hoy `ChassisSample.position` es el centro de masa, pero las posiciones de las ruedas (`VehicleConfig.WHEELS`) están escritas respecto del **centro del `Body`**. El núcleo calcula el brazo de cada rueda desde `position`.
  - Funciona solo porque el auto de cajas es simétrico y el centro de masa cae en el centro de la caja.
  - Con el lastre, el centro de masa se corre, y la velocidad de cada rueda (`v + ω × r`) sale mal.
- **De la conversación con Nico:** quiere poder meter cualquier modelo sin que cambie el manejo, y ajustar el reparto de peso como un valor más. El centro de masa **no** se mueve al doblar: el traspaso de carga ya sale de la suspensión.
- **Contratos:** ninguno.

**Dónde trabaja:** rama `a/7-centro-de-masa-codigo`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp7`.

## Objetivo

Que el núcleo use siempre el centro de masa real para los brazos de las ruedas y las cargas estáticas, y que el reparto de peso y la altura del centro de masa se ajusten desde `VehicleConfig` con un lastre invisible.

## Entregables

### Núcleo (`src/vehicle/core/`)

1. **`ChassisSample.origin: vector`** (campo nuevo): el origen del marco de las ruedas en el mundo, o sea la posición del `Body`. `position` sigue siendo el centro de masa.
2. **Brazo de cada rueda:** `r = (origin + mountOffset(wheel)) − position`, en lugar de `mountOffset(wheel)`. Se usa para la velocidad del montaje y para todo lo que hoy usa `offsets`.
3. **Carga estática por rueda según el centro de masa:**
   - **Reparto por eje:** sale de la posición local del centro de masa. Sobre el eje del chasis, `fracciónDelantera = (zTrasero − zCM) / (zTrasero − zDelantero)`, con `z` locales.
   - **Reparto por lado:** igual, con `x`.
   - **Carga estática de cada rueda:** `masa · g · fracciónDeSuEje · fracciónDeSuLado`.
   - **Resorte y amortiguación de cada rueda:** se calculan con su propia masa suspendida (`cargaEstática / g`). Así el auto queda nivelado en reposo con cualquier reparto.
   - **Si el centro de masa cae fuera de las ruedas** (fracción < 0,05 o > 0,95), se recorta a ese rango.
   - **Si `origin` no es finito,** se usa `position`, o sea el comportamiento de hoy.
4. **`VehicleConfig`:**
   - `FRONT_WEIGHT_FRACTION` = 0,5;
   - `CENTER_OF_MASS_HEIGHT_STUDS` = 1, medido desde el plano de montaje de las ruedas (y = −1 local), así que queda en el centro del `Body` como hoy;
   - `BALLAST_MASS_FRACTION` = 0,5, la parte de la masa total que lleva el lastre.
   - **El núcleo no los usa:** son para el adaptador. Van acá porque `VehicleConfig` es el único lugar de los valores de ajuste (CP-6).
5. **`ToyWorld` (pruebas):** acepta un desplazamiento del centro de masa respecto del origen de las ruedas e integra el cuerpo alrededor del centro de masa.

### Adaptadores

6. **`VehicleModelBuilder` (servidor):**
   - Agrega una pieza `Ballast` invisible (`Transparency = 1`, `CanCollide = false`, `CanQuery = false` y `CanTouch = false`), soldada al `Body`.
   - **Su masa:** `BALLAST_MASS_FRACTION` del total, con el `Body` llevando el resto. Se ajusta con la densidad de cada pieza.
   - **Su tamaño es el del `Body` (6 × 2 × 10, de la misma constante).** El lastre no puede reducir la inercia de giro del conjunto: una pieza chica suma masa pero casi nada de inercia (483 medida en Studio contra 952 de la caja entera), y con esa mitad el giro a baja velocidad es inestable (bug `docs/bugs/2026-10-16-vibracion-reposo.md`; límite medido en `ToyWorld`: fracción de inercia mínima estable ≈ 0,71).
   - **Su posición local** pone el centro de masa del ensamble en:
     - `zCM = zTrasero − FRONT_WEIGHT_FRACTION · (zTrasero − zDelantero)`;
     - `yCM = −1 + CENTER_OF_MASS_HEIGHT_STUDS`;
     - `xCM = 0`.

     Despejando, `posiciónLastre = cmObjetivo · (masaBody + masaLastre) / masaLastre`, porque el `Body` tiene su masa en su centro.
   - **Todas las demás piezas del modelo** (ruedas y, más adelante, el modelo visual de #48) van con `Massless = true`. El constructor tiene una función que marca así cualquier modelo visual que se le pase.
   - **Un cambio de estos valores se aplica al aparecer el auto:**
     - el lastre lo arma el servidor, así que los `Cfg_` del cliente no lo mueven;
     - para probar en Studio: poner el atributo en `Workspace` desde la vista del **servidor** y reaparecer;
     - `TuningOverrides` se amplía para leer también en el servidor, solo en Studio.
7. **`VehicleController` (cliente):** arma `ChassisSample.origin` con `body.Position`.

## Pruebas
- **Núcleo, unitarias:**
  - Con `origin ≠ position`, una rotación pura alrededor del centro de masa da en cada rueda `ω × (montaje − centroDeMasa)`, no `ω × montaje`.
  - Las cargas estáticas suman `masa · g` y respetan el reparto por eje.
  - Con `origin` NaN se usa `position`.
- **Propiedades con `ToyWorld`:**
  - **Reposo con el centro de masa corrido:**
    - 0,15 studs hacia adelante y 0,3 hacia abajo;
    - asienta en menos de 2 s, con un cabeceo menor a 1° y la deriva y la velocidad como en la propiedad 1;
    - las ruedas delanteras cargan más que las traseras, en la proporción esperada ± 5%.
  - **Ninguna de las 16 propiedades del WP-3 cambia** con el centro de masa centrado: es el caso de hoy.
- **Studio** (subagente de adaptadores, en el Baseplate de prueba):
  - Con `FRONT_WEIGHT_FRACTION` 0,5, 0,6 y 0,4, el auto asienta nivelado (cabeceo < 1°), quieto 10 s sin moverse, a 60 y a 30 FPS.
  - `AssemblyCenterOfMass` queda a ± 0,05 studs del objetivo.
  - Acelerar y frenar como en el WP-4, sin divergencias.

## Fuera de alcance
- El modelo visual del auto (#48): este WP deja lista la función que lo marca sin masa.
- La barra estabilizadora (`ANTI_ROLL`).
- Cambiar otros valores de manejo.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Las pruebas de arriba pasan, y las 16 propiedades del WP-3 siguen pasando.
- [ ] En Studio, el centro de masa queda donde dice la configuración y el auto asienta nivelado con los tres repartos.
- [ ] Sin números mágicos; archivos ≤ 200 líneas y funciones ≤ 30.

## Pruebas manuales
- [ ] (Nico) Manejar con `FRONT_WEIGHT_FRACTION` 0,4 y 0,6, y con `CENTER_OF_MASS_HEIGHT_STUDS` 0,5 y 1,5, y contar cómo cambia: más atrás, la cola debería soltarse más fácil; más alto, el auto debería inclinarse más.
