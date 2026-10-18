--!strict
-- Cajas de colisión de cada pieza de daño (WP-18). Puro: toma las cajas de las mallas (marco del modelo), junta las de
-- cada pieza y las pasa al marco del Body con la colocación del modelo. Las mallas sin caja se ignoran.
local DamageConfig = require("./DamageConfig")
local DamageTypes = require("./DamageTypes")
local ModelPlacement = require("../ModelPlacement")
local VehicleModels = require("../VehicleModels")
local VehicleTypes = require("../VehicleTypes")

type MeshBox = DamageTypes.MeshBox
type MeshRef = VehicleModels.MeshRef
type PieceHitbox = DamageTypes.PieceHitbox
type VehicleModelSheet = VehicleModels.VehicleModelSheet
type VehicleSettings = VehicleTypes.VehicleSettings

local HitboxLayout = {}

local MIN_THICKNESS = DamageConfig.HITBOX.MIN_THICKNESS_STUDS

-- Esquinas de la caja de una malla; con `side`, solo la mitad de ese lado, cortada por el centro de la malla en x.
local function meshRange(box: MeshBox, side: "left" | "right"?): (vector, vector)
	local half = box.size * 0.5
	local low, high = box.center - half, box.center + half
	if side == "left" then
		low = vector.create(box.center.x, low.y, low.z)
	elseif side == "right" then
		high = vector.create(box.center.x, high.y, high.z)
	end
	return low, high
end

-- La caja que envuelve a todas las mallas de la pieza; nil si ninguna tiene caja.
local function pieceRange(refs: { MeshRef }, meshBoxes: { [string]: MeshBox }): (vector?, vector?)
	local low, high = nil, nil
	for _, ref in refs do
		local box = meshBoxes[if type(ref) == "string" then ref else ref.mesh]
		if box ~= nil then
			local meshLow, meshHigh = meshRange(box, if type(ref) == "string" then nil else ref.side)
			low = if low == nil then meshLow else vector.min(low, meshLow)
			high = if high == nil then meshHigh else vector.max(high, meshHigh)
		end
	end
	return low, high
end

-- El giro del modelo es un múltiplo de 90°: solo intercambia x con z, no hace falta rotar la caja.
local function turnedSize(size: vector, turnDegrees: number): vector
	local sine, cosine = math.abs(math.sin(math.rad(turnDegrees))), math.abs(math.cos(math.rad(turnDegrees)))
	return vector.create(cosine * size.x + sine * size.z, size.y, sine * size.x + cosine * size.z)
end

local function sortedPieceIds(sheet: VehicleModelSheet): { string }
	local ids = {}
	for pieceId in sheet.damageMeshes do
		table.insert(ids, pieceId)
	end
	table.sort(ids)
	return ids
end

-- Una caja por pieza de la ficha que tenga alguna malla con caja, ordenadas por id. Ninguna mide menos de
-- `MIN_THICKNESS_STUDS` en ningún eje.
function HitboxLayout.compute(
	sheet: VehicleModelSheet,
	meshBoxes: { [string]: MeshBox },
	config: VehicleSettings,
	gravity: number
): { PieceHitbox }
	local hitboxes: { PieceHitbox } = {}
	local minimum = vector.create(MIN_THICKNESS, MIN_THICKNESS, MIN_THICKNESS)
	for _, pieceId in sortedPieceIds(sheet) do
		local low, high = pieceRange(sheet.damageMeshes[pieceId], meshBoxes)
		if low ~= nil and high ~= nil then
			table.insert(hitboxes, {
				pieceId = pieceId,
				offset = ModelPlacement.toBodyFrame(sheet, config, gravity, (low + high) * 0.5),
				size = vector.max(turnedSize(high - low, sheet.turnDegrees), minimum),
			})
		end
	end
	return hitboxes
end

return HitboxLayout
