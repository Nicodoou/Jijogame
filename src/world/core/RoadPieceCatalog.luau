--!strict
-- Datos de las piezas de ruta. Sumar o ajustar una pieza es cambiar esta tabla, no código.
-- Largos en studs (se redondean a pasos de integración), radios en studs y pendientes en grados.
-- Toda pieza empieza y termina con curvatura 0 y la sube y baja en rampas lineales, así la curvatura es continua.
-- El orden de la lista importa: el sorteo la recorre en orden y tiene que dar lo mismo en cualquier plataforma.

export type PieceKind = "straight" | "gentleCurve" | "sharpCurve" | "sCurve"

export type PieceDefinition = {
	kind: PieceKind,
	weight: number,
	-- Cantidad de lóbulos de curvatura. La S tiene dos, de sentido opuesto.
	lobeCount: number,
	minLengthStuds: number,
	maxLengthStuds: number,
	-- Radio de la parte constante de cada lóbulo. La recta tiene radio infinito.
	minRadiusStuds: number,
	maxRadiusStuds: number,
	-- Fracción de cada lóbulo que se usa para subir (y otra igual para bajar) la curvatura.
	rampFraction: number,
	minSlopeDegrees: number,
	maxSlopeDegrees: number,
}

local definitions: { PieceDefinition } = {
	{
		kind = "straight",
		weight = 3,
		lobeCount = 1,
		minLengthStuds = 120,
		maxLengthStuds = 360,
		minRadiusStuds = math.huge,
		maxRadiusStuds = math.huge,
		rampFraction = 0.25,
		minSlopeDegrees = -5,
		maxSlopeDegrees = 5,
	},
	{
		kind = "gentleCurve",
		weight = 4,
		lobeCount = 1,
		minLengthStuds = 180,
		maxLengthStuds = 420,
		minRadiusStuds = 180,
		maxRadiusStuds = 400,
		rampFraction = 0.3,
		minSlopeDegrees = -6,
		maxSlopeDegrees = 6,
	},
	{
		kind = "sharpCurve",
		weight = 2,
		lobeCount = 1,
		minLengthStuds = 80,
		maxLengthStuds = 180,
		minRadiusStuds = 60,
		maxRadiusStuds = 110,
		rampFraction = 0.35,
		minSlopeDegrees = -3,
		maxSlopeDegrees = 3,
	},
	{
		kind = "sCurve",
		weight = 2,
		lobeCount = 2,
		minLengthStuds = 240,
		maxLengthStuds = 480,
		minRadiusStuds = 90,
		maxRadiusStuds = 200,
		rampFraction = 0.3,
		minSlopeDegrees = -4,
		maxSlopeDegrees = 4,
	},
}

return {
	definitions = definitions,
}
