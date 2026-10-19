--!strict
-- Arma la configuración del simulador (`VehicleSettings`) con tres fichas: el auto, el motor y la caja (WP-20a).
-- Es una función pura: no toca las fichas y devuelve la configuración congelada o la razón por la que la combinación
-- no tiene sentido. El simulador no sabe de fichas: sigue leyendo la misma tabla de siempre.
local SpecTypes = require("./specs/SpecTypes")
local TorqueCurve = require("./TorqueCurve")
local VehicleSettingsType = require("./specs/VehicleSettingsType")

type CarSpec = SpecTypes.CarSpec
type EngineSpec = SpecTypes.EngineSpec
type GearboxSpec = SpecTypes.GearboxSpec
type VehicleSettings = VehicleSettingsType.VehicleSettings

local VehicleBuild = {}

-- Son del simulador y no de una ficha.
local MAX_STEP_SECONDS = 1 / 15
-- Magnitud por debajo de la cual el producto vectorial que da el "arriba" del contacto es degenerado.
local CONTACT_PLANE_DEGENERATE_THRESHOLD = 1e-4
-- Calibra los "HP de juego" (decisión U1): con ella el motor del 147 da 50. Su torque · rpm máximo es
-- 648 · 0,85 · 6500 = 3 580 200.
local GAME_HP_CONSTANT = 71604
local HP_SWEEP_STEP_RPM = 25
-- Las posiciones son `vector` (float32, error ~1e-7): el reparto de peso se redondea a 6 decimales para que el 147
-- dé 0,7 exacto y no 0,699999997.
local WEIGHT_ROUNDING = 1e6

local function validateGearbox(gearbox: GearboxSpec): string?
	if #gearbox.GEAR_RATIOS == 0 then
		return "la caja no tiene marchas"
	end
	for index, ratio in gearbox.GEAR_RATIOS do
		if ratio <= 0 then
			return `la relación de la marcha {index} es {ratio}: tiene que ser mayor que 0`
		end
	end
	if gearbox.REVERSE_RATIO <= 0 or gearbox.FINAL_DRIVE <= 0 then
		return "la reversa y el diferencial necesitan relaciones mayores que 0"
	end
	local efficiency = gearbox.DRIVETRAIN_EFFICIENCY
	if efficiency <= 0 or efficiency > 1 then
		return `la eficiencia de la transmisión es {efficiency}: tiene que estar en (0, 1]`
	end
	return nil
end

local function validateEngine(engine: EngineSpec): string?
	if #engine.TORQUE_CURVE == 0 then
		return "la curva de torque está vacía"
	end
	for index = 2, #engine.TORQUE_CURVE do
		if engine.TORQUE_CURVE[index].rpm <= engine.TORQUE_CURVE[index - 1].rpm then
			return `la curva de torque no está ordenada por RPM en el punto {index}`
		end
	end
	if engine.PEAK_TORQUE <= 0 then
		return "el torque pico tiene que ser mayor que 0"
	end
	if engine.ENGINE_MASS <= 0 then
		return "la masa del motor tiene que ser mayor que 0"
	end
	if engine.REDLINE_RPM <= engine.IDLE_RPM then
		return "el corte tiene que estar por encima del ralentí"
	end
	return nil
end

local function wheelbase(car: CarSpec): number
	local frontZ, rearZ = math.huge, -math.huge
	for _, wheel in car.WHEELS do
		frontZ = math.min(frontZ, wheel.offset.z)
		rearZ = math.max(rearZ, wheel.offset.z)
	end
	return rearZ - frontZ
end

local function validateCar(car: CarSpec): string?
	if car.CHASSIS_MASS <= 0 then
		return "la masa del chasis tiene que ser mayor que 0"
	end
	if car.WHEEL_RADIUS_STUDS <= 0 then
		return "el radio de la rueda tiene que ser mayor que 0"
	end
	if wheelbase(car) <= 0 then
		return "las ruedas necesitan un paso entre ejes mayor que 0"
	end
	return nil
end

-- Reparto de peso del auto armado: el motor corre el centro de masa hacia donde está. `car.FRONT_WEIGHT_FRACTION` es el
-- del chasis solo; el del conjunto se mide desde el eje trasero sobre el paso entre ejes.
local function frontWeightFraction(car: CarSpec, engine: EngineSpec): number
	local rearZ = -math.huge
	for _, wheel in car.WHEELS do
		rearZ = math.max(rearZ, wheel.offset.z)
	end
	local length = wheelbase(car)
	local chassisZ = rearZ - car.FRONT_WEIGHT_FRACTION * length
	local totalMass = car.CHASSIS_MASS + engine.ENGINE_MASS
	local centerZ = (car.CHASSIS_MASS * chassisZ + engine.ENGINE_MASS * car.ENGINE_POSITION_Z) / totalMass
	local fraction = (rearZ - centerZ) / length
	return math.floor(fraction * WEIGHT_ROUNDING + 0.5) / WEIGHT_ROUNDING
end

-- Aceleración de la 1ra a torque pico: F = torque · relación · diferencial · eficiencia / radio, sobre la masa total.
-- Un motor más pesado o un auto más pesado con el mismo torque aceleran menos.
local function firstGearAcceleration(car: CarSpec, engine: EngineSpec, gearbox: GearboxSpec): number
	local wheelForce = engine.PEAK_TORQUE
		* gearbox.GEAR_RATIOS[1]
		* gearbox.FINAL_DRIVE
		* gearbox.DRIVETRAIN_EFFICIENCY
		/ car.WHEEL_RADIUS_STUDS
	return wheelForce / (car.CHASSIS_MASS + engine.ENGINE_MASS)
end

-- Devuelve la configuración congelada, o nil y la razón si la combinación no sirve.
function VehicleBuild.assemble(car: CarSpec, engine: EngineSpec, gearbox: GearboxSpec): (VehicleSettings?, string?)
	local problem = validateCar(car) or validateEngine(engine) or validateGearbox(gearbox)
	if problem ~= nil then
		return nil, problem
	end
	local settings: { [string]: any } = {}
	for _, spec in { car, engine, gearbox } :: { { [string]: any } } do
		for key, value in spec do
			settings[key] = value
		end
	end
	settings.TOTAL_MASS = car.CHASSIS_MASS + engine.ENGINE_MASS
	settings.FRONT_WEIGHT_FRACTION = frontWeightFraction(car, engine)
	settings.FIRST_GEAR_PEAK_ACCELERATION = firstGearAcceleration(car, engine, gearbox)
	settings.MAX_STEP_SECONDS = MAX_STEP_SECONDS
	settings.CONTACT_PLANE_DEGENERATE_THRESHOLD = CONTACT_PLANE_DEGENERATE_THRESHOLD
	return table.freeze(settings) :: any, nil
end

-- "HP de juego": el máximo de torque · rpm entre el ralentí y el corte, sobre la constante de calibración. Solo informa.
function VehicleBuild.powerHp(engine: EngineSpec): number
	local best = 0
	for rpm = engine.IDLE_RPM, engine.REDLINE_RPM, HP_SWEEP_STEP_RPM do
		local torque = engine.PEAK_TORQUE * TorqueCurve.fractionAt(engine.TORQUE_CURVE, rpm)
		best = math.max(best, torque * rpm)
	end
	return best / GAME_HP_CONSTANT
end

return VehicleBuild
