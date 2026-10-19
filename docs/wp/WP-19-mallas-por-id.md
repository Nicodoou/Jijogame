# WP-19 — Mallas del auto por id al arrancar

**Issue:** problema encontrado el 2026-10-16. Rojo no puede escribir `MeshPart.MeshId` cuando sincroniza en vivo, así que en Studio el 147 aparece como cajas grises y hay que clonarlo a mano después de cada sincronización. Nico aprobó la solución el 2026-10-17.
**Requerimientos:** ninguno nuevo. Es infraestructura de desarrollo, que también protege al juego publicado si un archivo pierde sus mallas.
**Diseño:** `docs/disenos/auto.md`, sección "Centro de masa y modelo del auto". Agrega un paso al armado del modelo visual, sin cambiar la arquitectura.
**Responsable:** Agente A
**Depende de:** el 147 nuevo en `main` (WP-14), porque los ids salen de sus mallas.

## Subagente
- **Nombre:** `.claude/agents/programador-adaptador.md` (Sonnet). La mayor parte es adaptador y Studio; la parte de datos puros lleva sus pruebas.
- **Entrega:** su informe, con mediciones **hechas con comandos y en Studio**.

## Contexto
- **Leer:**
  - `src/vehicle/server/VehicleVisualModel.luau` y `src/vehicle/core/VehicleModels.luau`;
  - `docs/guia-de-desarrollo.md`, sección 11.
- **Lo que se sabe:**
  - **En vivo:** con Rojo sincronizando, cada `MeshPart` del modelo queda con `MeshId` vacío y `MeshContent` en `None`; tamaño, posición, color y material sí llegan.
  - **Con `rojo build`:** el lugar construido tiene las 33 mallas con sus `rbxassetid` (medido el 2026-10-16).
  - **Crear mallas desde un id:** `AssetService:CreateMeshPartAsync(Content.fromUri(id))` crea una `MeshPart` con esa malla en tiempo de ejecución. Funcionó en Studio en la investigación de la hitbox, con `CreateEditableMeshAsync` sobre las mismas mallas.

**Dónde trabaja:** rama `a/mallas-por-id`, en el worktree `C:\Users\Nico\Documents\Rally-wp19`.

## Entregables
1. **Datos (`src/vehicle/core/models/Fiat147Meshes.luau`):** para cada malla del modelo, `{ meshId, textureId }`, por nombre.
   - Se generan con un script en Studio sobre el modelo con mallas, que queda comentado arriba del archivo, igual que `Fiat147Hitbox`.
   - La ficha (`VehicleModels`) apunta a este archivo.
2. **Prueba:** cada nombre de `meshNames` tiene su id, y cada id empieza con `rbxassetid://` y no está vacío.
3. **`VehicleVisualModel` (servidor):** al clonar el modelo, toda `MeshPart` que llegue con `MeshId` vacío se reemplaza por una creada con `CreateMeshPartAsync` desde su id.
   - Copia nombre, tamaño, `CFrame`, color, material, `TextureID`, transparencia y atributos.
   - Después se suelda como hoy.
   - Si la malla ya tiene id (juego publicado o `rojo build`), no hace nada.
4. **Cuándo se crean:** una vez por servidor, en una plantilla en memoria que después se clona para cada auto.
   - Mientras no estén listas, el auto se ve con sus cajas físicas, como hoy cuando falta el modelo.
   - Si una creación falla, se registra en el log y esa pieza queda como caja; el auto se arma igual.
5. **Guía (`docs/guia-de-desarrollo.md`, sección 11):** cómo regenerar `Fiat147Meshes.luau` cuando Nico sube un modelo nuevo, y que ya no hace falta clonar el modelo a mano en Studio.

## Pruebas en Studio
- **Con Rojo conectado, sin clonar nada a mano:** en Play, el auto tiene sus 44 mallas con id y las cajas grises no se ven.
- **Igual que hoy:**
  - masa y centro de masa sin cambios;
  - mallas soldadas, sin colisión ni masa, y ruedas apoyadas.
- **Costo:** tiempo hasta que el auto se ve con mallas desde el Play, y tiempo del armado con y sin plantilla.
- **Falla simulada** (un id inválido en una copia de los datos durante la prueba): el auto se arma, esa pieza queda como caja y hay una línea en el log.

## Fuera de alcance
- Generar los ids de forma automática en el CI: no hay acceso a Studio desde ahí.
- Otros autos: el mecanismo es genérico, pero solo se cargan los datos del 147.

## Criterios de aceptación
- [ ] `scripts/check-all.sh` da todo OK, con cobertura ≥ 87%.
- [ ] Archivos ≤ 200 líneas, funciones ≤ 30 y ≤ 7 funciones públicas, **medido con comandos**.
- [ ] En Studio con Rojo, el 147 se ve con mallas sin hacer nada a mano.
