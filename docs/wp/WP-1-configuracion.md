# WP-1 — Configuración del repo: herramientas, pruebas, chequeos y CI

**Issue:** #6
**Requerimientos:** ninguno del MVP. Es la base que piden las reglas de pruebas y cobertura (`docs/reglas-de-trabajo.md`, sección 5) y que necesitan todos los WPs con código, empezando por el WP-2.
**Diseño:** `docs/disenos/politica-de-codigo.md` (aprobado), sección "Arquitectura"
**Responsable:** Agente A

## Subagente
- **Nombre:** `.claude/agents/configurador.md` (nuevo, en este mismo PR)
- **Modelo:** Sonnet. El WP fija qué archivos van, qué hace cada script y cómo se prueba, así que el trabajo es implementar y verificar. Las dudas de diseño vuelven al orquestador.
- **Herramientas permitidas:** Bash, PowerShell, Read, Write, Edit, Glob, Grep y WebFetch (solo para leer documentación de las herramientas y bajar el archivo de definiciones del riesgo 4).
- **Entrega:** el informe de su definición, con los criterios de aceptación uno por uno.

## Contexto para el subagente

- **Leer:**
  - `docs/reglas-de-trabajo.md` (secciones 3, 4 y 5);
  - `docs/disenos/politica-de-codigo.md` completo, en especial "Resultados del experimento `exp/toolchain`" y "Arquitectura";
  - `docs/decisiones.md`;
  - `docs/nombres.md`;
  - `src/shared/contracts/Surface.luau`;
  - `docs/wp/WP-2-ruta-nucleo.md`, sección "Depende de", para saber qué espera el Agente B de este WP.
- **Decisiones que aplican** (`docs/decisiones.md`): "Política de pruebas, cobertura y estructura de `src/`".
- **Supuestos vigentes** (verificados en #16 y en el PR #20):
  - Rokit 1.2.0 instala y corre las herramientas en Windows 10, con `rokit trust` en modo no interactivo. Ya está instalado en `C:\Users\Nico\.rokit`.
  - `luau --coverage <archivo>` escribe `coverage.out` en formato LCOV, con `SF:` y `DA:` para el archivo y los módulos que requiere. Las rutas salen relativas al directorio desde donde se corre.
  - `require("./X")` y `require("../../X")` funcionan igual en el CLI y en Roblox (probado a mano en Studio; con Rojo falta confirmarlo).
  - `luau` no tiene `--version` ni `-e`.
  - En el experimento, `luau-lsp analyze` solo corrió con `--platform=standard`.
- **De la conversación con Nico:** quiere los merges con aprobación y prefiere avanzar rápido. Nada de lo que hace este WP toca la lógica del juego.
- **Contratos que usa o provee:** ninguno. `src/shared/contracts/` ya existe y no se modifica.

**Dónde trabaja:** rama `a/6-configuracion`, creada desde `main`, en un worktree aparte: `C:\Users\Nico\Documents\Rally-wp1`. No toca `C:\Users\Nico\Documents\Rally` (el checkout del orquestador). Al terminar, pushea la rama.

## Objetivo

Dejar el repo listo para que cualquier WP con código tenga, desde el primer commit, formato, lint, chequeo de tipos, pruebas con cobertura y CI, tal como lo define la arquitectura.

## Entregables

1. **Toolchain:** `rokit.toml` con Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, luau-lsp 1.70.1 y Luau 0.742.0 (las versiones del experimento).
2. **Rojo:** `default.project.json` con el mapeo de la arquitectura (la jerarquía del juego copia la del repo):
   - `src/shared/` → `ReplicatedStorage.shared`;
   - `src/<área>/core/` → `ReplicatedStorage.<área>.core`, para `vehicle`, `input`, `camera` y `world`.

   Las carpetas `client/`, `server/` y `src/app/` todavía no existen; se suman al mapeo en el WP que las cree. Si Rojo exige que existan las carpetas `core/`, se crean vacías de la forma que Rojo ignore, y se documenta cuál es.
3. **Formato y fin de línea:** `stylua.toml` con `line_endings = "Unix"` y `.gitattributes` que fuerce LF en todos los archivos de texto. El resto de las opciones de StyLua quedan por defecto.
4. **Lint:**
   - `selene.toml` con `std = "roblox"`, para los adaptadores;
   - `selene-core.toml` con una std que **no** tenga los globales de Roblox, para el núcleo y los contratos (riesgo 3).
5. **Corredor de pruebas** `tests/Runner.luau`, con:
   - `test(name, fn)`;
   - `expectEqual(actual, expected)`;
   - `expectNear(actual, expected, tolerance)`;
   - `expectError(fn)`;
   - un resumen final que termina el proceso con error si alguna prueba falló.

   Los mensajes de falla dicen qué se esperaba, qué se obtuvo y en qué prueba. El corredor tiene sus propias pruebas en `tests/runner/`, incluidas las que comprueban que detecta fallas.
6. **Scripts** (bash, que corran igual en Git Bash de Windows y en Linux):
   - `scripts/test.sh`: corre todos los `tests/**/*.test.luau` con cobertura y deja un solo reporte combinado (riesgo 2). Falla si falla alguna prueba.
   - `scripts/coverage.sh [umbral]`: con el reporte combinado, calcula el porcentaje de líneas cubiertas de `src/*/core/**`. Umbral por defecto: 87. **Los archivos de `src/*/core/**` que no aparecen en el reporte cuentan con todas sus líneas ejecutables sin cubrir.** Lista las líneas sin cubrir. Si no hay ningún archivo de núcleo, termina bien e informa que no hay nada que medir. Falla si queda por debajo del umbral.
   - `scripts/check-core.sh`: falla si en `src/*/core/**` hay un `require` a otra área (solo se permite la misma área o `src/shared/contracts/`), si aparece `Vector3` o `CFrame`, si falta `--!strict` en la primera línea o si existe una carpeta `core/` fuera de `src/<área>/core/`. También exige `--!strict` en `src/shared/contracts/`.
   - `scripts/check-all.sh`: corre todos los chequeos en el mismo orden que el CI y termina con error si alguno falla.

   Las constantes de los scripts (umbral, carpetas y palabras prohibidas) van arriba, con nombre.
7. **Pruebas de los scripts:** casos en `tests/fixtures/` (fuera de `src/`, así no los sincroniza Rojo ni los mide la cobertura) y un `scripts/test-scripts.sh` que comprueba que cada chequeo **falla** con su caso malo y **pasa** con su caso bueno. Como mínimo:
   - un núcleo que usa `game`, que Selene del núcleo tiene que rechazar;
   - un `require` a otra área y un archivo sin `--!strict`, que `check-core.sh` tiene que rechazar;
   - un núcleo sin pruebas, que tiene que contar 0% en `coverage.sh`;
   - una cobertura justo por debajo y justo en el umbral (borde).

   `check-all.sh` también corre `test-scripts.sh`.
8. **Tipos:**
   - el núcleo, los contratos y las pruebas se analizan con `luau-lsp analyze --platform=standard`;
   - el resto de `src/` (cuando exista), con `--platform=roblox`, el sourcemap y el archivo de definiciones de Roblox (riesgo 4).
9. **CI:** `.github/workflows/ci.yml` en `ubuntu-latest`, en cada PR y en cada push a `main`:
   - instala Rokit 1.2.0 desde su release oficial de GitHub;
   - corre `rokit trust` sobre las herramientas de `rokit.toml` y después `rokit install`;
   - después, `scripts/check-all.sh` y `rojo build`.
10. **Guía:** `docs/guia-de-desarrollo.md`, en español:
    - instalar Rokit en Windows, con lo aprendido en #16;
    - `rokit install`;
    - instalar el plugin de Rojo y usar `rojo serve` desde Studio;
    - correr `scripts/check-all.sh`;
    - agregar un área o una carpeta `client/` o `server/` al mapeo;
    - escribir una prueba con el corredor.
11. **`.gitignore`:** suma `coverage.out` y los reportes intermedios que genere `test.sh`.
12. **Limpieza:** se borra `.claude/agents/.gitkeep` si quedó, y no queda ningún archivo de prueba suelto.

## Riesgos que se confirman primero

Antes de armar el resto, el subagente confirma estos riesgos. Si alguno falla, **frena**.
- **Riesgo 2:** cómo dar un solo reporte de cobertura con varios archivos de prueba. Por ejemplo, un archivo que requiere a todos los demás, o juntar varios `coverage.out`, siempre que las líneas de un mismo archivo se sumen bien.
- **Riesgo 3:** que Selene tenga una std sin globales de Roblox y que con ella rechace `game`, `workspace`, `Instance`, `Random` y `task`. Si ninguna std integrada sirve, se puede definir una propia en el repo.
- **Riesgo 4:** de dónde sale el archivo de definiciones de Roblox para `luau-lsp --platform=roblox` (por ejemplo, el que publica el repo de luau-lsp para la versión 1.70.1). Hay que bajarlo de esa fuente oficial, fijado a esa versión, y comprobar que `luau-lsp analyze` lo usa sin errores sobre un archivo de prueba que use `game`. En CI se baja en cada corrida; no se commitea si pesa más de 1 MB.

## Fuera de alcance

- Cualquier código de juego, núcleo o adaptador.
- `src/app/`, carpetas `client/` y `server/` y sus scripts de arranque: se crean en el primer WP que las necesite.
- Cambios a los contratos.
- Wally, Jest o cualquier otro framework de pruebas.
- La protección de `main` en GitHub (CI obligatorio): se pide a Nico con un issue `necesita-humano` cuando el CI esté en `main`.
- Instalar algo en la máquina de Beni.

## Criterios de aceptación

- [ ] `rokit install` en un clon limpio deja las cinco herramientas con las versiones de `rokit.toml`.
- [ ] `rojo build default.project.json -o build.rbxl` termina bien y el mapeo coincide con la tabla de la arquitectura.
- [ ] `scripts/check-all.sh` termina bien en la rama, en Windows (Git Bash).
- [ ] Cada chequeo falla con su caso malo de `tests/fixtures/` y lo explica con un mensaje claro (`scripts/test-scripts.sh` pasa).
- [ ] `coverage.sh` cuenta como 0% un archivo de núcleo sin pruebas y respeta el borde del umbral.
- [ ] El corredor tiene pruebas que comprueban que detecta fallas.
- [ ] El workflow de CI corre en GitHub Actions sobre la rama y termina en verde. Si el subagente no puede dispararlo, queda como prueba manual.
- [ ] `stylua --check`, `selene` y `luau-lsp analyze` pasan sobre todos los archivos `.luau` del repo, incluido `Surface.luau`.
- [ ] Los riesgos 2, 3 y 4 quedan confirmados y documentados en el informe.
- [ ] La guía existe y alcanza para que Beni configure su máquina sin preguntar.
- [ ] No hay código comentado, `print` de depuración ni `TODO` sin issue.

## Pruebas manuales
- [ ] **Nico:** clonar la rama en una carpeta nueva y seguir la guía de punta a punta. Con `rojo serve` y el plugin en un Baseplate, comprobar que aparecen `ReplicatedStorage.shared.contracts.Surface` y las carpetas `core` de cada área.
- [ ] **Nico, con Rojo sincronizando:** crear a mano dos ModuleScripts temporales en el repo (`src/world/core/A.luau`, que hace `require("../../shared/contracts/Surface")`, y uno que lo use), sincronizar y confirmar en Studio que los `require` resuelven. Después, borrarlos. Con esto se cierra la salvedad de #16 y del PR #20.
- [ ] Romper a propósito el formato de un archivo en un commit de prueba y comprobar que el CI falla. Después, revertir.
- [ ] **Beni,** cuando instale: seguir la guía en Windows 11 y reportar cualquier diferencia en #6.
