--!strict
-- Posiciona la cámara de Roblox con lo que calcula el núcleo de la cámara. Hasta que haya auto, no la toca.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage.camera.core.CameraConfig)
local FirstPersonCamera = require(ReplicatedStorage.camera.core.FirstPersonCamera)
local TuningOverrides = require(ReplicatedStorage.vehicle.shared.TuningOverrides)

type CameraConfig = typeof(CameraConfig)
type CameraState = FirstPersonCamera.CameraState
type LookRates = FirstPersonCamera.LookRates
type VehicleView = FirstPersonCamera.VehicleView

-- Si la cabeza se mueve más que esto entre dos cuadros, el auto reapareció: el estado viejo ya no sirve.
local RESPAWN_JUMP_STUDS = 50

local FirstPersonCameraController = {}
FirstPersonCameraController.__index = FirstPersonCameraController

export type FirstPersonCameraController = typeof(setmetatable(
	{} :: {
		_camera: Camera,
		_tuning: TuningOverrides.TuningOverrides<CameraConfig>,
		_state: CameraState?,
		_lastHeadPosition: vector?,
	},
	FirstPersonCameraController
))

function FirstPersonCameraController.new(camera: Camera): FirstPersonCameraController
	return setmetatable({
		_camera = camera,
		_tuning = TuningOverrides.new(CameraConfig, Workspace, RunService:IsStudio()),
		_state = nil,
		_lastHeadPosition = nil,
	}, FirstPersonCameraController)
end

local function toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function hasRespawned(self: FirstPersonCameraController, vehicleView: VehicleView): boolean
	local last = self._lastHeadPosition
	return last ~= nil and vector.magnitude(vehicleView.headPosition - last) > RESPAWN_JUMP_STUDS
end

local function currentState(self: FirstPersonCameraController, vehicleView: VehicleView): CameraState
	local state = self._state
	if state == nil or hasRespawned(self, vehicleView) then
		return FirstPersonCamera.newState()
	end
	return state
end

function FirstPersonCameraController.step(
	self: FirstPersonCameraController,
	vehicleView: VehicleView?,
	look: LookRates,
	isLookingBack: boolean,
	dt: number
)
	if vehicleView == nil then
		self._state, self._lastHeadPosition = nil, nil
		return
	end
	local config = self._tuning:getConfig()
	local state, pose =
		FirstPersonCamera.step(currentState(self, vehicleView), vehicleView, look, isLookingBack, dt, config)
	self._state, self._lastHeadPosition = state, vehicleView.headPosition
	self._camera.CameraType = Enum.CameraType.Scriptable
	self._camera.FieldOfView = config.FIELD_OF_VIEW_DEGREES
	self._camera.CFrame = CFrame.fromMatrix(toVector3(pose.position), toVector3(pose.right), toVector3(pose.up))
end

return FirstPersonCameraController
