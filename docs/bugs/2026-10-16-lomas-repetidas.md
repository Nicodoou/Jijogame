# Bug: el perfil de lomas se repite cada 51.200 studs

**Issue:** #57
**Rama:** `b/58-wp-9-ruta-impl` (va dentro del WP-9, por decisión de Beni del 2026-10-16)
**Estado:** resuelto

## Por qué es un bug
Contradice la sesión de 30 minutos sin repetición visible (requerimientos del MVP) y el WP-9. A 100 studs/s la repetición llega a los ~8,5 minutos.

## Esperado y observado
- **Esperado:** el perfil de alturas de la ruta no se repite en por lo menos 30 min × 150 studs/s = 270.000 studs.
- **Observado:** `HillProfile.getTargetHeight(s)` da lo mismo que `getTargetHeight(s + 51200)` (diferencia ~1e-12) para cualquier semilla.

## Condiciones mínimas
Cualquier semilla, cualquier `s`, desfase de 51.200 studs. No depende del trazado: el perfil depende solo de `arcLength`.

## Cómo replicarlo
1. `HillProfile.new(seed)` con cualquier semilla.
2. Comparar `getTargetHeight(s)` con `getTargetHeight(s + 51200)` en una ventana de 32 puntos.

**Frecuencia:** siempre.
**Prueba que lo reproduce:** `the hill profile does not repeat itself during a 30 minute session (#57)` en `tests/world/HillProfile.test.luau`. Antes del arreglo falla con `se esperaba nil y se obtuvo 51200`.

## Hipótesis
### H1 — la entrada del ruido crece por un solo eje
- **Causa:** `math.noise` repite cada 256 en cada eje. El perfil llamaba `math.noise(arcLength / wavelength + offset, constante)`: solo avanza el primer eje, así que repite cada 256 × `HILL_WAVELENGTH_STUDS` = 51.200 studs. Las octavas siguientes (longitud de onda 100 y 50) también, porque 51.200 es múltiplo de sus períodos.
- **Predicción:** si se recorre el plano (x, y) del ruido en una dirección con tangente irracional, ya no existe un desfase con los dos ejes alineados con la grilla de 256, y la prueba pasa. La velocidad en el plano no cambia (se usa coseno y seno), así que el tamaño de las lomas queda igual.
- **Evidencia:** el desfase de la prueba es justo 256 × 200.
- **Aprobada por:** el WP-9 lo indica como arreglo ("recorrer el plano (x, y) del ruido").
- **Cambio probado:** `HILL_NOISE_DIRECTION_DEGREES = 20`; la entrada es `(t·cos θ + a, t·sin θ + b)` con `t = arcLength / wavelength`.
- **Resultado:** confirmada. Sobre 20 semillas, el desfase más parecido entre 5.000 y 270.000 studs deja una diferencia máxima de 15 a 22 studs en la ventana (la prueba pide más de 0,5).

## Causa y corrección
Ver H1. Se cambió `HillProfile.getTargetHeight` y se agregó `HILL_NOISE_DIRECTION_DEGREES` a `WorldConfig`.

## Regresión
- [x] Suite completa
- [x] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas (recorrer la ruta con el terreno: pendiente de Beni)
- [x] Rendimiento: `getTargetHeight` hace una multiplicación más por octava, sin medición aparte.
- [x] Código de depuración borrado

## Qué aprendimos
`math.noise` es periódico (256): una entrada que crece por un solo eje repite el resultado. Para recorridos largos hay que mover la entrada en más de un eje.
