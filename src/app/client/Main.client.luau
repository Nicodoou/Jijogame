--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputSmoother = require(ReplicatedStorage.input.core.InputSmoother)
local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local VehicleSimulator = require(ReplicatedStorage.vehicle.core.VehicleSimulator)
local ChaseCameraController = require("../camera/ChaseCameraController")
local InputReader = require("../input/InputReader")
local VehicleController = require("../vehicle/VehicleController")
local RearAxleVisual = require("../vehicle/RearAxleVisual")
local WorldClient = require("../world/WorldClient")

-- El mundo y el auto se piden la posición y el terreno uno al otro: se arma primero el mundo (necesita la semilla) y
-- recién después el auto, así getVehiclePosition ya puede devolver el punto de aparición desde el primer frame.
local controller: VehicleController.VehicleController
local world = WorldClient.new({
	seed = WorldClient.waitForSeed(),
	getVehiclePosition = function()
		return controller:getVehiclePosition()
	end,
})

local inputReader = InputReader.new()
controller = VehicleController.new({
	getSurfaceAt = world.getSurfaceAt,
	isWorldReadyAt = world.isWorldReadyAt,
	getSpawnPoint = world.getSpawnPoint,
	simulator = VehicleSimulator,
	config = VehicleConfig,
})
local cameraController = ChaseCameraController.new(Workspace.CurrentCamera)
local rearAxleVisual = RearAxleVisual.new(Players.LocalPlayer.UserId)
local inputState = InputSmoother.newState()

controller:start()

RunService.Heartbeat:Connect(function()
	world.step()
end)

RunService.PreSimulation:Connect(function(dt)
	inputState = InputSmoother.step(inputState, inputReader:read(), dt)
	controller:step(inputState, dt)
end)

RunService.PreRender:Connect(function(dt)
	cameraController:step(controller:getVehicleView(), inputState.isLookingBack, dt)
	rearAxleVisual:step()
end)
