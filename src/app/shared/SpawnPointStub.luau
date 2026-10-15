--!strict
-- Stub hasta el adaptador del mundo (#35). Lo usan el servidor y el cliente, así los dos dan el mismo punto.
-- Está sobre el Baseplate, lejos de la SpawnLocation que viene en el origen, mirando a -z.
local RoadPoint = require("../shared/contracts/RoadPoint")

local SPAWN_POSITION = vector.create(0, 1, 60)
local SPAWN_DIRECTION = vector.create(0, 0, -1)
local SPAWN_ARC_LENGTH = 0

local SpawnPointStub = {}

function SpawnPointStub.getSpawnPoint(): RoadPoint.RoadPoint
	return { position = SPAWN_POSITION, direction = SPAWN_DIRECTION, arcLength = SPAWN_ARC_LENGTH }
end

return SpawnPointStub
