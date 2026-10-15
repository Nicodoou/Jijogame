# Guía de desarrollo

Cómo dejar tu máquina lista, sincronizar con Studio, correr los chequeos y escribir pruebas. Las herramientas y sus versiones están en `rokit.toml`; el porqué de la arquitectura, en `docs/disenos/politica-de-codigo.md`.

## 1. Requisitos

- **Git para Windows**, que incluye Git Bash. Los scripts de `scripts/` son de bash y se corren desde Git Bash (en Linux y macOS, desde cualquier terminal bash).
- **Roblox Studio**, para sincronizar con Rojo y para las pruebas manuales.
- Conexión a internet la primera vez (las herramientas y el archivo de definiciones de Roblox se bajan de GitHub).

## 2. Instalar Rokit (Windows)

Rokit es el administrador que instala las herramientas del proyecto con la versión exacta de `rokit.toml`. La versión que usa el proyecto es la 1.2.0.

1. Bajá `rokit-1.2.0-windows-x86_64.zip` de https://github.com/rojo-rbx/rokit/releases/tag/v1.2.0 y descomprimilo. Adentro está `rokit.exe`.
2. En PowerShell, desde la carpeta donde quedó `rokit.exe`:

   ```powershell
   .\rokit.exe self-install
   ```

   Eso copia Rokit a `C:\Users\<vos>\.rokit\bin` y lo agrega al `PATH` del usuario.
3. **Cerrá y volvé a abrir la terminal** (y Git Bash) para que tome el `PATH`. Si la terminal está adentro de otro programa (VS Code, la app de Claude u otro editor), **cerrá y abrí el programa entero**: la terminal hereda las variables del programa, y si no, sigue sin encontrar `rokit`.
4. Si tu Git Bash no encuentra `rokit`, agregá esta línea a `~/.bashrc` y abrí una terminal nueva:

   ```bash
   export PATH="$HOME/.rokit/bin:$PATH"
   ```

5. Comprobá: `rokit --version` tiene que mostrar `1.2.0`.

## 3. Instalar las herramientas del proyecto

Desde la carpeta del repo:

```bash
rokit trust rojo-rbx/rojo
rokit trust JohnnyMorganz/StyLua
rokit trust Kampfkarren/selene
rokit trust JohnnyMorganz/luau-lsp
rokit trust luau-lang/luau
rokit install
```

`rokit trust` hace falta una sola vez por herramienta: sin él, `rokit install` pregunta de forma interactiva y se cuelga en una terminal sin entrada. Después de `rokit install` tienen que andar:

```bash
rojo --version      # 7.7.1
stylua --version    # 2.6.0
selene --version    # 0.32.0
luau-lsp --version  # 1.70.1
```

`luau` no tiene `--version`; para comprobarlo, `rokit list` muestra las herramientas instaladas con su versión (Luau 0.742.0).

**Trampa conocida:** los programas de `.rokit\bin` son proxies que solo funcionan dentro de una carpeta que tenga un `rokit.toml` (o dentro de una subcarpeta de una que lo tenga). Si corrés `rojo` o `stylua` desde otra carpeta, fallan porque no encuentran la herramienta. Trabajá siempre dentro del repo.

## 4. Rojo y Studio

Rojo sincroniza el repo con Studio: lo que escribís en `src/` aparece en el juego. El mapeo está en `default.project.json` y la jerarquía del juego copia la del repo:

| Repo | Roblox |
| --- | --- |
| `src/shared/` | `ReplicatedStorage.shared` |
| `src/<área>/core/` | `ReplicatedStorage.<área>.core`, para `vehicle`, `input`, `camera` y `world` |

1. Instalá el plugin de Rojo una sola vez: `rojo plugin install`. Reiniciá Studio.
2. En Studio, abrí un lugar vacío (por ejemplo, un Baseplate).
3. Desde la carpeta del repo, en una terminal: `rojo serve`. Queda corriendo y muestra el puerto (34872 por defecto).
4. En Studio, pestaña **Plugins** → **Rojo** → **Connect**. Tienen que aparecer `ReplicatedStorage.shared.contracts.Surface` y las carpetas `core` de cada área.
5. Para cortar, **Disconnect** en Studio y `Ctrl+C` en la terminal.

Rojo sincroniza del repo a Studio. Lo que cambies a mano en Studio sobre lo sincronizado se pierde; el repo es la fuente de verdad.

**Carpetas vacías:** Rojo exige que existan las carpetas que mapea. Como Git no guarda carpetas vacías, las `core/` que todavía no tienen código llevan un archivo `.gitkeep`, que Rojo ignora. Se borra cuando la carpeta tiene su primer módulo.

## 5. Correr los chequeos

```bash
scripts/check-all.sh
```

Corre, en el mismo orden que el CI, y sigue aunque uno falle (al final lista cuáles fallaron):

| Paso | Qué hace | Script |
| --- | --- | --- |
| Formato | `stylua --check src tests` | |
| Lint | Selene con `selene-core.toml` (núcleo, contratos y pruebas, sin globales de Roblox) y con `selene.toml` (adaptadores, `std = "roblox"`) | `scripts/lint.sh` |
| Reglas del núcleo | `--!strict` en la primera línea, sin `Vector3` ni `CFrame`, `require` solo a la misma área o a `src/shared/contracts/`, sin carpetas `core/` fuera de `src/<área>/core/` | `scripts/check-core.sh` |
| Tipos del núcleo | `luau-lsp analyze --platform=standard` | `scripts/analyze-core.sh` |
| Tipos de adaptadores | `luau-lsp analyze --platform=roblox` con el sourcemap de Rojo y las definiciones de Roblox | `scripts/analyze-adapters.sh` |
| Pruebas de los scripts | Cada chequeo tiene que fallar con su caso malo de `tests/fixtures/` y pasar con el bueno | `scripts/test-scripts.sh` |
| Pruebas | Todos los `tests/**/*.test.luau`, con cobertura | `scripts/test.sh` |
| Cobertura | 87% de líneas de `src/*/core/**` | `scripts/coverage.sh [umbral]` |
| Rojo | `rojo build`, para validar el mapeo | |

Se pueden correr por separado. La primera vez, `analyze-adapters.sh` baja las definiciones de Roblox de luau-lsp (unos 850 KB) a `.cache/`, que Git ignora.

**Formato:** `stylua src tests` arregla el formato; `stylua --check src tests` solo lo verifica. Los fines de línea son LF en todo el repo (`.gitattributes` y `stylua.toml`), también en Windows.

## 6. Agregar un área o una carpeta `client/` o `server/` al mapeo

El mapeo vive en `default.project.json`. Las carpetas `client/`, `server/` y `src/app/` todavía no existen: se suman en el WP que las crea, según la tabla de la arquitectura.

| Repo | Roblox |
| --- | --- |
| `src/<área>/shared/` | `ReplicatedStorage.<área>.shared` |
| `src/<área>/client/` | `StarterPlayer.StarterPlayerScripts.<área>` |
| `src/<área>/server/` | `ServerScriptService.<área>` |
| `src/app/client/` | `StarterPlayer.StarterPlayerScripts.app` |
| `src/app/server/` | `ServerScriptService.app` |

**Un área nueva** (por ejemplo `audio`): creá `src/audio/core/` con un `.gitkeep` y sumá la entrada dentro de `ReplicatedStorage`:

```json
"audio": {
  "$className": "Folder",
  "core": {
    "$path": "src/audio/core"
  }
}
```

**Una carpeta `client/`** de un área que ya está en el mapeo: creá `src/vehicle/client/` y sumá, dentro de `tree`:

```json
"StarterPlayer": {
  "$className": "StarterPlayer",
  "StarterPlayerScripts": {
    "$className": "StarterPlayerScripts",
    "vehicle": {
      "$path": "src/vehicle/client"
    }
  }
}
```

**Una carpeta `server/`**: igual, con `"ServerScriptService": { "$className": "ServerScriptService", "vehicle": { "$path": "src/vehicle/server" } }`.

Después de cambiar el mapeo: `rojo build default.project.json --output build.rbxl` tiene que terminar bien (el archivo `.rbxl` lo ignora Git) y, con `rojo serve`, la jerarquía tiene que aparecer en Studio como en la tabla. El código de `client/` y `server/` se chequea con `scripts/analyze-adapters.sh`.

Reglas que siguen valiendo: todo el núcleo de un área vive en `src/<área>/core/` (nunca dentro de `client/` o `server/`), y cada archivo de `core/` y de `src/shared/contracts/` empieza con `--!strict`.

## 7. Escribir una prueba

Las pruebas del núcleo van en `tests/<área>/X.test.luau` (fuera de `src/`, así Rojo no las sincroniza al juego y la cobertura no las cuenta). Corren con el CLI `luau`, sin Roblox.

**Desde dónde corre `scripts/test.sh`:** desde la **raíz del repo**, sin importar desde dónde lo llames. Corre `luau --coverage tests/<área>/X.test.luau` por cada archivo. Los `require` por string son relativos al archivo que los hace, así que desde `tests/<área>/X.test.luau`:

- el núcleo es `require("../../src/<área>/core/X")`;
- el corredor es `require("../Runner")`.

Ejemplo completo. El módulo:

```lua
--!strict
-- src/vehicle/core/Clamp.luau
local Clamp = {}

function Clamp.clamp(value: number, minimum: number, maximum: number): number
	return math.max(minimum, math.min(maximum, value))
end

return Clamp
```

Su prueba:

```lua
--!strict
-- tests/vehicle/Clamp.test.luau
local Runner = require("../Runner")
local Clamp = require("../../src/vehicle/core/Clamp")

Runner.test("clamp returns the value when it is inside the range", function()
	Runner.expectEqual(Clamp.clamp(5, 0, 10), 5)
end)

Runner.test("clamp returns the minimum when the value is below the range", function()
	Runner.expectEqual(Clamp.clamp(-1, 0, 10), 0)
end)

Runner.test("clamp keeps the exact limits", function()
	Runner.expectEqual(Clamp.clamp(0, 0, 10), 0)
	Runner.expectEqual(Clamp.clamp(10, 0, 10), 10)
end)

Runner.test("clamp with a fractional value stays near the maximum", function()
	Runner.expectNear(Clamp.clamp(10.0000001, 0, 10), 10, 1e-6)
end)

Runner.finish()
```

El corredor (`tests/Runner.luau`) ofrece:

| Función | Qué hace |
| --- | --- |
| `Runner.test(name, fn)` | Corre `fn`. Si lanza un error o una aserción falla, la prueba falla y se imprime `FALLA <name>: <qué se esperaba y qué se obtuvo>`. Las demás pruebas siguen. |
| `Runner.expectEqual(actual, expected)` | Falla si `actual ~= expected`. Compara con `==`: dos tablas distintas no son iguales. |
| `Runner.expectNear(actual, expected, tolerance)` | Falla si la diferencia es mayor que la tolerancia. Se usa para flotantes. |
| `Runner.expectError(fn)` | Falla si `fn` termina sin lanzar un error. |
| `Runner.finish()` | **Va siempre al final de cada archivo.** Imprime el resumen y falla el proceso si alguna prueba falló. `test.sh` rechaza un archivo que no lo llama. |

Reglas de las pruebas (de `docs/reglas-de-trabajo.md`, sección 5): determinísticas (azar con semilla fija y `dt` falso, nunca `os.clock`), una cosa por prueba con el nombre que dice cuál, y siempre los bordes: cero, máximos, negativos, vacíos y justo en los límites.

Para correrlas:

```bash
scripts/test.sh          # todas las pruebas, con cobertura
scripts/coverage.sh      # cobertura de src/*/core/**; falla por debajo de 87%
```

`coverage.sh` lista las líneas sin cubrir. Un archivo de `core/` que ninguna prueba carga cuenta con todas sus líneas sin cubrir.

## 8. CI

`.github/workflows/ci.yml` corre en cada PR y en cada push a `main`: instala Rokit 1.2.0 desde su release oficial, confía en las herramientas de `rokit.toml`, las instala y corre `scripts/check-all.sh` y `rojo build`. Si el CI falla, corré `scripts/check-all.sh` en tu máquina: tiene que dar lo mismo.

## 9. Problemas frecuentes

| Síntoma | Causa y arreglo |
| --- | --- |
| `rojo` (u otra herramienta) dice que no encuentra la herramienta | Estás fuera de una carpeta con `rokit.toml`. Entrá al repo. |
| `rokit: command not found` justo después de instalarlo | La terminal se abrió antes de instalar Rokit. Reiniciá la terminal o el programa que la contiene (sección 2, paso 3), o corré `export PATH="$HOME/.rokit/bin:$PATH"` en esa terminal. |
| `rokit install` se cuelga | Falta `rokit trust` de alguna herramienta (sección 3). |
| `stylua --check` falla solo en tu máquina | Fin de línea. Confirmá que el archivo es LF con `git ls-files --eol <archivo>`; `.gitattributes` fuerza LF al hacer checkout. |
| `no encuentro 'luau'` (u otra) desde un script | Falta el `PATH` de Rokit en Git Bash (sección 2, paso 4). |
| `Unknown global 'game'` en `core/` | Es lo esperado: el núcleo no puede usar nada de Roblox. Esa lógica va en un adaptador. |
| `ambiguous` al hacer `require` de un módulo | En Windows las rutas no distinguen mayúsculas: un archivo `Runner.luau` y una carpeta `runner/` en el mismo directorio chocan. Evitá nombres que solo se diferencien por mayúsculas. |
| `Key 'X' not found in external type 'vector'` | En el tipo `vector` de Luau los componentes son `x`, `y`, `z` en minúscula. |
