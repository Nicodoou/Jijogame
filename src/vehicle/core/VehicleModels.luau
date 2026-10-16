--!strict
-- Fichas de los modelos visuales del auto. Solo datos: el adaptador las usa para ubicar el modelo y moverlo.
-- Todas las posiciones están en el marco del modelo: el origen es su pivote, x a la izquierda, y arriba y +z adelante.

export type VehicleModelSheet = {
	-- Nombre del archivo en assets/vehicles (sin extensión) y del modelo en ReplicatedStorage.vehicle.models.
	fileName: string,
	-- Giro alrededor de y que hace falta para que el modelo mire a -z, como el auto.
	turnDegrees: number,
	-- Altura de la parte de abajo de las ruedas sobre el pivote.
	modelGroundY: number,
	-- Todas las mallas del modelo (la lista declarada que valida la prueba).
	meshNames: { string },
	-- Mallas de las ruedas delanteras: nombre de la malla -> rueda física.
	frontWheelMeshes: { [string]: string },
	-- Mallas del eje trasero rígido: se mueven como una sola pieza entre las dos ruedas traseras.
	rearAxleMeshes: { string },
	-- Centro de cada rueda (FL, FR, RL, RR), para comparar con VehicleConfig.WHEELS.
	wheelCenters: { [string]: vector },
	-- Cabeza del conductor (para la primera persona): el asiento más 1,3 studs hacia arriba.
	driverHead: vector,
}

local Fiat147: VehicleModelSheet = {
	fileName = "Fiat147",
	turnDegrees = 180,
	modelGroundY = 1.22,
	meshNames = table.freeze({
		"Bonnet",
		"Chasis",
		"Copilot's seat",
		"Copilot's seat2",
		"Driver's seat",
		"Driver's seat2",
		"FL Light",
		"FL Susp",
		"FL Susp2",
		"FL Susp3",
		"FR Light",
		"FR Susp",
		"FR Susp2",
		"FR Susp3",
		"Front BUmp",
		"Interior",
		"LF",
		"Left Door",
		"Parrilla",
		"RF",
		"RL Light",
		"RL Susp",
		"RL Susp2",
		"RR Susp",
		"RR Susp2",
		"RR Susp3",
		"Rear Bump",
		"Rear Wheels",
		"Rear Wheels2",
		"Rear seats",
		"Right Door",
		"Steering wheel",
		"Trunk",
	}),
	frontWheelMeshes = table.freeze({ LF = "FL", RF = "FR" }),
	rearAxleMeshes = table.freeze({ "Rear Wheels", "Rear Wheels2" }),
	wheelCenters = table.freeze({
		FL = vector.create(2.34, 2.03, 2.88),
		FR = vector.create(-2.34, 2.03, 2.88),
		RL = vector.create(2.34, 1.98, -3.06),
		RR = vector.create(-2.34, 1.98, -3.06),
	}),
	driverHead = vector.create(1.35, 3.87, -0.54),
}

return table.freeze({
	Fiat147 = table.freeze(Fiat147),
})
