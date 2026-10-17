--!strict
-- Retraso suave del yaw de la cámara respecto del yaw del auto (solo cámara, no toca la dirección ni la física).
-- La cámara sigue al auto con un resorte críticamente amortiguado: un cambio brusco de velocidad de giro entra de a
-- poco. `offset` es yaw de la cámara menos yaw del auto (rad, positivo a la derecha) y `rate` su velocidad propia.
local CameraAim = require("./CameraAim")

type Config = typeof(require("./CameraConfig"))

export type YawLag = {
	offset: number,
	rate: number,
	carYaw: number?,
}

local CameraYawLag = {}

function CameraYawLag.new(): YawLag
	return { offset = 0, rate = 0, carYaw = nil }
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Solución exacta del resorte críticamente amortiguado: estable con cualquier frecuencia y dt.
local function springStep(offset: number, rate: number, frequency: number, dt: number): (number, number)
	local decay = math.exp(-frequency * dt)
	local push = rate + frequency * offset
	return (offset + push * dt) * decay, (rate - frequency * push * dt) * decay
end

-- `isReset` (mirar atrás) deja la cámara pegada al auto al instante. Con frecuencia 0 no hay suavizado.
function CameraYawLag.step(lag: YawLag, forward: vector, dt: number, isReset: boolean, config: Config): YawLag
	local carYaw = CameraAim.yawOf(forward)
	local previous = lag.carYaw
	local turned = if carYaw ~= nil and previous ~= nil then wrap(carYaw - previous) else 0
	local nextYaw = carYaw or previous
	if isReset or not (config.CAMERA_YAW_SMOOTHING > 0) then
		return { offset = 0, rate = 0, carYaw = nextYaw }
	end
	local offset, rate = springStep(lag.offset - turned, lag.rate, config.CAMERA_YAW_SMOOTHING, dt)
	local limit = math.rad(config.CAMERA_YAW_MAX_LAG_DEGREES)
	if math.abs(offset) > limit then
		offset, rate = math.clamp(offset, -limit, limit), 0
	end
	return { offset = offset, rate = rate, carYaw = nextYaw }
end

return CameraYawLag
