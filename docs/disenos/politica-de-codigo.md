# Política de código: herramientas, pruebas y cobertura

**Issue:** #6
**Requerimientos:** transversal (reglas de pruebas y cobertura de `docs/reglas-de-trabajo.md`, sección 5)
**Estado:** opciones presentadas

## Investigación

Hecha por el subagente `investigador` el 2026-10-14. Marcas: **[V]** verificado en fuente primaria, **[S]** fuente secundaria, **[NC]** no confirmado. El orquestador volvió a verificar contra la fuente cinco datos clave: el estado del PR de Lune, TestEZ y Aftman archivados, la versión de Rojo y la opción `--coverage` del CLI de Luau.

### Lo más importante: cobertura

- **Dentro del motor de Roblox no se puede medir cobertura**, ni en Studio, ni en Open Cloud, ni con Jest. Roblox lo reconoció en abril de 2025 (la librería `debug` no está expuesta) y no hay novedades posteriores [V] ([DevForum](https://devforum.roblox.com/t/add-way-to-get-lcov-code-coverage-in-studio-engine-and-in-open-cloud-luau-execution-session-task/3576690)).
- **La única cobertura que existe hoy es la del CLI `luau`** (`--coverage`, salida tipo LCOV) [V] ([Coverage.cpp](https://raw.githubusercontent.com/luau-lang/luau/master/CLI/src/Coverage.cpp)). Mide **líneas**, no ramas. Solo corre Luau puro: no existen `Instance`, `game`, servicios, `Vector3`, `CFrame`, `Random` ni `task`. No está documentada en luau.org, así que es una función del CLI sin garantía de estabilidad.
- **Lune** (runtime de Luau fuera de Roblox) todavía no tiene cobertura. El PR [lune-org/lune#421](https://github.com/lune-org/lune/pull/421), abierto el 2026-10-06 y sin revisar, la agrega [V].
- **Qué se puede medir:**
  - **Hoy, con `luau`:** lógica pura, como la generación de la ruta con semilla, la matemática del modelo de conducción y las curvas de input. El código que use tipos de Roblox necesita una capa propia o emulación.
  - **Nunca, con lo que existe:** los adaptadores que tocan `Instance`, `Workspace`, `RunService`, `UserInputService`, la cámara o los remotos, y todo lo que depende de la física del motor.

### Herramientas (vigencia al 2026-10-14)

| Herramienta | Estado | Fuente |
| --- | --- | --- |
| Rojo 7.7.1 | Mantenido. Corrige rutas en Windows. Sincroniza repo → Studio; la sincronización inversa es experimental. Terrain y CSG no sincronizan en vivo. | [releases](https://github.com/rojo-rbx/rojo/releases), [formato](https://rojo.space/docs/v7/project-format/) [V] |
| Rokit 1.2.0 | Mantenido. Lee también `aftman.toml` y `foreman.toml`. Uso en Windows 10 [NC]. | [releases](https://github.com/rojo-rbx/rokit/releases) [V] |
| Aftman | **Archivado** | [V] |
| StyLua 2.6.0 | Mantenido, soporta Luau | [V] |
| Selene 0.32.0 | Mantenido, `std = "roblox"` | [V] |
| luau-lsp 1.70.1 | Mantenido. `luau-lsp analyze` chequea tipos en CI usando el sourcemap de Rojo. | [V] / uso en CI [S] |
| Wally 0.3.2 (0.4 en alpha) | Activo. Necesario solo si se usa Jest. | [V] |
| pesde 0.7.4 | Activo. Compatibilidad con los paquetes de Wally [NC]. | [V] |
| TestEZ | **Archivado** | [V] |
| Jest (Roblox/jest-roblox) | Activo. **Solo corre dentro de Roblox** (Studio u Open Cloud). Mocks y tiempo falso en Luau [NC]. | [repo](https://github.com/Roblox/jest-roblox) [V] |
| Jest-Lua (jsdotlua) | Fork comunitario, último release en 2024-12 | [V] |
| Lune 0.11.0 | Mantenido. Tiene un DOM propio de Roblox, pero no pretende correr juegos completos. | [V] |
| lune-test | Comunitario, de mayo de 2026. Emula Instances, remotos y un `task` con planificador falso. Sin física. Más lento por `getfenv()`. | [DevForum](https://devforum.roblox.com/t/cli-lune-test-a-local-luau-test-runner-run-and-test-roblox-code-locally/4658410) [S] |
| Open Cloud Luau Execution | Estable. Límites: 5 min por tarea, 450 KB de logs, 5 tareas por minuto. Sin física. Requiere API key y un universo de Roblox. | [doc](https://create.roblox.com/docs/cloud/reference/features/luau-execution.md) [V] |
| MCP de Studio | Ejecuta Luau en Studio, controla el modo Play y lee la consola. Requiere Studio abierto **con un lugar** (si no, responde "Place is not open", verificado por el Agente B), así que no sirve en CI. Estabilidad para una suite completa [NC]. | [doc](https://create.roblox.com/docs/studio/mcp) [V] |

### CI

En GitHub Actions corren sin Studio: la instalación con Rokit, `stylua --check`, `rojo sourcemap`, `luau-lsp analyze`, `selene`, `rojo build` y las pruebas con `luau` o Lune [S, sin probar]. **Studio no corre en CI** [NC]. Las pruebas dentro del motor solo pueden ir por Open Cloud. Para el umbral de cobertura hay que escribir un script que lea las líneas `DA:` del reporte; no encontramos una herramienta lista [NC].

### Lo que existe y lo que no en el CLI de Luau

Agregado por la revisión del Agente B (#15), verificado en [luau.org](https://luau.org):

- **Existen:** `math.noise` y la librería `vector` (`vector.create`), que son parte de la biblioteca estándar de Luau.
- **No existen:** `Random` y `task`. La lógica pura necesita un generador pseudoaleatorio propio (PCG o xorshift, por ejemplo), y no puede esperar ni ceder el control con `task.wait()`.

### Pendiente de confirmar con un experimento (`exp/toolchain`)

1. Que Rokit instale y corra todas las herramientas en Windows. Nico usa Windows 10 y Beni, Windows 11 Home.
2. Que `luau --coverage` funcione con módulos que se hacen `require` entre sí y entregue un reporte usable. También, encontrar una forma de `require` que funcione igual en el CLI (`require("./X")`) y en Roblox (`require(script.Parent.X)`). Si no la hay, el núcleo no se puede probar tal como corre en el juego.
3. Qué Jest instala bien (el de Roblox o el de jsdotlua) y si tiene mocks y tiempo falso. Solo si se elige una opción con Jest.
4. Si Jest corre completo a través del MCP de Studio. Solo si se elige una opción con Jest.
5. Si en Roblox el tipo `vector` es el mismo que `Vector3`. Si es así, los contratos pueden usar `vector` y la lógica pura los puede importar desde el CLI.
6. **Determinismo entre el CLI y Studio:** el mismo módulo con la misma semilla tiene que dar el mismo resultado (comparado con un hash), `math.noise` incluido. El Agente B se ofreció a hacer la parte de Studio con el MCP.

## Opciones

Hay tres decisiones: **cómo se prueba y se mide la cobertura**, **cómo se reparten las carpetas de `src/`** y **dónde viven las utilidades puras que usan las dos áreas**. Las herramientas base van en todas las opciones: Rokit, Rojo, StyLua, Selene, luau-lsp con `--!strict` y CI en GitHub Actions.

### Decisión 1: pruebas y cobertura

#### Opción 1: núcleo puro medido con `luau`

La lógica se escribe en módulos **puros**, sin APIs de Roblox, y los adaptadores que tocan el motor son delgados. Las pruebas de la lógica corren con el CLI `luau` y un corredor de pruebas propio y mínimo. La cobertura se mide con `luau --coverage` y un script que exige el umbral. Los adaptadores se prueban a mano en Studio, sin porcentaje.

- **Bueno:** es la única opción en la que el 87% es medible y verificable hoy. Corre en CI sin cuentas de Roblox. Encaja con las reglas de arquitectura (capas, inyección de dependencias, sin estado global). Las pruebas son rápidas y deterministas.
- **Malo:** hay que escribir y mantener el corredor de pruebas (aserciones, descubrimiento, reporte). Mide líneas, no ramas. Los tipos de Roblox (`Vector3`, `CFrame`) no existen fuera del motor, así que la lógica pura los tiene que evitar o usar tipos propios.
- **Riesgoso:** la cobertura del CLI no está documentada y puede cambiar. Se puede caer en "pureza" forzada, con capas de más solo para medir.
- **Funciona bien cuando:** la generación de la ruta y el modelo de conducción se pueden expresar como matemática sobre datos propios.
- **Deja de funcionar cuando:** gran parte del comportamiento depende de la física del motor (por ejemplo, si el auto usa constraints de Roblox en vez de raycast; ver #7). Ahí el código medible se achica.
- **Consecuencias para la arquitectura** (de la revisión del Agente B):
  - La lógica pura usa un generador pseudoaleatorio propio, no `Random`. Así, la misma semilla da la misma secuencia en las pruebas y en el juego.
  - La lógica pura no usa `task`. Lo que lleva varios frames (por ejemplo, generar un tramo) se diseña como pasos que el adaptador avanza con un presupuesto por frame, para no dar tirones (tabla de rendimiento de los requerimientos).
  - Qué cuenta como lógica pura queda definido por la carpeta `core/` de cada área (ver Decisión 2).

#### Opción 2: Jest dentro de Roblox, sin cobertura numérica

Jest (de Roblox) con Wally. Durante el desarrollo, las pruebas corren en Studio (con el MCP o un script), y en CI, por Open Cloud Luau Execution con un lugar armado con `rojo build`.

- **Bueno:** es el framework estándar y mantenido, y se usa en Roblox. Puede probar código que usa `Instance` y los tipos de Roblox.
- **Malo:** **no hay cobertura**, así que la regla del 87% se tiene que reemplazar por otra (por ejemplo, que toda función pública de un módulo de lógica tenga al menos una prueba, revisado a mano). Suma Wally, una API key, un universo de Roblox y un secreto en GitHub.
- **Riesgoso:** los límites de Open Cloud (450 KB de logs, 5 tareas por minuto) con una suite grande. Sin física en Open Cloud. Mocks y tiempo falso sin confirmar.
- **Funciona bien cuando:** se acepta perder la medición numérica.
- **Deja de funcionar cuando:** la cobertura medible es un requisito.

#### Opción 3: Lune con lune-test

Las pruebas corren fuera de Roblox con la emulación de lune-test, que trae un planificador falso. La cobertura depende de que se mergee el PR de Lune.

- **Bueno:** permite probar fuera de Studio código que usa algunos tipos de Roblox. El planificador falso sirve para el tiempo falso.
- **Malo:** **hoy tampoco tiene cobertura**. La emulación es incompleta y no tiene física.
- **Riesgoso:** lune-test es de mayo de 2026 y de un solo autor, y el PR de cobertura no tiene revisión ni fecha.
- **Funciona bien cuando:** se puede esperar a la cobertura de Lune.
- **Deja de funcionar cuando:** el PR no se mergea o lune-test se abandona.

#### Opción 4: híbrida (1 + 2)

La lógica pura se mide con `luau` (87% sobre esa parte) y los adaptadores se prueban con Jest en Studio u Open Cloud, sin porcentaje.

- **Bueno:** es la que más código cubre con pruebas automáticas.
- **Malo:** dos frameworks de pruebas, más herramientas y todo lo de Open Cloud.
- **Riesgoso:** más superficie para mantener desde el arranque del MVP.
- **Funciona bien cuando:** los adaptadores crecen y empiezan a romperse.
- **Deja de funcionar cuando:** el costo de mantener dos caminos supera lo que aporta.

**Recomendación del agente:** **Opción 1**, con la regla de cobertura redefinida como **"87% de líneas en los módulos de lógica pura; los adaptadores al motor se mantienen delgados y se cubren con pruebas manuales en Studio"**. Es la única opción en la que la regla se puede cumplir y verificar hoy, y empuja a la arquitectura por capas que ya piden las reglas. Si los adaptadores empiezan a dar problemas, se puede pasar a la Opción 4 sin rehacer nada. Antes de escribir la arquitectura, conviene confirmar en `exp/toolchain` los puntos 1 y 2 de "Pendiente de confirmar".

### Decisión 2: estructura de `src/`

Roblox necesita que el código de servidor, el de cliente y el compartido vayan a servicios distintos. Las reglas piden esa separación en carpetas, y la coordinación reparte el código por área.

#### Opción A: primero el área

`src/world/`, `src/vehicle/`, `src/input/`, `src/camera/`, `src/shared/contracts/`. El `default.project.json` mapea cada subcarpeta a su servicio. Con las precisiones de la revisión del Agente B:

- **Cada área tiene una carpeta `core/`** con su lógica pura (por ejemplo, `src/world/core/` y `src/vehicle/core/`). La cobertura del 87% se mide sobre `*/core/**`, y un chequeo en CI rechaza en `core/` cualquier uso de `game`, `workspace`, `script`, `Instance`, `Random`, `task` o servicios. Así, "lógica pura" queda definida por la ruta y no a criterio.
- **Las subcarpetas `server/`, `client/` y `shared/` se crean cuando el diseño del área las necesita.** Por ejemplo, si la ruta se genera en el cliente o en el servidor se decide en #9 y #10, y recién ahí se ajusta el project file.
- Que Terrain no sincronice con Rojo no es un riesgo si el terreno se genera mientras corre el juego (#10).

- **Bueno:** cada agente tiene su carpeta completa, como dice la tabla de áreas, y la propiedad de cada archivo es obvia.
- **Malo:** el project file de Rojo es más largo, con una entrada por área y por lado.
- **Riesgoso:** que alguien ponga código de servidor en una carpeta de cliente por error. Selene o una prueba de estructura lo pueden detectar.

#### Opción B: primero el lado (convención habitual de Rojo)

`src/server/world/`, `src/client/vehicle/`, `src/shared/world/`, `src/shared/contracts/`, etc.

- **Bueno:** es el patrón más común, y el project file es corto (tres entradas).
- **Malo:** el área de cada agente queda repartida en varias carpetas, así que hay que actualizar la tabla de áreas de la coordinación.
- **Riesgoso:** más archivos compartidos entre agentes en la misma carpeta raíz, y más fácil pisarse.

**Recomendación del agente:** **Opción A** con las precisiones de arriba, porque mantiene la tabla de áreas tal cual, hace evidente quién es dueño de cada archivo y define qué mide la cobertura. El Agente B coincide.

### Decisión 3: utilidades puras que usan las dos áreas

Por ejemplo, el generador pseudoaleatorio o funciones de vectores. Pregunta abierta por el Agente B en su revisión.

#### Opción a: cada área tiene las suyas en su `core/`

- **Bueno:** nadie depende del otro y cada agente cambia lo suyo sin pedir permiso.
- **Malo:** puede haber código duplicado.
- **Riesgoso:** que el mismo concepto termine con dos implementaciones que se comportan distinto.

#### Opción b: carpeta compartida `src/shared/util/`, que se cambia por acuerdo como los contratos

- **Bueno:** una sola implementación.
- **Malo:** cada cambio pasa por el proceso de contratos, que es más lento.
- **Riesgoso:** que se vuelva un cajón de sastre.

**Recomendación del agente:** **Opción a** para el MVP, como propone el Agente B. Si algo termina duplicado de verdad, se mueve a `src/shared/` por acuerdo.

## Decisión

Pendiente: deciden Nico y Beni (toca a los dos agentes).

## Arquitectura

Pendiente: se escribe cuando esté la decisión.

## Aprobación

Pendiente.
