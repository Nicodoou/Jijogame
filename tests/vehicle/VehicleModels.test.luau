--!strict
local Runner = require("../Runner")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleModels = require("../../src/vehicle/core/VehicleModels")

local WHEEL_TOLERANCE_STUDS = 0.05
-- El eje trasero del modelo está 0,05 más abajo que las ruedas delanteras (medido en el modelo).
local GROUND_TOLERANCE_STUDS = 0.06
local MESH_COUNT = 33

local function contains(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

-- Gira el punto alrededor de y (x a la izquierda y +z adelante en el modelo; se devuelve en el marco del auto).
local function turned(point: vector, turnDegrees: number): (number, number)
	local angle = math.rad(turnDegrees)
	return point.x * math.cos(angle) + point.z * math.sin(angle), -point.x * math.sin(angle) + point.z * math.cos(angle)
end

Runner.test("the Fiat 147 sheet declares each mesh once", function()
	local seen: { [string]: boolean } = {}
	for _, name in VehicleModels.Fiat147.meshNames do
		Runner.expectEqual(seen[name], nil)
		seen[name] = true
	end
	Runner.expectEqual(#VehicleModels.Fiat147.meshNames, MESH_COUNT)
end)

Runner.test("the meshes named by the sheet exist in the declared list", function()
	local sheet = VehicleModels.Fiat147
	for meshName, wheelName in sheet.frontWheelMeshes do
		Runner.expectEqual(contains(sheet.meshNames, meshName), true)
		Runner.expectEqual(typeof(sheet.wheelCenters[wheelName]), "vector")
	end
	for _, meshName in sheet.rearAxleMeshes do
		Runner.expectEqual(contains(sheet.meshNames, meshName), true)
	end
end)

Runner.test("an invented mesh name is not in the declared list", function()
	Runner.expectEqual(contains(VehicleModels.Fiat147.meshNames, "Spoiler"), false)
end)

Runner.test("the wheels of the sheet match VehicleConfig.WHEELS once the model is turned", function()
	local sheet = VehicleModels.Fiat147
	for _, wheel in VehicleConfig.WHEELS do
		local center = sheet.wheelCenters[wheel.name]
		local x, z = turned(center, sheet.turnDegrees)
		Runner.expectNear(x, wheel.offset.x, WHEEL_TOLERANCE_STUDS)
		Runner.expectNear(z, wheel.offset.z, WHEEL_TOLERANCE_STUDS)
	end
end)

Runner.test("the bottom of the wheels of the sheet is at the ground height of the sheet", function()
	local sheet = VehicleModels.Fiat147
	for _, wheel in VehicleConfig.WHEELS do
		local bottom = sheet.wheelCenters[wheel.name].y - VehicleConfig.WHEEL_RADIUS_STUDS
		Runner.expectNear(bottom, sheet.modelGroundY, GROUND_TOLERANCE_STUDS)
	end
end)

Runner.test("the driver head is above the seat and inside the width of the car", function()
	local head = VehicleModels.Fiat147.driverHead
	Runner.expectEqual(head.y > VehicleModels.Fiat147.modelGroundY, true)
	Runner.expectEqual(math.abs(head.x) < math.abs(VehicleConfig.WHEELS[1].offset.x), true)
end)

Runner.finish()
