--!strict
-- Del tipo de superficie al agarre y a la resistencia al rodar de cada rueda (CP-3).
-- El cambio se filtra para que un borde nítido no se sienta como un golpe.
local VehicleConfig = require("./VehicleConfig")
local VehicleMath = require("./VehicleMath")
local VehicleTypes = require("./VehicleTypes")

type WheelState = VehicleTypes.WheelState
type SurfaceKind = VehicleTypes.SurfaceKind
type VehicleSettings = VehicleTypes.VehicleSettings

local SurfaceGrip = {}

local INITIAL_SURFACE: SurfaceKind = "Road"

function SurfaceGrip.newWheelState(config: VehicleSettings?): WheelState
	local settings = config or VehicleConfig
	return {
		compressionStuds = 0,
		compressionSpeed = 0,
		missedContactSteps = 0,
		gripMultiplier = settings.SURFACE_GRIP[INITIAL_SURFACE],
		rollingResistance = settings.SURFACE_ROLLING_RESISTANCE[INITIAL_SURFACE],
		isGrounded = false,
	}
end

-- Un `nil` (sin contacto o fuera del mundo generado) mantiene los valores anteriores.
function SurfaceGrip.step(wheel: WheelState, surface: SurfaceKind?, dt: number, config: VehicleSettings?): WheelState
	local settings = config or VehicleConfig
	local nextWheel: WheelState = {
		compressionStuds = wheel.compressionStuds,
		compressionSpeed = wheel.compressionSpeed,
		missedContactSteps = wheel.missedContactSteps,
		gripMultiplier = wheel.gripMultiplier,
		rollingResistance = wheel.rollingResistance,
		isGrounded = wheel.isGrounded,
	}
	if surface == nil then
		return nextWheel
	end
	local alpha = VehicleMath.smoothingAlpha(settings.SURFACE_BLEND_RATE, dt)
	local targetGrip = settings.SURFACE_GRIP[surface]
	local targetResistance = settings.SURFACE_ROLLING_RESISTANCE[surface]
	nextWheel.gripMultiplier += (targetGrip - wheel.gripMultiplier) * alpha
	nextWheel.rollingResistance += (targetResistance - wheel.rollingResistance) * alpha
	return nextWheel
end

return SurfaceGrip
