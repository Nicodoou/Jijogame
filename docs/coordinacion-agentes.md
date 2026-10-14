# Coordinación entre agentes

Este proyecto lo programan dos agentes, cada uno trabajando con una persona: **Agente A** con Nico y **Agente B** con Beni. Cada agente es un orquestador en Opus que trabaja por subagentes (ver la regla principal de `docs/reglas-de-trabajo.md`). Los agentes no comparten memoria entre sesiones. Todo lo que necesite saber el otro agente, o uno mismo en la próxima sesión, queda escrito en GitHub o en `docs/`.

Leé este archivo entero antes de cualquier tarea.

## 1. Principios

1. **GitHub es la única fuente de verdad.** Si no está en un issue, un PR o `docs/`, no existe. No se asume nada de una conversación que el otro agente no vio.
2. **Un dueño por área.** Cada agente modifica solo sus carpetas. Para tocar algo del otro, se pide por issue.
3. **Los contratos se cambian por acuerdo, nunca en silencio.** Las interfaces compartidas tienen su propio proceso (sección 5).
4. **Los humanos deciden; los agentes mergean con su aprobación.** Ningún agente mergea a `main` sin la aprobación explícita de su persona (sección 4, paso Merge).
5. **Ante la duda, frená y preguntá.** Un issue con pregunta es más barato que un día de trabajo en la dirección equivocada.

## 2. Herramientas del repositorio

El código de Roblox no vive en git por defecto (vive dentro del archivo del lugar). Para poder trabajar con agentes y GitHub, el código tiene que estar en archivos de texto.

- **Rojo:** sincroniza las carpetas del repo con Roblox Studio. El repo es la fuente de verdad, no el archivo `.rbxl`.
- **StyLua:** formato automático del código Luau.
- **Selene:** linter.
- **Pruebas:** framework de pruebas para Luau (a definir en la política de código).

> Pendiente: confirmar estas herramientas en la política de código.

## 3. Áreas y dueños

| Área | Dueño | Carpetas | Requerimientos del MVP |
| --- | --- | --- | --- |
| Calles infinitas (ruta, terreno, chunks, obstáculos) | Agente B | `src/world/` | RC-1 a RC-12 |
| Conducción (auto, controles, cámara, feedback) | Agente A | `src/vehicle/`, `src/input/`, `src/camera/` | CP-1 a CP-16 |
| Contratos compartidos | Ambos (por acuerdo) | `src/shared/contracts/` | — |
| Rendimiento | Ambos | — | RN-1, RN-2 |

> El reparto de áreas lo confirman Nico y Beni. Si cambia, se actualiza esta tabla antes de seguir.

Cada agente puede **leer** todo el repo. Solo **escribe** en sus carpetas, en `docs/` (lo que le corresponda) y en `src/shared/contracts/` siguiendo la sección 5.

## 4. Flujo de trabajo

**Una tarea = un issue = un WP = una rama = un PR.**

1. **Issue.** Toda tarea arranca como issue, con los IDs de requerimiento que cubre (ej.: `RC-3`). Si la tarea no tiene requerimiento, se pregunta antes de empezar.
1. **Diseño y WP.** Antes de programar, se sigue el proceso de `docs/reglas-de-trabajo.md` (investigación, opciones, decisión, arquitectura, aprobación). Termina con el WP mergeado en `main`. El trabajo cubre lo que dice el WP y nada más.
2. **Rama.** `a/<id>-<descripcion-corta>` o `b/<id>-<descripcion-corta>`. Ejemplo: `b/RC-3-pool-de-tramos`.
3. **Commits.** En español, en presente, con el ID: `RC-3: devuelve tramos liberados a la pool`.
4. **PR.** Usa la plantilla de la sección 8. Linkea el issue con `Closes #N`.
5. **Revisión.** Si el PR toca un contrato o algo que el otro agente usa, se lo asigna como revisor y espera su comentario.
6. **Merge.** Lo hace el agente dueño del PR, solo después de que su persona lo pruebe en Studio (si aplica) y le apruebe el merge de forma explícita. Si el PR toca un contrato o el área del otro, hace falta la aprobación de las dos personas. Antes de mergear, el agente deja un comentario en el PR con quién aprobó.

### Antes de empezar cada sesión

1. Leer la memoria propia (issue "Memoria — Agente A/B").
1. Leer este archivo y los documentos de `docs/` que toque la tarea.
2. Revisar issues abiertos con etiqueta `para-agente-a` o `para-agente-b` según corresponda.
3. Revisar PRs abiertos del otro agente que puedan afectar el área propia.
4. Revisar `docs/decisiones.md` por decisiones nuevas.
5. Revisar `docs/notas/` por notas nuevas desde la última sesión.
6. Leer las últimas 3 entradas del diario del otro agente y las 3 propias (sección 11).

### Al terminar cada sesión

Dejar un comentario en el issue en curso con:

- **Hecho:** qué quedó terminado.
- **En curso:** qué quedó a medias y en qué estado.
- **Siguiente:** el próximo paso concreto.
- **Bloqueos:** qué falta y de quién.

Ese comentario es lo primero que lee el agente en la próxima sesión.

Después, escribir la entrada del diario (sección 11).

## 5. Contratos entre áreas

Los dos sistemas se tocan en pocos puntos. Esos puntos son contratos: módulos en `src/shared/contracts/` que definen tipos y funciones, sin lógica.

Contratos previstos para el MVP:

| Contrato | Lo provee | Lo usa | Para qué |
| --- | --- | --- | --- |
| Punto de ruta más cercano (posición y dirección) | Agente B | Agente A | Reset del auto (RC-12) |
| Tipo de superficie en una posición | Agente B | Agente A | Agarre en ruta y fuera de ruta (CP-3) |
| Posición del jugador o del auto | Agente A | Agente B | Generar y liberar tramos (RC-2, RC-3) |

**Para cambiar un contrato:**

1. Issue con etiqueta `contrato`, con la firma actual, la propuesta y por qué.
2. El otro agente responde en el issue (acepta, propone otra cosa o pregunta).
3. Si hay acuerdo, el que lo propuso hace el PR, con el otro como revisor.
4. Si no hay acuerdo, se etiqueta `necesita-humano` y deciden Nico y Beni.

Mientras un contrato no exista, el que lo usa trabaja contra una versión falsa (stub) dentro de su área, nunca adivinando la implementación real.

## 6. Comunicación entre agentes

Los agentes se hablan por issues. Nunca por comentarios en el código ni por archivos sueltos.

| Etiqueta | Uso |
| --- | --- |
| `para-agente-a` / `para-agente-b` | Pedido o pregunta dirigida a un agente |
| `contrato` | Propuesta de cambio de contrato |
| `bloqueado` | La tarea no puede avanzar hasta que se resuelva otra cosa |
| `necesita-humano` | Requiere algo de Nico o Beni (sección 7) |
| `bug` | Sigue `docs/resolucion-de-bugs.md` |
| `decision` | Decisión tomada que hay que registrar en `docs/decisiones.md` |
| `diario` | Los dos issues fijados del diario (sección 11) |
| `memoria` | Los dos issues fijados con la memoria de cada orquestador |

Formato de un pedido entre agentes:

```markdown
**De:** Agente A
**Para:** Agente B
**Tipo:** pregunta | pedido | aviso
**Contexto:** qué estoy haciendo y por qué lo necesito (con ID de requerimiento)
**Pedido:** qué necesito, concreto
**Bloquea:** #N o "nada"
```

Si un issue bloquea trabajo propio, se marca `bloqueado`, se linkea y se pasa a otra tarea que no dependa de eso.

## 7. Pedidos al humano

Hay cosas que un agente no puede hacer: modelos 3D, sonidos, subir assets a Roblox, decidir sobre diseño y, sobre todo, **juzgar si el manejo se siente bien**. Para eso se abre un issue con `necesita-humano`.

### Tipos de pedido

| Tipo | Ejemplos |
| --- | --- |
| `asset-modelo` | Auto, árboles, rocas, piezas de ruta |
| `asset-sonido` | Motor, neumáticos, choques |
| `asset-textura` | Superficie de tierra, pasto |
| `prueba-de-juego` | Probar el derrape, la cámara, el reset |
| `decision` | Elegir entre opciones de diseño |
| `configuracion` | Permisos, publicar el lugar, IDs de assets |

### Plantilla general

```markdown
**Tipo:** asset-modelo | asset-sonido | asset-textura | prueba-de-juego | decision | configuracion
**Para:** Nico | Beni | cualquiera
**Requerimiento:** RC-x / CP-x
**Qué necesito:** una línea
**Para qué:** cómo se va a usar
**Especificación:** (según el tipo, ver abajo)
**Cómo me lo entregás:** ruta en el repo, ID de asset en Roblox, o respuesta en el issue
**Criterio de aceptado:** cómo sé que está bien
**Bloquea:** #N o "nada"
**Mientras tanto:** qué uso como reemplazo (ej.: cubo gris del mismo tamaño)
```

### Especificación según el tipo

**Modelo 3D**

- Dimensiones en studs (largo × ancho × alto).
- Presupuesto de triángulos máximo.
- Pivote: dónde va el origen (ej.: centro de la base) y hacia dónde mira el frente.
- Partes separadas y sus nombres exactos (ej.: `Body`, `WheelFL`, `WheelFR`, `WheelRL`, `WheelRR`).
- Colisión: qué partes chocan y con qué forma simplificada.
- Variantes de detalle si hacen falta (completo, pobre, impostor).
- Formato de entrega (`.fbx` u `.obj`) y carpeta: `assets/models/`.

**Sonido**

- Qué representa y en qué situación suena.
- Si es en bucle o de un solo disparo.
- Duración aproximada.
- Qué parámetro lo modifica en el juego (ej.: tono según RPM).
- Formato de entrega (`.ogg` o `.mp3`) y carpeta: `assets/sounds/`.

**Textura**

- Superficie y bioma.
- Resolución.
- Si tiene que repetirse sin cortes.
- Carpeta: `assets/textures/`.

**Prueba de juego**

- Qué probar, en qué rama y cómo abrirla en Studio.
- Qué parámetros se pueden ajustar y dónde (archivo de configuración).
- Preguntas concretas, no "¿qué te parece?". Ejemplo: "¿podés iniciar un derrape con freno de mano en una curva cerrada?", "¿el auto se siente pesado o liviano? (1 a 5)".
- Cuánto tiempo jugar.

**Decisión**

- Opciones numeradas, cada una con su costo y su consecuencia.
- La recomendación del agente, marcada como recomendación.
- Qué pasa si no se decide (qué queda bloqueado).

El humano responde en el mismo issue. Si es una decisión, el agente la registra en `docs/decisiones.md` y cierra el issue.

## 8. Plantilla de PR

```markdown
## Qué hace
Una o dos líneas.

## WP
WP-<número> (todo lo de este PR está dentro de su alcance)

## Requerimientos
RC-x, CP-x

## Pruebas
- Cobertura: X% (mínimo 87%)
- [ ] Pruebas manuales del WP, buscando romperlo

## Cómo probarlo en Studio
1. Paso concreto
2. Qué se tiene que ver

## Contratos
Ninguno tocado | Toca `<contrato>` (issue #N)

## Pendiente o conocido
Qué no cubre este PR, o "nada".

Closes #N
```

## 9. Registro de decisiones

`docs/decisiones.md` guarda cada decisión tomada, la más nueva arriba:

```markdown
## AAAA-MM-DD — Título corto
**Decidió:** Nico | Beni | ambos
**Issue:** #N
**Decisión:** qué se eligió.
**Por qué:** una o dos líneas.
**Descartado:** qué otras opciones había.
```

Nada que esté en este registro se reabre sin un issue nuevo que explique por qué.

## 10. Notas

`docs/notas/` es para lo que conviene dejar escrito pero no es una tarea, un pedido ni una decisión: observaciones, ideas, hallazgos de investigación, cosas aprendidas, impresiones de una prueba. Pueden escribir los agentes y los humanos.

**Regla para no mezclar:** si alguien tiene que hacer algo a partir de la nota, no es una nota, es un issue. La nota puede existir igual, pero el pedido va al issue y se linkean.

### Notas cortas

Una o pocas líneas. Van todas en `docs/notas/rapidas.md`, la más nueva arriba:

```markdown
- **AAAA-MM-DD · Agente B:** la generación de tramos tarda más en curvas cerradas; revisar cuando se mida rendimiento (RC-2).
- **AAAA-MM-DD · Nico:** con gamepad el derrape se siente mucho mejor que con teclado.
```

### Notas largas

Un archivo por nota en `docs/notas/`, con el nombre `AAAA-MM-DD-autor-tema.md` (ej.: `2026-10-20-agente-a-modelos-de-derrape.md`):

```markdown
# Título

**Autor:** Agente A | Agente B | Nico | Beni
**Fecha:** AAAA-MM-DD
**Relacionado:** RC-x / CP-x / #N

## Resumen
Dos o tres líneas con la conclusión. El que no lea más, se queda con esto.

## Desarrollo
El contenido completo.
```

Cuando una nota larga se crea, se agrega una línea en `rapidas.md` que la linkee, así queda en un solo lugar lo nuevo.

Las notas no se borran. Si quedan desactualizadas, se agrega al principio una línea `**Desactualizada:** ver <nota o decisión nueva>`.

## 11. Diario de los agentes

El diario es donde cada agente deja **cómo está pensando**: el enfoque que eligió, los supuestos que está haciendo, las dudas y lo que vio del área del otro. Sirve para que los dos estén alineados sin tener que preguntarse todo.

No reemplaza al resto:

| Dónde | Qué va |
| --- | --- |
| Comentario de cierre en el issue | Estado de esa tarea (hecho, en curso, siguiente) |
| Diario | Razonamiento y supuestos que cruzan tareas |
| Notas | Hallazgos e ideas que conviene guardar |
| Issue | Cualquier cosa que alguien tenga que hacer |

### Dónde vive

Un issue fijado por agente, con etiqueta `diario`: **"Diario — Agente A"** y **"Diario — Agente B"**. Cada sesión es un comentario nuevo. Esos issues no se cierran nunca.

Se usa un issue y no un archivo porque los comentarios se ven al instante. Un archivo en una rama no lo ve el otro agente hasta que se mergea, y además dos agentes escribiendo el mismo archivo generan conflictos.

### Formato de cada entrada

```markdown
## AAAA-MM-DD — Sesión con Nico | Beni

**Trabajé en:** #N, #M (sin repetir el estado; está en cada issue)

**Cómo lo estoy encarando:** el enfoque elegido y por qué, en pocas líneas.

**Supuestos que estoy haciendo:**
- Supuesto concreto y verificable (ej.: "asumo que la ruta nunca supera 15° de pendiente").

**Dudas:** lo que no tengo claro y todavía no amerita un issue.

**Sobre el área del otro:** algo que vi o que me va a afectar, o "nada".

**Próximo:** en qué pienso seguir.
```

### Reglas

1. Una entrada por sesión, al terminar. Corta: si pasa de 20 líneas, sobra algo o hay una nota larga para escribir.
2. **Los supuestos son lo más importante.** Si un agente lee un supuesto del otro que contradice su trabajo, abre un issue `para-agente-x` en esa misma sesión. No lo discute en el diario.
3. El diario no es para pedidos ni decisiones. Si algo requiere acción, va a un issue; si se decidió algo, va a `docs/decisiones.md`.
4. No se editan entradas viejas. Si algo cambió, se aclara en la entrada nueva.

## 12. Reglas de código y bugs

Las reglas de código, el proceso antes de programar, la documentación, los bugs y la revertibilidad están en `docs/reglas-de-trabajo.md`.

Son obligatorias. Si una tarea las contradice, frená y preguntá.
