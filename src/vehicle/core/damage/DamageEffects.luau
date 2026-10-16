--!strict
-- Efectos del daño en el manejo (WP-15). Devuelve una copia de la configuración del simulador con los efectos
-- aplicados: el simulador no cambia, solo recibe otra configuración. Vida = 1 − daño / 100.
local DamageConfig = require("./DamageConfig")
local DamageTypes = require("./DamageTypes")
local VehicleTypes = require("../VehicleTypes")

type DamageState = DamageTypes.DamageState
type PieceSpecs = DamageTypes.PieceSpecs
type VehicleSettings = VehicleTypes.VehicleSettings

local DamageEffects = {}

local EFFECTS = DamageConfig.EFFECTS
local FULL_DAMAGE = DamageConfig.RULES.DETACH_DAMAGE

-- Lo que se va acumulando mientras se recorren las piezas.
type Accumulator = {
	power: number,
	shiftSlowdown: number,
	wheelGrip: { number },
	steerOffsetDegrees: number,
}

local function sortedIds(specs: PieceSpecs): { string }
	local ids = {}
	for id in specs do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function lifeOf(damage: number): number
	return 1 - math.clamp(damage, 0, FULL_DAMAGE) / FULL_DAMAGE
end

-- Rueda: agarre en proporción a la vida; caída, 0.
local function applyWheel(accumulator: Accumulator, index: number, damage: number, isDetached: boolean)
	accumulator.wheelGrip[index] *= if isDetached then 0 else lifeOf(damage)
end

-- Suspensión de una rueda: esa rueda agarra menos y la dirección tira hacia su lado (derecha positiva).
local function applySuspension(accumulator: Accumulator, index: number, damage: number, settings: VehicleSettings)
	local clamped = math.clamp(damage, 0, FULL_DAMAGE)
	accumulator.wheelGrip[index] *= 1 - EFFECTS.SUSPENSION_GRIP_LOSS * clamped / FULL_DAMAGE
	local side = if settings.WHEELS[index].isLeft then -1 else 1
	accumulator.steerOffsetDegrees += side * EFFECTS.STEERING_PULL_DEGREES_PER_DAMAGE * clamped
end

local function applyPiece(
	accumulator: Accumulator,
	kind: DamageTypes.PieceKind,
	wheelIndex: number?,
	damage: number,
	isDetached: boolean,
	settings: VehicleSettings
)
	if kind == "engine" then
		accumulator.power *= lifeOf(damage)
	elseif kind == "radiator" then
		accumulator.power *= 1 - (1 - EFFECTS.RADIATOR_MIN_POWER) * (1 - lifeOf(damage))
	elseif kind == "gearbox" then
		accumulator.shiftSlowdown += EFFECTS.GEARBOX_SHIFT_SLOWDOWN * math.clamp(damage, 0, FULL_DAMAGE) / FULL_DAMAGE
	elseif kind == "steering" then
		accumulator.steerOffsetDegrees += EFFECTS.STEERING_OFFSET_DEGREES_PER_DAMAGE * math.clamp(
			damage,
			0,
			FULL_DAMAGE
		)
	elseif kind == "wheel" and wheelIndex ~= nil then
		applyWheel(accumulator, wheelIndex, damage, isDetached)
	elseif kind == "suspension" and wheelIndex ~= nil then
		applySuspension(accumulator, wheelIndex, damage, settings)
	end
end

-- Copia de `settings` con el daño aplicado. Con todo el daño en 0 es idéntica a la original.
function DamageEffects.apply(settings: VehicleSettings, damageState: DamageState, specs: PieceSpecs): VehicleSettings
	local accumulator: Accumulator = {
		power = 1,
		shiftSlowdown = 0,
		wheelGrip = table.clone(settings.WHEEL_GRIP_MULTIPLIERS),
		steerOffsetDegrees = settings.STEER_OFFSET_DEGREES,
	}
	for _, id in sortedIds(specs) do
		local piece = damageState.pieces[id]
		if piece ~= nil then
			applyPiece(accumulator, specs[id].kind, specs[id].wheelIndex, piece.damage, piece.isDetached, settings)
		end
	end
	local result = table.clone(settings)
	result.FIRST_GEAR_PEAK_ACCELERATION = settings.FIRST_GEAR_PEAK_ACCELERATION * accumulator.power
	result.SHIFT_DURATION_SECONDS = settings.SHIFT_DURATION_SECONDS * (1 + accumulator.shiftSlowdown)
	result.WHEEL_GRIP_MULTIPLIERS = accumulator.wheelGrip
	result.STEER_OFFSET_DEGREES = accumulator.steerOffsetDegrees
	return result
end

return DamageEffects
