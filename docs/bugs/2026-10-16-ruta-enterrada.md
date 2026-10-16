# Bug: la ruta queda enterrada bajo el terreno en Studio

**Issue:** sin issue (lo encontró Beni en Studio con el cliente real; va dentro del WP-6)
**Rama:** `b/10-wp-6-terreno-impl` (va dentro del WP-6, que todavía no está mergeado)
**Estado:** resuelto en el núcleo (pendiente de repetir la pasada en Studio)

## Por qué es un bug
Contradice RC-6 y el WP-6: el terreno sigue a la ruta, y sobre el eje y la banquina es plano a la altura del eje. Un tramo de ruta enterrado más de 30 studs no se puede manejar.

## Esperado y observado
- **Esperado:** al terminar de escribir los chunks alrededor del auto, la altura escrita sobre el eje de la ruta viva está a ±0,5 del eje.
- **Observado (Studio, semilla 393026859):** el auto se movió por script sobre el eje a 80 studs/s, con `world.step()` en Heartbeat. Un rayo desde 30 studs por encima del eje, cada 0,25 s, pegaba en el terreno entre -15 y +30 studs del eje (y a veces no pegaba: ruta enterrada más de 30 studs durante unos 150 studs), en los arcLength 48.438 a 48.626, 50.451 a 50.491, 52.258 a 52.505 y 53.150 a 53.193. Un minuto después seguía igual: no se corrige solo. Con la pantalla apagada (cuadros baratos) casi no pasaba (1 de 1.173 chequeos).

## Condiciones mínimas
- La semilla del reporte (393026859) alcanza, pero no hace falta ir a los 48.000 studs: el mismo bug aparece en los **2.140 a 2.700 studs** de esa semilla, donde la ruta da una vuelta sobre sí misma (la pasada del arcLength 2.300 queda a 72 studs de la del 2.790, y la del 2.584 a 150 de la del 1.344).
- Hace falta que el trabajo del mundo vaya **atrasado respecto del auto**. En el CLI se logra con un reloj falso que cuesta 1 ms por paso del planificador y el presupuesto real de 4 ms por cuadro: unos 4 pasos por cuadro.
- No depende de la velocidad: aparece a 80 y a 150 studs/s. Con 0,25 ms por paso (mucho trabajo por cuadro) no aparece.

## Cómo replicarlo
1. `tests/world/TerrainDrive.luau`: `WorldPlanner` real con el armador de chunks real y un sumidero falso que guarda la altura escrita de cada columna; un auto que avanza por el eje de `RoadPath.new(seed)` (la ruta de referencia, entera); `WorkBudget` con un reloj falso.
2. Cada 15 cuadros se mide, en 400 studs de eje alrededor del auto, la altura escrita en el vóxel que contiene cada punto contra la altura del eje en ese lugar.
3. `luau tests/world/TerrainFollowsRoad.test.luau` (semilla 393026859, 150 studs/s, 1 ms por paso, 2.400 studs). Antes del arreglo: 155 de 3.252 puntos listos mal, el primero con el auto en 2.137 y el eje en 2.405 (-11,8 studs). A 80 studs/s y 1 ms por paso, a los 3.000 studs: 543 de 7.623.

**Frecuencia:** siempre (es determinista: el reloj es falso).
**Prueba que lo reproduce:** `at speed with the work lagging, the terrain on the road axis matches the axis wherever the world is ready (ruta enterrada)` en `tests/world/TerrainFollowsRoad.test.luau`. Además: `a chunk is stale only if new road arrived near it and its signature changed`, `clearing the notes remembers the chunks that went stale even if no plan asked about them` y `a stale chunk is not ready until it is rewritten, even if it is written` en `tests/world/ChunkRegistry.test.luau`, y `a chunk that went stale while the work was lagging behind the car ends up with the same road as without lag` en `tests/world/WorldPlanner.test.luau`. La corrida larga está en `tests/world/long/TerrainFollowsRoad.luau`.

## Hipótesis
### H1 — la reescritura de un chunk viejo se pierde cuando el replan tira la cola
- **Causa:** `ChunkRegistry.isStale` solo revisa los chunks que tienen un aviso (un tramo nuevo cerca o una marca de `flagForCheck`), y `clearNotes` borra los avisos en cada replan, antes de que la cola corra. `WorldPlanner.replan` además rehace la cola desde cero. Si llega otro replan (el auto avanzó 32 studs, o llegó otro tramo) antes de que corra la reescritura, el chunk sigue escrito con la ruta vieja y ya nada lo marca.
- **Predicción:** en un chunk que falla, `isStale` da `true` en un replan y, en el siguiente, `false` aunque su firma siga siendo distinta de la actual y nunca se haya reescrito. Si la causa es esa, al recordar los chunks descubiertos viejos hasta que se reescriben, la prueba pasa; y con trabajo rápido (0,25 ms por paso) no hace falta, porque la cola se vacía a tiempo.
- **Evidencia:** con prints temporales sobre el chunk (-2, -3) (el del eje del arcLength 2.592): al llegar el tramo 9, `isStale` dio `true` (cambió de firma, 3141378234 a 3902592308); en el replan siguiente dio `false` con la misma firma distinta, sin aviso, y nunca se reescribió (más abajo llegaron los tramos 10 y 11 con el mismo resultado). Con el tramo 8, la cola corrió entera antes del siguiente replan y se reescribió a tiempo.
- **Aprobada por:** Opus, en el encargo (daba la hipótesis de "el chunk se escribe antes de que llegue el tramo y no se reescribe" y pedía verificarla). La causa exacta salió de la instrumentación.
- **Cambio probado:** `ChunkRegistry` recuerda los chunks descubiertos viejos (`staleKeys`) hasta que se reescriben (`record`) o se borran (`remove`).
- **Resultado:** confirmada. La prueba de la semilla pasa de 155 malos a 0, y las corridas largas de 55.000 studs (`tests/world/long/TerrainFollowsRoad.luau`) dan 0 malos en 139.789 chequeos listos a 0,5 ms por paso y en 139.306 a 1 ms (la peor diferencia es 0,017 studs).

### H2 (la misma causa, un caso más) — un chunk fuera de lo querido no se entera
- **Causa:** el plan solo le pregunta `isStale` a los chunks que quiere ahora (`ChunkPlan.build`). Un chunk escrito que quedó atrás del auto (conservado por la histéresis, pero no querido) al que llega ruta nueva, pierde el aviso en `clearNotes` sin que nadie lo haya revisado, y si el auto vuelve atrás (un reinicio) y lo vuelve a querer, no se reescribe.
- **Predicción:** con un chunk escrito, un tramo nuevo cerca, y `clearNotes` sin que nadie llame a `isStale`, `isStale` tiene que dar `true` después.
- **Evidencia:** prueba del registro; antes del arreglo da `false`.
- **Aprobada por:** pendiente: es la misma causa que H1 y se agregó sin esperar, porque sin esto el arreglo de H1 deja el mismo agujero para los chunks que nadie preguntó. Opus puede pedir sacarlo (es el bucle de `clearNotes` y su prueba).
- **Cambio probado:** `clearNotes` revisa todos los chunks escritos antes de olvidar los avisos.
- **Resultado:** confirmada con la prueba del registro. La prueba del planificador (el estadio con trabajo atrasado y un reinicio hacia atrás) pasa con H1 solo: H2 no tiene prueba de integración propia.

### H3 (descartada como causa del bug) — el terreno ignora ruta que ya olvidó la ventana
- **Causa posible:** `RoadWindow` olvida los bloques que quedan más atrás de `BLOCK_MEMORY_STUDS`, y un chunk querido por la ruta de adelante puede estar influido por un tramo viejo ya olvidado (la firma del chunk cambia sin que llegue ruta nueva).
- **Evidencia:** pasa de verdad (instrumentado en el estadio con `FORGET`), pero solo cambia el mezclado fuera de la ruta: sobre el eje y la banquina la altura es la del bloque más cercano, y el anti-cruce deja a las pasadas no vecinas a 60 studs o más, así que el eje de un tramo no depende de un tramo olvidado. No es la causa del bug y no se cambió.
- **Resultado:** descartada. La prueba del planificador compara solo los chunks de `x >= 12` por este motivo.

## Causa y corrección
Ver H1 y H2. `ChunkRegistry` pasó de "revisar solo los chunks avisados, y olvidar los avisos al replanificar" a "recordar cada chunk descubierto viejo hasta que se reescribe". Cambios en `src/world/core/ChunkRegistry.luau`:
- `staleKeys`: chunks descubiertos viejos y no reescritos. `isStale` da `true` mientras estén ahí; `record` y `remove` los sacan.
- `clearNotes` revisa todos los chunks escritos antes de olvidar los avisos.
- `isReadyAt` da `false` si un chunk del radio está en `staleKeys`: un chunk viejo no es "seguro para apoyar algo". Con el trabajo sobrecargado (2 ms por paso: la cola no se vacía nunca, más de 600 tareas pendientes) el terreno cerca del auto sigue mal por ratos, pero el mundo lo avisa: en la corrida larga de 55.000 studs a 2 ms por paso, 0 de 88.480 chequeos "listos" dan mal, y los 3.707 malos son todos de puntos que `IsWorldReadyAt` daba por no listos.

`WorldPlanner` y `ChunkPlan` no cambiaron.

## Regresión
- [x] Suite completa (`bash scripts/check-all.sh`)
- [x] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas: repetir en Studio la pasada de 5.000 studs sobre el eje con la pantalla prendida y la semilla 393026859, y manejar por la vuelta de los 2.300 a 2.800 studs
- [x] Rendimiento: `clearNotes` recorre los chunks escritos (decenas) una vez por replan, y solo calcula la firma de los que están cerca de un aviso. `isReadyAt` hace una consulta más por chunk del radio. Sin medición en Studio.
- [x] Código de depuración borrado

## Qué aprendimos
- Una cola de trabajo que se rehace en cada replan no puede depender de avisos que el mismo replan borra: lo que se descubrió (un chunk viejo) tiene que quedar guardado hasta que se resuelve, no hasta que se arma la cola.
- Las pruebas del planificador corrían el trabajo hasta vaciar la cola en cada avance del auto, que es justo lo que no pasa con cuadros caros. Una prueba de integración con trabajo atrasado (reloj falso) encuentra este tipo de carreras; `tests/world/TerrainDrive.luau` queda como herramienta para eso.
- El eje de la ruta de referencia puede cruzarse con una pasada vieja que el mundo ya olvidó (el anti-cruce solo rige en la ruta viva): al comparar contra la referencia, hay que buscar el punto más cercano solo cerca del arcLength que se mide.
