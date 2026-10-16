# WP-13 — El 147 como modelo del auto

**Issue:** #48 (modelo del auto)
**Requerimientos:** CP-2, CP-6 (geometría y peso por configuración). Base para el WP-14 (primera persona) y para la hitbox.
**Diseño:** `docs/disenos/auto.md`, sección "Centro de masa y modelo del auto". Decisión de Nico (2026-10-16): **la física usa la geometría del modelo**.
**Responsable:** Agente A
**Depende de:** que Nico guarde el modelo corregido como archivo en el repo (ver "Antes de empezar").

## Antes de empezar (Nico)
Guardar `Workspace.147_corregido` desde Studio: clic derecho → **Save to File…** → `C:\Users\Nico\Documents\Rally\assets\vehicles\Fiat147.rbxm`. El orquestador lo commitea.

## Subagente
- **Nombre:** `.claude/agents/programador-adaptador.md` (Sonnet). Para el núcleo (entregable 1) usa las reglas del núcleo: puro y con pruebas en el CLI.
- **Entrega:** el informe de su definición, con mediciones **hechas con comandos** (líneas, funciones públicas y cobertura) y las pruebas en Studio con números.

## Contexto para el subagente

- **Leer:**
  - `docs/disenos/auto.md` ("Centro de masa y modelo del auto");
  - `docs/wp/WP-7-centro-de-masa.md`;
  - `src/vehicle/server/VehicleModelBuilder.luau`, `VehicleSpawner.luau`;
  - `src/vehicle/client/*`;
  - `src/vehicle/core/VehicleConfig.luau`;
  - `docs/reglas-de-trabajo.md`.
- **Lo que ya se probó en Studio (scripts temporales del orquestador, que este WP reemplaza):**
  - **Import de Blockbench:** el modelo importado de Blockbench viene como un rig. Studio pone cada pieza en `raíz · C0 · C1⁻¹`, pero la posición correcta es `raíz · (2·C0 − C1)`, porque el importador resta el pivote en vez de sumarlo. Las submallas de un grupo (con C1 = 0) van en `centroDelGrupo + C0 − (C0_grupo − C1_grupo)`.
  - **El archivo `Fiat147.rbxm`** ya trae las piezas corregidas, ancladas, con el `WorldPivot` en el origen del modelo.
  - **Orientación:** el modelo mira a **+z**. Hay que girarlo 180° para que mire a −z, como el auto, y con el giro el lado L del modelo queda a la izquierda.
  - **Geometría medida:**
    - ruedas en x = ±2,34, z = −2,88 adelante y +3,06 atrás (después del giro), con radio 0,81;
    - la parte de abajo de las ruedas está a y = 1,22 del pivote.
  - **Ruedas delanteras:** `LF` y `RF`, cada una una malla.
  - **Eje trasero rígido:** `Rear Wheels` y `Rear Wheels2` son el eje con las dos ruedas y la barra. Se mueve **como una sola pieza** entre las dos ruedas físicas traseras: se inclina si una sube más que la otra y gira con las ruedas.
- **Decisiones que aplican:**
  - "Auto: modelo visual sin masa y centro de masa por configuración";
  - "Auto: tracción delantera, peso adelante…";
  - las de política de código.
- **Contratos:** ninguno.

**Dónde trabaja:** rama `a/48-modelo-147`, desde `main`, en el worktree `C:\Users\Nico\Documents\Rally-wp13`. Studio: "Experiencia sin título", nunca otro lugar.

## Objetivo
Que el auto del juego sea el 147: el modelo visual, la geometría física que sale del modelo y el eje trasero rígido visual. Además, una herramienta para corregir futuras importaciones de Blockbench.

## Entregables

1. **Ficha del modelo (núcleo, datos):** `src/vehicle/core/VehicleModels.luau` con la ficha `Fiat147`:
   - nombre del archivo;
   - giro;
   - `modelGroundY`;
   - mallas de rueda delantera (`LF` → FL y `RF` → FR);
   - mallas del eje rígido trasero;
   - posición de la cabeza del conductor (para el WP-14, en el marco del modelo; valor inicial: el asiento del conductor más 1,3 studs hacia arriba).

   La ficha es datos. Un test valida que las mallas nombradas existan en una lista declarada y que las ruedas coincidan con `VehicleConfig.WHEELS` (± 0,05).
2. **Geometría física del 147 en `VehicleConfig`:**
   - `WHEELS`: x = ±2,34, z = −2,88 y +3,06, con el mismo y de montaje;
   - `WHEEL_RADIUS_STUDS` = 0,81;
   - `FINAL_DRIVE` = 4,0, para compensar el radio menor y mantener la relación entre velocidad y RPM;
   - **las propiedades que cambien se reportan con números, sin relajarlas.**
3. **Mapeo de Rojo:** `assets/vehicles` → `ReplicatedStorage.vehicle.models` (solo los `.rbxm`).
4. **`VehicleModelBuilder` (servidor):** clona el modelo de la ficha y lo ubica con el giro y la altura del piso, calculada como en el núcleo (resorte en reposo).
   - Le aplica `markMassless`.
   - **Suelda** cada pieza al `Body`, salvo las ruedas delanteras, que se sueldan a su rueda física, y el eje trasero, que queda **anclado** y con un atributo `RearAxleOffset`.
   - Las cajas grises (`Body` y ruedas) quedan invisibles (`Transparency` 1); el `Ballast` ya lo es.
5. **`RearAxleVisual` (cliente, `src/vehicle/client/`):**
   - **Cuándo corre:** en `PreRender`.
   - **Qué hace:** ubica el eje entre `WheelRL` y `WheelRR` y lo inclina con su diferencia de altura.
   - **El giro:** el de la rueda física trasera izquierda.
   - **Quién lo arma:** el arranque del cliente.
6. **Herramienta de corrección de imports de Blockbench:** `tools/blockbench/FixImport.luau`, para pegar en la barra de comandos de Studio, fuera de `src/` y del juego.
   - Toma un modelo seleccionado y crea una copia corregida con la regla de arriba.
   - Avisa las piezas sin grupo.
   - Documentada en `docs/guia-de-desarrollo.md` ("Importar un auto de Blockbench").

## Pruebas
- **Núcleo:** la ficha y su validación. Con la geometría nueva, **todas las propiedades del manejo** siguen pasando, o se reporta cuáles no, con números.
- **Studio (subagente):**
  - el auto aparece con el 147, apoya en el piso (la parte de abajo de las ruedas a ± 0,1 del suelo plano) y no queda nada gris a la vista;
  - el eje trasero queda centrado entre las ruedas, con un error menor a 0,05;
  - quieto 10 s sin moverse, a 60 y a 30 FPS;
  - acelera, frena y dobla sin divergir;
  - `AssemblyMass` y el centro de masa iguales que sin el modelo.
- **Nico:** manejarlo, mirar el eje trasero en los pozos y probar la herramienta con un import nuevo.

## Fuera de alcance
- La primera persona (WP-14) y la hitbox (sus WPs).
- El eje rígido en la **física** (hoy la suspensión trasera es independiente). Si hace falta, va en otro WP.
- Las luces que se prenden: hoy son solo mallas.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Las pruebas en Studio de arriba pasan, con números.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas por módulo, **medido con comandos**.
- [ ] Los scripts temporales `PruebaModelo147` y `PruebaEjeTrasero147` ya no hacen falta; Nico los borra.
