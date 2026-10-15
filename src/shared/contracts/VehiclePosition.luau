--!strict
-- Contrato acordado en #22. Lo provee Conducción (src/vehicle/) y lo usa Calles infinitas (src/world/).

-- Posición actual del auto del jugador local, en coordenadas del mundo. Nunca es nil:
-- si el auto no existe o está reapareciendo, devuelve la última posición conocida o el punto de aparición.
export type GetVehiclePosition = () -> vector

return {}
