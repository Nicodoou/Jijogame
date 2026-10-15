# Experimento #32: estabilidad de la física del auto (`exp/auto-fisica`)

Fecha: 2026-10-15. Studio "Place1" (Baseplate), modo Play, datamodel `Server`. Todo medido con `execute_luau` y conexiones a `RunService`. Scripts: `exp/fuerza_vs_impulso.luau` (preg. 1) y `exp/suspension.luau` (preg. 2 y 3).

## Cómo se simularon 30 FPS
Una conexión a `RunService.Heartbeat` con espera activa (`while os.clock() < target do end`) hasta que pasan 1/30 s desde el inicio del Heartbeat anterior. FPS real medido (frames / tiempo con `os.clock`): **30,0 a 30,1**. Sin límite, el servidor del Studio corre a **60,0 FPS** (el `deltaTime` de `PreSimulation` es 0,0167 en promedio, con jitter de frame: se vieron 0,0125 y 0,0208 alternados). Una fila nominal de 60 midió 58,8 FPS (una prueba, ruido del Studio).

## Pregunta 1: `VectorForce` contra `ApplyImpulse`
Parte 4x4x4 desanclada, gravedad 0 (se restaura), masa 44,8, a = F/m = 10 studs/s². Se mide Δv por frame / (a · dt real entre `PreSimulation`), 174 frames por fila. `ApplyImpulse` aplica `F·dtArg` en cada `PreSimulation`.

| Modo | FPS real | Razón media Δv/(F/m·dt) | mín | máx |
| --- | --- | --- | --- | --- |
| VectorForce, sin límite | 60,0 | 1,002 | 0,843 | 1,246 |
| ApplyImpulse, sin límite | 60,0 | 1,002 | 0,698 | 1,363 |
| VectorForce, cap 60 | 60,0 | 1,001 | 0,918 | 1,091 |
| ApplyImpulse, cap 60 | 60,0 | 1,003 | 0,000 | 1,884 |
| VectorForce, cap 30 | 30,0 | 1,001 | 0,483 | 1,587 |
| ApplyImpulse, cap 30 | 30,0 | 1,001 | 0,849 | 1,168 |

**Conclusión [comprobado]:** el `VectorForce` constante rige todos los pasos de física del frame (razón media 1,00 también a 30 FPS, donde un solo paso daría ~0,125). `VectorForce` persiste entre frames hasta que se cambia. Los mínimos y máximos por frame son jitter entre el dt de pared y el de la física, no un error sistemático.

**Hallazgo crítico [comprobado]: sueño del ensamble.** Con `VectorForce` actualizado por frame y el chasis casi quieto, la posición y la velocidad leídas en `PreSimulation` quedaban **congeladas durante 4 a 9 frames seguidos** y luego saltaban; la suspensión divergía (el chasis salía disparado a más de 90 studs en 5 s, a 60 y a 30 FPS). Probado:
- `VectorForce` puro (`vf0`): diverge.
- `VectorForce` + `ApplyImpulse(Vector3.zero)` cada frame: diverge.
- `VectorForce` + `ApplyImpulse(Vector3.new(0, 0.001, 0))` cada frame (`vf`): estable.
- `ApplyImpulseAtPosition` (`imp`): estable en el sentido de que no diverge (el impulso despierta el chasis), pero con jitter (ver abajo).

La causa exacta (que el motor duerme el ensamble y no atiende el cambio de `Force`) es una **suposición** coherente con lo observado; no se pudo ver el estado de sueño directamente. Un auto detenido sobre su suspensión es justo el caso que duerme, así que el diseño real necesita un despertador por frame.

## Pregunta 2: suspensión por raycast
Chasis 6x2x10 studs, masa 84 (`Part.Mass`; `AssemblyMass` da `inf` si la parte está anclada y parentada). Cuatro ruedas en (±2,5, -1, ±4) locales. En cada `PreSimulation`: `Raycast` hacia abajo desde 2 studs sobre el punto de rueda, largo 2 + L0 con L0 = 4 studs (resorte extendido). Compresión x = L0 - distancia; fuerza por rueda `F = max(0, k·x + c·v_compresión)`, con `v_compresión = -GetVelocityAtPosition(pw).Y`, `k = (m/4)·ω²`, `c = 2ζ·sqrt(k·m/4)`, ω = 2π·f. La fuerza va siempre hacia arriba (suelo plano). El suelo es el SpawnLocation del Baseplate; la normal no se usa.

**Cómo se aplicó la fuerza** (dos variantes):
- `vf`: un `VectorForce` por rueda (`Attachment` en la rueda, `ApplyAtCenterOfMass = false`, `RelativeTo = World`) + `ApplyImpulse` de 0,001 para evitar el sueño.
- `imp`: `ApplyImpulseAtPosition(F·dt, posición de la rueda)` con `dt` = `deltaTime` de `PreSimulation`.

Pruebas de 5 s: **reposo** (arranca en la altura de equilibrio, velocidad 0) y **caída** (arranca 2 studs más arriba). Criterio de "estable": reposo con variación total de altura (`ptp`) < 0,05; en la caída, variación de los últimos 2 s < 0,05; sin divergencia. `cruces` = cruces de ±0,05 studs alrededor del equilibrio; `asienta` = último instante con desvío mayor que 0,05.

### `vf` (VectorForce por rueda + despertador)

| f (Hz) | ζ | FPS | ptp reposo | ptp caída 3-5 s | cruces | asienta (s) | ¿Estable? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1,5 | 0,3 | 60 | 0,0000 | 0,0003 | 3 | 1,12 | sí |
| 1,5 | 0,6 | 60 | 0,0000 | 0,0000 | 1 | 0,55 | sí |
| 1,5 | 1,0 | 60 | 0,0000 | 0,0000 | 0 | 0,60 | sí |
| 2,5 | 0,3 | 60 | 0,0000 | 0,0000 | 3 | 0,67 | sí |
| 2,5 | 0,6 | 60 | 0,0000 | 0,0000 | 1 | 0,33 | sí |
| 2,5 | 1,0 | 60 | 0,0000 | 0,0000 | 0 | 0,30 | sí |
| 4,0 | 0,3 | 60 | 0,0000 | 0,0000 | 3 | 0,45 | sí |
| 4,0 | 0,6 | 60 | 0,0000 | 0,0000 | 1 | 0,23 | sí |
| 4,0 | 1,0 | 60 | 0,0000 | 0,0000 | 1 | 0,22 | sí |
| 1,5 | 0,3 | 30 | 0,0000 | 0,0009 | 4 | 1,33 | sí |
| 1,5 | 0,6 | 30 | 0,0000 | 0,0000 | 1 | 0,53 | sí |
| 1,5 | 1,0 | 30 | 0,0000 | 0,0000 | 0 | 0,60 | sí |
| 2,5 | 0,3 | 30 | 0,0000 | 0,0000 | 4 | 0,80 | sí |
| 2,5 | 0,6 | 30 | 0,0000 | 0,0000 | 1 | 0,30 | sí |
| 2,5 | 1,0 | 30 | 0,0000 | 0,0000 | 0 | 0,33 | sí |
| 4,0 | 0,3 | 30 | 0,0000 | 0,0000 | 5 | 0,67 | sí |
| 4,0 | 0,6 | 30 | 0,0000 | 0,0000 | 1 | 0,20 | sí |
| 4,0 | 1,0 | 30 | 0,0000 | 0,0000 | 4 | 0,87 | sí |

Los 18 casos son estables y vuelven a la altura de equilibrio (`finalDev` = 0,0000 en los que se midió: 1,5 / 2,5 / 4 Hz con ζ = 0,6 a 30 FPS). El reposo da 0,0000 porque arranca justo en el equilibrio; la caída y el golpecito (abajo) muestran que además amortigua. En ningún caso la caída tocó el suelo (desvío mínimo -0,84 studs, con 1,5 Hz y ζ = 0,3 a 30 FPS).

Golpecito (impulso de 2 studs/s hacia arriba en t = 1 s, `vf`, ζ = 0,6): 1,5 Hz a 30 FPS sube 0,137, 2,5 Hz a 30 FPS sube 0,095, 4 Hz a 30 FPS sube 0,070, 2,5 Hz a 60 FPS sube 0,071 studs; todos vuelven a `finalDev` = 0,0000.

### `imp` (ApplyImpulseAtPosition por rueda)

| f (Hz) | ζ | FPS | ptp reposo | ptp caída 3-5 s | ¿Estable (< 0,05)? |
| --- | --- | --- | --- | --- | --- |
| 1,5 | 0,3 | 60 | 0,110 | 0,096 | no |
| 1,5 | 0,6 | 60 | 0,087 | 0,037 | no (reposo) |
| 1,5 | 1,0 | 60 | 0,055 | 0,048 | no (reposo) |
| 2,5 | 0,3 | 60 | 0,049 | 0,059 | no (caída) |
| 2,5 | 0,6 | 60 | 0,060 | 0,021 | no (reposo) |
| 2,5 | 1,0 | 60 | 0,054 | 0,014 | no (reposo) |
| 4,0 | 0,3 | 60 | 0,063 | 0,023 | no (reposo) |
| 4,0 | 0,6 | 60 | 0,042 | 0,000 | sí |
| 4,0 | 1,0 | 60 | 0,027 | 0,019 | sí |
| 1,5 | 0,3 | 30 | 0,143 | 0,092 | no |
| 1,5 | 0,6 | 30 | 0,304 | 0,073 | no |
| 1,5 | 1,0 | 30 | 0,390 | 0,060 | no |
| 2,5 | 0,3 | 30 | 0,106 | 0,083 | no |
| 2,5 | 0,6 | 30 | 0,155 | 0,045 | no (reposo) |
| 2,5 | 1,0 | 30 | 0,238 | 0,048 | no (reposo) |
| 4,0 | 0,3 | 30 | 0,107 | 0,058 | no |
| 4,0 | 0,6 | 30 | 0,108 | 0,082 | no |
| 4,0 | 1,0 | 30 | 0,267 | 0,163 | no |

Con impulsos, a 30 FPS **ningún caso queda por debajo de 0,05** y la altura en reposo deriva hacia arriba (hasta +0,39 studs; en el golpecito con 2,5 Hz y ζ = 0,6 termina 0,123 sobre el equilibrio). Hipótesis (no comprobada): diente de sierra del impulso, que entra al inicio del frame mientras la gravedad actúa el resto, más el uso del `deltaTime` anterior en vez del real.

### Límite de rigidez a 30 FPS (`vf`, caída)

| f (Hz) | ζ = 0,3 | ζ = 0,6 | ζ = 1,0 |
| --- | --- | --- | --- |
| 6 | asienta (rebote total 9,5 studs, 11 cruces) | asienta (3,1 studs, 6 cruces) | diverge |
| 8 | no asienta (oscila ±20 studs) | diverge | diverge |
| 12 | diverge | diverge | diverge |

A 60 FPS: 8 Hz con ζ = 0,6 asienta; 12 Hz y 16 Hz con ζ = 0,6 divergen. Más amortiguación no ayuda en el límite (ζ = 1,0 a 6 Hz diverge); el límite parece venir de la frecuencia natural contra el retardo de un frame (suposición). Hasta 4 Hz hay margen a 30 FPS (ω·dt = 0,84 a 4 Hz).

### `PhysicsSteppingMethod` (Fixed contra Adaptive): no probado
`workspace.PhysicsSteppingMethod` no se puede leer ni escribir desde un script: en Edit da `PhysicsSteppingMethod is not a valid member of Workspace` y `GetPropertyChangedSignal` da `PhysicsSteppingMethod is not a scriptable property`. `UsePhysicsAdaptiveStepping` tampoco existe. Tampoco se pudo leer el valor actual de Place1, así que **todas las mediciones corrieron con el modo que traiga Place1 por defecto, sin confirmar cuál es**. Para cambiarlo a mano: en Studio, Explorer, seleccionar `Workspace`, y en la ventana Properties buscar `PhysicsSteppingMethod` (no verificado en qué sección aparece en esta versión). No se cambió ningún ajuste de Studio.

## Pregunta 3: costo por frame
Promedio de `os.clock` alrededor del cálculo de los 4 rayos y las fuerzas (más el despertador en `vf`), sobre ~150 a ~300 frames por prueba, Studio en PC, modo Play:

| Modo | Costo por frame |
| --- | --- |
| `vf` (4 `Raycast`, 4 `GetVelocityAtPosition`, 4 `Force`, 1 impulso) | 57 a 113 µs (típico 65 a 85) |
| `imp` (4 `Raycast`, 4 `GetVelocityAtPosition`, 4 `ApplyImpulseAtPosition`) | 38 a 56 µs (típico 40 a 46) |

Es ~0,4 a 0,7% de un frame de 16,7 ms. Es el costo en PC, **no en un celular de gama media** (queda pendiente, punto 5 del diseño). Incluye el overhead de `os.clock`. Las pruebas que divergen no sirven para el costo (los rayos fallan).

## Resumen
1. ¿`VectorForce` rige todos los pasos del frame? **Sí** (razón 1,00 a 60 y a 30 FPS). Pero un chasis quieto con `VectorForce` se duerme y la suspensión diverge salvo que se lo despierte cada frame.
2. ¿Suspensión por raycast estable a 30 FPS? **Sí con `VectorForce` por rueda más despertador**: las 9 combinaciones de 1,5 / 2,5 / 4 Hz y ζ 0,3 / 0,6 / 1,0 son estables a 30 y a 60 FPS. Con `ApplyImpulseAtPosition` **no** a 30 FPS (ningún caso baja de 0,1 studs en reposo, con deriva). Límite de rigidez a 30 FPS: hasta 6 Hz. **Fixed contra Adaptive: no concluyente** (no se puede cambiar desde script).
3. Costo: 40 a 110 µs por frame en PC.

## Limitaciones
Un solo chasis sobre suelo plano, solo fuerza vertical (sin neumáticos, motor, dirección ni fuerzas laterales). El reposo arranca en el equilibrio exacto. Servidor del Studio, no cliente con dueño de red (que es como correrá el juego). No se probó Terrain ni la `Normal`. Sin celular. El corte de FPS por espera activa no reproduce la carga de render de un celular. Cada resultado es una sola corrida, sin repeticiones.
