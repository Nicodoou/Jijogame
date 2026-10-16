# Reglas de trabajo

Estas reglas valen para todo el trabajo del proyecto: código, assets, documentación y decisiones. Las cumplen los agentes y las personas. Son obligatorias. Si una tarea las contradice, frená y preguntá.

## Regla principal: todo se hace por subagentes

Cada agente del proyecto (A y B) es un **orquestador que corre en Opus**. No escribe código ni investiga por su cuenta: habla con su persona, arma los WPs, define y lanza subagentes y revisa lo que entregan.

### Subagentes

- **Al definir un WP se define también el subagente que lo ejecuta.** Opus elige cuál: tipo, modelo y herramientas, según lo que pida el trabajo.
- Las definiciones viven en `.claude/agents/<nombre>.md`. Si ya existe un subagente que sirve, se reutiliza en vez de crear otro.
- **Opus define el contexto del subagente.** El subagente no ve la conversación, así que Opus le arma en el WP la sección "Contexto para el subagente". Ahí va todo lo que necesita y nada más: archivos y documentos a leer, decisiones que aplican, supuestos vigentes y lo relevante que se habló con la persona, resumido.
- Toda decisión que Opus pase en el contexto tiene que estar también en `docs/decisiones.md`. El contexto resume, no decide.
- Si el subagente reporta que le falta contexto, Opus lo completa en el WP y lo vuelve a lanzar.
- **El subagente no decide ni habla con la persona.** Si encuentra algo fuera del WP, una contradicción o una decisión pendiente, frena y se lo reporta al orquestador.
- Un subagente por WP. Si corren varios en paralelo, cada uno trabaja en su propio worktree y sobre archivos distintos.
- La investigación de la fase de diseño también la hace un subagente. El orquestador arma las opciones con lo que devuelve y las presenta.
- **El que hizo el trabajo no lo aprueba.** Antes del PR, el orquestador verifica la entrega contra los criterios de aceptación del WP, y puede usar otro subagente distinto para revisarla.

### Pruebas y consultas del subagente

**El subagente corre las pruebas**, las programadas y la parte automatizable de las manuales, antes de entregar.

**Cuándo frena.** Si algo no le cierra, frena el flujo en vez de resolverlo por su cuenta. Frena cuando:

- Falla una prueba que no esperaba que fallara, incluidas las que no tocó.
- Una prueba falla y no sabe explicar por qué.
- La cobertura queda por debajo del mínimo y no puede subirla dentro del WP.
- El WP es ambiguo, se contradice o choca con otro documento.
- Para seguir tendría que salirse del WP.

Que una prueba nueva falle mientras el subagente escribe el código que la hace pasar es parte normal del trabajo y no es motivo para frenar.

**Cómo frena.** Termina su ejecución y le devuelve a Opus un reporte:

```markdown
**Frené en:** qué estaba haciendo
**Qué pasó:** qué esperaba y qué obtuve (con la salida de la prueba si aplica)
**Lo que ya descarté:**
**Pregunta concreta:**
**Opciones que veo:** si las hay
```

**Qué hace Opus:**

1. **Si la respuesta está en el WP, en `docs/` o en una decisión ya tomada**, Opus la resuelve. Retoma el mismo subagente con la respuesta y con la referencia de dónde sale.
2. **Si es ambiguo**, o la respuesta implicaría una decisión nueva o un cambio de alcance, Opus no decide. Le lleva la pregunta a su persona con las opciones, y le pasa al subagente lo que la persona responda.
3. Lo que se resolvió queda escrito. Si cambia el WP, se actualiza el WP. Si es una decisión nueva, va a `docs/decisiones.md`. Si fue un bug, sigue el proceso de bugs.

Opus nunca le contesta al subagente con una suposición propia. Si no puede citar de dónde sale la respuesta, la pregunta va a la persona.

### Compactar la sesión

**Siempre que se termina una sección del código, se compacta la sesión.** Compactar resume la conversación y descarta detalle, así que lo que no esté guardado se pierde. El orden es obligatorio:

1. **Guardar el estado:** comentario de cierre en el issue, entrada del diario y documentos actualizados (WP, diseño, bugs, decisiones).
2. **Opus escribe sus memorias** (ver abajo).
3. **Compactar** (`/compact`), indicando qué conservar: WP en curso, siguiente paso y supuestos activos.
4. **Releer** la memoria propia y el comentario de cierre antes de seguir.

### Memoria de Opus

Cada orquestador tiene su memoria en el cuerpo de un issue fijado, con etiqueta `memoria`: **"Memoria — Agente A"** y **"Memoria — Agente B"**. No se cierra nunca.

- **Es el estado actual, no un historial.** Se reescribe entera cada vez; lo que ya no aplica se borra. El historial está en el diario.
- Va en un issue y no en un archivo para que sobreviva aunque se pierda la rama o la máquina, y para que se vea al instante.

```markdown
# Memoria — Agente A

**Actualizada:** AAAA-MM-DD

## En curso
WP, estado y siguiente paso concreto.

## Decisiones vigentes que estoy aplicando
Con link a `docs/decisiones.md`.

## Supuestos activos

## Lo que aprendí del proyecto
Cómo está armado el código, dónde están las cosas, trampas del motor.

## Cómo trabaja mi persona
Preferencias y formas de trabajo que me pidió.

## No repetir
Errores cometidos y qué hacer en su lugar.
```

## 1. Alcance: el paquete de trabajo (WP)

**Se hace lo que dice el WP, y nada más.** Nada de features extra, refactors no pedidos ni "mejoras de paso". Si el agente ve algo que mejoraría, lo deja en una nota o en un issue nuevo, no lo hace.

Cada tarea tiene su WP en `docs/wp/WP-<número>-<tema>.md`:

```markdown
# WP-<número> — Título

**Issue:** #N
**Requerimientos:** RC-x / CP-x
**Diseño:** docs/disenos/<tema>.md
**Responsable:** Agente A | Agente B

## Subagente
- **Nombre:** `.claude/agents/<nombre>.md` (nuevo o existente)
- **Modelo:** cuál y por qué
- **Herramientas permitidas:**
- **Entrega:** qué devuelve al orquestador

## Contexto para el subagente
Lo escribe Opus. Tiene que alcanzar para trabajar sin la conversación.
- **Leer:** archivos y documentos necesarios, nada más.
- **Decisiones que aplican:** con link a `docs/decisiones.md`.
- **Supuestos vigentes:**
- **De la conversación con la persona:** lo relevante, resumido.
- **Contratos que usa o provee:**

## Objetivo
Una o dos líneas.

## Entregables
- Qué tiene que existir al terminar (módulos, pruebas, documentos).

## Fuera de alcance
- Lo que explícitamente no se hace en este WP.

## Criterios de aceptación
- [ ] Condición verificable.

## Pruebas manuales
- [ ] Qué se prueba a mano y qué se intenta romper.
```

- El WP lo redacta el agente y lo aprueba su persona. **Con esa aprobación, el agente mergea el WP a `main`** (ver el paso Merge en `docs/coordinacion-agentes.md`). Sin WP en `main`, no se empieza.
- Si durante el trabajo aparece algo que el WP no cubre, se frena y se pide actualizar el WP. No se resuelve por cuenta propia.

## 2. Proceso antes de escribir código

**Nunca se escribe código sin pasar por estos pasos, en este orden.** Saltear uno es motivo para descartar el trabajo.

| Paso | Qué se hace | Qué queda escrito |
| --- | --- | --- |
| 1. Investigar | Cómo se resuelve bien este problema: documentación oficial de Roblox, enfoques conocidos, limitaciones del motor | Sección "Investigación" del documento de diseño |
| 2. Presentar opciones | Si hay más de una forma, se explican **todas**, con lo bueno, lo malo y lo riesgoso de cada una | Sección "Opciones" |
| 3. Decide el humano | El agente puede recomendar, marcándolo como recomendación. Decide la persona | Sección "Decisión" + `docs/decisiones.md` |
| 4. Arquitectura | Capas, responsabilidades de cada una y patrones de diseño, con el porqué de cada patrón | Sección "Arquitectura" |
| 5. Aprobación | La persona aprueba la arquitectura de forma explícita | Comentario "Aprobado" en el issue |
| 6. WP | Se redacta el WP sobre la arquitectura aprobada y se mergea | `docs/wp/` |
| 7. Implementar | Recién acá se escribe código, siguiendo el WP | Código + pruebas + PR |

### Documento de diseño

Cada problema tiene su documento en `docs/disenos/<tema>.md`:

```markdown
# Tema

**Issue:** #N
**Requerimientos:** RC-x / CP-x
**Estado:** investigando | opciones presentadas | decidido | arquitectura propuesta | aprobado | implementado

## Investigación
Qué se averiguó y de dónde (con links).

## Opciones
### Opción 1 — Nombre
- **Bueno:**
- **Malo:**
- **Riesgoso:**
- **Funciona bien cuando:**
- **Deja de funcionar cuando:**

### Opción 2 — Nombre
(igual)

**Recomendación del agente:** cuál y por qué.

## Decisión
Qué eligió la persona y por qué.

## Arquitectura
Capas, qué hace cada una, qué no hace, cómo se comunican y qué patrones se usan.

## Aprobación
Quién aprobó, fecha y link al comentario.
```

### Quién aprueba

- Un problema dentro del área de un agente: la persona que trabaja con ese agente.
- Un problema que toca un contrato o el área del otro: las dos personas.

Si la arquitectura aprobada resulta no servir durante la implementación, **se frena**, se documenta por qué y se vuelve al paso 4. No se cambia la arquitectura sobre la marcha.

### Presentar un WP o un PR a la persona

Pedido de Nico (2026-10-16): los WPs y los PRs se presentaban de forma muy vaga, con dos o tres preguntas semiabiertas, y así la persona no tiene control. **Todo WP y todo PR de código que se pida aprobar se presenta en el chat con esta estructura, en este orden.** El WP o el PR tiene el detalle completo; la presentación es lo que la persona tiene que leer para decidir.

1. **Qué hace, en concreto:** qué va a poder hacer o ver la persona cuando esté, y qué no.
2. **Módulos y responsabilidades:** cada módulo nuevo o cambiado, en una línea, con la capa a la que pertenece (núcleo, adaptador, arranque o contrato).
3. **Patrones y por qué:** cada patrón usado (por ejemplo, núcleo puro con `step`, configuración como datos, composición, estrategia u observador), con el problema que resuelve en este WP. Si no se usa ninguno nuevo, se dice.
4. **Alternativas descartadas:** qué otra forma había y por qué no.
5. **Riesgos y supuestos:** lo que puede salir mal y lo que todavía no está medido.
6. **Opinión del orquestador sobre el código** (solo en PRs de código): lo que está bien, lo que está flojo, la deuda que queda y si se pasa de algún límite (líneas, funciones, cobertura). Basada en haber leído el código, no solo el informe del subagente.
7. **Qué prueban las pruebas y qué no:** los números que importan y lo que queda para la prueba manual.
8. **Decisiones que tiene que tomar la persona:** cerradas, cada una con las opciones, lo que implica cada una y la recomendación. Nada de "¿te parece bien?" sin opciones.

Si algo de esto no aplica, se dice "no aplica" en vez de omitirlo.

### Experimentos

A veces investigar requiere probar código (por ejemplo, ver cómo se comporta la física de Roblox). Para eso existen las ramas `exp/<tema>`:

- **Son descartables.** Nunca se mergean y nunca se reutiliza su código tal cual. Si el experimento funcionó, se reescribe siguiendo todo el proceso.
- Lo que se aprendió se documenta en la sección "Investigación" del diseño, con link a la rama.
- No necesitan aprobación previa, pero sí un issue que diga qué se quiere averiguar.

## 3. Arquitectura

- **Por capas.** Cada capa tiene una responsabilidad y sabe lo mínimo de las demás.
- **Sin pisarse entre capas.** Las dependencias van en una sola dirección. Una capa no salta a otra que no le corresponde ni usa sus detalles internos.
- **Comunicación por interfaces.** Las capas y las áreas se hablan por funciones públicas definidas, nunca tocando el estado interno de otra.
- **Patrones de diseño con justificación.** Cada patrón usado se nombra en el documento de diseño con el problema que resuelve. Si no resuelve nada, no se usa.
- **Sin estado global.** Nada de singletons ni estado compartido escondido. Cada módulo recibe lo que necesita de forma explícita (por parámetros o al construirse), armado en un único punto de arranque.

### Cliente y servidor

En Roblox, el cliente está en manos del jugador y puede ser modificado. Por eso:

- **El servidor es la autoridad.** Las reglas del juego, la generación del mundo y todo lo que afecta a otros jugadores se deciden en el servidor.
- **El servidor nunca confía en el cliente.** Todo lo que llega por un `RemoteEvent` o `RemoteFunction` se valida: tipo, rango y si es posible en ese momento.
- **El cliente se ocupa de:** input, cámara, efectos visuales y sonoros, interfaz y la física del propio auto (para que responda al instante, RN-2).
- **Como la física del auto corre en el cliente**, el servidor controla que lo que reporta sea creíble (velocidades, posiciones, saltos de lugar) y corrige o descarta lo que no lo sea.
- Los eventos remotos tienen límite de frecuencia por jugador.
- La separación cliente/servidor se respeta en las carpetas: código de servidor, código de cliente y código compartido, sin mezclarse.

## 4. Código

### Funciones

- **Una sola tarea por función.** Si para describir lo que hace hace falta un "y", son dos funciones.
- Cortas y legibles de arriba abajo.

### Módulos y clases

- **Archivos chicos.** Un módulo resuelve una cosa. Si crece, se divide.
- **API pública chica.** Lo que un módulo expone es lo mínimo necesario; el resto queda privado.
- Si hay clases públicas, chicas y con una responsabilidad.

Valores de referencia (se ajustan con la experiencia):

| Elemento | Límite orientativo |
| --- | --- |
| Función | 30 líneas |
| Archivo | 200 líneas |
| Funciones públicas por módulo | 7 |

Pasarse no es automáticamente un error, pero obliga a justificarlo en el PR.

### Idioma

- **Código en inglés:** nombres de variables, funciones, módulos, tipos y archivos.
- **Documentación en español.**
- **Comentarios en español.**
- Los textos que ve el jugador van en archivos aparte, nunca escritos dentro de la lógica.

### Nombres: el código se explica solo

El código tiene que entenderse leyendo los nombres, sin necesitar comentarios.

- **Funciones:** empiezan con un verbo y dicen qué hacen: `generateSegment`, `releaseChunk`, `applySurfaceGrip`.
- **Booleanos:** se leen como pregunta: `isDrifting`, `hasCollision`, `shouldRespawn`.
- **Variables:** dicen qué contienen y, si aplica, en qué unidad: `maxSpeedStuds`, `lodDistanceFar`, `rampUpSeconds`.
- **Sin abreviaturas** salvo las universales (`id`, `max`, `min`). Nada de `tmp`, `val`, `obj`, `data` o `x` sueltos. Una letra solo para índices de bucles cortos.
- **Un concepto, un nombre.** Si a algo se le dice "tramo", es `segment` en todo el proyecto. La tabla de nombres vive en `docs/nombres.md` y se consulta antes de nombrar algo nuevo.
- **Convenciones de Luau:**

| Elemento | Formato | Ejemplo |
| --- | --- | --- |
| Variables y funciones | camelCase | `currentSpeed` |
| Módulos, clases y tipos | PascalCase | `RoadGenerator` |
| Constantes | UPPER_SNAKE_CASE | `MAX_ACTIVE_CHUNKS` |
| Privado dentro de un módulo | prefijo `_` | `_recycleSegment` |

### Comentarios

- **Por defecto, sin comentarios.** Si hace falta un comentario para entender qué hace el código, primero se mejoran los nombres o se divide la función.
- Solo se comenta **el porqué** cuando no es obvio: una limitación de Roblox, un valor que parece raro pero es correcto, una decisión documentada (con link).
- Nunca comentarios que repitan lo que dice el código.

### Limpieza

Nada de esto llega a un PR:

- Código comentado.
- Variables, funciones, parámetros o módulos sin usar.
- `print` y código de depuración.
- Archivos o assets que ya no se usan.
- `TODO` sin issue asociado (se escribe `-- TODO(#N): ...` o no se escribe).

### Configuración

- **Sin números mágicos.** Todo valor de ajuste va a configuración: agarre, peso, potencia, distancias de LOD, tamaños de tramo, rampas de input.
- La configuración vive en módulos propios de configuración, separados de la lógica, con nombre y unidad en cada valor.
- Los valores fijos del motor de Roblox, que no se ajustan, van a constantes con nombre.

### Rendimiento

- **Primero limpio, después rápido.** Se mide antes de optimizar (MicroProfiler y estadísticas de Studio). No se optimiza por suposición.
- Solo se sacrifica limpieza por velocidad en código que corre muy seguido (por frame o por tick) y cuando la medición lo justifica.
- **Cuando se sacrifica limpieza, se documenta en detalle** al lado del código y en el PR: qué hace paso a paso, por qué está escrito así, cuánto mejoró la medición y cómo se vería la versión limpia. Tiene que poder seguirlo alguien que no lo escribió.

## 5. Pruebas

**Todo se prueba, buscando que falle.** Probar solo el camino feliz no cuenta. Las pruebas las corre el subagente que hizo el trabajo, y frena ante cualquier falla que no pueda explicar (ver la regla principal).

### Programadas

- Toda lógica del juego llega con sus pruebas automáticas.
- Las pruebas son deterministas: azar con semilla fija y tiempo falso. La misma prueba da siempre el mismo resultado.
- Cada prueba verifica una cosa y su nombre dice cuál.
- Se prueban los bordes: valores en cero, máximos, negativos, vacíos, y lo que pasa justo en los límites (por ejemplo, la histéresis del LOD).

### Cobertura

- **Mínimo 87% de cobertura del código.** Un PR que la baje del mínimo no se mergea.
- **Pendiente obligatorio:** confirmar en la investigación inicial qué herramienta mide cobertura en Luau y qué partes del código puede medir. Si no hay una herramienta confiable, esta regla se redefine antes de escribir código.

### Manuales

- Cada PR incluye una lista de pruebas manuales en Studio que cubre todo lo que cambió.
- Las pruebas manuales buscan romper: manejar mal a propósito, chocar, volcar, salirse del mapa, apretar teclas al mismo tiempo.
- El "feel" (si el manejo se siente bien) solo lo puede juzgar una persona. Se pide con un issue `prueba-de-juego`.

## 6. Documentación

**Se documenta todo.** Lo que no está escrito, para el proyecto no pasó.

| Qué | Dónde |
| --- | --- |
| Paquetes de trabajo | `docs/wp/` |
| Diseño de cada problema | `docs/disenos/` |
| Decisiones tomadas | `docs/decisiones.md` |
| Nombres del proyecto | `docs/nombres.md` |
| Bugs | `docs/bugs/` (proceso en `docs/resolucion-de-bugs.md`) |
| Hallazgos e ideas | Notas (ver coordinación) |
| Razonamiento de cada sesión | Diario (ver coordinación) |

Toda decisión o enfoque se documenta con:

- **Lo bueno.**
- **Lo malo.**
- **Lo riesgoso.**
- **Bajo qué condiciones** funciona y bajo cuáles deja de funcionar.
- **Qué se descartó** y por qué.

## 7. Bugs

Ningún bug se arregla probando cosas. El proceso es obligatorio y está en [`docs/resolucion-de-bugs.md`](resolucion-de-bugs.md).

## 8. Revertibilidad

**Todo tiene que poder deshacerse.** El objetivo es no hacer nunca parches sobre parches.

- Commits chicos: un cambio lógico por commit.
- Cada commit deja el proyecto funcionando y con las pruebas pasando.
- Un cambio que no funcionó se revierte entero antes de intentar otra cosa. Nunca se acumulan intentos.
- **Si un arreglo necesita otro arreglo, se revierten los dos** y se vuelve al análisis.
- Los cambios grandes van por partes que se puedan revertir por separado.
