--!strict
-- Mueve el eje trasero rígido del modelo visual: lo ubica entre las dos ruedas físicas traseras, lo inclina si una
-- sube más que la otra y lo hace girar como la rueda trasera izquierda. Solo es visual (la suspensión sigue
-- siendo independiente por rueda).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)

type Rig = {
	body: BasePart,
	leftWheel: BasePart,
	rightWheel: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
}

local RearAxleVisual = {}
RearAxleVisual.__index = RearAxleVisual

export type RearAxleVisual = typeof(setmetatable(
	{} :: {
		_userId: number,
		_rig: Rig?,
	},
	RearAxleVisual
))

function RearAxleVisual.new(userId: number): RearAxleVisual
	return setmetatable({ _userId = userId, _rig = nil }, RearAxleVisual)
end

local function findPart(parent: Instance?, name: string): BasePart?
	local child = if parent ~= nil then parent:FindFirstChild(name) else nil
	return if child ~= nil and child:IsA("BasePart") then child else nil
end

-- Puede dar nil mientras el modelo todavía no terminó de replicarse: se vuelve a intentar en el frame siguiente.
local function findRig(userId: number): Rig?
	local vehicle = Workspace:FindFirstChild(VehicleParts.modelName(userId))
	local visual = if vehicle ~= nil then vehicle:FindFirstChild(VehicleParts.VISUAL_MODEL_NAME) else nil
	local body = findPart(vehicle, VehicleParts.BODY_NAME)
	local left = findPart(vehicle, VehicleParts.wheelName("RL"))
	local right = findPart(vehicle, VehicleParts.wheelName("RR"))
	if visual == nil or body == nil or left == nil or right == nil then
		return nil
	end
	local parts, offsets = {}, {}
	for _, child in visual:GetChildren() do
		local offset = child:GetAttribute(VehicleParts.REAR_AXLE_OFFSET_ATTRIBUTE)
		if child:IsA("BasePart") and typeof(offset) == "CFrame" then
			table.insert(parts, child)
			table.insert(offsets, offset)
		end
	end
	return { body = body, leftWheel = left, rightWheel = right, parts = parts, offsets = offsets }
end

local function axleFrame(rig: Rig): CFrame
	local center = (rig.leftWheel.Position + rig.rightWheel.Position) / 2
	local axis = (rig.rightWheel.Position - rig.leftWheel.Position).Unit
	local up = rig.body.CFrame.UpVector
	up = (up - axis * up:Dot(axis)).Unit
	local spin = rig.body.CFrame:ToObjectSpace(rig.leftWheel.CFrame):ToEulerAnglesXYZ()
	return CFrame.fromMatrix(center, axis, up, axis:Cross(up)) * CFrame.Angles(spin, 0, 0)
end

-- Corre en PreRender.
function RearAxleVisual.step(self: RearAxleVisual)
	self._rig = self._rig or findRig(self._userId)
	local rig = self._rig
	if rig == nil then
		return
	end
	local frame = axleFrame(rig)
	for index, part in rig.parts do
		part.CFrame = frame * rig.offsets[index]
	end
end

return RearAxleVisual
