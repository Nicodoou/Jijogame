--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local DamageReportReceiver = require("../vehicle/DamageReportReceiver")
local VehicleSpawner = require("../vehicle/VehicleSpawner")
local WorldSeedServer = require("../world/WorldSeedServer")

-- La semilla se publica antes del spawner y de PlayerAdded: si no, el primer auto aparecería sin punto de aparición.
local worldSeed = WorldSeedServer.start()

local spawner = VehicleSpawner.new(worldSeed.getSpawnPoint, VehicleConfig)
local damageReceiver = DamageReportReceiver.new()

Players.PlayerAdded:Connect(function(player)
	spawner:spawnFor(player)
end)
Players.PlayerRemoving:Connect(function(player)
	spawner:despawnFor(player)
	damageReceiver:clear(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(spawner.spawnFor, spawner, player)
end
