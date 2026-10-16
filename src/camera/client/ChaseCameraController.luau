--!strict
-- Posiciona la cámara de Roblox con lo que calcula el núcleo de la cámara. Hasta que haya auto, no la toca.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FirstPersonCamera = require(ReplicatedStorage.camera.core.FirstPersonCamera)

type CameraState = FirstPersonCamera.CameraState
type LookRates = FirstPersonCamera.LookRates
type VehicleView = FirstPersonCamera.VehicleView

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

function ChaseCameraController.step(
	self: ChaseCameraController,
	vehicleView: VehicleView?,
	look: LookRates,
	isLookingBack: boolean,
	dt: number
)
	if vehicleView == nil then
		return
	end
	local state, pose =
		FirstPersonCamera.step(self._state or FirstPersonCamera.newState(), vehicleView, look, isLookingBack, dt)
	self._state = state
	self._camera.CameraType = Enum.CameraType.Scriptable
	self._camera.CFrame = CFrame.fromMatrix(toVector3(pose.position), toVector3(pose.right), toVector3(pose.up))
end

return ChaseCameraController
