--!strict
-- Contrato acordado en #17. Lo provee Calles infinitas (src/world/) y lo usa Conducción (src/vehicle/).

export type SurfaceKind = "Road" | "Shoulder" | "Grass" | "Mud"

-- Ignora la altura. Devuelve nil si la posición cae en una zona no generada o ya liberada.
export type GetSurfaceAt = (position: vector) -> SurfaceKind?

return {}
