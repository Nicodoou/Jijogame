--!strict
-- Tipos compartidos del núcleo del auto. Las ruedas van siempre en el orden FL, FR, RL, RR.
local Surface = require("../../shared/contracts/Surface")
local VehicleSettingsType = require("./specs/VehicleSettingsType")

export type SurfaceKind = Surface.SurfaceKind

-- Los módulos reciben la configuración como último parámetro opcional (por defecto, VehicleConfig, que arma `VehicleBuild`)
-- para que las pruebas puedan probar valores extremos sin tocar la configuración compartida.
export type VehicleSettings = VehicleSettingsType.VehicleSettings

export type VehicleControls = {
	steer: number,
	throttle: number,
	brake: number,
	isHandbrakeOn: boolean,
}

-- `position` es el centro de masa y los ejes son unitarios en el mundo.
-- `mass` y `gravity` los lee el adaptador del motor, así la configuración no depende de la masa del modelo.
export type ChassisSample = {
	-- Origen del marco de las ruedas (la posición del `Body`). `position` es el centro de masa.
	origin: vector,
	position: vector,
	right: vector,
	up: vector,
	forward: vector,
	linearVelocity: vector,
	angularVelocity: vector,
	mass: number,
	gravity: number,
}

-- `distanceStuds` se mide desde el punto de montaje de la rueda hacia abajo del chasis.
-- Puede ser negativa si el suelo quedó por encima del montaje (el rayo sale desde arriba, #31).
export type WheelContact = {
	hasHit: boolean,
	distanceStuds: number,
	point: vector,
	surface: SurfaceKind?,
}

export type WheelState = {
	compressionStuds: number,
	compressionSpeed: number,
	missedContactSteps: number,
	gripMultiplier: number,
	rollingResistance: number,
	isGrounded: boolean,
}

-- `gear` va de 1 a N y -1 es la reversa.
export type VehicleState = {
	wheels: { WheelState },
	gear: number,
	shiftRemainingSeconds: number,
	engineRpm: number,
	-- Fracción del agarre trasero que deja el freno de mano (1 = sin efecto).
	rearGripFactor: number,
	-- Memoria de la caja para el kickdown: tiempo desde la última subida e inclinación del auto filtrada (nil al arrancar).
	secondsSinceUpshift: number,
	filteredForwardY: number?,
}

-- `force` está en el mundo y se aplica en el punto de montaje de la rueda.
export type WheelOutput = {
	force: vector,
	isGrounded: boolean,
	steerAngleRadians: number,
	compressionStuds: number,
	spinRadiansPerSecond: number,
}

export type WheelFeedback = {
	slipRatio: number,
	slipAngleRadians: number,
	isSliding: boolean,
	surface: SurfaceKind?,
}

export type VehicleFeedback = {
	speedStudsPerSecond: number,
	forwardSpeedStudsPerSecond: number,
	engineRpm: number,
	gear: number,
	isShifting: boolean,
	driftAngleRadians: number,
	isDrifting: boolean,
	wheels: { WheelFeedback },
}

-- Lo que `VehicleSimulator` calcula una vez por paso y las fuerzas de las ruedas leen.
export type StepContext = {
	settings: VehicleSettings,
	controls: VehicleControls,
	chassis: ChassisSample,
	mass: number,
	gravity: number,
	forwardSpeed: number,
	driftAngle: number,
	steerAngle: number,
	contactUp: vector,
	offsets: { vector },
	loadShares: { number },
	velocities: { vector },
	stepSeconds: number,
	rearGripFactor: number,
}

return {}
