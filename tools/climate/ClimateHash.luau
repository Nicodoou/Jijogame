--!strict
-- Herramienta descartable: imprime un hash de 1.000 muestras de ClimateField para compararlo con el de Studio.
-- Desde la raíz del repo: luau tools/climate/ClimateHash.luau
-- Los dos hashes recorren los mismos 1.000 puntos con la semilla 12345: el primero mira los bits exactos de los tres
-- valores de cada muestra, y el segundo solo los primeros 9 decimales (por si Studio y el CLI difirieran en el último bit).

local ClimateField = require("../../src/world/core/ClimateField")

local SEED = 12345
local SAMPLE_COUNT = 1000
local AREA_DIAMETER_STUDS = 16000
local X_STRIDE = 7919
local Z_STRIDE = 104729
local X_OFFSET = 0.5
local Z_OFFSET = 0.25
local HASH_MULTIPLIER = 31
local HASH_MODULUS = 4294967296
local BITS_FORMAT = "<ddd"
local DECIMALS_FORMAT = "%.9f,%.9f,%.9f;"

local function hashText(text: string, hash: number): number
	for index = 1, #text do
		hash = (hash * HASH_MULTIPLIER + string.byte(text, index)) % HASH_MODULUS
	end
	return hash
end

local field = ClimateField.new(SEED)
local bitsHash, decimalsHash = 0, 0
for index = 1, SAMPLE_COUNT do
	local x = (index * X_STRIDE) % AREA_DIAMETER_STUDS - AREA_DIAMETER_STUDS / 2 + X_OFFSET
	local z = (index * Z_STRIDE) % AREA_DIAMETER_STUDS - AREA_DIAMETER_STUDS / 2 + Z_OFFSET
	local sample = field.sample(x, z)
	bitsHash = hashText(string.pack(BITS_FORMAT, sample.relief, sample.humidity, sample.temperature), bitsHash)
	decimalsHash =
		hashText(string.format(DECIMALS_FORMAT, sample.relief, sample.humidity, sample.temperature), decimalsHash)
end
print(`bits: {bitsHash}`)
print(`decimals: {decimalsHash}`)
