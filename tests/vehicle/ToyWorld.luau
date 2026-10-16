--!strict
-- Mundo de juguete SOLO para las pruebas: integra el chasis como cuerpo rígido con Euler semiimplícito a 240 Hz
-- contra un plano (con pendiente opcional) y le da al simulador lo que le daría Roblox. No es parte del núcleo.
-- Corre el simulador a la frecuencia de cuadros que se pida, y mantiene las fuerzas fijas entre cuadros.
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")
local VehicleTypes = require("../../src/vehicle/core/VehicleTypes")

type ChassisSample = VehicleTypes.ChassisSample
type SurfaceKind = VehicleTypes.SurfaceKind
type VehicleControls = VehicleTypes.VehicleControls
type VehicleFeedback = VehicleTypes.VehicleFeedback
type VehicleSettings = VehicleTypes.VehicleSettings
type VehicleState = VehicleTypes.VehicleState
type WheelContact = VehicleTypes.WheelContact
type WheelOutput = VehicleTypes.WheelOutput

export type ToyWorldOptions = {
	config: VehicleSettings?,
	frameSeconds: number?,
	mass: number?,
	gravity: number?,
	slopeDegrees: number?,
	surfaceAt: ((position: vector) -> SurfaceKind?)?,
	dropStuds: number?,
	initialForwardSpeed: number?,
	initialYawDegrees: number?,
	-- Apoya el auto alineado con el plano (su "arriba" es la normal) en vez de derecho.
	isAlignedToSlope: boolean?,
	-- Centro de masa respecto del origen del marco de las ruedas, en coordenadas locales (z positivo es atrás).
	centerOfMassOffset: vector?,
	yawInertiaFraction: number?,
}

export type ToyWorld = {
	frameSeconds: number,
	timeSeconds: number,
	position: vector,
	linearVelocity: vector,
	right: vector,
	up: vector,
	forward: vector,
	angularVelocity: vector,
	vehicleState: VehicleState,
	outputs: { WheelOutput },
	feedback: VehicleFeedback,
	mass: number,
	gravity: number,
	settings: VehicleSettings,
	centerOfMassOffset: vector,
	yawInertiaFraction: number,
}

local ToyWorld = {}

local PHYSICS_HZ = 240
local DEFAULT_FRAME_SECONDS = 1 / 30
local DEFAULT_MASS = 1000
local DEFAULT_GRAVITY = 196.2
-- Dimensiones de la caja del chasis (ancho, alto, largo) para el tensor de inercia.
local BOX_WIDTH = 6
local BOX_HEIGHT = 2
local BOX_LENGTH = 10
-- El rayo del adaptador sale desde arriba del montaje (#31): ve el suelo aunque esté un poco por encima.
local RAY_START_ABOVE_MOUNT = 4
local MIN_SLOPE_ALIGNMENT = 1e-6

local function rotateAround(value: vector, rotation: vector): vector
	local angle = vector.magnitude(rotation)
	if angle < 1e-12 then
		return value
	end
	local axis = rotation / angle
	local cosine, sine = math.cos(angle), math.sin(angle)
	return value * cosine + vector.cross(axis, value) * sine + axis * (vector.dot(axis, value) * (1 - cosine))
end

local function groundNormal(slopeDegrees: number): vector
	local slope = math.rad(slopeDegrees)
	return vector.create(0, math.cos(slope), math.sin(slope))
end

local function restHeight(settings: VehicleSettings, gravity: number): number
	local angularFrequency = 2 * math.pi * settings.SUSPENSION_FREQUENCY_HZ
	local staticCompression = gravity / (angularFrequency * angularFrequency)
	return -settings.WHEELS[1].offset.y
		+ settings.SUSPENSION_REST_LENGTH_STUDS
		+ settings.WHEEL_RADIUS_STUDS
		- staticCompression
end

local function mountWorldOffset(world: ToyWorld, localOffset: vector): vector
	return world.right * localOffset.x + world.up * localOffset.y - world.forward * localOffset.z
end

-- Apoya el auto sobre el plano: su "arriba" pasa a ser la normal y conserva el rumbo en el plano.
local function alignToPlane(world: ToyWorld, normal: vector, height: number)
	local flat = world.forward - normal * vector.dot(world.forward, normal)
	world.forward = vector.normalize(flat)
	world.up = normal
	world.right = vector.cross(world.forward, normal)
	world.position = normal * height + mountWorldOffset(world, world.centerOfMassOffset)
end

-- `position` es el centro de masa; el origen del marco de las ruedas queda desplazado de él.
local function frameOrigin(world: ToyWorld): vector
	return world.position - mountWorldOffset(world, world.centerOfMassOffset)
end

local function sampleChassis(world: ToyWorld): ChassisSample
	return {
		origin = frameOrigin(world),
		position = world.position,
		right = world.right,
		up = world.up,
		forward = world.forward,
		linearVelocity = world.linearVelocity,
		angularVelocity = world.angularVelocity,
		mass = world.mass,
		gravity = world.gravity,
	}
end

-- Rayo hacia abajo del chasis desde cada punto de montaje contra el plano del suelo.
local function castWheels(world: ToyWorld, normal: vector, surfaceAt: (vector) -> SurfaceKind?): { WheelContact? }
	local settings = world.settings
	local reach = settings.SUSPENSION_REST_LENGTH_STUDS + settings.WHEEL_RADIUS_STUDS
	local alignment = vector.dot(world.up, normal)
	local contacts: { WheelContact? } = {}
	for index, wheel in settings.WHEELS do
		local mount = frameOrigin(world) + mountWorldOffset(world, wheel.offset)
		local distance = vector.dot(mount, normal) / alignment
		if alignment > MIN_SLOPE_ALIGNMENT and distance <= reach and distance >= -RAY_START_ABOVE_MOUNT then
			local point = mount - world.up * distance
			contacts[index] = { hasHit = true, distanceStuds = distance, point = point, surface = surfaceAt(point) }
		end
	end
	return contacts
end

local function inertiaTimes(world: ToyWorld, value: vector, inverse: boolean): vector
	local mass = world.mass
	local pitch = mass * (BOX_HEIGHT * BOX_HEIGHT + BOX_LENGTH * BOX_LENGTH) / 12
	local yaw = world.yawInertiaFraction * mass * (BOX_WIDTH * BOX_WIDTH + BOX_LENGTH * BOX_LENGTH) / 12
	local roll = mass * (BOX_WIDTH * BOX_WIDTH + BOX_HEIGHT * BOX_HEIGHT) / 12
	local factorRight = if inverse then 1 / pitch else pitch
	local factorUp = if inverse then 1 / yaw else yaw
	local factorForward = if inverse then 1 / roll else roll
	return world.right * (vector.dot(value, world.right) * factorRight)
		+ world.up * (vector.dot(value, world.up) * factorUp)
		+ world.forward * (vector.dot(value, world.forward) * factorForward)
end

local function orthonormalize(world: ToyWorld)
	local forward = vector.normalize(world.forward)
	local right = vector.normalize(world.right - forward * vector.dot(world.right, forward))
	world.forward = forward
	world.right = right
	world.up = vector.cross(right, forward)
end

local function integrate(world: ToyWorld, outputs: { WheelOutput }, substepSeconds: number)
	local force = vector.create(0, -world.gravity * world.mass, 0)
	local torque = vector.create(0, 0, 0)
	for index, wheel in world.settings.WHEELS do
		local wheelForce = outputs[index].force
		force += wheelForce
		torque += vector.cross(
			mountWorldOffset(world, wheel.offset) - mountWorldOffset(world, world.centerOfMassOffset),
			wheelForce
		)
	end
	local angularMomentum = inertiaTimes(world, world.angularVelocity, false)
	local gyroscopic = vector.cross(world.angularVelocity, angularMomentum)
	world.linearVelocity += force / world.mass * substepSeconds
	world.angularVelocity += inertiaTimes(world, torque - gyroscopic, true) * substepSeconds
	world.position += world.linearVelocity * substepSeconds
	local rotation = world.angularVelocity * substepSeconds
	world.right = rotateAround(world.right, rotation)
	world.forward = rotateAround(world.forward, rotation)
	orthonormalize(world)
end

-- Un cuadro: el simulador se llama una vez y sus fuerzas quedan fijas durante todos los pasos de física del cuadro.
function ToyWorld.advanceFrame(
	world: ToyWorld,
	controls: VehicleControls,
	normal: vector,
	surfaceAt: (vector) -> SurfaceKind?
)
	local contacts = castWheels(world, normal, surfaceAt)
	local newState, outputs, feedback = VehicleSimulator.step(
		world.vehicleState,
		controls,
		sampleChassis(world),
		contacts,
		world.frameSeconds,
		world.settings
	)
	world.vehicleState, world.outputs, world.feedback = newState, outputs, feedback
	local substeps = math.max(1, math.floor(world.frameSeconds * PHYSICS_HZ + 0.5))
	for _ = 1, substeps do
		integrate(world, outputs, world.frameSeconds / substeps)
	end
	world.timeSeconds += world.frameSeconds
end

export type Runner = {
	world: ToyWorld,
	step: (controls: VehicleControls) -> (),
	run: (seconds: number, controlsAt: (world: ToyWorld) -> VehicleControls, onFrame: ((world: ToyWorld) -> ())?) -> (),
}

function ToyWorld.new(options: ToyWorldOptions?): Runner
	local resolved: ToyWorldOptions = options or {}
	local settings = resolved.config or VehicleConfig
	local gravity = resolved.gravity or DEFAULT_GRAVITY
	local normal = groundNormal(resolved.slopeDegrees or 0)
	local surfaceAt = resolved.surfaceAt or function(_: vector): SurfaceKind?
		return "Road"
	end
	local yaw = math.rad(resolved.initialYawDegrees or 0)
	local forward = vector.create(-math.sin(yaw), 0, -math.cos(yaw))
	local right = vector.create(math.cos(yaw), 0, -math.sin(yaw))
	local height = restHeight(settings, gravity) + (resolved.dropStuds or 0)
	local base = vector.create(0, height, 0)
	local world: ToyWorld = {
		frameSeconds = resolved.frameSeconds or DEFAULT_FRAME_SECONDS,
		timeSeconds = 0,
		position = base,
		linearVelocity = forward * (resolved.initialForwardSpeed or 0),
		right = right,
		up = vector.cross(right, forward),
		forward = forward,
		angularVelocity = vector.create(0, 0, 0),
		vehicleState = VehicleSimulator.newState(settings),
		outputs = {},
		feedback = {
			speedStudsPerSecond = 0,
			forwardSpeedStudsPerSecond = 0,
			engineRpm = settings.IDLE_RPM,
			gear = 1,
			isShifting = false,
			driftAngleRadians = 0,
			isDrifting = false,
			wheels = {},
		},
		mass = resolved.mass or DEFAULT_MASS,
		gravity = gravity,
		settings = settings,
		centerOfMassOffset = resolved.centerOfMassOffset or vector.create(0, 0, 0),
		yawInertiaFraction = resolved.yawInertiaFraction or 1,
	}
	world.position = base + mountWorldOffset(world, world.centerOfMassOffset)
	if resolved.isAlignedToSlope then
		alignToPlane(world, normal, height)
	end
	local function step(controls: VehicleControls)
		ToyWorld.advanceFrame(world, controls, normal, surfaceAt)
	end
	local function run(seconds: number, controlsAt: (ToyWorld) -> VehicleControls, onFrame: ((ToyWorld) -> ())?)
		local frames = math.floor(seconds / world.frameSeconds + 0.5)
		for _ = 1, frames do
			step(controlsAt(world))
			if onFrame ~= nil then
				onFrame(world)
			end
		end
	end
	return { world = world, step = step, run = run }
end

return ToyWorld
