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
