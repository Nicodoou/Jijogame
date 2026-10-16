# Bug: el auto vibra y se arrastra solo después de manejarlo

**Issue:** (sin número)
**Rama:** bug/2026-10-16-vibracion-reposo
**Estado:** resuelto (causa confirmada y corregida en la rama del WP-7)

## Por qué es un bug
Contradice WP-3, propiedad 1 (reposo: sin input, la deriva horizontal queda < 0,05 studs y la velocidad < 0,05 studs/s) y WP-4, pruebas manuales ("Quieto 10 s: no se desliza ni tiembla"; "el auto quieto no diverge a 60 ni a 30 FPS"). Esas pruebas arrancan desde el reposo; este caso es el mismo reposo, pero después de manejar.

## Esperado y observado
- **Esperado:** al soltar todo el input el auto desacelera y termina quieto, sin temblar.
- **Observado en Studio (código de `a/7-centro-de-masa-codigo`):** sin tocar nada, cuando la velocidad baja de ~31 studs/s (60 FPS) aparece un giro que crece solo; al final el auto queda en un ciclo límite: se arrastra a 0,75 studs/s y su velocidad de giro alterna entre +39,6 y −39,6 °/s **en cada cuadro** (30 Hz a 60 FPS), con fuerzas horizontales de ~2600 N por rueda. Eso es "vibra" (la alternancia) y "se va patinando solo" (el arrastre).

## Condiciones mínimas
Acelerar ~1 s en línea recta, soltar todo y esperar. Sin dirección ni freno. Con el chasis del WP-7 (lastre invisible de 1×1×1). A 30 FPS empieza a ~68 studs/s. Con el chasis de `main` (sin lastre) el modelo de juguete no lo reproduce (ver Paso 0).

## Cómo replicarlo
1. Play en Studio con el código del WP-7; sin tocar el teclado (se midió `GetKeysPressed()` y el gamepad durante la corrida: 0 teclas, 0 gamepads).
2. `W` 0,9 s a 1,5 s y soltar.
3. Dejar 40 s. Registrar la velocidad angular por cuadro.

**Frecuencia:** 3 de 3 corridas a 60 FPS (aparición a 31 a 33 studs/s, estado final idéntico: 0,747 studs/s y 39,63 °/s con cambio de signo en el 100% de los cuadros) y 2 de 2 a 30 FPS (aparición a ~68 studs/s, sigue caótico a los 45 s, hasta 16,5 °/s).
**Prueba que lo reproduce:** `tests/vehicle/RestAfterDriving.test.luau` (con `ToyWorld` y la inercia de giro del conjunto con lastre). Falla a 60 y a 30 FPS; la prueba de control con la inercia de la caja entera pasa.

## Datos medidos (Studio)
- Inercia de giro del conjunto del WP-7: 483 (impulso angular de 100 sobre el `Body`, `ΔΩ` = 0,207 rad/s). `ToyWorld` y `main` suponen 952 (`m·(6²+10²)/12` con m = 84). El `Body` solo (masa 42) da 476: el lastre aporta masa pero casi no inercia, por ser de 1×1×1 en el centro.
- Crecimiento inicial del giro: ×1,22 por cuadro con signo alternado (se ve ×1,48 cada dos cuadros muestreados), de 0,09 a 39 °/s en ~0,4 s.
- `ToyWorld` con `yawInertiaFraction` = 0,5: aparición a 31,7 studs/s (60 FPS) y a 70,4 studs/s (30 FPS), estado final 40,2 °/s alternando; con 1,0 no aparece nunca.

## Paso 0: origen
Bug **introducido por el WP-7** (rama `a/7-centro-de-masa-codigo`, todavía sin mergear). `main` tiene la inercia de giro de la caja entera (952) y el modelo de juguete es estable con ella a cualquier velocidad, a 60 y a 30 FPS. No se corrió `main` en Studio: Nico manejó `main` y el experimento sin reportar esto.

## Hipótesis
### H1 — el lastre suma masa pero no inercia de giro
- **Causa:** el `Ballast` de 1×1×1 en el centro dejó el conjunto con una inercia de giro de 483 (medida en Studio con un impulso angular), contra 952 de la caja entera. Con la mitad de inercia, la ganancia del lazo explícito de las fuerzas del neumático sube ×2 y por debajo de una velocidad crítica (~32 studs/s a 60 FPS, ~70 a 30 FPS) el factor por cuadro pasa de −1.
- **Predicción:** con el `Ballast` del tamaño del `Body` la inercia vuelve a ≈ 952 y la aparición desaparece a 60 y a 30 FPS.
- **Evidencia:** inercia medida 483; réplica en `ToyWorld` con la mitad de inercia (aparición a 31,7 y 70,4 studs/s; en Studio 31–33 y ~68); el ciclo límite alterna de signo en cada cuadro.
- **Aprobada por:** Opus
- **Cambio probado:** `Ballast` con el tamaño del `Body` (una línea de constante) en `a/7-centro-de-masa-codigo`.
- **Resultado:** **confirmada**. Inercia medida en Studio: 952 (objetivo 952). Réplica (1 s de `W`, o 0,5 s de `W`, tap de `D` de 0,25 s y 1,1 s más de `W` a 30 FPS, soltar todo, 45 a 70 s de espera): 3 de 3 corridas a 60 FPS (velocidad máxima 57,5; a los 4 s en adelante el giro es 0,000 °/s, velocidad final 0,0008, 0 cambios de signo) y 3 de 3 a 30 FPS (velocidad máxima 80 a 81; giro 0,000 °/s, velocidad final 0,000 a 0,0008). Antes del cambio eran 3 de 3 y 2 de 2 con el ciclo límite. Con `FRONT_WEIGHT_FRACTION` 0,6 el centro de masa queda en z = −0,8000 (objetivo −0,80), cabeceo en reposo 0,000°.

### H2 — el tope por paso no considera la inercia de giro (queda para después)
- **Causa:** el tope `(m/4)·|v|/dt` por rueda ignora que en giro la inercia efectiva de las 4 ruedas es el doble de la real.
- **Predicción:** usar la inercia real en el tope estabilizaría el giro con cualquier inercia.
- **Evidencia:** sólo analítica. No se prueba ahora (decisión del orquestador).

### H3 — el estado de arrastre es consecuencia de H1
- **Resultado:** descartada como causa independiente: al confirmarse H1 el estado final es 0,000 studs/s.

## Margen de estabilidad medido en `ToyWorld` (sin tocar código del juego)
Perturbación de 0,0015 rad/s, 2 s de acelerador, 100 s, criterio: velocidad < 0,05 y giro < 0,5 °/s entre los 90 y los 100 s.

| FPS | fracción de inercia mínima estable |
| --- | --- |
| 60 | ≈ 0,71 (0,7 inestable, 0,8 estable) |
| 30 | ≈ 0,71 (igual) |
| 25 | estable ya con 1,0 |
| 20 | inestable incluso con 1,0 (aparición a ~66 studs/s); el giro se estabiliza con ≥ 2,0, pero queda un arrastre residual de 1,79 studs/s con cualquier inercia |
| 15 | diverge numéricamente con cualquier inercia probada (velocidades de 10^4 studs/s) |

Conclusión: a 60 y a 30 FPS el margen es ~30% de inercia; por debajo de ~25 FPS el núcleo ya es inestable aunque la inercia sea la de la caja entera (otro problema, independiente de este bug).

## Causa y corrección
La causa es que el lastre del adaptador reducía la inercia de giro del conjunto a la mitad. Corrección: el `Ballast` mide lo mismo que el `Body`. Prueba: `tests/vehicle/RestAfterDriving.test.luau` (pasada a la rama del WP-7 con la inercia de la caja entera, más una variante con la mitad marcada como límite conocido).

## Regresión
- [x] Suite completa (`check-all` OK en la rama del WP-7)
- [x] Cobertura ≥ 87%
- [x] Pruebas manuales relacionadas (cinco corridas y la medición de inercia y de centro de masa en Studio)
- [ ] Rendimiento (no aplica: sólo cambia la construcción del modelo)
- [x] Código de depuración borrado (no se dejó instrumentación en el repo)

## Qué aprendimos
Una pieza de lastre cambia la inercia además de la masa y el centro de masa: tiene que tener la forma (y el tamaño) de la masa que reemplaza. El núcleo y `ToyWorld` suponen la inercia de la caja entera; si algún día el modelo cambia, hay que medir la inercia de giro en Studio antes de afinar. A 25 FPS o menos el núcleo tiene problemas de estabilidad propios (ver margen).
