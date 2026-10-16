# WP-11 — Camino de ripio claro: que la ruta se distinga del terreno

**Issue:** #73
**Requerimientos:** RC-6 (el terreno acompaña a la ruta) y la legibilidad del camino al manejar
**Diseño:** `docs/disenos/terreno.md` (opción T1, con la nota de materiales de este PR)
**Responsable:** Agente B
**Depende de:** WP-6 (PR #70). Se implementa sobre `main` después de mergearlo.

## Por qué
Al probar el WP-6, Beni vio que el camino casi no se distingue del resto:
- la ruta y la banquina son `Ground`, sin nada que marque el borde;
- el `Grass` de Roblox, en pendientes empinadas, se dibuja con textura de tierra, y alrededor de la ruta hay muchas lomas y taludes.

**Beni decidió (2026-10-16):** ripio claro (`Limestone`) en el camino y tierra (`Ground`) en la banquina.

## Subagente
- **Nombre:** `.claude/agents/programador-nucleo.md` para el núcleo. El adaptador es una línea (la tabla de materiales de `TerrainWriter`) y la hace el mismo subagente, porque no tiene lógica.
- **Modelo:** Sonnet.
- **Herramientas permitidas:** Bash, Read, Write, Edit, Glob y Grep. Sin red ni Studio.
- **Entrega:** el informe de su definición.

## Contexto para el subagente
- **Leer:**
  - `docs/disenos/terreno.md` (opción T1 y la nota de materiales);
  - `docs/wp/WP-6-terreno.md`;
  - `docs/reglas-de-trabajo.md`;
  - `src/world/core/VoxelChunkBuilder.luau`, `TerrainHeightField.luau`, `SurfaceClassifier.luau`, `BiomeCatalog.luau` y `WorldConfig.luau`;
  - `src/world/client/TerrainWriter.luau`;
  - sus pruebas en `tests/world/`.
- **Supuestos vigentes:** la ruta mide `ROAD_WIDTH_STUDS` (16) y cada banquina `SHOULDER_WIDTH_STUDS` (4). Los vóxeles son de 4 studs, así que la ruta ocupa unos 4 vóxeles de ancho y la banquina 1 de cada lado, con el borde serruchado (aceptado en el diseño).

## Entregables
1. **Material del camino (`VoxelChunkBuilder`):**
   - la columna cuyo centro queda a no más de `ROAD_WIDTH_STUDS / 2` del eje (en el plano, contra el punto de ruta viva más cercano) lleva en la superficie el material de ruta nuevo, `"Limestone"`;
   - la columna en la banquina (de `ROAD_WIDTH_STUDS / 2` a `ROAD_WIDTH_STUDS / 2 + SHOULDER_WIDTH_STUDS`) lleva `"Ground"`;
   - lo demás no cambia (pasto, barro y mezcla de biomas).
   - Si `TerrainHeightField.sampleColumn` no da la distancia al eje, se agrega como tercer valor de retorno, sin crear tablas por columna.
   - Los nombres de material van como constantes con nombre (por ejemplo en `WorldConfig` o arriba del módulo), no sueltos.
2. **Adaptador (`TerrainWriter`):** agregar `Limestone = Enum.Material.Limestone` a la tabla de materiales.
3. **Pruebas en el CLI:**
   - en un chunk con una recta conocida, las columnas del centro de la ruta llevan `Limestone`, las de la banquina `Ground` y las de afuera el material del bioma;
   - lo mismo en una curva cerrada (la U), donde la distancia al eje no es solo lateral;
   - `GetSurfaceAt` no cambia: las pruebas del clasificador siguen igual.
4. **`docs/disenos/terreno.md`:** queda la nota de materiales que trae este PR. Si la implementación cambia algo, se actualiza.

## Fuera de alcance
- La superficie del contrato (`GetSurfaceAt`) y el agarre del auto: no cambian.
- La malla visual de la ruta (opción T2), el decorado y el borde prolijo.
- Colores globales del Terrain (`SetMaterialColor`).

## Criterios de aceptación
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] Las pruebas de material del camino (recta y U) pasan.
- [ ] Las pruebas de `SurfaceClassifier` y del terreno del WP-6 siguen pasando sin cambios en lo que esperan.
- [ ] El tiempo de CI de `check-all` no sube de forma apreciable (hoy ~60 s).

## Pruebas manuales
- [ ] (Beni o Nico) En Studio, manejar y ver que el camino se distingue: franja clara con borde de tierra sobre el pasto, también en las lomas y en las U.

## Revisión 1 (2026-10-16, después de verlo en Studio)
Beni lo miró en Studio: el camino salió **blanco y con manchones** (blanco y gris alternados en las pendientes).

**Causa (bug de capas, ya estaba en el WP-6):** cada columna lleva el material de superficie solo en el vóxel de arriba; los de abajo son el material profundo (`Ground`). En pendiente la superficie sube a escalones de 4 studs, y en cada escalón el vóxel de arriba queda casi vacío y Roblox muestra el de abajo. Por eso asoman manchones de tierra en el camino, y por eso el pasto de las lomas se veía como tierra (la primera queja de #73).

**Beni decidió (2026-10-16):**
- **Camino de ripio gris:** se mantiene `Limestone`, pero oscurecido con `Terrain:SetMaterialColor` a un gris medio, que no contraste de más con el resto.
- **Una sola textura por columna:** el material de superficie va también en las capas de abajo hasta `TERRAIN_TOP_LAYER_STUDS` (8 studs, dos vóxeles), así ni el camino ni el pasto muestran la capa profunda en las pendientes. Más abajo sigue el material profundo del bioma.
- **Todo lo que no es camino, pasto:** la banquina deja de ser `Ground` y lleva el material del bioma (`Grass` o `LeafyGrass`). El barro (`Mud`) se conserva como está: manchones fuera de la banquina, visibles y reportados por `GetSurfaceAt`.
- Las rocas y los detalles van después como assets (WP del decorado).

### Entregables de la revisión
1. **`VoxelChunkBuilder`:** el material de superficie ocupa el vóxel de la superficie y los de abajo hasta `TERRAIN_TOP_LAYER_STUDS` (constante nueva en `WorldConfig`); más abajo, el profundo. La banquina usa el material del bioma (`picker.pickMaterial`), no `Ground`.
2. **Color del camino:** `WorldConfig.ROAD_COLOR_RGB` (tres enteros, gris medio; por ejemplo 128, 126, 120) y una línea en el adaptador que lo aplica con `Workspace.Terrain:SetMaterialColor(Enum.Material.Limestone, ...)` al crear `TerrainWriter`. Es un valor de ajuste: se calibra a ojo con Beni.
3. **Pruebas:**
   - en una rampa al 20° (la pendiente máxima de la ruta), ninguna columna del camino tiene `Ground` en los vóxeles con ocupación hasta 8 studs bajo la superficie;
   - lo mismo para el pasto en una loma de 45°;
   - la banquina lleva el material del bioma;
   - `GetSurfaceAt` y las pruebas de barro no cambian.
4. **Docs:** `terreno.md` y `biomas.md` con las capas y la banquina de pasto.

### Criterios de aceptación de la revisión
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] Las pruebas de capas (rampa del camino y loma de pasto) fallan con el código anterior y pasan con el nuevo.
- [ ] (Beni) En Studio el camino se ve gris y parejo, sin manchones, y el pasto verde también en las lomas.

## Revisión 2 (2026-10-16, después de la segunda prueba en Studio)
Beni lo vio otra vez: el ripio gris sigue viéndose **muy claro**, parece asfalto y "no se ve nada como rally". En cambio, la textura del barro (`Mud`) le funciona mejor para un camino de tierra.

**Beni decidió (2026-10-16):**
- **Camino de tierra oscura:** el camino pasa a usar el material `Mud`, pintado de **marrón oscuro** con `Terrain:SetMaterialColor` (`ROAD_COLOR_RGB`, a calibrar a ojo). Se deja de usar `Limestone`.
- **Sin manchones de barro por ahora:** el campo es solo pasto (`Grass` y `LeafyGrass`). Los manchones de barro del bosque se sacan del catálogo, pero se conservan su mecanismo y sus valores en `WorldConfig` para retomarlos más adelante (la idea de barro en bordes y curvas, #78). Qué material queda para el barro se decide después.
- **Se mantiene de la revisión 1:** una sola textura por columna (`TERRAIN_TOP_LAYER_STUDS`) y la banquina de pasto.
- **`GetSurfaceAt` sigue coherente con lo que se ve:** como el bosque ya no tiene manchones, fuera de la ruta da `Grass`. El contrato no cambia (`Mud` sigue existiendo como valor). El camino sigue siendo `Road`, aunque use el material `Mud` de Roblox: la superficie del contrato sale de los datos de la ruta, no del material.

### Entregables de la revisión 2
1. **`VoxelChunkBuilder`:** `ROAD_MATERIAL = "Mud"`.
2. **Color:** `ROAD_COLOR_RGB` pasa a un marrón oscuro (por ejemplo 86, 64, 44) y `TerrainWriter` lo aplica a `Enum.Material.Mud` en lugar de `Limestone`.
3. **`BiomeCatalog` (bosque):** sin manchones de barro (`patches` vacío). Los valores `MUD_*` de `WorldConfig` quedan, con un comentario de que se retoman con #78.
4. **Pruebas:** las del camino esperan `Mud`; las del campo, solo pasto; las de `SurfaceClassifier` del bosque, `Grass` fuera de la ruta. El mecanismo de manchones sigue probado con un catálogo de prueba que sí los tenga.
5. **Docs:** `terreno.md` y `biomas.md`.

### Criterios de aceptación de la revisión 2
- [ ] `check-all.sh` da "todo OK" y la cobertura es ≥ 87 %.
- [ ] (Beni) En Studio el camino se ve como tierra oscura de rally y el campo es todo pasto.
