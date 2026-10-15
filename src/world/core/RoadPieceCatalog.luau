--!strict
-- Datos de las piezas de ruta. Sumar o ajustar una pieza es cambiar esta tabla, no código.
-- Largos en studs (se redondean a pasos de integración), radios en studs y giros en grados. La altura no es de las
-- piezas: la da HillProfile.
-- Toda pieza empieza y termina con curvatura 0 y la sube y baja en rampas lineales, así la curvatura es continua.
-- El orden de la lista importa: el sorteo la recorre en orden y tiene que dar lo mismo en cualquier plataforma.

export type PieceKind = "straight" | "gentleCurve" | "sharpCurve" | "sCurve" | "hairpinPair" | "uTurn"

export type PieceDefinition = {
	kind: PieceKind,
	weight: number,
	-- Cantidad de lóbulos de curvatura. La S tiene dos, de sentido opuesto. En la horquilla doble, cada horquilla es uno.
	lobeCount: number,
	-- Largo de la pieza. En la horquilla doble es el de la recta que une las dos horquillas.
	minLengthStuds: number,
	maxLengthStuds: number,
	-- Radio de la parte constante de cada lóbulo. La recta tiene radio infinito.
	minRadiusStuds: number,
	maxRadiusStuds: number,
	-- Fracción de cada lóbulo que se usa para subir (y otra igual para bajar) la curvatura.
	rampFraction: number,
	-- Curva de un solo sentido: es la única que se sortea cuando la guía queda muy de costado.
	isSimpleCurve: boolean,
	-- Da la vuelta: gira más que el rumbo relativo a la guía que se permite, así que queda exenta de ese límite, y solo se
	-- sortea cerca de la guía.
	turnsBack: boolean,
	-- Solo se sortea si la guía queda a por lo menos este ángulo del rumbo: una vuelta que no hace falta se pasa de largo.
	minHeadingErrorDegrees: number?,
	-- Giro total de cada vuelta (cada horquilla, o la U). Solo la horquilla doble y la U lo tienen.
	minTurnDegrees: number?,
	maxTurnDegrees: number?,
}

local definitions: { PieceDefinition } = {
	{
		kind = "straight",
		weight = 1,
		lobeCount = 1,
		minLengthStuds = 30,
		maxLengthStuds = 80,
		minRadiusStuds = math.huge,
		maxRadiusStuds = math.huge,
		rampFraction = 0.25,
		isSimpleCurve = false,
		turnsBack = false,
	},
	{
		kind = "gentleCurve",
		weight = 3,
		lobeCount = 1,
		minLengthStuds = 180,
		maxLengthStuds = 420,
		minRadiusStuds = 180,
		maxRadiusStuds = 400,
		rampFraction = 0.3,
		isSimpleCurve = true,
		turnsBack = false,
	},
	{
		kind = "sharpCurve",
		weight = 6,
		lobeCount = 1,
		minLengthStuds = 80,
		maxLengthStuds = 180,
		minRadiusStuds = 60,
		maxRadiusStuds = 110,
		rampFraction = 0.35,
		isSimpleCurve = true,
		turnsBack = false,
	},
	{
		kind = "sCurve",
		weight = 4,
		lobeCount = 2,
		minLengthStuds = 240,
		maxLengthStuds = 480,
		minRadiusStuds = 90,
		maxRadiusStuds = 200,
		rampFraction = 0.3,
		isSimpleCurve = false,
		turnsBack = false,
	},
	{
		kind = "hairpinPair",
		weight = 6,
		lobeCount = 1,
		minLengthStuds = 20,
		maxLengthStuds = 50,
		minRadiusStuds = 60,
		maxRadiusStuds = 84,
		rampFraction = 0.25,
		isSimpleCurve = false,
		turnsBack = true,
		minTurnDegrees = 150,
		maxTurnDegrees = 180,
	},
	{
		kind = "uTurn",
		weight = 6,
		lobeCount = 1,
		-- No se usa: el largo sale del giro y del radio.
		minLengthStuds = 200,
		maxLengthStuds = 480,
		minRadiusStuds = 60,
		maxRadiusStuds = 85,
		rampFraction = 0.25,
		isSimpleCurve = true,
		turnsBack = false,
		minHeadingErrorDegrees = 90,
		minTurnDegrees = 150,
		maxTurnDegrees = 180,
	},
}

return {
	definitions = definitions,
}
