# WP-9 — Ruta: regla de altura entre pasadas, generación por pasos y lomas sin repetición

**Issues:** #57 (lomas que se repiten) y #10 (lo que encontró el núcleo del terreno)
**Requerimientos:** RC-4, RC-6, la tabla de rendimiento (sin tirones) y la sesión de 30 minutos sin repetición visible
**Diseño:** `docs/disenos/ruta.md` (revisión versión 2) y `docs/disenos/terreno.md`
**Responsable:** Agente B
**Depende de:** WP-5 (en `main`). Va **antes** de mergear el WP-6, que lo consume (rama `b/10-wp-6-terreno-impl`, ya pusheada).

## Por qué

Al implementar el núcleo del terreno (WP-6) aparecieron dos problemas de la ruta. Más el #57, son tres:

1. **Paredes entre pasadas muy cercanas.**
   - La regla anti-cruce deja pasadas a 30 studs (`LIVE_NEAR_CLEARANCE_STUDS`) si el `arcLength` difiere entre 400 y 1.200, y a 60 si difiere más.
   - Entre dos banquinas a 30 studs de eje quedan unos 6 studs, y nada impide que una pasada esté 30 a 50 studs más alta que la otra. Ahí el terreno no puede bajar y queda un talud casi vertical.
   - En 40 semillas aparece un sitio con otra pasada a menos de 60 studs cada ~7.700 studs de ruta, y en el 37 % de esos sitios la pendiente supera los 62°.
   - **Beni decidió (2026-10-16):** una regla de altura en el anti-cruce, la única que lo garantiza.
2. **Tirones al generar.** `RoadPath.generateNextSegment` tarda en promedio ~1 ms, pero tiene picos de 8 a 11 ms en el CLI (secuenciador, previsualización y retroceso de la guía). Eso rompe el presupuesto por frame una vez cada ~5 s de manejo. **Beni decidió:** partir la generación en pasos.
3. **#57:** el perfil de lomas se repite exacto cada 51.200 studs (período 256 de `math.noise` × longitud de onda de 200). A 100 studs/s son ~8,5 min. **Beni decidió:** arreglarlo acá, siguiendo `docs/resolucion-de-bugs.md` (replicar con una prueba, causa y arreglo).

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md`
- **Modelo:** Sonnet.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, con la corrida completa de 200 × 400 y los tiempos.

## Contexto para el subagente
- **Leer:**
  - `docs/disenos/ruta.md` (sobre todo la revisión versión 2);
  - `docs/wp/WP-5-ruta-rally.md`;
  - `docs/resolucion-de-bugs.md`;
  - `docs/reglas-de-trabajo.md`;
  - el código de `src/world/core/` (ruta del WP-5: `RoadPath`, `RoadPieceSequencer`, `RoadPiecePreview`, `LiveRoadIndex`, `RoadGuide`, `HillProfile` y `WorldConfig`) y `tests/world/`;
  - de la rama `b/10-wp-6-terreno-impl`, `TerrainHeightField` y `WorldPlanner`, solo para ver cómo los usa el terreno (`git show origin/b/10-wp-6-terreno-impl:<ruta>`).
- **Decisiones que aplican:** las de la ruta de rally y la de este WP (va en `docs/decisiones.md` en este mismo PR).
- **Supuestos vigentes:** `math.noise` tiene período 256 y da lo mismo en el CLI y en Studio. El terreno acepta una pendiente máxima de `TERRAIN_MAX_SLOPE_DEGREES` (62°) entre pasadas, y la banquina mide 4 studs.

## Entregables (todo en `src/world/core/` y `tests/world/`)

1. **Regla de altura en el anti-cruce (`LiveRoadIndex` y `RoadPiecePreview`):** al aceptar una pieza, cada muestra que quede a menos de `LIVE_HEIGHT_RULE_RADIUS_STUDS` (en el plano) de una muestra viva no vecina se **rechaza** si `|Δy| > tan(TERRAIN_MAX_SLOPE_DEGREES) · max(0, distancia − ROAD_WIDTH − 2·SHOULDER_WIDTH)`, con un margen.
   - "Vecina" se define como hoy.
   - El radio cubre las pasadas que ve el terreno (por ejemplo, 192 studs, igual que `TERRAIN_ROAD_REACH_STUDS` del WP-6).
   - El valor de `TERRAIN_MAX_SLOPE_DEGREES` se trae a `WorldConfig` si todavía no está en `main`.
2. **Generación por pasos (`RoadPath`):** un método nuevo, por ejemplo `generateStep(): Segment?`, que avanza la generación en pasos acotados (como mucho una pieza, una alternativa o un retroceso por llamada) y devuelve el tramo cuando se completa. `generateNextSegment` sigue existiendo (llama a `generateStep` hasta tener el tramo) y su resultado no cambia: **misma semilla, mismo hash**.
   - El costo de cada paso tiene que ser chico: medí el peor paso sobre 200 semillas e informalo. Objetivo: < 2 ms en el CLI de esta PC.
3. **Lomas sin repetición (#57), siguiendo el proceso de bugs:**
   - Primero, una prueba que **replique** el bug: el perfil en `s` y en `s + 51.200` hoy coincide.
   - Después, el arreglo: que la entrada del ruido no crezca en un solo eje. Por ejemplo, recorrer un círculo grande en el plano (x, y) del ruido con un radio tal que la vuelta completa dure mucho más que 30 minutos, o sumar un segundo eje que avance despacio.
   - Al final, la prueba pasa: no hay repetición en, por lo menos, `30 min × 150 studs/s` = 270.000 studs.
   - Las métricas de lomas (pendiente > 10° y largo de las subidas) siguen dentro de los umbrales del WP-5.
4. **Pruebas:**
   - la propiedad de altura entre pasadas sobre 40 semillas (CI) y 200 (a mano): 0 violaciones, sin encierros nuevos;
   - el hash de la ruta se informa (cambia por el #57 y la regla de altura);
   - `generateStep` da el mismo resultado que `generateNextSegment`.
5. **`docs/decisiones.md`:** la regla de altura y la generación por pasos (decidió Beni). **`docs/disenos/ruta.md`:** una nota corta en la revisión versión 2.

## Fuera de alcance
- El terreno (WP-6), salvo leerlo.
- Cambiar otras métricas de rally o los valores de la guía.
- Contratos.

## Criterios de aceptación
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] 200 × 400: 0 encierros, 0 violaciones del anti-cruce y 0 violaciones de la regla de altura, con las métricas de rally dentro de los umbrales del WP-5.
- [ ] El peor paso de `generateStep` está por debajo de 2 ms en el CLI (o se informa con números si no se llega).
- [ ] La prueba del #57 replica el bug antes del arreglo y pasa después.
- [ ] El tiempo de CI de `test.sh` queda por debajo de 60 s.

## Pruebas manuales
- [ ] (Beni) Recorrer la ruta con la vista previa o con el auto, cuando esté el terreno, para ver que las U siguen sintiéndose igual de apretadas.
