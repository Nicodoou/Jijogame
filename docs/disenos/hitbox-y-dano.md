# Hitbox modular y daño por pieza

**Issue:** pedido de Nico (2026-10-16). Va al MVP.
**Requerimientos:** CP-5 (choques con consecuencia pero sin frustración). Este diseño lo amplía con daño por pieza (cambio de alcance aprobado por Nico).
**Estado:** aprobado (Nico, 2026-10-16)

## Lo que pidió Nico

- **Una hitbox modular por auto,** con las mismas piezas en todos los autos y configurable por auto.
- **Un editor dentro de Studio** para ubicar y escalar cada pieza.
- **Daño por pieza, con dos valores:**
  - **desgaste:** baja la condición máxima de la pieza;
  - **daño:** si llega a 100, la pieza **se cae del auto** y queda inservible. Si no llega, la pieza se puede reparar hasta el valor que permite el desgaste.
- **El daño se ve solo con cambios de textura:** de 3 a 5 por pieza, según la vida.
- **El efecto depende de la pieza:** por ejemplo, el radiador afecta al motor y el tanque pierde combustible.
- **La mecánica de reparar queda para después del MVP.**
- **Las bases del sistema de piezas intercambiables quedan asentadas** (#63): la hitbox nace como parte de la ficha del chasis (`ChassisSpec`).

## Investigación

La hizo el subagente `investigador` el 2026-10-16. **[V]** es verificado en la documentación oficial; **[S]**, fuente secundaria; **[NC]**, no confirmado.

- **Detección de golpes por pieza: hay una API oficial, `BasePart:BindToCollisionSummaries(callback)`** [V] ([colisiones](https://create.roblox.com/docs/workspace/collisions)).
  - **Qué da, una vez por frame y por contacto:** la parte propia, la otra parte, el punto, la normal, la velocidad relativa antes de que el motor resuelva el choque, y el área.
  - **Dónde corre:** solo en el dueño de red, que en nuestro caso es el cliente. No se replica.
  - **Cuándo no funciona:** con `CanCollide = false` o entre partes dormidas.
  - **Costo:** crece con la cantidad de partes suscriptas.
  - **Antigüedad:** según blogs, la lanzaron hace unos 10 días, y no se sabe si es beta [NC].
- **`Touched` no sirve como base:** no da ni fuerza ni punto, y pierde golpes a alta velocidad [S].
- **Muchas cajas soldadas al auto:**
  - `Massless` solo funciona si la caja está soldada a una parte con masa [S].
  - Hay un bug reportado de partes `Massless` que igual aportan inercia si tienen un constraint adentro [S].
  - Hay que verificar `AssemblyMass` y el centro de masa.
- **Grupos de colisión:** se registran con `workspace:RegisterCollisionGroup` [V]. El límite sería de ~32 [NC].
- **Desprender una pieza:**
  - romper soldaduras en el cliente que es dueño de red trae problemas conocidos de réplica y de dueño (staff de Roblox, 2021) [S];
  - las partes creadas en el cliente solo existen en ese cliente [S].
- **Texturas de daño:**
  - **`SurfaceAppearance`** (la textura de mejor calidad) **no se puede cambiar por script** [V];
  - **`MeshPart.TextureID`** no tiene restricción listada; si se puede cambiar en pleno juego no está confirmado [NC].
- **Autoridad:** Roblox no verifica la física de partes que simula el cliente [V]. Con un jugador por servidor, una trampa solo afecta a ese jugador, salvo en lo que se guarde, como el desgaste.
- **Antecedentes:** Car Crushers 2 arranca piezas, pero no publica su técnica. En los foros el patrón común es `Touched` + un umbral + romper soldaduras, y tiene fallas conocidas [S].
- **Editor:** con un plugin se pueden usar las herramientas nativas de Studio para mover y escalar, con deshacer, y `ChangeHistoryService` [V]. Programar `Handles` propios es más trabajo [V].

Informe completo del investigador: comentario de este PR.

## Resultados del experimento `exp/hitbox` (#82)

Lo corrió el subagente `experimentador` el 2026-10-16, en el Baseplate de prueba, con un `Body` de prueba dueño del cliente. Los detalles están en la rama `exp/hitbox`, archivo `exp/hitbox/RESULTADOS.md`.

| Pregunta | Resultado |
| --- | --- |
| **`BindToCollisionSummaries`** | **Funciona.**<ul><li>A 30, 60 y 120 studs/s contra una pared, la velocidad relativa normal da 30, 60 y 120 exactos.</li><li>Contra un poste de 0,5 detecta 8 de 8 golpes a 120 studs/s, y también a 200 y 300.</li><li>Solo llega en el cliente dueño de red. En el servidor no llega nada.</li><li>El signo depende del orden de las partes, así que se usa el valor absoluto.</li><li>`Area` no es confiable.</li><li>El piso genera un resumen por frame mientras está apoyado: se filtra con un umbral.</li></ul> |
| **30 cajas `Massless` soldadas** | **No cambian nada:** la masa, el centro de masa y la inercia quedan iguales (±0,02%). Con masa sí cambian. Con un auto, el costo es imperceptible (~0,01 ms por caja en contacto continuo). |
| **`MeshPart.TextureID` en juego** | **Se puede cambiar** desde un `Script` (replica) y desde un `LocalScript` (solo local), sin error. Que se vea en pantalla no se confirmó: se prueba en el WP de adaptadores. |
| **Pieza que se cae** | **P1** (ocultar y clonar en el cliente) no cambia el dueño de red y no deja efectos persistentes. **P2** (romper la soldadura en el cliente) deja el servidor y el cliente inconsistentes, así que se descarta. El clon se crea **sin colisión durante 0,2 s** y separado del auto, para evitar el golpe que se midió en el frame del evento. |

**Consecuencias:** se confirman D1, C1, P1 y A1. T1 queda condicionada a verlo en pantalla. El daño se calcula en el cliente: es el único lado que recibe los resúmenes.

## Las piezas

**Exteriores**, con caja de colisión propia:
- base del chasis (golpes de abajo), capot, baúl y techo;
- puertas (N), paragolpes delantero y trasero, y parrilla;
- guardabarros (4) y zócalos (2);
- parabrisas, luneta, ventanas y espejos;
- luces (todas las que haya) y ruedas (4).

**Interiores**, sin colisión, que se dañan a través de las exteriores que las cubren:
- motor, radiador y caja de cambios;
- suspensión (una por rueda) y dirección;
- tanque de combustible.

Cada auto declara qué exteriores cubren a cada interior, con un factor. Por ejemplo, la parrilla y el paragolpes delantero cubren al radiador.

## Efecto de cada pieza (propuesta)

| Pieza | Efecto según la vida (de 100 a 0) | A 0: se cae |
| --- | --- | --- |
| Motor | La potencia baja en proporción | El auto no tiene empuje |
| Radiador | Sube un "recalentamiento" que baja la potencia del motor | El motor pierde mucha potencia |
| Caja | Los cambios tardan más (`SHIFT_DURATION`) | Se traba en una marcha |
| Suspensión (por rueda) | Rueda torcida: el auto tira para ese lado y esa rueda agarra menos | La rueda casi no agarra |
| Dirección | Volante desalineado (desvío fijo) | Desvío grande |
| Ruedas | Agarre de esa rueda en proporción | Se cae la rueda |
| Tanque | **Pierde combustible:** no hay combustible en el MVP; ver decisión 7 | — |
| Capot, baúl, puertas, techo, guardabarros, zócalos, paragolpes y parrilla | Solo visual. **Protegen a las interiores** | Se cae; lo que cubría queda expuesto |
| Vidrios, espejos y luces | Solo visual | Se cae o se rompe |
| Base del chasis | Protege suspensión, tanque y caja de golpes de abajo | Se cae; lo de abajo queda expuesto |

**Daño por golpe:**
- `daño = K_pieza · max(0, v_impacto − umbral)²`, donde `v_impacto` es la velocidad relativa en la dirección de la normal;
- el cuadrado hace que los roces casi no dañen y que los choques fuertes sí;
- `K_pieza` y el umbral van en la configuración de cada auto.

**Desgaste:** en el MVP sube con cada golpe, una fracción del daño (`WEAR_PER_DAMAGE`). Sin reparación todavía, en el MVP el desgaste solo queda registrado, preparado para cuando exista el taller.

## Opciones

### Decisión 1: detección de golpes

- **D1. `BindToCollisionSummaries` por caja (recomendada).** Da qué, dónde y a qué velocidad. Es la vía oficial.
  - **Riesgo:** es muy nueva. Se confirma con el experimento 1.
- **D2. `Touched` más la velocidad del auto.** Es simple, pero sin punto ni fuerza, y pierde golpes a velocidad.
- **D3. Barridos propios (`Blockcast`) por frame.** Control total, pero cuesta cada frame y no ve lo que el motor de física resuelve.

### Decisión 2: cajas de colisión

- **C1. Cajas `Massless` y con colisión, soldadas al `Body` (recomendada).** No cambian el manejo, porque el centro de masa y la inercia quedan como hoy (WP-7). En un grupo de colisión propio del auto, para que no choquen entre sí ni con los rayos de las ruedas.
- **C2. Cajas con masa.** Es más real, pero cambia el centro de masa y obliga a reafinar el manejo.
- **C3. Cajas solo para consultas, sin colisión.** No sirven con D1, porque los resúmenes de colisión necesitan `CanCollide = true`.

### Decisión 3: cuando una pieza se cae

- **P1. Ocultar la pieza del auto y crear un clon suelto, solo en el cliente (recomendada).** No toca las soldaduras del auto que simula el cliente, así que esquiva los problemas conocidos. El clon es solo visual, y se borra a los N segundos o si se acumulan más de M.
- **P2. Romper la soldadura en el cliente.** Es lo más directo, pero tiene problemas conocidos de réplica y de dueño de red.
- **P3. Que el servidor cree la pieza suelta.** Todos la ven, pero con un solo jugador no hace falta, y suma latencia.

### Decisión 4: texturas de daño

- **T1. Cambiar `MeshPart.TextureID` por estado (recomendada si el experimento 4 confirma que se puede).** De 3 a 5 texturas por pieza, sin `SurfaceAppearance`.
- **T2. Varias `SurfaceAppearance` armadas de antemano, que se intercambian.** Tiene más calidad (PBR), pero lleva N instancias por pieza y el costo de intercambiarlas no está confirmado.

### Decisión 5: quién calcula el daño

- **A1. El cliente, junto con la física (recomendada para el MVP).** Sin latencia y simple. El servidor recibe el estado por `RemoteEvent` con límite de frecuencia, para cuando haga falta guardarlo.
- **A2. El cliente calcula y el servidor valida rangos.** Cuando el desgaste se guarde entre partidas, después del MVP.

### Decisión 6: el editor

- **E1. Plugin de Studio sobre las herramientas nativas (recomendada).** Cada pieza es una `Part` con atributos (tipo e índice). Se mueve y escala con Mover y Escalar de Studio, con deshacer. Un botón exporta la configuración como texto Luau, para pegarla en el archivo de configuración del auto y subirla por PR.
- **E2. Plugin con manipuladores propios (`Handles`).** Más control, como espejar izquierda y derecha, pero mucho más trabajo.

### Decisión 7: el tanque de combustible

El tanque "pierde combustible", pero hoy **no hay combustible**. Las opciones:
- **F1. Tanque sin efecto en el MVP, solo visual (recomendada).** El combustible va con las ideas del #63.
- **F2. Sumar combustible al MVP:** consumo, tanque y quedarse sin nafta. Es una mecánica nueva.

## Arquitectura (propuesta)

Sigue las capas de siempre: contratos, núcleo, adaptadores y arranque.

**Núcleo (`src/vehicle/core/damage/`, puro, en el CLI):**
- **`DamageConfig`:** las fichas de cada pieza (tipo, `K`, umbral, efecto y qué interiores protege con qué factor). Va dentro de `ChassisSpec`.
- **`DamageModel`:**
  - `newState(spec)`;
  - `applyImpact(state, pieceId, impactSpeed, spec)`: devuelve el estado nuevo y los eventos, por ejemplo "la pieza X se cayó";
  - el daño pasa a las interiores según los factores.
- **`DamageEffects.apply(settings, damageState)`:** devuelve una **copia** de la configuración del simulador con los efectos aplicados (potencia, agarre por rueda, desvío de la dirección, tiempo de cambio). El simulador **no cambia**: recibe otra configuración. Se apoya en que la configuración ya se inyecta por parámetro.

**Adaptadores (cliente, salvo donde se aclara):**
- **`HitboxBuilder` (servidor, al armar el auto):** crea las cajas desde la ficha, `Massless` y en su grupo de colisión, soldadas al `Body`.
- **`CollisionReader`:** se suscribe con `BindToCollisionSummaries` a cada caja y convierte cada resumen en `(pieceId, impactSpeed)`.
- **`DamageVisuals`:** cambia texturas y oculta la pieza, y crea y limpia los clones sueltos.
- **`DamageReporter`:** manda el estado al servidor con límite de frecuencia. En el MVP solo se registra.
- **Plugin `HitboxEditor`:** en una carpeta de herramientas de Studio, fuera de `src/`, porque no corre en el juego.

**Patrones y por qué:**
- **Datos más un núcleo puro:** las piezas son fichas; el daño y los efectos se prueban en el CLI.
- **Modificador de configuración (`DamageEffects`):** el daño cambia el manejo **sin tocar el simulador**, y es la misma idea del ensamblador de piezas del #63.
- **Observador:** `CollisionReader` emite golpes y el modelo de daño los consume.

## Plan de trabajo

1. **Experimento `exp/hitbox`, primero.** Confirma lo incierto:
   - que `BindToCollisionSummaries` funcione a velocidad de rally;
   - que 30 cajas `Massless` no cambien la masa ni el centro de masa, y cuánto cuestan;
   - que se pueda cambiar `TextureID` en pleno juego;
   - el método P1 de desprender piezas.
2. **WP: núcleo del daño** (`DamageConfig`, `DamageModel` y `DamageEffects`) con sus pruebas.
3. **WP: adaptadores** (cajas, detección, efectos visuales y piezas que se caen).
4. **WP: plugin del editor.**
5. **Las texturas de daño de cada pieza las hace Nico** (`necesita-humano`).

## Decisión

Decidió Nico el 2026-10-16: **las 7 recomendaciones** (D1, C1, P1, T1, A1, E1 y F1), y **la hitbox modular vuelve al MVP**.

- La reparación queda para después del MVP.
- Si el experimento `exp/hitbox` (#82) muestra que alguna opción no funciona, se vuelve a decidir con los números.
