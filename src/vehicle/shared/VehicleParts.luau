--!strict
-- Nombres de las instancias del auto. Los comparten el servidor, que las crea, y el cliente, que las busca.
local VehicleParts = {}

VehicleParts.BODY_NAME = "Body"
VehicleParts.OWNER_ATTRIBUTE = "OwnerUserId"
VehicleParts.RELEASE_REMOTE_NAME = "VehicleReleaseRequest"

function VehicleParts.modelName(userId: number): string
	return "Vehicle_" .. userId
end

function VehicleParts.wheelName(wheelName: string): string
	return "Wheel" .. wheelName
end

function VehicleParts.motorName(wheelName: string): string
	return "Motor" .. wheelName
end

function VehicleParts.mountName(wheelName: string): string
	return "Mount" .. wheelName
end

function VehicleParts.forceName(wheelName: string): string
	return "Force" .. wheelName
end

return VehicleParts
