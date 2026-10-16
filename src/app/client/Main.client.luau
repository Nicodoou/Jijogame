--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InputSmoother = require(ReplicatedStorage.input.core.InputSmoother)
local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local VehicleSimulator = require(ReplicatedStorage.vehicle.core.VehicleSimulator)
local FirstPersonCameraController = require("../camera/FirstPersonCameraController")
local OwnVehicleVisibility = require("../camera/OwnVehicleVisibility")
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
local cameraController = FirstPersonCameraController.new(Workspace.CurrentCamera)
local rearAxleVisual = RearAxleVisual.new(Players.LocalPlayer.UserId)
local ownVehicleVisibility = OwnVehicleVisibility.new()
local inputState = InputSmoother.newState()

controller:start()

RunService.Heartbeat:Connect(function()
	world.step()
end)

RunService.PreSimulation:Connect(function(dt)
	inputState = InputSmoother.step(inputState, inputReader:read(), dt)
	controller:step(inputState, dt)
end)

-- La mirada se suaviza en PreRender con el dt del cuadro: el mouse entrega píxeles por cuadro de render,
-- y en PreSimulation (varias veces por cuadro) se confundirían los dt.
RunService.PreRender:Connect(function(dt)
	local look = InputSmoother.step(InputSmoother.newState(), inputReader:read(), dt)
	cameraController:step(
		controller:getVehicleView(),
		{ yawRate = look.lookYawRate, pitchRate = look.lookPitchRate },
		look.isLookingBack,
		dt
	)
	rearAxleVisual:step()
	ownVehicleVisibility:step(controller:getModel())
end)
