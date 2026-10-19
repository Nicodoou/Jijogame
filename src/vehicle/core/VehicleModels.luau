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
	-- Mallas de las ruedas: nombre de la malla -> rueda física (cada una sigue a su rueda: suspensión, dirección y giro).
	wheelMeshes: { [string]: string },
	-- Mallas del eje trasero rígido (si el modelo lo trae): se mueven como una sola pieza entre las dos ruedas traseras.
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
		"Baul",
		"Capot",
		"Capot2",
		"Chasis",
		"Chasis10",
		"Chasis11",
		"Chasis12",
		"Chasis13",
		"Chasis14",
		"Chasis15",
		"Chasis16",
		"Chasis2",
		"Chasis3",
		"Chasis4",
		"Chasis5",
		"Chasis6",
		"Chasis7",
		"Chasis8",
		"Chasis9",
		"FL Light",
		"FR Light",
		"Front Bumper",
		"Interior front",
		"LF Wheel",
		"LR Wheel",
		"Left Door",
		"Left Driver's seat",
		"Left Mirror",
		"Left Mirror2",
		"Parrilla",
		"RF Wheel",
		"RL Light",
		"RR Light",
		"RR Wheel",
		"Rear Bumper",
		"Rear Mirror",
		"Rear seats",
		"Right Door",
		"Right Driver's seat",
		"Right Mirror",
		"Right Mirror2",
		"Right Mirror3",
		"Steering Wheel",
		"Techo",
	}),
	wheelMeshes = table.freeze({ ["LF Wheel"] = "FL", ["RF Wheel"] = "FR", ["LR Wheel"] = "RL", ["RR Wheel"] = "RR" }),
	rearAxleMeshes = table.freeze({}),
	wheelCenters = table.freeze({
		FL = vector.create(2.02, 2.02, 3.05),
		FR = vector.create(-2.02, 2.02, 3.05),
		RL = vector.create(2.02, 2.02, -3.04),
		RR = vector.create(-2.02, 2.02, -3.04),
	}),
	driverHead = vector.create(1.26, 4.06, -0.34),
}

return table.freeze({
	Fiat147 = table.freeze(Fiat147),
})
