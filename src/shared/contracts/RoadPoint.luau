--!strict
-- Contrato acordado en #35. Lo provee Calles infinitas (src/world/) y lo usa Conducción (src/vehicle/).

-- Un punto sobre el eje de la ruta, a la altura de la superficie.
-- direction es unitario, hacia adelante en el sentido de marcha, con la pendiente incluida.
-- arcLength son los studs recorridos sobre el eje desde el inicio de la ruta.
export type RoadPoint = {
	position: vector,
	direction: vector,
	arcLength: number,
}

-- Ignora la altura. Devuelve nil si no hay ruta cargada a menos de 1.000 studs.
export type GetNearestRoadPoint = (position: vector) -> RoadPoint?

-- El inicio de la ruta. Da lo mismo en el cliente y en el servidor para la misma semilla, sin esperar al Terrain.
export type GetSpawnPoint = () -> RoadPoint

return {}
