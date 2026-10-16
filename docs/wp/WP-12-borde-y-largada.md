# WP-12 — Borde natural del corredor y largada plana

**Issue:** #80
**Requerimientos:**
- RC-8: terreno transitable a ambos lados, lo bastante ancho para salirse y volver;
- RC-12: no caerse del mundo, aunque el reset de A lo cubra como último recurso;
- RC-6;
- la sesión de juego sin frustraciones.

**Diseño:** `docs/disenos/terreno.md` y `docs/disenos/ruta.md`. Este WP agrega una nota a cada uno.
**Responsable:** Agente B
**Depende de:** WP-6 y WP-9, ya en `main`. Es independiente del WP-11 (#75).

## Por qué
Probando en Studio aparecieron dos problemas (#80):
1. **Caerse del mundo.** El terreno solo se genera en un corredor de `TERRAIN_CORRIDOR_HALF_WIDTH_STUDS` (160) alrededor de la ruta viva, más 64 de margen. Si el auto se va derecho por el pasto, a unos 230 studs se termina el suelo y cae al vacío.
2. **Largada en bajada.** El auto aparece a `SPAWN_ARC_LENGTH_STUDS` (16) del inicio, donde la ruta ya baja unos 13°. Sin input, rueda y se sale. Que el auto se quede quieto en pendiente es de A; de nuestro lado, la largada puede ser plana.

## Decisiones (las aprueba Beni con este WP)
1. **Borde natural:** más allá de cierta distancia de la ruta, el terreno sube en una loma empinada que el auto no puede trepar. Encierra la ruta en un valle ancho, sin paredes invisibles.
   - **Descartado:** generar terreno también alrededor del auto. Nunca se acaba el suelo, pero se puede manejar sin límite lejos de la ruta y cuesta más generar. Queda como alternativa si el borde no gusta.
   - **Descartado:** solo el reset de A (RC-12). Es el último recurso, no la primera defensa.
2. **Largada plana y recta:** los primeros `START_FLAT_STUDS` de la ruta van rectos y sin pendiente, y las lomas entran de a poco después.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md`.
- **Modelo:** Sonnet.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición, en los 8 puntos de `docs/reglas-de-trabajo.md`.

## Contexto para el subagente
- **Leer:**
  - `docs/disenos/terreno.md` y `docs/disenos/ruta.md` (revisión 2);
  - `docs/wp/WP-6-terreno.md` y `docs/wp/WP-9-ruta-ajustes.md`;
  - `docs/reglas-de-trabajo.md` y `docs/resolucion-de-bugs.md`;
  - el núcleo de `src/world/core/`, sobre todo `TerrainHeightField`, `TerrainHills`, `HillProfile`, `RoadGuide`, `RoadPieceSequencer`, `RoadPath`, `SpawnPoint` y `WorldConfig`;
  - `tests/world/`.
- **Supuestos vigentes:**
  - el terreno salva como mucho `TERRAIN_MAX_SLOPE_DEGREES` (62°);
  - según A, el auto no trepa más de unos 35° en pasto (agarre 0,7);
  - el corredor generado llega a 160 studs de la ruta viva, y el alcance de la ruta sobre la altura (`TERRAIN_ROAD_REACH_STUDS`) a 192.

## Entregables (todo en `src/world/core/` y `tests/world/`)
1. **Borde (`TerrainHeightField`):**
   - a la altura del terreno se le suma una loma de borde que depende de la distancia a la ruta viva más cercana (la misma distancia al eje que ya calcula):
     - 0 hasta `TERRAIN_BORDER_START_STUDS` (por ejemplo, 112);
     - sube hasta `TERRAIN_BORDER_HEIGHT_STUDS` (por ejemplo, 48) en `TERRAIN_BORDER_END_STUDS` (por ejemplo, 152);
     - sigue plana hasta el borde del corredor.
   - **Forma:** suave en el pie y en la cresta (por ejemplo, smoothstep), con una pendiente máxima de entre 45° y `TERRAIN_MAX_SLOPE_DEGREES`. El auto no tiene que poder treparla, pero tiene que verse natural.
   - **Entre dos pasadas cercanas:** la distancia es a la pasada más cercana, así que no aparece una loma entre las dos. No hay que tratarlo aparte.
   - El borde no cambia nada dentro de `TERRAIN_BORDER_START_STUDS`: la ruta, la banquina y el campo cercano quedan como hoy.
2. **Largada (`HillProfile`, `RoadGuide` o `RoadPieceSequencer`, lo que sea más simple):**
   - los primeros `START_FLAT_STUDS` (por ejemplo, 160) son una recta con pendiente 0, a la altura de `START_POSITION`;
   - después, la amplitud de las lomas sube de 0 a la completa en `START_HILL_FADE_STUDS` (por ejemplo, 200), sin escalones de pendiente (RC-4);
   - el anti-cruce, la regla de altura y el determinismo siguen valiendo. El hash de la ruta cambia: informalo.
3. **Pruebas:**
   - **borde:** la altura es exacta hasta el inicio, sube de forma monótona hasta el fin y queda plana después; la pendiente máxima está entre 45° y 62°; con dos pasadas a 100 studs no aparece loma entre ellas;
   - **largada:** de 0 a `START_FLAT_STUDS`, rumbo y altura constantes en 40 semillas; después, la pendiente cambia como mucho `HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP` por paso;
   - **la corrida de 200 × 400 del WP-9** sigue sin encierros ni violaciones, con las métricas de rally dentro de los umbrales.
4. **Docs:** `terreno.md` (borde) y `ruta.md` (largada), una nota corta cada uno, y la decisión en `docs/decisiones.md`.

## Fuera de alcance
- El reset (RC-12) y que el auto se quede quieto en pendiente: son de A.
- El decorado, que también ayudará a marcar el borde.
- Generar terreno alrededor del auto.

## Criterios de aceptación
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] Las pruebas del borde y de la largada pasan, y la corrida de 200 × 400 sigue sana.
- [ ] El tiempo de CI de `check-all` no sube de forma apreciable.

## Pruebas manuales
- [ ] (Beni o Nico) En Studio: salirse de la ruta y no poder pasar el borde manejando normal; que se vea como un valle y no como una pared.
- [ ] (Beni o Nico) El auto aparece en la largada plana y no rueda solo.
