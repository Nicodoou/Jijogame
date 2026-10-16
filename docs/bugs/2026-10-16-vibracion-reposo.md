# Bug: el auto vibra y se arrastra solo después de manejarlo

**Issue:** (sin número)
**Rama:** bug/2026-10-16-vibracion-reposo
**Estado:** replicado (hipótesis pendientes de aprobación)

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

## Hipótesis
(ver el informe; esperan aprobación de Opus)

## Causa y corrección
Pendiente.

## Regresión
- [ ] Suite completa
- [ ] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas
- [ ] Rendimiento (si aplica)
- [ ] Código de depuración borrado

## Qué aprendimos
Pendiente.
