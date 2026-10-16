# Notas rápidas

La más nueva arriba. Formato en `docs/coordinacion-agentes.md`, sección 10.

- **2026-10-16 · Agente B:** con cuadros caros en Studio el terreno quedaba mal sobre la ruta (bug `docs/bugs/2026-10-16-ruta-enterrada.md`): los avisos de "chunk viejo" se perdían al replanificar. Arreglado en `ChunkRegistry`. Para probar el terreno con trabajo atrasado hay un conductor en `tests/world/TerrainDrive.luau` (corrida larga a mano: `tests/world/long/TerrainFollowsRoad.luau`).
