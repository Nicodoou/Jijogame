--!strict
-- Resorte y amortiguador de cada rueda (CP-2). La carga de la rueda es la fuerza que devuelve.
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")

type WheelState = VehicleTypes.WheelState
type WheelContact = VehicleTypes.WheelContact
type VehicleSettings = VehicleTypes.VehicleSettings

local Suspension = {}

function Suspension.staticLoad(mass: number, gravity: number, wheelCount: number): number
	return mass * gravity / wheelCount
end

function Suspension.springRate(mass: number, wheelCount: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local angularFrequency = 2 * math.pi * settings.SUSPENSION_FREQUENCY_HZ
	return mass / wheelCount * angularFrequency * angularFrequency
end

function Suspension.damperRate(mass: number, wheelCount: number, config: VehicleSettings?): number
	local settings = config or VehicleConfig
	local wheelMass = mass / wheelCount
	return 2
		* settings.SUSPENSION_DAMPING_RATIO
		* math.sqrt(Suspension.springRate(mass, wheelCount, config) * wheelMass)
end

local function compressionFromContact(contact: WheelContact, settings: VehicleSettings): number
	local distance = contact.distanceStuds
	if distance ~= distance or distance < 0 then
		return settings.SUSPENSION_MAX_COMPRESSION_STUDS
	end
	local compression = settings.SUSPENSION_REST_LENGTH_STUDS + settings.WHEEL_RADIUS_STUDS - distance
	return math.clamp(compression, 0, settings.SUSPENSION_MAX_COMPRESSION_STUDS)
end

-- Suspensión a tope (#31): si el rayo ya no pega pero la rueda venía casi a fondo, sigue apoyada.
local function wasBottomedOut(wheel: WheelState, settings: VehicleSettings): boolean
	return wheel.compressionStuds >= settings.BOTTOM_OUT_FRACTION * settings.SUSPENSION_MAX_COMPRESSION_STUDS
end

local function resolveCompression(
	wheel: WheelState,
	contact: WheelContact?,
	settings: VehicleSettings
): (number, boolean)
	if contact ~= nil and contact.hasHit then
		return compressionFromContact(contact, settings), true
	end
	if wasBottomedOut(wheel, settings) then
		return settings.SUSPENSION_MAX_COMPRESSION_STUDS, true
	end
	return 0, false
end

function Suspension.step(
	wheel: WheelState,
	contact: WheelContact?,
	compressionSpeedRaw: number,
	mass: number,
	gravity: number,
	dt: number,
	config: VehicleSettings?
): (WheelState, number)
	local settings = config or VehicleConfig
	local compression, isGrounded = resolveCompression(wheel, contact, settings)
	local nextWheel: WheelState = {
		compressionStuds = compression,
		compressionSpeed = 0,
		gripMultiplier = wheel.gripMultiplier,
		rollingResistance = wheel.rollingResistance,
		isGrounded = isGrounded,
	}
	if not isGrounded then
		return nextWheel, 0
	end
	local alpha = VehicleMath.smoothingAlpha(settings.COMPRESSION_SPEED_FILTER_RATE, dt)
	local rawSpeed = VehicleMath.finiteOr(compressionSpeedRaw, 0)
	nextWheel.compressionSpeed = wheel.compressionSpeed + (rawSpeed - wheel.compressionSpeed) * alpha
	local wheelCount = #settings.WHEELS
	local force = Suspension.springRate(mass, wheelCount, config) * compression
		+ Suspension.damperRate(mass, wheelCount, config) * nextWheel.compressionSpeed
	local maxForce = settings.SUSPENSION_MAX_FORCE_PER_STATIC_LOAD * Suspension.staticLoad(mass, gravity, wheelCount)
	return nextWheel, math.clamp(force, 0, maxForce)
end

return Suspension
