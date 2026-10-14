# Rally procedural (Roblox) — Requerimientos del MVP

Oct 14, 2026 · @Nicolas Orona

## Qué es el MVP

Un jugador maneja por una ruta de rally infinita con un auto propio que se siente bien. Nada más: sin enemigos, sin progresión, sin multijugador.

El MVP responde una sola pregunta: **¿manejar acá es divertido por sí solo?** Si la respuesta es sí, todo lo demás se construye encima. Si es no, no hay contenido que lo salve.

**Terminado significa:** alguien que no participó del desarrollo juega 15 minutos seguidos sin que se lo pidan, y al final quiere seguir.

## Alcance

Un solo bioma, un solo auto, un solo jugador. Los biomas múltiples salen del MVP a propósito: agregan trabajo de generación sin responder si el manejo es divertido.

| Entra | Queda afuera |
| --- | --- |
| Ruta procedural infinita con curvas variadas | Varios biomas y transiciones |
| Un bioma (tierra con bosque) | Túneles, puentes, prefabs |
| Árboles y rocas con colisión al costado | Tránsito, zombies, armas |
| Un auto con modelo de conducción propio | Varios autos, mejoras por piezas |
| Modo arcade con caja automática | Caja manual y embrague |
| Teclado con suavizado y gamepad | Mouse como volante, espejos |
| Cámara de persecución + mirar atrás | Multijugador y modo chaos |
| Sonido, partículas y marcas de derrape | Loot, muerte, progresión |
| Contador de distancia y botón de reset | Dificultad escalable, bifurcaciones |

## Calles infinitas

La ruta se genera por tramos delante del auto, se libera lo que queda atrás y nunca se nota el corte.

**Generación**

- **RC-1** Ruta generada a partir de una semilla: misma semilla, misma ruta (necesario para probar y repetir bugs).
- **RC-2** Tramos generados por delante del jugador con un margen suficiente para no verlos aparecer.
- **RC-3** Tramos que quedan atrás se liberan; los objetos se devuelven a una pool para reusarse.
- **RC-4** Continuidad: entre tramos no hay saltos de dirección, altura ni ancho. El auto no tiene que sentir dónde termina un tramo.

**Diseño de la ruta**

- **RC-5** Variedad de curvas: rectas cortas, curvas abiertas, curvas cerradas y encadenadas (S). Nunca una curva imposible de tomar a velocidad razonable.
- **RC-6** Pendientes suaves de subida y bajada; el terreno sigue a la ruta y no al revés.
- **RC-7** La ruta tiene un ancho fijo para el MVP y una superficie de tierra con fricción propia.

**Terreno al costado**

- **RC-8** Terreno transitable a ambos lados, lo bastante ancho para salirse y volver a la ruta.
- **RC-9** Árboles y rocas al costado con colisión cerca del auto (activación por distancia, con histéresis). Salirse tiene que tener riesgo.
- **RC-10** Decorado lejano sin colisión y en baja calidad.
- **RC-11** El terreno se arma con pocas mallas grandes, no con muchas Parts chicas.

**Recuperación**

- **RC-12** Si el auto vuelca, se traba o cae fuera del mundo, un botón lo devuelve a la ruta, sobre el tramo más cercano, mirando hacia adelante.

## Conducción pulida

El auto default de Roblox se descarta; el MVP usa un modelo propio pensado para derrapar. "Pulido" se define por sensaciones verificables, no por realismo.

**Modelo del auto**

- **CP-1** Derrape controlable: se puede iniciar (freno, cambio brusco de peso, acelerar en curva), sostener con acelerador y volante, y cortar enderezando.
- **CP-2** Peso perceptible: al frenar la trompa carga, al acelerar se aliviana, en curva se inclina. Se nota en el agarre, no solo visualmente.
- **CP-3** Agarre distinto en ruta (tierra) y fuera de ruta (pasto o barro): salirse cuesta velocidad y control.
- **CP-4** Caja automática con cambios que se escuchan y se sienten (breve pérdida de empuje).
- **CP-5** Choques con consecuencia pero sin frustración: el auto rebota o se frena, no sale disparado por bugs de física.
- **CP-6** Todos los parámetros del auto (agarre, peso, potencia, frenos, dirección) expuestos en un solo lugar para ajustar sin tocar código.

**Controles**

- **CP-7** Teclado: volante, acelerador y freno con suavizado (rampa de subida y de retorno, ajustables por separado).
- **CP-9** Freno de mano en tecla y botón propios, como herramienta principal para iniciar derrapes.
- **CP-10** La dirección se vuelve menos sensible a alta velocidad, para que el auto no sea nervioso en rectas.

**Cámara**

- **CP-11** Cámara de persecución que acompaña con algo de retraso: se abre en el derrape y deja ver hacia dónde va el auto, no solo hacia dónde apunta.
- **CP-12** Tecla para mirar atrás mientras se mantiene apretada.

**Feedback**

- **CP-13** Sonido de motor que sigue las RPM y los cambios.
- **CP-14** Chirrido o arrastre de neumáticos proporcional al deslizamiento.
- **CP-15** Polvo y marcas en el suelo durante el derrape (con límite de cantidad y vida corta).
- **CP-16** HUD mínimo: velocidad, marcha y distancia recorrida.

## Rendimiento

Objetivos iniciales propuestos; se ajustan cuando haya mediciones reales.

| Métrica | PC | Celular gama media |
| --- | --- | --- |
| FPS estable | 60 | 30 |
| Tirones al generar o liberar tramos | Ninguno perceptible | Ninguno perceptible |
| Sesión continua sin degradación | 30 min | 30 min |

- **RN-1** Memoria e instancias activas estables en el tiempo: si suben sin parar, algo no se está liberando.
- **RN-2** La física del auto corre en el cliente del jugador (dueño de red) para que la respuesta sea inmediata.

## Criterios de aceptación

El MVP se da por terminado cuando todo esto se cumple.

- [ ] Manejar 30 minutos seguidos sin que la ruta se corte, se repita visiblemente o el juego se trabe.
- [ ] No se percibe dónde empieza y termina cada tramo.
- [ ] Un jugador nuevo logra derrapar a propósito en menos de 5 minutos.
- [ ] Tomar una curva cerrada bien se siente distinto a tomarla mal (la línea importa).
- [ ] Salirse de la ruta cuesta tiempo o termina en choque.
- [ ] Se juega cómodo con teclado y con gamepad.
- [ ] El botón de reset resuelve cualquier vuelco o traba.
- [ ] Se cumplen los objetivos de rendimiento en PC y en un celular de prueba.
- [ ] Dos personas ajenas al desarrollo juegan 15 minutos sin que se lo pidan y quieren seguir.

## Decisiones abiertas

Hay que resolverlas antes de programar; cada una cambia cómo se construye.

1. **Modelo de física del auto:** sobre las restricciones físicas de Roblox (ruedas con constraints) o un modelo propio por raycast. El raycast da más control sobre el derrape; los constraints son más rápidos de armar.
2. **Representación de la ruta:** spline o puntos de control, y cómo se arma la malla a partir de eso.
3. **Cómo se genera el terreno:** Terrain de Roblox o mallas propias. Afecta rendimiento y cómo la ruta esculpe el suelo.
4. **Tipo de auto:** rally liviano tracción total, o trasera (derrapa más fácil, es más difícil de controlar).
5. **Reparto con Ariel:** quién toma calles infinitas y quién conducción, ya que se pueden trabajar en paralelo.
