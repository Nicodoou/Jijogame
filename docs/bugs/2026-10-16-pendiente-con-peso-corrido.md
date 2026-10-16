# Bug: con el peso corrido hacia adelante, el auto vuelve a deslizarse de costado en una pendiente

**Issue:** (sin número; lo encontró la corrección de las propiedades del manejo en la rama `a/7-valores-nico-2`)
**Rama:** a/7-valores-nico-2 (el reparto 70/30 todavía no está en `main`, así que el bug lo introduce esta rama y se corrige antes del merge)
**Estado:** resuelto

## Por qué es un bug
Contradice lo ya resuelto en `docs/bugs/2026-10-16-deslizamiento-pendiente.md` y la prueba `tests/vehicle/SlopeHold.test.luau`: de costado en una pendiente, sin input o con freno de mano, el auto queda quieto (< 0,05 studs/s) mientras el agarre alcance (`mu · cos θ ≥ sen θ`). Con `FRONT_WEIGHT_FRACTION` 0,7 (decisión del 2026-10-16, "Auto: tracción delantera, peso adelante y contravolante asistido") la prueba deja de cumplirse.

## Esperado y observado
**Esperado:** igual que con el centro de masa centrado: velocidad < 0,05 studs/s a 5°, 10° y 15°.

**Observado** (ToyWorld con el centro de masa configurado, 70/30, de costado, 6 s, 30 FPS):

| Pendiente | Sin input | Freno de mano |
| --- | --- | --- |
| 5° | 3,8 studs/s | 1,26 |
| 10° | 50,6 | 0,50 |
| 15° | 120,1 | 15,9 |

Con el centro de masa centrado las mismas corridas dan 0,000.

## Condiciones mínimas
Pendiente ≥ 5°, de costado, centro de masa corrido de la mitad (`FRONT_WEIGHT_FRACTION` distinto de 0,5). Nada más.

## Cómo replicarlo
1. `ToyWorld.new({ slopeDegrees = 5, initialYawDegrees = 90, isAlignedToSlope = true })` (el centro de masa por defecto es el configurado).
2. Correr 6 s sin input y leer `vector.magnitude(world.linearVelocity)`.

**Frecuencia:** siempre.
**Prueba que lo reproduce:** `SlopeHold`, "sideways on a slope the car stays still with no input" y "... with the handbrake".

## Hipótesis
### H1 — el tope por paso reparte `m/4` por rueda, pero con el peso corrido cada rueda sostiene una parte distinta
- **Causa:** el tope de la fuerza lateral de cada rueda era `(masa / 4) · |v| / dt`. En una pendiente cada rueda tiene que dar `parte · m · g · sen θ`, y con 70/30 las delanteras sostienen 0,35 cada una y las traseras 0,15. Con un tope igual para todas, las delanteras no llegan, las traseras sobran, y el torque de las fuerzas de las ruedas alrededor del centro de masa no se cancela: el auto gira y se arrastra.
- **Predicción:** si el tope de cada rueda usa su parte de la masa (`loadShares[i]`, de WP-7), de costado a 5°, 10° y 15° y a 30 y 60 FPS la velocidad queda < 0,05; con el centro de masa centrado (partes de 0,25) no cambia nada; siguen pasando `LongitudinalLimit`, `RestAfterDriving` y la propiedad 1.
- **Evidencia:** las mediciones de arriba (centrado sí sostiene, 70/30 no) y que el brazo de cada rueda ya salía del centro de masa real desde WP-7 pero el tope no.
- **Aprobada por:** Opus
- **Cambio probado:** `VehicleMath.opposingForceLimit(masa, parte, v, dt)` recibe la parte de la masa en lugar de la cantidad de ruedas; `WheelFriction.opposingLateral` le pasa `loadShares[índice]`. El tope longitudinal común sigue siendo la masa entera (parte 1).
- **Resultado:** **confirmada.**

## Causa y corrección
El tope por paso suponía el mismo reparto de masa en las cuatro ruedas. Ahora cada rueda usa su parte real (`WeightDistribution.wheelShares`), que ya se calculaba para la suspensión. El tope longitudinal común no cambia: sigue siendo la masa total.

Verificación (ToyWorld, 10 s, de costado, sin input y con freno de mano, yaw 90 y 270): con 70/30, 0,00000 a 0,00002 studs/s a 5°, 10° y 15° y a 30 y 60 FPS; con el centro de masa centrado, 0,00000 a 0,00003. Siguen pasando `LongitudinalLimit`, `RestAfterDriving` y la propiedad 1.

## Regresión
- [x] Suite completa de las pruebas que no tocan estas fallas (ver el informe de la rama)
- [x] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas (Studio: del WP-4)
- [x] Rendimiento: un indexado más por rueda y por cuadro
- [x] Código de depuración borrado (no se agregó)

## Qué aprendimos
Los topes y límites que se derivan de la masa tienen que repartirse con el mismo reparto que usa la suspensión. Las pruebas de manejo tienen que correr con el centro de masa configurado, no centrado, o estos bugs no se ven (por eso `ToyWorld` ahora lo usa por defecto).
