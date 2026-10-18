# Hitbox automática a partir de las mallas del 147

Medido en Studio "Experiencia sin título" (solo lectura, modo Edit, `Workspace.147_corregido`). No se modificó nada: las `EditableMesh` se crearon en memoria y se destruyeron. [V] = verificado en la doc oficial o medido por mí; [S] = fuente secundaria; [NC] = no confirmado.

## 1. Resumen

- Sí se puede. Las 33 mallas se leen con `AssetService:CreateEditableMeshAsync` desde el contexto de Studio Edit (probado, 7.219 vértices en total, ~20 s la primera vez). [V medido]
- Las 33 `MeshPart` tienen `Orientation = 0`, así que su caja delimitadora alineada a ejes (`Size` + `CFrame`) ya es exacta. No hace falta OBB para este modelo. [V medido]
- 25 de las 33 mallas son 1 a 1 (o N a 1) con piezas de daño. El problema es la malla `Chasis` (5,57 x 3,46 x 10,19; 196 studs³ de caja), que envuelve todo y probablemente contiene techo, guardabarros, zócalos y vidrios. Se parte con una grilla sobre los vértices: 3x2x4 da 17 cajas con 30% del volumen de la caja entera. [V medido]
- Recomiendo un generador en el plugin (corre en Edit, con `EditableMesh`) más el editor para retocar. Algoritmo en la sección 5.

## 2. Opciones en Roblox

| Opción | Qué da | Límite | Estado |
| --- | --- | --- | --- |
| `Size` + `CFrame` de la `MeshPart` (o `Model:GetBoundingBox`) | Caja delimitadora exacta si la parte no está rotada. Instantáneo. | Una sola caja por pieza; inútil para `Chasis`. Si la malla está rotada, la caja de `Size` es orientada (OBB) pero no ajustada a la forma. | [V medido] [`MeshPart`](https://create.roblox.com/docs/reference/engine/classes/MeshPart) |
| `CollisionFidelity` de la propia `MeshPart` | `Box` = "caja delimitadora", `Hull` = casco convexo, `Default` = forma aproximada con concavidad, `PreciseConvexDecomposition` = la más precisa y cara. | Acopla visual y hitbox (la pieza que se oculta se lleva la colisión). "Las partes no convexas complejas pueden dar varios resúmenes por el mismo par". Costo de `BindToCollisionSummaries` crece con las partes suscriptas. No editable por pieza ni por auto. Hoy las 33 están en `Default`, `CanCollide = true`, `Anchored = true`. | [V] [colisiones](https://create.roblox.com/docs/workspace/collisions). Que `Box` coincida exactamente con el AABB y si se puede cambiar en juego: [NC]. `TriangleMeshPart.CollisionFidelity` no figura como solo lectura ([ref](https://create.roblox.com/docs/reference/engine/classes/TriangleMeshPart)). |
| `AssetService:CreateEditableMeshAsync(Content)` + `GetVertices` / `GetPosition` / `GetFaces` / `GetFaceVertices` | Geometría real: permite cajas ajustadas, grillas, PCA, partir mallas. | Método con capability `AssetRead`; lectura de vértices con `DynamicGeneration`. Permisos de asset, límites de memoria/triángulos y disponibilidad en experiencias publicadas: no figuran en la página de referencia que pude leer. | [V] [AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService), [EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh). Medido: funciona en Studio Edit con los assets de Nico. |
| `AssetService:CreateMeshPartAsync(content, options)` | Crea una `MeshPart` con una fidelidad de colisión elegida. | Sirve para fabricar colisión por `Hull`/`PreciseConvexDecomposition`, no para obtener cajas. No lo probé. | [V firma] [AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService); comportamiento [NC] |
| `GeometryService` | No pude confirmar que ofrezca nada útil para esto (booleanas de partes, no cajas ajustadas). | — | [NC] |
| `WorldRoot:GetPartsInPart`, `GetPartBoundsInBox`, `Blockcast` | Consultas de solapamiento y barridos. | Sirven para validar una hitbox ya hecha (¿qué mallas toca cada caja?), no para generarla. | [V firma] [WorldRoot](https://create.roblox.com/docs/reference/engine/classes/WorldRoot) |

Nota de compatibilidad con el diseño: C1 pide cajas `Massless` soldadas al `Body` con `CanCollide = true` en un grupo propio. Usar la `MeshPart` visual como colisión (fila 2) sería C2/otra variante y rompe "las mismas piezas en todos los autos y configurable por auto".

## 3. Piezas grandes que envuelven otras

Medido sobre los vértices de `Chasis` (2.779 vértices, 1.659 caras; malla centrada en el origen, de -2,78 a 2,78 en X, -1,73 a 1,73 en Y, -5,10 a 5,10 en Z). Agrupé los vértices en una grilla uniforme, descarté las celdas con menos de 0,5% del área y calculé la caja ajustada de cada celda restante:

| Grilla (X x Y x Z) | Cajas | Volumen sumado | % de la caja entera |
| --- | --- | --- | --- |
| 1x1x1 | 1 | 196,1 | 100% |
| 2x2x2 (octantes) | 8 | 85,8 | 44% |
| 3x2x4 | 17 | 58,4 | 30% |
| 4x3x8 | 40 | 19,1 | 10% |

Lectura: con octantes ya se corta más de la mitad del volumen; con 3x2x4 la forma se parece a un auto. La grilla uniforme es la base; los otros caminos son:

- **A. Grilla + fusión voraz:** celdas ocupadas del mismo "rol" que se tocan se fusionan en una caja mientras el volumen vacío agregado sea menor a un umbral. Simple, determinista.
- **B. Cajas por región semántica:** el generador usa posiciones relativas (fracción de X/Y/Z) para asignar cada celda a una pieza: capa inferior -> `chassisBase`; capa superior -> `roof`; celdas laterales a la altura de cada eje de rueda -> `fender_*`; franja baja entre ejes -> `sideSkirt_*`. Depende de que el 147 tenga esa disposición; con otro auto hay que parametrizar.
- **C. Cortar con las otras mallas:** quitar de `Chasis` lo que ya cubren Bonnet, Trunk, puertas y paragolpes (todas están 100% dentro de la caja de `Chasis`, ver sección 4.4), para no duplicar cajas. Usa `GetPartsInPart` o la comparación de cajas propia.

## 4. Mapeo malla -> pieza de daño

### 4.1 Las 33 mallas (nombre, caja delimitadora en studs, vértices)

Las mallas están sin rotar, así que `Size` es la caja en ejes del mundo.

| Malla | Caja X x Y x Z | Vért. | Pieza de daño (propuesta) |
| --- | --- | --- | --- |
| Chasis | 5,57 x 3,46 x 10,19 | 2779 | `chassisBase` y, probablemente, `roof`, `fender_*`, `sideSkirt_*`, vidrios (a confirmar viendo la malla) |
| Bonnet | 5,22 x 0,27 x 3,48 | 55 | `bonnet` |
| Trunk | 4,32 x 1,56 x 2,51 | 148 | `trunk` |
| Left Door | 0,69 x 2,92 x 2,71 | 204 | `door_L` |
| Right Door | 0,69 x 2,92 x 2,71 | 204 | `door_R` |
| Front BUmp | 5,55 x 0,76 x 1,44 | 148 | `frontBumper` |
| Rear Bump | 5,46 x 0,76 x 1,08 | 154 | `rearBumper` |
| Parrilla | 2,81 x 0,63 x 0,06 | 31 | `grille` (muy fina: caja de 0,06; conviene engrosar) |
| FL Light | 1,01 x 0,56 x 0,54 | 24 | `headlight_L` (el nombre FL y la posición X ≈ -47,5 coinciden con Left Door) |
| FR Light | 1,01 x 0,56 x 0,54 | 24 | `headlight_R` |
| RL Light | 4,52 x 0,56 x 0,45 | 48 | `taillight_L` y `taillight_R` en una sola malla: partir por la mitad en X |
| LF | 0,72 x 1,62 x 1,62 | 56 | `wheel_FL` |
| RF | 0,72 x 1,62 x 1,62 | 56 | `wheel_FR` |
| Rear Wheels2 | 5,40 x 1,62 x 1,62 | 112 | `wheel_RL` y `wheel_RR` en una sola malla: partir por la mitad en X |
| FL Susp, FL Susp2, FL Susp3 | 0,41 / 0,18 / 0,57 de ancho; alto 0,96-1,62 | 24-432 | `suspension_FL` (interna: no necesita colisión) |
| FR Susp, FR Susp2, FR Susp3 | ídem | | `suspension_FR` |
| RL Susp, RL Susp2 | 0,18 x 1,17 x 0,18; 0,62 x 1,22 x 0,56 | | `suspension_RL` |
| RR Susp, RR Susp2, RR Susp3 | | | `suspension_RR` |
| Interior, Driver's seat, Driver's seat2, Copilot's seat, Copilot's seat2, Rear seats, Steering wheel, Rear Wheels | varias | | Sin pieza de daño en la ficha (visuales internos). `Steering wheel` podría ser visual de `steering`: no lo puedo afirmar. |

Cuenta: 14 (exteriores) + 11 (suspensión) + 8 (sin pieza) = 33.

### 4.2 Piezas de la ficha sin malla propia

- **Internas, sin colisión por diseño (5):** `radiator`, `engine`, `gearbox`, `steering`, `fuelTank`. Nunca llevan caja.
- **Exteriores sin malla propia (12):** `roof`, `fender_FL/FR/RL/RR`, `sideSkirt_L/R`, `windshield`, `rearWindow`, `window_L/R`, `mirror_L/R`. Si están dentro de `Chasis` hay que sacarles caja de ahí (sección 3); los espejos no aparecen como malla y quizás no existan en el modelo. No lo pude confirmar sin inspeccionar la malla visualmente.
- Total: 33 exteriores + 5 interiores = 38 piezas. Las 5 internas no necesitan caja.

### 4.3 Qué falta para confirmar el mapeo

La asignación de nombres a lados (L/R) se infiere de las posiciones (Left Door en X ≈ -47,2; FL Susp en X ≈ -47,8; FR en X ≈ -51,2). El frente es -Z (Parrilla en Z ≈ -15,8). El script debe usar una tabla de mapeo declarada (nombre de malla -> pieza), no adivinar por texto.

### 4.4 Solapamiento entre mallas

528 pares posibles; 75 pares con cajas que se solapan. De ésos, los que superan 50% del volumen de la más chica:

- Con `Chasis`: casi todos (Bonnet, Trunk, Left/Right Door, Rear Bump, Parrilla, asientos, Interior, volante, FL/FR Light 99%, Front BUmp 87%, RL Light 86%, todas las suspensiones). Es de esperar: la caja de `Chasis` es el auto entero. 
- Entre piezas pequeñas: asientos con `Interior`; las tres mallas de suspensión de cada rueda entre sí (54-100%); suspensión trasera con `Rear seats` (81-85%) y con `Rear Wheels2` (56-71%); `Rear Wheels` dentro de `Rear Wheels2` (100%).
- Entre exteriores distintos (puertas, paragolpes, capot, luces, ruedas): ningún par supera 50%, así que las cajas por pieza casi no se pisan.

## 5. Recomendación (marcada como recomendación, no decisión)

Generador automático dentro del plugin `HitboxEditor` (corre en Edit, donde `EditableMesh` anda) que escribe la primera hitbox; después se retoca con las herramientas nativas (decisión E1).

**Algoritmo:**

1. **Tabla de mapeo declarada** por auto: `{ meshName = {pieceId, splitAxis?} }` (sección 4). Las mallas sin pieza se ignoran.
2. **Piezas 1 a 1 (Bonnet, Trunk, puertas, paragolpes, grilla, faros delanteros, ruedas delanteras):** una caja = `Size` y `CFrame` de la `MeshPart`, expresada relativa al `Body`. Con piezas finas (`Parrilla` 0,06) forzar un espesor mínimo (p. ej. 0,3 studs; valor a calibrar).
3. **Mallas que contienen dos piezas (RL Light, Rear Wheels2):** leer vértices con `EditableMesh`, repartirlos por el signo de X respecto del plano medio del auto y calcular la caja ajustada de cada mitad.
4. **Chasis:**
   1. Leer vértices y caras; usar centroides de caras ponderados por área.
   2. Grilla (por defecto 3x2x4; ajustable) y descartar celdas con menos de ~0,5% del área.
   3. Caja ajustada por celda (mín/máx de sus vértices).
   4. Asignar cada celda a una pieza por posición relativa (regla B de la sección 3): capa baja -> `chassisBase`, capa alta -> `roof`, celdas laterales a la altura de las ruedas -> `fender_*`, franja baja lateral entre ejes -> `sideSkirt_*`; el resto -> `chassisBase`.
   5. Fusionar celdas contiguas de la misma pieza si el volumen vacío agregado es menor a un umbral.
5. **Recorte final:** no hace falta evitar solapes entre cajas (el diseño las pone en un grupo propio que no choca consigo mismo), pero conviene no dar a `Chasis` cajas donde ya hay Bonnet/Trunk/puertas/paragolpes.
6. **Salida:** `Part`s con atributos `pieceId` e índice, `Massless`, `CanCollide = true`, `Transparency = 1` en Studio, listas para que el editor las mueva y exporte el texto de configuración.

**Límites:**

- La caja da un hit-test grueso: una grilla de 17 cajas cubre 30% del volumen del cuadro del Chasis; un choque en una esquina cóncava puede contarse en la pieza vecina.
- Un shell hueco se vuelve sólido: golpes que "entrarían" al capó o la cabina se detectan igual.
- El mapeo por posición relativa de `Chasis` es heurístico y específico del 147; con otro modelo hay que reajustar las reglas.
- Los espejos y los vidrios no aparecen como mallas aparte: sus cajas hay que dibujarlas a mano o derivarlas de zonas del `Chasis`.
- `EditableMesh` en tiempo de ejecución (experiencia publicada) puede requerir permisos o límites que no pude confirmar: por eso el generador corre en el plugin y guarda el resultado como datos, no calcula en juego.
- La primera lectura de 33 mallas tardó ~20 s (descarga del asset); con caché es más rápido.

## 6. No pude confirmar

- Si `CollisionFidelity = Box` en la `MeshPart` da exactamente el AABB y si se puede cambiar en juego (se prueba en una rama `exp/`).
- Permisos y límites de `EditableMesh` en un servidor o cliente publicado (ownership, verificación, tope de triángulos/memoria): la página de la referencia no los lista.
- Si `GeometryService` o `CreateMeshPartAsync` aportan algo para generar la hitbox.
- Qué contiene `Chasis` (si trae vidrios, espejos, techo, guardabarros): sólo se midió su geometría, no se inspeccionó visualmente.
- Nota de entorno: `execute_luau` del Studio MCP exige `datamodel_type`: se usó `Edit`.
