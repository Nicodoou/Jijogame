--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DamageTypes = require("../../../src/vehicle/core/damage/DamageTypes")
local Fiat147Hitbox = require("../../../src/vehicle/core/damage/Fiat147Hitbox")
local HitboxLayout = require("../../../src/vehicle/core/damage/HitboxLayout")
local ModelPlacement = require("../../../src/vehicle/core/ModelPlacement")
local VehicleConfig = require("../../../src/vehicle/core/VehicleConfig")
local VehicleModels = require("../../../src/vehicle/core/VehicleModels")

type MeshBox = DamageTypes.MeshBox
type PieceHitbox = DamageTypes.PieceHitbox
type VehicleModelSheet = VehicleModels.VehicleModelSheet

local SHEET = VehicleModels.Fiat147
local GRAVITY = 196.2
local MIN_THICKNESS = DamageConfig.HITBOX.MIN_THICKNESS_STUDS
local TOLERANCE = 1e-6

local function layout(sheet: VehicleModelSheet, boxes: { [string]: MeshBox }): { PieceHitbox }
	return HitboxLayout.compute(sheet, boxes, VehicleConfig, GRAVITY)
end

local function byPiece(hitboxes: { PieceHitbox }): { [string]: PieceHitbox }
	local result = {}
	for _, hitbox in hitboxes do
		result[hitbox.pieceId] = hitbox
	end
	return result
end

local function sheetWith(damageMeshes: { [string]: { VehicleModels.MeshRef } }, turnDegrees: number): VehicleModelSheet
	local sheet = table.clone(SHEET)
	sheet.damageMeshes = damageMeshes
	sheet.turnDegrees = turnDegrees
	return sheet
end

local function isFinite(value: number): boolean
	return value == value and math.abs(value) ~= math.huge
end

local function meshBox(centerX: number, sizeX: number): MeshBox
	return { center = vector.create(centerX, 3, 1), size = vector.create(sizeX, 1, 2) }
end

Runner.test("every piece id of the sheet exists in DamageConfig and has an exterior piece", function()
	for pieceId in SHEET.damageMeshes do
		Runner.expectEqual(DamageConfig.PIECES[pieceId] ~= nil, true)
		Runner.expectEqual(DamageConfig.PIECES[pieceId].isExterior, true)
	end
end)

Runner.test("every mesh named by the sheet is declared and has a measured box", function()
	for _, refs in SHEET.damageMeshes do
		for _, ref in refs do
			local name = if type(ref) == "string" then ref else ref.mesh
			Runner.expectEqual(table.find(SHEET.meshNames, name) ~= nil, true)
			Runner.expectEqual(Fiat147Hitbox[name] ~= nil, true)
		end
	end
	for _, name in SHEET.meshNames do
		Runner.expectEqual(Fiat147Hitbox[name] ~= nil, true)
	end
end)

Runner.test("the measured boxes have finite positive sizes", function()
	for _, box in Fiat147Hitbox do
		for _, value in { box.size.x, box.size.y, box.size.z, box.center.x, box.center.y, box.center.z } do
			Runner.expectEqual(isFinite(value), true)
		end
		Runner.expectEqual(box.size.x > 0 and box.size.y > 0 and box.size.z > 0, true)
	end
end)

Runner.test("the layout of the 147 has one box per piece with a mesh, sorted, none empty or NaN", function()
	local hitboxes = layout(SHEET, Fiat147Hitbox)
	local count = 0
	for _ in SHEET.damageMeshes do
		count += 1
	end
	Runner.expectEqual(#hitboxes, count)
	for index, hitbox in hitboxes do
		Runner.expectEqual(index == 1 or hitboxes[index - 1].pieceId < hitbox.pieceId, true)
		for _, value in
			{ hitbox.size.x, hitbox.size.y, hitbox.size.z, hitbox.offset.x, hitbox.offset.y, hitbox.offset.z }
		do
			Runner.expectEqual(isFinite(value), true)
		end
	end
end)

Runner.test("no box is thinner than the minimum thickness and the grille is raised to it", function()
	for _, hitbox in layout(SHEET, Fiat147Hitbox) do
		Runner.expectEqual(hitbox.size.x >= MIN_THICKNESS and hitbox.size.y >= MIN_THICKNESS, true)
		Runner.expectEqual(hitbox.size.z >= MIN_THICKNESS, true)
	end
	Runner.expectNear(byPiece(layout(SHEET, Fiat147Hitbox)).grille.size.z, MIN_THICKNESS, TOLERANCE)
end)

Runner.test("the box of a piece contains the box of each of its meshes in the Body frame", function()
	local hitboxes = byPiece(layout(SHEET, Fiat147Hitbox))
	for pieceId, refs in SHEET.damageMeshes do
		local hitbox = hitboxes[pieceId]
		for _, ref in refs do
			local mesh = Fiat147Hitbox[ref :: string]
			local center = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, mesh.center)
			-- El giro es de 180°: los tamaños no cambian de eje. De una rueda solo cuenta la mitad de arriba.
			local isWheel = DamageConfig.PIECES[pieceId].kind == "wheel"
			local centerY = if isWheel then center.y + mesh.size.y / 4 else center.y
			local sizeY = if isWheel then mesh.size.y / 2 else mesh.size.y
			local axes = {
				{ center.x, hitbox.offset.x, mesh.size.x, hitbox.size.x },
				{ centerY, hitbox.offset.y, sizeY, hitbox.size.y },
				{ center.z, hitbox.offset.z, mesh.size.z, hitbox.size.z },
			}
			for _, axis in axes do
				Runner.expectEqual(math.abs(axis[1] - axis[2]) + axis[3] / 2 <= axis[4] / 2 + 1e-6, true)
			end
		end
	end
end)

Runner.test(
	"the layout puts the left door on the left of the car (x negative in the Body frame after the turn)",
	function()
		local hitboxes = byPiece(layout(SHEET, Fiat147Hitbox))
		Runner.expectEqual(hitboxes.door_L.offset.x < 0 and hitboxes.door_R.offset.x > 0, true)
		Runner.expectEqual(hitboxes.frontBumper.offset.z < hitboxes.rearBumper.offset.z, true)
	end
)

Runner.test("the two halves of a shared mesh do not overlap and together cover the mesh", function()
	local sheet = sheetWith({
		piece_L = { { mesh = "Shared", side = "left" } },
		piece_R = { { mesh = "Shared", side = "right" } },
	}, 180)
	local hitboxes = byPiece(layout(sheet, { Shared = meshBox(0.5, 4) }))
	local left, right = hitboxes.piece_L, hitboxes.piece_R
	Runner.expectNear(left.size.x, 2, TOLERANCE)
	Runner.expectNear(right.size.x, 2, TOLERANCE)
	-- Tras el giro de 180° la mitad "left" (x del modelo positivo) queda en x negativo del Body.
	Runner.expectNear(left.offset.x + left.size.x / 2, -0.5, TOLERANCE)
	Runner.expectNear(right.offset.x - right.size.x / 2, -0.5, TOLERANCE)
end)

Runner.test("a mesh that is not in the boxes is ignored and a piece with no boxes gets none", function()
	local sheet = sheetWith({ solo = { "Missing" }, mixed = { "Missing", "Real" } }, 180)
	local hitboxes = byPiece(layout(sheet, { Real = meshBox(0, 1) }))
	Runner.expectEqual(hitboxes.solo, nil)
	Runner.expectEqual(hitboxes.mixed ~= nil, true)
end)

Runner.test("a sheet without damage meshes gives an empty layout", function()
	Runner.expectEqual(#layout(sheetWith({}, 180), Fiat147Hitbox), 0)
end)

Runner.test("a quarter turn swaps the x and z sizes", function()
	local box: MeshBox = { center = vector.zero, size = vector.create(2, 1, 6) }
	local hitbox = layout(sheetWith({ piece = { "Box" } }, 90), { Box = box })[1]
	Runner.expectNear(hitbox.size.x, 6, TOLERANCE)
	Runner.expectNear(hitbox.size.z, 2, TOLERANCE)
end)

Runner.test("a box thinner than the minimum is grown around its center", function()
	local box: MeshBox = { center = vector.create(0, 3, 0), size = vector.create(2, 0.06, 2) }
	local thin = layout(sheetWith({ piece = { "Box" } }, 180), { Box = box })[1]
	Runner.expectNear(thin.size.y, MIN_THICKNESS, TOLERANCE)
	local center = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, box.center)
	Runner.expectNear(thin.offset.y, center.y, TOLERANCE)
end)

Runner.test(
	"the bottom of each wheel box is not below the axle and the rest of the pieces keep their full height",
	function()
		local hitboxes = byPiece(layout(SHEET, Fiat147Hitbox))
		for _, name in { "FL", "FR", "RL", "RR" } do
			local mesh = Fiat147Hitbox[(SHEET.damageMeshes["wheel_" .. name][1]) :: string]
			local axle = ModelPlacement.toBodyFrame(SHEET, VehicleConfig, GRAVITY, mesh.center).y
			local hitbox = hitboxes["wheel_" .. name]
			Runner.expectEqual(hitbox.offset.y - hitbox.size.y / 2 >= axle - 1e-5, true)
			Runner.expectNear(hitbox.size.y, mesh.size.y / 2, TOLERANCE)
		end
		Runner.expectNear(hitboxes.door_L.size.y, Fiat147Hitbox["Left Door"].size.y, TOLERANCE)
	end
)

Runner.finish()
