--!strict
-- Pone el modelo visual (el 147) sobre el auto. El modelo no pesa: lo soldado sigue al Body o a su rueda física,
-- y el eje trasero rígido queda anclado para que el cliente lo mueva entre las dos ruedas traseras.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ModelPlacement = require(ReplicatedStorage.vehicle.core.ModelPlacement)
local VehicleModels = require(ReplicatedStorage.vehicle.core.VehicleModels)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleModelSheet = VehicleModels.VehicleModelSheet

local VehicleVisualModel = {}

-- Centro del eje trasero en reposo, en el marco del Body.
local function rearAxleRest(body: BasePart, config: VehicleSettings): CFrame
	local rear = config.WHEELS[3].offset
	local centerY = rear.y
		- (config.SUSPENSION_REST_LENGTH_STUDS - ModelPlacement.staticCompression(config, Workspace.Gravity))
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
		-- Solo la orientación: el eje queda centrado entre las ruedas (el modelo lo trae 0,05 más abajo y al girar bailaría).
		local offset = rearAxleRest(body, config):ToObjectSpace(part.CFrame)
		part:SetAttribute(VehicleParts.REAR_AXLE_OFFSET_ATTRIBUTE, offset.Rotation)
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
	local heightStuds, turnRadians = ModelPlacement.pivotOffset(sheet, config, Workspace.Gravity)
	visual:PivotTo(body.CFrame * CFrame.new(0, heightStuds, 0) * CFrame.Angles(0, turnRadians, 0))
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
