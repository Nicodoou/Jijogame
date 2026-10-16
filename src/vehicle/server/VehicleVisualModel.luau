--!strict
-- Pone el modelo visual (el 147) sobre el auto. El modelo no pesa: lo soldado sigue al Body o a su rueda física,
-- y el eje trasero rígido queda anclado para que el cliente lo mueva entre las dos ruedas traseras.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Suspension = require(ReplicatedStorage.vehicle.core.Suspension)
local VehicleModels = require(ReplicatedStorage.vehicle.core.VehicleModels)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleModelSheet = VehicleModels.VehicleModelSheet

-- La compresión estática no depende de la masa: se cancela entre la carga y la rigidez.
local UNIT_MASS = 1

local VehicleVisualModel = {}

local function staticCompression(config: VehicleSettings): number
	local wheelCount = #config.WHEELS
	return Suspension.staticLoad(UNIT_MASS, Workspace.Gravity, wheelCount)
		/ Suspension.springRate(UNIT_MASS, wheelCount, config)
end

-- Altura (en el marco del Body) donde apoya el piso: es la misma cuenta del núcleo, con el resorte en reposo.
local function groundHeight(config: VehicleSettings): number
	local mountY = config.WHEELS[1].offset.y
	return mountY - (config.SUSPENSION_REST_LENGTH_STUDS - staticCompression(config)) - config.WHEEL_RADIUS_STUDS
end

-- Centro del eje trasero en reposo, en el marco del Body.
local function rearAxleRest(body: BasePart, config: VehicleSettings): CFrame
	local rear = config.WHEELS[3].offset
	local centerY = rear.y - (config.SUSPENSION_REST_LENGTH_STUDS - staticCompression(config))
	return body.CFrame * CFrame.new(0, centerY, rear.z)
end

local function weld(first: BasePart, second: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = first
	joint.Part1 = second
	joint.Parent = second
end

local function physicalWheel(vehicle: Model, sheet: VehicleModelSheet, meshName: string): BasePart?
	local wheelName = sheet.frontWheelMeshes[meshName]
	local wheel = if wheelName ~= nil then vehicle:FindFirstChild(VehicleParts.wheelName(wheelName)) else nil
	return if wheel ~= nil and wheel:IsA("BasePart") then wheel else nil
end

local function attachPart(
	vehicle: Model,
	body: BasePart,
	part: BasePart,
	sheet: VehicleModelSheet,
	config: VehicleSettings
)
	part.Anchored = false
	local wheel = physicalWheel(vehicle, sheet, part.Name)
	if wheel ~= nil then
		part.CFrame = wheel.CFrame
		weld(wheel, part)
	elseif table.find(sheet.rearAxleMeshes, part.Name) ~= nil then
		part.Anchored = true
		part:SetAttribute(
			VehicleParts.REAR_AXLE_OFFSET_ATTRIBUTE,
			rearAxleRest(body, config):ToObjectSpace(part.CFrame)
		)
	else
		weld(body, part)
	end
end

-- Las cajas físicas quedan invisibles: lo que se ve es el modelo.
local function hidePhysicalBoxes(vehicle: Model, visual: Model)
	for _, descendant in vehicle:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant:IsDescendantOf(visual) then
			descendant.Transparency = 1
		end
	end
end

-- Si el modelo no está (por ejemplo, el archivo no se sincronizó), el auto queda con sus cajas visibles.
function VehicleVisualModel.attach(
	vehicle: Model,
	body: BasePart,
	sheet: VehicleModelSheet,
	config: VehicleSettings,
	markMassless: (Instance) -> ()
): Model?
	local models = ReplicatedStorage.vehicle:FindFirstChild("models")
	local template = if models ~= nil then models:FindFirstChild(sheet.fileName) else nil
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local visual = template:Clone()
	visual.Name = VehicleParts.VISUAL_MODEL_NAME
	visual:PivotTo(
		body.CFrame
			* CFrame.new(0, groundHeight(config) - sheet.modelGroundY, 0)
			* CFrame.Angles(0, math.rad(sheet.turnDegrees), 0)
	)
	markMassless(visual)
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			attachPart(vehicle, body, descendant, sheet, config)
		end
	end
	visual.Parent = vehicle
	hidePhysicalBoxes(vehicle, visual)
	return visual
end

return VehicleVisualModel
