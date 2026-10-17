--!strict
-- Las instancias del auto propio que usa el controlador: el chasis, la fuerza y el motor de cada rueda.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type ChassisSample = VehicleTypes.ChassisSample
type VehicleSettings = VehicleTypes.VehicleSettings

export type VehicleRig = {
	model: Model,
	body: BasePart,
	mounts: { Vector3 },
	forces: { VectorForce },
	motors: { Motor6D },
}

local VehicleRig = {}

local function findOwnModel(userId: number): Model?
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(VehicleParts.OWNER_ATTRIBUTE) == userId then
			return child
		end
	end
	return nil
end

-- Puede dar nil si el modelo todavía no terminó de replicarse: el controlador vuelve a intentar en el frame siguiente.
function VehicleRig.find(userId: number, config: VehicleSettings): VehicleRig?
	local model = findOwnModel(userId)
	local body = if model ~= nil then model:FindFirstChild(VehicleParts.BODY_NAME) else nil
	if model == nil or body == nil or not body:IsA("BasePart") then
		return nil
	end
	local mounts, forces, motors = {}, {}, {}
	for index, wheel in config.WHEELS do
		local wheelPart = model:FindFirstChild(VehicleParts.wheelName(wheel.name))
		local motor = if wheelPart ~= nil then wheelPart:FindFirstChild(VehicleParts.motorName(wheel.name)) else nil
		local force = body:FindFirstChild(VehicleParts.forceName(wheel.name))
		if motor == nil or force == nil or not motor:IsA("Motor6D") or not force:IsA("VectorForce") then
			return nil
		end
		mounts[index], forces[index], motors[index] = VectorConversion.toVector3(wheel.offset), force, motor
	end
	return { model = model, body = body, mounts = mounts, forces = forces, motors = motors }
end

-- El estado del chasis en el mundo, en el formato del núcleo.
function VehicleRig.readChassis(body: BasePart): ChassisSample
	local cframe = body.CFrame
	return {
		origin = VectorConversion.toVector(body.Position),
		position = VectorConversion.toVector(body.AssemblyCenterOfMass),
		right = VectorConversion.toVector(cframe.RightVector),
		up = VectorConversion.toVector(cframe.UpVector),
		forward = VectorConversion.toVector(cframe.LookVector),
		linearVelocity = VectorConversion.toVector(body.AssemblyLinearVelocity),
		angularVelocity = VectorConversion.toVector(body.AssemblyAngularVelocity),
		mass = body.AssemblyMass,
		gravity = Workspace.Gravity,
	}
end

return VehicleRig
