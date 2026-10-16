--!strict
-- Fichas ficticias para probar que la infraestructura de biomas funciona con N fichas. Solo existen en las pruebas:
-- el juego tiene únicamente `forest`, y estas fichas se pasan a las funciones como catálogo inyectado.

local BiomeCatalog = require("../../src/world/core/BiomeCatalog")
local BiomeTypes = require("../../src/world/core/BiomeTypes")
local WorldConfig = require("../../src/world/core/WorldConfig")

export type BiomeDefinition = BiomeTypes.BiomeDefinition

-- Tres cajas separadas por 0,2 (relieve) y 0,3 (humedad): con el radio de transición de WorldConfig el interior de cada
-- una es puro.
local lowland: BiomeDefinition = {
	id = "lowland",
	climate = {
		relief = { min = 0, max = 0.4 },
		humidity = { min = 0, max = 0.5 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 0.5, hillRoughness = 1 },
	materials = {
		surface = { { material = "Grass", proportion = 0.6 }, { material = "LeafyGrass", proportion = 0.4 } },
		transition = "Ground",
		deep = "Ground",
	},
	surfaces = { offroad = "Grass", patches = {} },
	decoration = { { kind = "Bush", density = 0.01, minSpacingStuds = 8, collision = "sphere" } },
}

local highland: BiomeDefinition = {
	id = "highland",
	climate = {
		relief = { min = 0.6, max = 1 },
		humidity = { min = 0, max = 0.5 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 3, hillRoughness = 2 },
	materials = {
		surface = { { material = "Rock", proportion = 0.7 }, { material = "Slate", proportion = 0.3 } },
		transition = "Cobblestone",
		deep = "Basalt",
	},
	surfaces = {
		offroad = "Mud",
		patches = {
			{ surface = "Grass", noiseScalePerStud = 0.02, noiseThreshold = 0.1, minDistanceFromShoulderStuds = 3 },
		},
	},
	decoration = {},
}

local wetland: BiomeDefinition = {
	id = "wetland",
	climate = {
		relief = { min = 0, max = 1 },
		humidity = { min = 0.8, max = 1 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 0.1, hillRoughness = 0.5 },
	materials = {
		surface = { { material = "Mud", proportion = 0.5 }, { material = "Sand", proportion = 0.5 } },
		transition = "Limestone",
		deep = "Ground",
	},
	surfaces = { offroad = "Mud", patches = {} },
	decoration = {},
}

local function copyValue(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = copyValue(inner)
	end
	return copy
end

-- El bosque del juego ya no tiene manchones de barro (issue #78). Esta copia los conserva con los valores MUD_* de
-- WorldConfig, para seguir probando el mecanismo de manchones con una ficha de pasto y barro.
local muddyForest: BiomeDefinition = copyValue(BiomeCatalog.forest)
muddyForest.surfaces.patches = {
	{
		surface = "Mud",
		noiseScalePerStud = WorldConfig.MUD_NOISE_SCALE_PER_STUD,
		noiseThreshold = WorldConfig.MUD_NOISE_THRESHOLD,
		minDistanceFromShoulderStuds = WorldConfig.MUD_MIN_DISTANCE_FROM_SHOULDER_STUDS,
	},
}

local BiomeTestCatalog = {}

BiomeTestCatalog.lowland = lowland
BiomeTestCatalog.highland = highland
BiomeTestCatalog.wetland = wetland
BiomeTestCatalog.single = { BiomeCatalog.forest }
BiomeTestCatalog.muddyForest = muddyForest
BiomeTestCatalog.muddyForestOnly = { muddyForest }
BiomeTestCatalog.pair = { lowland, highland }
BiomeTestCatalog.triple = { lowland, highland, wetland }

-- Copia profunda y modificable de una ficha, para armar fichas mal formadas.
function BiomeTestCatalog.copyDefinition(definition: BiomeDefinition): any
	return copyValue(definition)
end

return BiomeTestCatalog
