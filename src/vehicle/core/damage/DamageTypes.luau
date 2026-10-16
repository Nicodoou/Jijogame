--!strict
-- Tipos del daño por pieza (WP-15, docs/disenos/hitbox-y-dano.md). Solo tipos.

export type PieceKind =
	"chassisBase"
	| "bonnet"
	| "trunk"
	| "roof"
	| "door"
	| "frontBumper"
	| "rearBumper"
	| "grille"
	| "fender"
	| "sideSkirt"
	| "windshield"
	| "rearWindow"
	| "window"
	| "mirror"
	| "light"
	| "wheel"
	| "engine"
	| "radiator"
	| "gearbox"
	| "suspension"
	| "steering"
	| "fuelTank"

-- A qué pieza cubre una pieza y con qué fracción del daño que recibe.
export type Protection = { pieceId: string, factor: number }

export type PieceSpec = {
	id: string,
	kind: PieceKind,
	isExterior: boolean,
	-- K: daño por (stud/s)² por encima del umbral.
	damagePerImpact: number,
	-- Velocidad de impacto (studs/s) por debajo de la cual el golpe no daña.
	impactThreshold: number,
	-- Cuánto desgaste suma cada punto de daño.
	wearPerDamage: number,
	protects: { Protection },
	-- Rueda a la que pertenece la pieza (1 a 4, en el orden FL, FR, RL, RR), si corresponde.
	wheelIndex: number?,
}

export type PieceState = {
	damage: number,
	wear: number,
	isDetached: boolean,
}

export type DamageState = {
	pieces: { [string]: PieceState },
}

export type DamageEvent = {
	pieceId: string,
	kind: "damaged" | "detached",
	damage: number,
}

-- Las fichas de las piezas, por id.
export type PieceSpecs = { [string]: PieceSpec }

return {}
