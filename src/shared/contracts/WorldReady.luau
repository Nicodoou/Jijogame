--!strict
-- Contrato acordado en #36. Lo provee Calles infinitas (src/world/) y lo usa Conducción (src/vehicle/). Solo en el cliente.

-- true si el Terrain en un radio fijo alrededor de la posición ya está escrito y es seguro apoyar algo ahí.
export type IsWorldReadyAt = (position: vector) -> boolean

return {}
