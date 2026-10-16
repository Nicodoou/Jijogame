--!strict
-- Fichas de bioma como datos (patrón Type Object): sumar un bioma es agregar una ficha y ponerla en `all`.
-- El resto de la infraestructura (clima, pesos y mezcla) solo lee estos datos y recibe el catálogo por parámetro.

local BiomeTypes = require("./BiomeTypes")
local BiomeValidation = require("./BiomeValidation")

export type BiomeDefinition = BiomeTypes.BiomeDefinition

local GRASS_PROPORTION = 0.8
local LEAFY_GRASS_PROPORTION = 0.2

-- Bosque: reproduce lo que hace hoy el terreno, con pasto y tierra debajo. Su caja ocupa todo el clima, así que
-- con un solo bioma el peso es 1 en cualquier punto.
local forest: BiomeDefinition = {
	id = "forest",
	climate = {
		relief = { min = 0, max = 1 },
		humidity = { min = 0, max = 1 },
		temperature = { min = 0, max = 1 },
	},
	terrain = { hillAmplitudeScale = 1, hillRoughness = 1 },
	materials = {
		surface = {
			{ material = "Grass", proportion = GRASS_PROPORTION },
			{ material = "LeafyGrass", proportion = LEAFY_GRASS_PROPORTION },
		},
		transition = "Ground",
		deep = "Ground",
	},
	surfaces = {
		offroad = "Grass",
		-- Sin manchones de barro por ahora: el campo es solo pasto. Se retoman con el issue #78 (los MUD_* siguen en
		-- WorldConfig).
		patches = {},
	},
	-- Todavía no hay decorado: lo define el WP del decorado.
	decoration = {},
}

local function freezeDeep(value: { [unknown]: unknown })
	for _, inner in value do
		if type(inner) == "table" then
			freezeDeep(inner :: { [unknown]: unknown })
		end
	end
	table.freeze(value)
end

freezeDeep(forest)

return table.freeze({
	forest = forest,
	-- Las fichas del juego, en orden fijo: el orden desempata y ordena las elecciones al azar coherente.
	all = table.freeze({ forest }),
	validate = BiomeValidation.validate,
})
