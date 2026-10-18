--!strict
-- Pone las cajas de colisión de las piezas de daño en el auto (WP-18): una `Part` invisible por pieza, sin masa y
-- soldada al Body, así el peso, el centro de masa y la inercia quedan como sin cajas (medido en exp/hitbox). Solo
-- sirven para que el cliente dueño de red lea los golpes con `BindToCollisionSummaries`.
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DamageTypes = require(ReplicatedStorage.vehicle.core.damage.DamageTypes)
local HitboxLayout = require(ReplicatedStorage.vehicle.core.damage.HitboxLayout)
local VectorConversion = require(ReplicatedStorage.vehicle.shared.VectorConversion)
local VehicleModels = require(ReplicatedStorage.vehicle.core.VehicleModels)
local VehicleParts = require(ReplicatedStorage.vehicle.shared.VehicleParts)
local VehicleTypes = require(ReplicatedStorage.vehicle.core.VehicleTypes)

type MeshBox = DamageTypes.MeshBox
type PieceHitbox = DamageTypes.PieceHitbox
type VehicleSettings = VehicleTypes.VehicleSettings

local HitboxBuilder = {}

-- Las cajas no chocan entre sí; las piezas sueltas (VehicleDebris) tampoco chocan con las cajas del auto.
local function ensureCollisionGroups()
	for _, groupName in { VehicleParts.HITBOX_COLLISION_GROUP, VehicleParts.DEBRIS_COLLISION_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(groupName) then
			PhysicsService:RegisterCollisionGroup(groupName)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(
		VehicleParts.HITBOX_COLLISION_GROUP,
		VehicleParts.HITBOX_COLLISION_GROUP,
		false
	)
	PhysicsService:CollisionGroupSetCollidable(
		VehicleParts.HITBOX_COLLISION_GROUP,
		VehicleParts.DEBRIS_COLLISION_GROUP,
		false
	)
end

local function createHitboxPart(hitbox: PieceHitbox, body: BasePart): Part
	local part = Instance.new("Part")
	part.Name = VehicleParts.hitboxName(hitbox.pieceId)
	part.Size = VectorConversion.toVector3(hitbox.size)
	part.CFrame = body.CFrame * CFrame.new(VectorConversion.toVector3(hitbox.offset))
	part.Transparency = 1
	part.CastShadow = false
	part.Massless = true
	part.CanCollide = true
	-- Sin consulta: los rayos de las ruedas y de la cámara las ignoran. Sin toque: no se usa `Touched`.
	part.CanQuery = false
	part.CanTouch = false
	part.CollisionGroup = VehicleParts.HITBOX_COLLISION_GROUP
	part:SetAttribute(VehicleParts.HITBOX_PIECE_ATTRIBUTE, hitbox.pieceId)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- Crea las cajas de las piezas que la ficha da con malla y las cuelga del auto. Devuelve cuántas creó.
function HitboxBuilder.build(
	vehicle: Model,
	body: BasePart,
	sheet: VehicleModels.VehicleModelSheet,
	meshBoxes: { [string]: MeshBox },
	config: VehicleSettings
): number
	ensureCollisionGroups()
	local hitboxes = HitboxLayout.compute(sheet, meshBoxes, config, Workspace.Gravity)
	for _, hitbox in hitboxes do
		createHitboxPart(hitbox, body).Parent = vehicle
	end
	return #hitboxes
end

return HitboxBuilder
