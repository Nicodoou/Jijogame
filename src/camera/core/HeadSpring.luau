--!strict
-- Resorte amortiguado de un eje de la cabeza (Euler semi-implícito: estable con MAX_STEP_SECONDS).
local CameraConfig = require("./CameraConfig")

export type HeadSpring = {
	offset: number,
	velocity: number,
}

local HeadSpring = {}

local STIFFNESS = CameraConfig.HEAD_SPRING_FREQUENCY * CameraConfig.HEAD_SPRING_FREQUENCY
local DAMPING = 2 * CameraConfig.HEAD_SPRING_DAMPING_RATIO * CameraConfig.HEAD_SPRING_FREQUENCY

function HeadSpring.new(): HeadSpring
	return { offset = 0, velocity = 0 }
end

-- El desplazamiento se recorta a `limit` para que el rebote no pase del tope configurado.
function HeadSpring.step(spring: HeadSpring, target: number, limit: number, dt: number): HeadSpring
	local velocity = spring.velocity + (STIFFNESS * (target - spring.offset) - DAMPING * spring.velocity) * dt
	return { offset = math.clamp(spring.offset + velocity * dt, -limit, limit), velocity = velocity }
end

return HeadSpring
