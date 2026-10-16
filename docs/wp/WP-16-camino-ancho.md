# WP-16 — Camino más ancho: de 16 a 20 studs

**Issue:** #88
**Requerimientos:** RC-5 (nunca una curva imposible a velocidad razonable), RC-7 (la ruta tiene un ancho fijo para el MVP) y CP-3.
**Diseño:** `docs/disenos/ruta.md` (revisión versión 2) y `docs/disenos/terreno.md`. Este WP cambia un valor de la ruta y la distancia mínima que depende de él.
**Responsable:** Agente B
**Depende de:** WP-5, WP-6, WP-9 y WP-11, todos en `main`.

## Por qué
Nico pidió calles más anchas. El camino mide 16 studs y el auto unos 6, así que con el auto en el centro quedan unos 5 studs por lado. En las U, a velocidad, se siente angosto.

**Beni decidió (2026-10-16): 20 studs.** Quedan unos 7 studs por lado, sigue siendo un camino de rally de montaña y deja más margen para derrapar.

## Qué cambia
- **`ROAD_WIDTH_STUDS`:** de 16 a 20. La banquina sigue en 4 studs por lado.
- **`LIVE_NEAR_CLEARANCE_STUDS`:** de 30 a 34. Es la distancia mínima entre dos pasadas de la ruta cuyo arcLength difiere entre 400 y 1.200 studs. Tiene que ser mayor que el ancho más las dos banquinas (hoy 16 + 8 = 24, contra 30; con 20 + 8 = 28, contra 34). Así se mantiene el mismo margen de 6 studs entre banquinas.
- **`LIVE_CLEARANCE_STUDS` (60):** no cambia, porque ya sobra.
- **La regla de altura entre pasadas** ya usa el ancho y las banquinas, así que se ajusta sola.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md`.
- **Modelo:** Sonnet.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, en los 8 puntos de `docs/reglas-de-trabajo.md`.

## Contexto para el subagente
- **Leer:**
  - `docs/disenos/ruta.md` y `docs/disenos/terreno.md`;
  - `docs/wp/WP-5-ruta-rally.md`, `docs/wp/WP-9-ruta-ajustes.md` y `docs/wp/WP-11-camino-de-ripio.md`;
  - `docs/reglas-de-trabajo.md`;
  - `src/world/core/WorldConfig.luau` y todo lo que use `ROAD_WIDTH_STUDS` o `LIVE_NEAR_CLEARANCE_STUDS` (con `grep`);
  - las pruebas de `tests/world/`.
- **Supuestos vigentes:**
  - el auto mide unos 6 studs de ancho;
  - la superficie del contrato (`GetSurfaceAt`) da `Road` hasta la mitad del ancho y `Shoulder` en los 4 studs siguientes;
  - el terreno pinta el camino hasta la mitad del ancho (WP-11).

## Entregables
1. **`WorldConfig`:** `ROAD_WIDTH_STUDS = 20` y `LIVE_NEAR_CLEARANCE_STUDS = 34`, con el comentario que explica la relación con el ancho y las banquinas. Si hay otro valor derivado del ancho escrito a mano, que salga de la constante.
2. **Pruebas:**
   - una prueba de config que verifique `LIVE_NEAR_CLEARANCE_STUDS > ROAD_WIDTH_STUDS + 2 · SHOULDER_WIDTH_STUDS`;
   - ajustar las pruebas que tenían 16 o un número derivado escrito a mano (por ejemplo, los conteos exactos de columnas del WP-11: con vóxeles de 4 studs, el camino pasa de 4 a 5 columnas);
   - el hash de 20 tramos con la semilla 12345 cambia: informalo.
3. **Corrida de 200 × 400 del WP-9** (`tests/world/long/RoadLongRun.luau`): encierros, violaciones del anti-cruce y de la regla de altura, y métricas de rally contra los umbrales del WP-5. Compará con `main`. Los encierros raros son el bug #86, que ya existía: informalos aparte, sin intentar arreglarlos acá.
4. **Docs:**
   - `ruta.md` y `terreno.md` con el ancho nuevo donde lo mencionen;
   - la decisión en `docs/decisiones.md` (decidió Beni, pedido de Nico, issue #88; descartado: 24 studs y dejar 16).

## Fuera de alcance
- El bug de encierro (#86).
- El borde y la largada (WP-12, en pausa).
- La banquina, que sigue en 4 studs.
- Contratos, adaptadores, `src/app/` y `src/vehicle/`.

## Criterios de aceptación
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] En la corrida de 200 × 400: 0 violaciones del anti-cruce y de la regla de altura, y métricas de rally dentro de los umbrales del WP-5. Si hay encierros, se informan comparados con `main` (#86).
- [ ] El tiempo de CI de `check-all` no sube de forma apreciable.

## Pruebas manuales
- [ ] (Beni o Nico) En Studio, manejar y ver que el camino de 20 se siente cómodo pero sigue siendo de rally, sobre todo en las U.
