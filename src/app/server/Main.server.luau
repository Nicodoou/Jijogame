--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnPointStub = require(ReplicatedStorage.app.SpawnPointStub)
local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local VehicleSpawner = require("../vehicle/VehicleSpawner")

-- Stub hasta el adaptador del mundo (#17 / #35 / #36)
local getSpawnPoint = SpawnPointStub.getSpawnPoint

local spawner = VehicleSpawner.new(getSpawnPoint, VehicleConfig)

Players.PlayerAdded:Connect(function(player)
	spawner:spawnFor(player)
end)
Players.PlayerRemoving:Connect(function(player)
	spawner:despawnFor(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(spawner.spawnFor, spawner, player)
end
