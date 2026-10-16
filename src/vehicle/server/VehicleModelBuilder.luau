--!strict
-- Arma el modelo de cajas del auto, anclado, hasta que llegue el asset. Los nombres son los de VehicleParts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings

local BODY_SIZE = Vector3.new(6, 2, 10)
local BODY_COLOR = Color3.fromRGB(150, 150, 150)
local WHEEL_COLOR = Color3.fromRGB(13, 13, 13)
local WHEEL_WIDTH_STUDS = 1.2

local VehicleModelBuilder = {}

local function createPart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function createBody(): Part
	local body = createPart(VehicleParts.BODY_NAME, BODY_SIZE, BODY_COLOR)
	body.Anchored = true
	body.CanCollide = true
	return body
end

local function createWheel(model: Model, body: Part, wheelName: string, offset: Vector3, diameter: number)
	local wheel =
		createPart(VehicleParts.wheelName(wheelName), Vector3.new(WHEEL_WIDTH_STUDS, diameter, diameter), WHEEL_COLOR)
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Massless = true
	wheel.CanCollide = false
	wheel.CanQuery = false
	wheel.CanTouch = false
	wheel.CFrame = body.CFrame * CFrame.new(offset)
	local motor = Instance.new("Motor6D")
	motor.Name = VehicleParts.motorName(wheelName)
	motor.Part0 = body
	motor.Part1 = wheel
	motor.C0 = CFrame.new(offset)
	motor.Parent = wheel
	wheel.Parent = model
end

local function createWheelForce(body: Part, wheelName: string, offset: Vector3)
	local mount = Instance.new("Attachment")
	mount.Name = VehicleParts.mountName(wheelName)
	mount.Position = offset
	mount.Parent = body
	local force = Instance.new("VectorForce")
	force.Name = VehicleParts.forceName(wheelName)
	force.Attachment0 = mount
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = false
	force.Force = Vector3.zero
	force.Parent = body
end

-- Devuelve el modelo sin padre y con el `Body` en `bodyCFrame`.
function VehicleModelBuilder.build(userId: number, bodyCFrame: CFrame, config: VehicleSettings): Model
	local model = Instance.new("Model")
	model.Name = VehicleParts.modelName(userId)
	model:SetAttribute(VehicleParts.OWNER_ATTRIBUTE, userId)
	local body = createBody()
	body.CFrame = bodyCFrame
	body.Parent = model
	model.PrimaryPart = body
	for _, wheel in config.WHEELS do
		local offset = VectorConversion.toVector3(wheel.offset)
		createWheel(model, body, wheel.name, offset, 2 * config.WHEEL_RADIUS_STUDS)
		createWheelForce(body, wheel.name, offset)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

return VehicleModelBuilder
