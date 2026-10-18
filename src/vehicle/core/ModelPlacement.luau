--!strict
-- Dónde queda el modelo visual respecto del `Body`. Lo comparten quien ubica el modelo y quien necesita
-- un punto del modelo (la cabeza del conductor), para no repetir la cuenta.
local Suspension = require("./Suspension")
local VehicleModels = require("./VehicleModels")
local VehicleTypes = require("./VehicleTypes")

type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleModelSheet = VehicleModels.VehicleModelSheet

-- La compresión estática no depende de la masa: se cancela entre la carga y la rigidez.
local UNIT_MASS = 1

local ModelPlacement = {}

function ModelPlacement.staticCompression(config: VehicleSettings, gravity: number): number
	local wheelCount = #config.WHEELS
	return Suspension.staticLoad(UNIT_MASS, gravity, wheelCount) / Suspension.springRate(UNIT_MASS, wheelCount, config)
end

-- Altura (en el marco del Body) donde apoya el piso: con el resorte en reposo.
function ModelPlacement.groundHeight(config: VehicleSettings, gravity: number): number
	local mountY = config.WHEELS[1].offset.y
	local restLength = config.SUSPENSION_REST_LENGTH_STUDS - ModelPlacement.staticCompression(config, gravity)
	return mountY - restLength - config.WHEEL_RADIUS_STUDS
end

-- Devuelve la altura sobre el Body y el giro alrededor de y con que queda el pivote del modelo.
function ModelPlacement.pivotOffset(
	sheet: VehicleModelSheet,
	config: VehicleSettings,
	gravity: number
): (number, number)
	return ModelPlacement.groundHeight(config, gravity) - sheet.modelGroundY, math.rad(sheet.turnDegrees)
end

-- Pasa un punto del marco del modelo (x a la izquierda, +z adelante) al marco del Body.
function ModelPlacement.toBodyFrame(
	sheet: VehicleModelSheet,
	config: VehicleSettings,
	gravity: number,
	point: vector
): vector
	local heightStuds, turnRadians = ModelPlacement.pivotOffset(sheet, config, gravity)
	local sine, cosine = math.sin(turnRadians), math.cos(turnRadians)
	return vector.create(point.x * cosine + point.z * sine, point.y + heightStuds, -point.x * sine + point.z * cosine)
end

function ModelPlacement.headInBodyFrame(sheet: VehicleModelSheet, config: VehicleSettings, gravity: number): vector
	return ModelPlacement.toBodyFrame(sheet, config, gravity, sheet.driverHead)
end

return ModelPlacement
