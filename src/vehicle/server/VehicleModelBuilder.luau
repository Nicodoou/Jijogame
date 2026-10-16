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

-- Densidad por defecto de Roblox: fija la masa total del auto (la del Body entero), que el lastre solo reparte.
local DEFAULT_DENSITY = 0.7
local BALLAST_NAME = "Ballast"
local MIN_BALLAST_MASS_FRACTION = 0.01
local PHYSICAL_FRICTION = 0.3
local PHYSICAL_ELASTICITY = 0.5

local function setDensity(part: Part, density: number)
	part.CustomPhysicalProperties = PhysicalProperties.new(density, PHYSICAL_FRICTION, PHYSICAL_ELASTICITY)
end

local function volumeOf(size: Vector3): number
	return size.X * size.Y * size.Z
end

-- Posición del centro de masa objetivo en el marco del Body: x = 0, z según el reparto de peso y y a la altura pedida
-- sobre el plano de montaje de las ruedas.
local function targetCenterOfMass(config: VehicleSettings): Vector3
	local frontZ, rearZ = math.huge, -math.huge
	for _, wheel in config.WHEELS do
		frontZ = math.min(frontZ, wheel.offset.z)
		rearZ = math.max(rearZ, wheel.offset.z)
	end
	local z = rearZ - config.FRONT_WEIGHT_FRACTION * (rearZ - frontZ)
	return Vector3.new(0, config.WHEELS[1].offset.y + config.CENTER_OF_MASS_HEIGHT_STUDS, z)
end

-- Marca sin masa, sin colisión y sin consulta cualquier modelo visual (y la pieza raíz, si lo es):
-- solo el Body y el lastre pesan, así el centro de masa depende de la configuración y no del modelo.
function VehicleModelBuilder.markMassless(root: Instance)
	local function mark(instance: Instance)
		if instance:IsA("BasePart") then
			instance.Massless = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
		end
	end
	mark(root)
	for _, descendant in root:GetDescendants() do
		mark(descendant)
	end
end

-- El lastre mide lo mismo que el Body: su inercia de giro es la de una caja, y el conjunto conserva la de la caja entera.
-- Con una pieza chica la inercia baja a la mitad y el giro a baja velocidad se vuelve inestable (bug 2026-10-16).
-- El Body tiene su masa en su centro, así que el lastre va a cmObjetivo · (masaBody + masaLastre) / masaLastre.
local function createBallast(model: Model, body: Part, config: VehicleSettings)
	local totalMass = volumeOf(BODY_SIZE) * DEFAULT_DENSITY
	local ballastFraction =
		math.clamp(config.BALLAST_MASS_FRACTION, MIN_BALLAST_MASS_FRACTION, 1 - MIN_BALLAST_MASS_FRACTION)
	local ballastMass = totalMass * ballastFraction
	setDensity(body, (totalMass - ballastMass) / volumeOf(BODY_SIZE))
	local ballast = createPart(BALLAST_NAME, BODY_SIZE, BODY_COLOR)
	setDensity(ballast, ballastMass / volumeOf(BODY_SIZE))
	ballast.Transparency = 1
	ballast.CanCollide = false
	ballast.CanQuery = false
	ballast.CanTouch = false
	ballast.CFrame = body.CFrame * CFrame.new(targetCenterOfMass(config) * (totalMass / ballastMass))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = ballast
	weld.Parent = ballast
	ballast.Parent = model
end

local function createWheel(model: Model, body: Part, wheelName: string, offset: Vector3, diameter: number)
	local wheel =
		createPart(VehicleParts.wheelName(wheelName), Vector3.new(WHEEL_WIDTH_STUDS, diameter, diameter), WHEEL_COLOR)
	wheel.Shape = Enum.PartType.Cylinder
	wheel.CFrame = body.CFrame * CFrame.new(offset)
	local motor = Instance.new("Motor6D")
	motor.Name = VehicleParts.motorName(wheelName)
	motor.Part0 = body
	motor.Part1 = wheel
	motor.C0 = CFrame.new(offset)
	motor.Parent = wheel
	wheel.Parent = model
	VehicleModelBuilder.markMassless(wheel)
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
	createBallast(model, body, config)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

return VehicleModelBuilder
