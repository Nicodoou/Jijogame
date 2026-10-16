--!strict
-- Rotaciones de un marco (derecha, arriba, adelante) sobre sus propios ejes. No depende de la
-- orientación del mundo, así que sirve igual con el auto volcado.

export type Frame = {
	right: vector,
	up: vector,
	forward: vector,
}

local CameraFrame = {}

-- Yaw positivo: el frente gira hacia la derecha.
function CameraFrame.yaw(frame: Frame, radians: number): Frame
	local sine, cosine = math.sin(radians), math.cos(radians)
	return {
		right = frame.right * cosine - frame.forward * sine,
		up = frame.up,
		forward = frame.forward * cosine + frame.right * sine,
	}
end

-- Pitch positivo: el frente sube.
function CameraFrame.pitch(frame: Frame, radians: number): Frame
	local sine, cosine = math.sin(radians), math.cos(radians)
	return {
		right = frame.right,
		up = frame.up * cosine - frame.forward * sine,
		forward = frame.forward * cosine + frame.up * sine,
	}
end

-- Roll positivo: la parte de arriba se inclina hacia la derecha.
function CameraFrame.roll(frame: Frame, radians: number): Frame
	local sine, cosine = math.sin(radians), math.cos(radians)
	return {
		right = frame.right * cosine - frame.up * sine,
		up = frame.up * cosine + frame.right * sine,
		forward = frame.forward,
	}
end

return CameraFrame
