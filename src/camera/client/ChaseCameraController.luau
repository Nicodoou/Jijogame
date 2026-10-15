--!strict
-- Posiciona la cámara de Roblox con lo que calcula el núcleo de la cámara. Hasta que haya auto, no la toca.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChaseCamera = require(ReplicatedStorage.camera.core.ChaseCamera)

type CameraState = ChaseCamera.CameraState
type CameraPose = ChaseCamera.CameraPose
type VehicleView = ChaseCamera.VehicleView

local ChaseCameraController = {}
ChaseCameraController.__index = ChaseCameraController

export type ChaseCameraController = typeof(setmetatable(
	{} :: {
		_camera: Camera,
		_state: CameraState?,
	},
	ChaseCameraController
))

function ChaseCameraController.new(camera: Camera): ChaseCameraController
	return setmetatable({ _camera = camera, _state = nil }, ChaseCameraController)
end

local function toVector3(value: vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function nextState(previous: CameraState?, view: VehicleView): CameraState
	return previous or ChaseCamera.newState(view)
end

function ChaseCameraController.step(
	self: ChaseCameraController,
	vehicleView: VehicleView?,
	isLookingBack: boolean,
	dt: number
)
	if vehicleView == nil then
		return
	end
	local state, pose = ChaseCamera.step(nextState(self._state, vehicleView), vehicleView, isLookingBack, dt)
	self._state = state
	self._camera.CameraType = Enum.CameraType.Scriptable
	self._camera.CFrame = CFrame.lookAt(toVector3(pose.position), toVector3(pose.lookAt))
end

return ChaseCameraController
