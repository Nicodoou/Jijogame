--!strict
-- Tipos compartidos por la infraestructura de biomas. Solo tipos: nada de lógica.

local Surface = require("../../shared/contracts/Surface")

-- Valores de clima ya normalizados por cuantil: todos en [0, 1].
export type ClimateSample = {
	relief: number,
	humidity: number,
	temperature: number,
}

export type ClimateRange = {
	min: number,
	max: number,
}

export type ClimateBox = {
	relief: ClimateRange,
	humidity: ClimateRange,
	temperature: ClimateRange,
}

export type MaterialShare = {
	material: string,
	proportion: number,
}

export type SurfacePatch = {
	surface: Surface.SurfaceKind,
	noiseScalePerStud: number,
	noiseThreshold: number,
	minDistanceFromShoulderStuds: number,
}

export type DecorationEntry = {
	kind: string,
	density: number,
	minSpacingStuds: number,
	collision: string,
}

export type BiomeDefinition = {
	id: string,
	climate: ClimateBox,
	terrain: {
		hillAmplitudeScale: number,
		hillRoughness: number,
	},
	materials: {
		surface: { MaterialShare },
		transition: string,
		deep: string,
	},
	surfaces: {
		offroad: Surface.SurfaceKind,
		patches: { SurfacePatch },
	},
	decoration: { DecorationEntry },
}

-- Peso de cada bioma por id. Los que no figuran pesan 0.
export type BiomeWeights = { [string]: number }

return {}
