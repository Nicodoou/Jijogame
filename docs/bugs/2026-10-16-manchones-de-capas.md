# Bug: manchones de tierra en el camino y en el pasto de las pendientes

**Issue:** #73
**Rama:** `b/73-wp-11-ripio-impl` (va dentro de la revisión 1 del WP-11, por decisión de Beni del 2026-10-16)
**Estado:** resuelto

## Por qué es un bug
Contradice el WP-11 (un camino que se distingue del terreno, de un solo material) y los diseños `terreno.md` y `biomas.md` (la superficie es `Grass` en el bosque). Ya estaba en el WP-6.

## Esperado y observado
- **Esperado:** el camino se ve de ripio parejo y el pasto de las lomas se ve verde.
- **Observado (Studio):** el camino sale con manchones de tierra, y el pasto de las lomas se ve como tierra.

## Condiciones mínimas
Una pendiente de más de unos pocos grados. En plano no pasa, porque el vóxel de la superficie está lleno.

## Cómo replicarlo
1. Armar un chunk sobre una rampa del camino al 20° (la pendiente máxima de la ruta) o sobre una loma de pasto a 45°.
2. Mirar los materiales de los vóxeles con ocupación hasta 8 studs bajo la superficie de cada columna.

**Frecuencia:** siempre (determinista).
**Prueba que lo reproduce:** `tests/world/TerrainLayers.test.luau`, pruebas "on a ramp the road columns have the road material down to the top layer, and the deep one below" y "on a grass hill the grass goes down to the top layer, whatever the slope and the direction". Con el código anterior fallan con `se esperaba "Limestone" y se obtuvo "Basalt"` y `se esperaba "Grass" y se obtuvo "Ground"`.

## Hipótesis
### H1 — el material de superficie va solo en el vóxel de arriba
- **Causa:** `VoxelChunkBuilder` ponía el material de superficie solo en el vóxel de la superficie y el profundo (`Ground`) en todos los de abajo. En pendiente la superficie sube a escalones de 4 studs (un vóxel); en cada escalón el vóxel de arriba queda casi vacío y Roblox dibuja el de abajo.
- **Predicción:** si el material de superficie ocupa también los vóxeles de abajo hasta 8 studs bajo la superficie, ningún vóxel con ocupación en esa franja tiene el material profundo y las pruebas pasan.
- **Evidencia:** los vóxeles con ocupación a 8 studs o menos bajo la superficie tenían el material profundo en las columnas inclinadas, y en las planas no.
- **Aprobada por:** Opus (el WP, revisión 1, ya la trae como causa y arreglo) y Beni (decisión del 2026-10-16).
- **Cambio probado:** `TERRAIN_TOP_LAYER_STUDS = 8` en `WorldConfig`; un vóxel lleva el material de superficie si su borde de arriba queda a menos de ese espesor bajo el relleno de su columna (`floor(relleno - capa)` es el primer vóxel de la capa); más abajo, el profundo.
- **Resultado:** confirmada. Las pruebas de la rampa y de la loma pasan.

## Causa y corrección
La capa de superficie era de un solo vóxel. Ahora es de `TERRAIN_TOP_LAYER_STUDS` (dos vóxeles): el material de superficie ocupa el vóxel de la superficie y los de abajo hasta esa profundidad, y más abajo va el profundo. En el mismo cambio la banquina deja de ser `Ground` y lleva el material del bioma (decisión de Beni, no es parte de la causa).

## Regresión
- [x] Suite completa
- [x] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas (Beni, en Studio: camino gris parejo y pasto verde en las lomas)
- [x] Rendimiento (solo cambia la elección de un material por vóxel; `test.sh` tarda 1 min 48 s antes y 1 min 51 s después)
- [x] Código de depuración borrado

## Qué aprendimos
Las pruebas del WP-6 miraban solo el vóxel de arriba de cada columna. El motor mezcla los materiales de vóxeles vecinos en pendiente, así que una prueba de material tiene que mirar también la franja de vóxeles bajo la superficie.
