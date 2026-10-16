--!strict
-- Elige la semilla del mundo al arrancar la partida y la publica para los clientes. También da el punto de aparición,
-- que sale solo de la semilla y del núcleo, así es el mismo que calcula el cliente.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoadPoint = require(ReplicatedStorage.shared.contracts.RoadPoint)
local SpawnPoint = require(ReplicatedStorage.world.core.SpawnPoint)

export type WorldSeedServer = {
	seed: number,
	getSpawnPoint: RoadPoint.GetSpawnPoint,
}

-- Mismo nombre que lee WorldClient.
local SEED_ATTRIBUTE_NAME = "WorldSeed"
-- Un entero positivo de 31 bits entra sin pérdida en un double y en las cuentas enteras del núcleo.
local MAX_SEED = 2 ^ 31 - 1

local WorldSeedServer = {}

-- Elige y publica la semilla. Tiene que correr antes de crear el spawner y de conectar PlayerAdded.
function WorldSeedServer.start(): WorldSeedServer
	local seed = Random.new():NextInteger(1, MAX_SEED)
	ReplicatedStorage:SetAttribute(SEED_ATTRIBUTE_NAME, seed)
	local spawnPoint = SpawnPoint.compute(seed)
	return {
		seed = seed,
		getSpawnPoint = function()
			return spawnPoint
		end,
	}
end

return WorldSeedServer
