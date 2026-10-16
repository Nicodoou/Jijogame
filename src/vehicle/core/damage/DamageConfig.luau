--!strict
-- Ficha de daño del Fiat 147 y valores de ajuste del daño (WP-15). Solo datos: la ficha vive aparte del manejo y es
-- la base de `ChassisSpec`. Las piezas de chapa tienen K = 0,05 y los vidrios y las luces, 0,08.
local DamageTypes = require("./DamageTypes")

type PieceKind = DamageTypes.PieceKind
type PieceSpec = DamageTypes.PieceSpec
type Protection = DamageTypes.Protection

local IMPACT_THRESHOLD = 15
local SHEET_METAL_K = 0.05
local GLASS_K = 0.08
local WEAR_PER_DAMAGE = 0.1

local GRILLE_PROTECTION = 0.6
local RADIATOR_PROTECTION = 0.3
local BASE_PROTECTION = 0.4
local FENDER_PROTECTION = 0.5

local WHEEL_NAMES = { "FL", "FR", "RL", "RR" }

local pieces: { [string]: PieceSpec } = {}

local function add(
	id: string,
	kind: PieceKind,
	isExterior: boolean,
	damagePerImpact: number,
	protects: { Protection }?,
	wheelIndex: number?
)
	pieces[id] = {
		id = id,
		kind = kind,
		isExterior = isExterior,
		damagePerImpact = damagePerImpact,
		impactThreshold = IMPACT_THRESHOLD,
		wearPerDamage = WEAR_PER_DAMAGE,
		protects = protects or {},
		wheelIndex = wheelIndex,
	}
end

local function addSheetMetal(id: string, kind: PieceKind, protects: { Protection }?)
	add(id, kind, true, SHEET_METAL_K, protects, nil)
end

local function addGlass(id: string, kind: PieceKind)
	add(id, kind, true, GLASS_K, nil, nil)
end

local basePieces: { Protection } = {
	{ pieceId = "fuelTank", factor = BASE_PROTECTION },
}
for index, name in WHEEL_NAMES do
	table.insert(basePieces, { pieceId = "suspension_" .. name, factor = BASE_PROTECTION })
	-- El guardabarros cubre su rueda y su suspensión.
	addSheetMetal("fender_" .. name, "fender", {
		{ pieceId = "wheel_" .. name, factor = FENDER_PROTECTION },
		{ pieceId = "suspension_" .. name, factor = FENDER_PROTECTION },
	})
	add("wheel_" .. name, "wheel", true, SHEET_METAL_K, nil, index)
	add("suspension_" .. name, "suspension", false, SHEET_METAL_K, nil, index)
end

addSheetMetal("chassisBase", "chassisBase", basePieces)
addSheetMetal("bonnet", "bonnet", nil)
addSheetMetal("trunk", "trunk", nil)
addSheetMetal("roof", "roof", nil)
addSheetMetal("door_L", "door", nil)
addSheetMetal("door_R", "door", nil)
addSheetMetal("frontBumper", "frontBumper", { { pieceId = "radiator", factor = GRILLE_PROTECTION } })
addSheetMetal("rearBumper", "rearBumper", nil)
addSheetMetal("grille", "grille", { { pieceId = "radiator", factor = GRILLE_PROTECTION } })
addSheetMetal("sideSkirt_L", "sideSkirt", nil)
addSheetMetal("sideSkirt_R", "sideSkirt", nil)

addGlass("windshield", "windshield")
addGlass("rearWindow", "rearWindow")
addGlass("window_L", "window")
addGlass("window_R", "window")
addGlass("mirror_L", "mirror")
addGlass("mirror_R", "mirror")
addGlass("headlight_L", "light")
addGlass("headlight_R", "light")
addGlass("taillight_L", "light")
addGlass("taillight_R", "light")

add("radiator", "radiator", false, SHEET_METAL_K, { { pieceId = "engine", factor = RADIATOR_PROTECTION } }, nil)
add("engine", "engine", false, SHEET_METAL_K, nil, nil)
add("gearbox", "gearbox", false, SHEET_METAL_K, nil, nil)
add("steering", "steering", false, SHEET_METAL_K, nil, nil)
add("fuelTank", "fuelTank", false, SHEET_METAL_K, nil, nil)

return table.freeze({
	PIECES = pieces,

	RULES = table.freeze({
		-- Con este daño la pieza se cae.
		DETACH_DAMAGE = 100,
		-- Profundidad máxima con la que un golpe pasa de una pieza a las que cubre (corta los ciclos de una ficha mal hecha).
		MAX_PROTECTION_DEPTH = 4,
	}),

	EFFECTS = table.freeze({
		-- La potencia que queda con el radiador al 100% de daño (con 0 de daño, 1).
		RADIATOR_MIN_POWER = 0.5,
		-- Cuánto se alarga el cambio de marcha con la caja al 100% de daño (el tiempo se multiplica por 1 + esto).
		GEARBOX_SHIFT_SLOWDOWN = 2,
		-- Cuánto agarre pierde una rueda con su suspensión al 100% de daño.
		SUSPENSION_GRIP_LOSS = 0.5,
		-- Desvío de la dirección, en grados por punto de daño de la suspensión (hacia el lado de la rueda).
		STEERING_PULL_DEGREES_PER_DAMAGE = 0.02,
		-- Desvío fijo del volante, en grados por punto de daño de la dirección.
		STEERING_OFFSET_DEGREES_PER_DAMAGE = 0.05,
	}),
})
