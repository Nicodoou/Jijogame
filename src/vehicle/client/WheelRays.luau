--!strict
-- Un rayo por rueda hacia abajo del chasis. Sale desde arriba del montaje porque un rayo que arranca
-- dentro del Terrain devuelve nil (#31).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Surface = require(ReplicatedStorage.shared.contracts.Surface)
local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings
type WheelContact = VehicleTypes.WheelContact

local RAY_START_ABOVE_MOUNT_STUDS = 3
local RAY_EXTRA_STUDS = 1

local WheelRays = {}

function WheelRays.newParams(model: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	return params
end

local function castWheel(
	chassisCFrame: CFrame,
	mount: Vector3,
	params: RaycastParams,
	getSurfaceAt: Surface.GetSurfaceAt,
	config: VehicleSettings
): WheelContact
	local up = chassisCFrame.UpVector
	local mountWorld = chassisCFrame:PointToWorldSpace(mount)
	local length = RAY_START_ABOVE_MOUNT_STUDS
		+ config.SUSPENSION_REST_LENGTH_STUDS
		+ config.WHEEL_RADIUS_STUDS
		+ RAY_EXTRA_STUDS
	local hit = Workspace:Raycast(mountWorld + up * RAY_START_ABOVE_MOUNT_STUDS, -up * length, params)
	if hit == nil then
		return { hasHit = false, distanceStuds = 0, point = VectorConversion.toVector(mountWorld), surface = nil }
	end
	local point = VectorConversion.toVector(hit.Position)
	return {
		hasHit = true,
		distanceStuds = hit.Distance - RAY_START_ABOVE_MOUNT_STUDS,
		point = point,
		surface = getSurfaceAt(point),
	}
end

function WheelRays.cast(
	chassisCFrame: CFrame,
	mounts: { Vector3 },
	params: RaycastParams,
	getSurfaceAt: Surface.GetSurfaceAt,
	config: VehicleSettings
): { WheelContact }
	local contacts = {}
	for index, mount in mounts do
		contacts[index] = castWheel(chassisCFrame, mount, params, getSurfaceAt, config)
	end
	return contacts
end

return WheelRays
