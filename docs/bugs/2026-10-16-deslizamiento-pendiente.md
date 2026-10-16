# Bug: el auto se desliza en una pendiente aunque el agarre alcance para sostenerlo

**Issue:** (sin número; lo reportó Nico)
**Rama:** bug/2026-10-16-deslizamiento-pendiente
**Estado:** resuelto (H1 y H2, aprobadas como una sola; H3 es pedido de cambio)

## Por qué es un bug

Lo que dijo Nico: "al subir una o dos ruedas sobre la plataforma de spawn, como para dejarlo inclinado, el auto se desliza hasta caerse, de costado, para atrás o para adelante, incluso con el freno de mano puesto".

**No hay un texto que diga "el auto queda quieto en una pendiente".** Lo más cercano que está escrito:

- `docs/disenos/auto.md`, "Opción N1": la fuerza lateral del neumático tiene "un tope de `mu × carga`". Con `mu` 0,7 en ruta, el modelo promete que el neumático puede sostener lateralmente hasta `atan(0,7)` = 35°. Hoy el tope existe pero a velocidad 0 la fuerza que se entrega es 0, así que esa capacidad no se puede usar.
- `docs/wp/WP-3-nucleos-conduccion.md`, propiedad 1 (reposo): solo habla de un plano horizontal. Sobre la pendiente no dice nada.
- WP-3, `brakeForce` y Decisión "freno de mano suave": el freno de mano frena solo atrás, con `HANDBRAKE_FORCE_PER_LOAD` (0,25) por unidad de carga.

Por eso lo separo en tres, según lo que contradice:

| Caso | ¿Contradice algo escrito? |
| --- | --- |
| **De costado**, sin input o con freno de mano | **Sí, en parte:** el tope `mu × carga` del neumático (N1) permite sostener hasta 35°, y el auto se arrastra desde 5°. Lo trato como bug. |
| **De frente o de espaldas con freno de mano, dentro de su capacidad** (hasta `tan θ = 0,25 / 2`, unos 7°) | **Sí, en parte:** WP-3 y la decisión del freno de mano dicen que el freno de mano frena las ruedas traseras con `0,25 · carga`. Dentro de esa capacidad tiene que sostener, y creepea. Lo trato como bug. |
| **De frente o de espaldas con freno de mano, más allá de 7°** | **No.** `HANDBRAKE_FORCE_PER_LOAD` = 0,25 y solo las traseras frenan: aunque hubiera fricción estática perfecta, no sostiene más de ~7°. Es un **pedido de cambio** (valor de diseño). |
| **Sin input, de frente o de espaldas** | **No.** El auto rueda libre como en punto muerto (no hay freno de estacionamiento ni freno motor ni inercia de rueda). Es un **pedido de cambio**. |
| **Con el freno a fondo, parado** | **No es un bug, es el diseño:** WP-3, "Reversa (arcade)": con el freno apretado, sin acelerador y `|v| < REVERSE_ENGAGE_SPEED`, pasa a −1 y el freno acelera hacia atrás. En la pendiente el auto se va en reversa por diseño. |

## Esperado y observado

**Esperado** (de los dos casos que trato como bug): con el auto de costado, sin input o con freno de mano, a 5°, 10° y 15° (`mu · cos θ ≥ sen θ` se cumple: 0,7·0,966 = 0,68 ≥ 0,26), la velocidad queda por debajo de 0,05 studs/s después de unos segundos. De frente o de espaldas, con freno de mano, lo mismo hasta su capacidad (3° y 5°).

**Observado** (ToyWorld, plano con pendiente, Road, 30 FPS, 10 s, `isAlignedToSlope = true`). Velocidad a los 10 s en studs/s:

| Pendiente | Orientación | Sin input | Freno a fondo | Freno de mano |
| --- | --- | --- | --- | --- |
| 5° | de frente | 141,8 (acelera a 14,2 studs/s²) | 165,6 (reversa) | **1,05** (arrastre constante) |
| 5° | de espaldas | 141,8 | 29,2 (reversa) | **1,04** |
| 5° | de costado | **0,57** | 29,7 (reversa) | **0,57** |
| 10° | de frente | 311,8 | 331,2 (reversa) | 62,1 (acelera) |
| 10° | de espaldas | 311,8 | 28,6 (reversa) | 79,8 (acelera) |
| 10° | de costado | **1,14** | 29,8 (reversa) | **1,14** |
| 15° | de frente | 479,5 | 496,0 (reversa) | 234,2 (acelera) |
| 15° | de espaldas | 479,5 | 7,1 (reversa) | 251,6 (acelera) |
| 15° | de costado | **1,69** | 29,8 (reversa) | **1,69** |

(En negrita, los que contradicen lo escrito. El resto cae en "pedido de cambio" o "diseño", ver la tabla de arriba.)

## Condiciones mínimas

Plano inclinado (`slopeDegrees` ≥ 3°), superficie Road, sin input o solo freno de mano, auto apoyado alineado con el plano (`isAlignedToSlope`). No hace falta nada más: no depende de la semilla, ni de la ruta, ni del azar. Hace falta tener contacto en las cuatro ruedas.

## Cómo replicarlo

1. `ToyWorld.new({ slopeDegrees = 5, initialYawDegrees = 90, isAlignedToSlope = true })`.
2. Correr 6 s con `{ steer = 0, throttle = 0, brake = 0, isHandbrakeOn = false }` (o con el freno de mano).
3. Leer `vector.magnitude(world.linearVelocity)`: da 0,57 studs/s y no baja nunca.

**Frecuencia:** siempre (el ToyWorld es determinista).
**Prueba que lo reproduce:** `tests/vehicle/SlopeHold.test.luau` (falla en 3 de 4 pruebas; la cuarta solo comprueba que el agarre alcanza para las pendientes elegidas). También se agregó la opción `isAlignedToSlope` a `ToyWorld`, que es código de pruebas.

### Medición de la velocidad de arrastre

De costado, sin input. Velocidad de equilibrio según los cuadros por segundo y la pendiente, contra `g · sen θ · dt`:

| FPS | 5° | 10° | 15° |
| --- | --- | --- | --- |
| 30 | 0,570 (pred. 0,570) | 1,136 (1,136) | 1,693 (1,693) |
| 60 | 0,285 (0,285) | 0,568 (0,568) | 0,846 (0,846) |
| 120 | 0,143 (0,142) | 0,284 (0,284) | 0,423 (0,423) |

Es decir, **la velocidad de arrastre es exactamente `g · sen θ · dt`**: proporcional a la pendiente y al tiempo de un cuadro. No depende de ningún valor de agarre (ver la hipótesis 1).

Con el freno de mano de frente (30 FPS): 0,62 studs/s a 3°, 1,04 a 5°, 1,50 a 7°, 1,73 a 8° (sigue creciendo con la pendiente, siempre por encima de 0). A 60 FPS: 0,37, 0,61, 0,85 y 0,97, o sea que también baja con `dt`.

Un hallazgo aparte, no relacionado: de costado, sin input, a 15 FPS (`dt` = 1/15, el máximo del paso) el auto no se estabiliza, sale disparado (314 a 1.405 studs/s). Queda anotado en "Qué aprendimos"; no es parte de este bug.

## Hipótesis

### H1 + H2 (aprobadas como una sola: "la zona de adherencia") — la fricción usa la velocidad prevista al final del cuadro

#### H1 — El tope por paso es la única fuerza que sostiene, y es proporcional a la velocidad: el equilibrio exige velocidad > 0
- **Causa:** el tope por paso `(masa/4)·|v|/dt` (WP-3, "Tope por paso") es el máximo que cualquier fuerza que se opone al movimiento puede dar. Cerca de 0 es el que manda (el pedido lateral del neumático es unas 17 veces mayor que el tope, y el freno regularizado también). Como el tope es proporcional a la velocidad, a `v` = 0 vale 0. La gravedad suma `g · sen θ · dt` de velocidad por cuadro; el tope solo frena esa velocidad después de que ya apareció. El punto de equilibrio entre las dos es el que se ve: `v = g · sen θ · dt`.
- **Predicción:**
  1. La velocidad de equilibrio tiene que ser `g · sen θ · dt` (proporcional a la pendiente y a la duración del cuadro), **sin importar** el valor del agarre lateral, la rigidez del neumático ni las regularizaciones. ✔ ya medido: ver la tabla, coincide a tres decimales a 30, 60 y 120 FPS.
  2. Si se cambia `TIRE_CORNERING_STIFFNESS_PER_RADIAN`, `LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND` o `BRAKE_REGULARIZATION_SPEED`, el arrastre lateral de 10° no cambia. ✔ medido: con rigidez ×4, regularización 0,3 y regularización del freno 0,1, el arrastre sigue siendo 1,136 studs/s.
  3. Si se corrige dándole fuerza estática al tope (ver más abajo), el arrastre pasa a < 0,05 studs/s y la fuerza total entregada en reposo en pendiente es la componente de la gravedad: `(m/4)·g·sen θ` por rueda.
- **Evidencia:** las mediciones de arriba. También el origen del tope: la propiedad 1 del WP-3 (reposo plano) se arregló con el tope porque ahí no hay fuerza externa a velocidad 0; el tope es correcto para frenar la velocidad que hay, pero no tiene en cuenta la aceleración que las demás fuerzas le van a sumar durante el mismo cuadro.
- **Cambio propuesto (no tocado hasta que se apruebe):** calcular el tope (y el deslizamiento de las fuerzas que se oponen) con la **velocidad prevista al final del cuadro**, `v_prev = v + a_ext · dt`, donde `a_ext` es la aceleración de la rueda por las fuerzas que no son de fricción (gravedad proyectada sobre el eje de la rueda y el empuje del motor). Así la fuerza de fricción es la que frena justo `v_prev` y cancela la gravedad, y como depende de `v_prev` y no solo de `v`, sigue siendo "la que alcanza para parar, y no más" (no sobrepasa y no vuelve a oscilar). La fuerza sigue recortada por el círculo de fricción (`mu · carga`), así que se sostiene hasta `mu · cos θ ≥ sen θ` y no más allá.
  - **Cómo se evita volver a oscilar:** el tope por paso sigue siendo "a lo sumo lo que alcanza para parar la velocidad prevista". Una fuerza así no puede invertir `v_prev` en un cuadro, que es lo que el tope por paso garantiza hoy. La propiedad 1 (reposo plano) y la 9 (reversa a 60 FPS) siguen valiendo porque con `a_ext` = 0 (plano) la fórmula se reduce a la de hoy.
  - **Riesgo:** `a_ext` se calcula del chasis, no de cada rueda con su `ω × r`. Para el equilibrio en reposo alcanza; con el auto girando, el error de la predicción es del orden de `ω × r · dt`, que es chico, pero hay que medirlo con las propiedades 4, 9 y 14.
- **Aprobada por:** Opus (junto con H2)
- **Cambio probado:** ver "Causa y corrección".
- **Resultado:** **confirmada** (ver abajo).

#### H2 — La regularización por velocidad no puede dar fuerza a v = 0, y el pedido de fuerza (no solo el tope) tiende a 0
- **Causa:** aparte del tope, el *pedido* de cada fuerza también es función de `v`: el lateral del neumático es `C · carga · atan(v/3)`, el freno es `clamp(v/1) · fuerzaMáxima`, la resistencia al rodar es `clamp(v/1) · resistencia`. A `v` = 0 las tres piden 0. Si se levantara el tope sin tocar el pedido, la fuerza en reposo seguiría siendo 0 y el equilibrio se movería a la velocidad en la que el pedido iguala a la gravedad (0,03 studs/s lateral a 5°, ~0,6 studs/s el freno de mano).
- **Predicción:** con el tope levantado (p. ej. solo para probar, con `dt` muy chico en el tope), el arrastre lateral a 5° baja de 0,570 a ≈ 0,033 studs/s (= `3 · tan θ / C`), y el del freno de mano a ≈ 0,6 studs/s, pero **sigue habiendo arrastre > 0** y el temblor de reposo (propiedad 1) vuelve. Es decir: arreglar solo el tope no alcanza; tiene que cambiar también el pedido.
- **Evidencia:** la rigidez del neumático ×4 y la regularización 0,3 no mueven el arrastre (el tope manda ahora), pero esas dos entran en el pedido, así que van a mandar cuando el tope ya no sea el límite. Hoy el pedido lateral por rueda a v pequeña (130·m·v) es 17 veces mayor que el tope (7,5·m·v), por eso el tope manda.
- **Cambio propuesto:** el mismo de H1 más pedir la fuerza que para `v_prev` (no la lineal en `v`): el pedido en la zona de adherencia (`|v_prev|` menor que un umbral, el equivalente de `LOW_SPEED_REGULARIZATION`) es "lo que hace falta para parar `v_prev` en un cuadro", y el círculo de fricción lo recorta a `mu · carga`. Fuera de la zona, el modelo de hoy (lineal con tope y caída) no cambia.
- **Aprobada por:** Opus (junto con H1)
- **Cambio probado:** el mismo que H1.
- **Resultado:** **confirmada**: con solo cambiar el tope, el arrastre habría quedado en 0,12 studs/s en el freno de mano; hizo falta cambiar también el pedido.

### H3 — Parte de lo que ve Nico no es el modelo de fricción: es el diseño del freno de mano y del punto muerto
- **Causa:** el freno de mano frena solo las ruedas traseras con `HANDBRAKE_FORCE_PER_LOAD` = 0,25, y sin input el auto no tiene nada que lo sostenga en ninguna dirección (no hay freno de estacionamiento, freno motor ni inercia de rueda). Aunque H1 y H2 se corrijan, el freno de mano de frente o de espaldas solo sostiene hasta `tan θ = 0,25/2` (~7°), y sin input el auto rueda libre en la dirección de la pendiente.
- **Predicción:**
  1. Con el freno de mano de frente, la pendiente a la que deja de sostener es independiente de `dt` y de la regularización, y es `atan(HANDBRAKE_FORCE_PER_LOAD/2)`. ✔ la medición apunta a eso: a 10° (más allá de ~7°) acelera a 62 y 80 studs/s; con `HANDBRAKE_FORCE_PER_LOAD` = 1,0 el arrastre a 10° baja de 49,9 a 2,2 studs/s.
  2. Después de H1 y H2, sin input y de frente a 5°, el auto sigue acelerando a ≈ 14 studs/s².
- **Evidencia:** la tabla de observado.
- **Cambio propuesto:** ninguno en el núcleo sin decisión: es de diseño (valor del freno de mano, un freno de estacionamiento automático al estar quieto sin input, o un freno motor). Lo lleva la persona.
- **Aprobada por:** no aplica: Opus se la lleva a Nico como **pedido de cambio** (freno de mano más fuerte, retención automática al estar quieto o freno motor).
- **Cambio probado:** ninguno.
- **Resultado:** no se toca. Quedan fuera de la prueba, documentados: freno de mano a más de ~7° (a 10° y 15° sostiene 82% y 54% de la fuerza que hace falta), sin input de frente o de espaldas (rueda libre) y freno a fondo estando parado (entra en reversa por diseño).

## Causa y corrección

**Causa:** la fuerza de fricción se calculaba con la velocidad **actual** de la rueda, y las dos cosas que la limitaban (el tope por paso y las rampas de regularización) valen 0 a velocidad 0. En una pendiente la gravedad suma `g · sen θ · dt` de velocidad en cada cuadro, y la fricción solo reaccionaba después, así que el equilibrio quedaba en una velocidad distinta de 0 (`g · sen θ · dt`).

**Corrección (un solo cambio conceptual):**
1. `WheelForces.expectedSpeeds`: la velocidad de la rueda en sus dos ejes se corrige con la gravedad que va a recibir durante el cuadro (`v + (g · eje) · dt`). La fricción (deslizamiento lateral, tope lateral, freno, freno de mano y resistencia al rodar) se calcula con esa velocidad prevista. En un plano horizontal la corrección es 0 y todo queda como antes.
2. `Drivetrain.brakeForce` y la resistencia al rodar: dentro de la zona de adherencia el pedido es la fuerza completa y el tope por paso (que para una velocidad prevista es "lo que hace falta para pararla") es lo que la limita; se sacó la rampa `clamp(v / BRAKE_REGULARIZATION_SPEED)` y con ella el valor `BRAKE_REGULARIZATION_SPEED` de `VehicleConfig`.
3. El tope por paso del freno se reparte entre las ruedas que frenan (`brakingWheelCount`): con el pedal, las cuatro; con solo el freno de mano, las dos traseras.

**Resultado de la predicción (ToyWorld, todo Road):**
- De costado, a 5°, 10° y 15°, a 30 y a 60 FPS, a los 10 s: sin input 0,000004 a 0,000025 studs/s; con freno de mano 0,0008 a 0,0045 studs/s (< 0,05).
- Freno de mano de frente y de espaldas, 3° a 7°, 10 s: 0,048 a 0,050 studs/s a 30 FPS y 0,024 a 0,025 a 60 FPS. A 5°: 0,0477 (de frente) y 0,04997 (de espaldas) a 30 FPS. **Pasa, pero con poco margen a 30 FPS** (a 6° y 7° de espaldas da 0,0501 y 0,0502). Causa del resto: la resistencia al rodar de las dos ruedas delanteras se suma a la de las traseras, que ya pararon `v_prev` por sí solas, y sobrepasa un poco. Queda anotado, no se tocó.
- Fuerza de las ruedas en el plano / `m · g · sen θ`: de costado, sin input, 0,99999 a 1,00000 en 5°, 10° y 15°; con freno de mano de costado 1,00002, 1,00002 y 1,0074; de frente a 5° con freno de mano 1,0000. A 10° y 15° de frente, con freno de mano, 0,82 y 0,54 (el freno de mano no alcanza: H3).
- Sin romper nada: pasan las 17 propiedades (reposo plano y perturbado, 4, 9 a 60 FPS, 14), `RestAfterDriving` a 60 y a 30 FPS y `check-all`.

**Efecto sobre el #64 (inestabilidad a 20 y 15 FPS) y el caso de costado a 15 FPS** (solo medido, no se arregló; velocidad a los 8 s, studs/s, con el cambio contra antes):

| FPS | Costado 5° | Costado 15° | Plano con 0,3 studs/s de empuje |
| --- | --- | --- | --- |
| 15 | 6,4 contra 39,3 | 264,9 contra 1409,7 | 6,7 contra 4,1 |
| 20 | 2,15 contra 0,55 | 1,53 contra 4,65 | 1,79 contra 1,79 |
| 24 | 0 contra 0,71 | 0 contra 2,12 | 0 contra 0 |
| 30 | 0 contra 0,57 | 0 contra 1,69 | 0 contra 0 |

A 24 FPS o más la pendiente queda quieta. A 20 y 15 FPS la inestabilidad sigue (el plano perturbado da lo mismo a 20 FPS y algo peor a 15): la zona de adherencia no la resuelve ni la empeora de forma clara.

## Regresión
- [x] Suite completa (`check-all.sh` en verde)
- [x] Cobertura ≥ 87% (99,8%)
- [ ] Pruebas manuales relacionadas (de Studio: del WP-4; sin Studio en este bug)
- [x] Rendimiento: el cambio agrega un producto escalar por eje y por rueda por cuadro; no se midió en Studio
- [x] Código de depuración borrado (no se agregó)

## Qué aprendimos
- El tope por paso resolvió la oscilación en reposo plano pero convirtió la fricción en una fuerza "viscosa" (proporcional a la velocidad): sirve para frenar un movimiento, no para mantener la quietud. Una fricción que sostenga necesita una fuerza que no dependa de la velocidad actual sino de la que va a haber al final del cuadro.
- Hallazgo aparte: de costado en una pendiente a 15 FPS (`dt` = 1/15, el máximo del paso) el auto no se estabiliza. No es parte de este bug; conviene una nota.
