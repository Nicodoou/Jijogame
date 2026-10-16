--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Surface = require(ReplicatedStorage.shared.contracts.Surface)
local SpawnPointStub = require(ReplicatedStorage.app.SpawnPointStub)
local InputSmoother = require(ReplicatedStorage.input.core.InputSmoother)
local VehicleConfig = require(ReplicatedStorage.vehicle.core.VehicleConfig)
local VehicleSimulator = require(ReplicatedStorage.vehicle.core.VehicleSimulator)
local ChaseCameraController = require("../camera/ChaseCameraController")
local InputReader = require("../input/InputReader")
local VehicleController = require("../vehicle/VehicleController")

-- Stub hasta el adaptador del mundo (#17 / #35 / #36)
local function getSurfaceAt(_position: vector): Surface.SurfaceKind?
	return "Road"
end

-- Stub hasta el adaptador del mundo (#17 / #35 / #36)
local function isWorldReadyAt(_position: vector): boolean
	return true
end

-- Stub hasta el adaptador del mundo (#17 / #35 / #36)
local getSpawnPoint = SpawnPointStub.getSpawnPoint

local inputReader = InputReader.new()
local controller = VehicleController.new({
	getSurfaceAt = getSurfaceAt,
	isWorldReadyAt = isWorldReadyAt,
	getSpawnPoint = getSpawnPoint,
	simulator = VehicleSimulator,
	config = VehicleConfig,
})
local cameraController = ChaseCameraController.new(Workspace.CurrentCamera)
local inputState = InputSmoother.newState()

controller:start()

RunService.PreSimulation:Connect(function(dt)
	inputState = InputSmoother.step(inputState, inputReader:read(), dt)
	controller:step(inputState, dt)
end)

RunService.PreRender:Connect(function(dt)
	cameraController:step(controller:getVehicleView(), inputState.isLookingBack, dt)
end)
