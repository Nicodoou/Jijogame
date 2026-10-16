--!strict
-- El simulador con la configuración que devuelve `DamageEffects`: el daño cambia el manejo sin tocar el simulador.
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DamageEffects = require("../../../src/vehicle/core/damage/DamageEffects")
local DamageModel = require("../../../src/vehicle/core/damage/DamageModel")
local ToyWorld = require("../ToyWorld")
local VehicleConfig = require("../../../src/vehicle/core/VehicleConfig")
local VehicleTypes = require("../../../src/vehicle/core/VehicleTypes")

type VehicleControls = VehicleTypes.VehicleControls
type VehicleSettings = VehicleTypes.VehicleSettings

local SPECS = DamageConfig.PIECES
local CRUISE_SPEED = 40
local CRUISE_SECONDS = 3
local MIN_DRIFT_STUDS = 2
local ACCELERATION_SECONDS = 5
local FRAME_RATES = { 30, 60 }

local function settingsWith(damages: { [string]: number }): VehicleSettings
	local state = DamageModel.newState(SPECS)
	for id, damage in damages do
		state.pieces[id].damage = damage
	end
	return DamageEffects.apply(VehicleConfig, state, SPECS)
end

local function controlsWith(throttle: number): VehicleControls
	return { steer = 0, throttle = throttle, brake = 0, isHandbrakeOn = false }
end

-- Desvío lateral (studs, respecto del rumbo inicial) en recta y con el volante al centro.
local function lateralDrift(settings: VehicleSettings, fps: number): number
	local runner = ToyWorld.new({ config = settings, initialForwardSpeed = CRUISE_SPEED, frameSeconds = 1 / fps })
	local start = runner.world.position
	runner.run(CRUISE_SECONDS, function()
		return controlsWith(0.3)
	end)
	return math.abs(runner.world.position.x - start.x)
end

local function speedAfterAccelerating(settings: VehicleSettings): number
	local runner = ToyWorld.new({ config = settings })
	runner.run(ACCELERATION_SECONDS, function()
		return controlsWith(1)
	end)
	return runner.world.feedback.forwardSpeedStudsPerSecond
end

Runner.test("without damage the car goes straight with the wheel centered", function()
	for _, fps in FRAME_RATES do
		Runner.expectEqual(lateralDrift(settingsWith({}), fps) < MIN_DRIFT_STUDS, true)
	end
end)

Runner.test(
	"with the front right suspension at 80 the car drifts sideways more than 2 studs in 3 seconds at 40 studs per second",
	function()
		for _, fps in FRAME_RATES do
			Runner.expectEqual(lateralDrift(settingsWith({ suspension_FR = 80 }), fps) > MIN_DRIFT_STUDS, true)
		end
	end
)

Runner.test("the car pulls to the side of the damaged suspension", function()
	local function signedDrift(damages: { [string]: number }): number
		local runner = ToyWorld.new({ config = settingsWith(damages), initialForwardSpeed = CRUISE_SPEED })
		local start = runner.world.position
		runner.run(CRUISE_SECONDS, function()
			return controlsWith(0.3)
		end)
		return runner.world.position.x - start.x
	end
	Runner.expectEqual(signedDrift({ suspension_FR = 80 }) > 0, true)
	Runner.expectEqual(signedDrift({ suspension_FL = 80 }) < 0, true)
	Runner.expectEqual(signedDrift({ steering = 80 }) > 0, true)
end)

Runner.test("with the engine at 50 the speed after 5 seconds is lower than without damage", function()
	local healthy = speedAfterAccelerating(settingsWith({}))
	local damaged = speedAfterAccelerating(settingsWith({ engine = 50 }))
	Runner.expectEqual(damaged < healthy, true)
end)

Runner.test("a detached engine leaves the car without push", function()
	local state = DamageModel.newState(SPECS)
	state.pieces.engine.damage = 100
	state.pieces.engine.isDetached = true
	local runner = ToyWorld.new({ config = DamageEffects.apply(VehicleConfig, state, SPECS) })
	runner.run(ACCELERATION_SECONDS, function()
		return controlsWith(1)
	end)
	Runner.expectEqual(runner.world.feedback.forwardSpeedStudsPerSecond < 1, true)
end)

Runner.test("a detached wheel has no grip and the simulation stays finite", function()
	local state = DamageModel.newState(SPECS)
	state.pieces.wheel_RR.damage = 100
	state.pieces.wheel_RR.isDetached = true
	local settings = DamageEffects.apply(VehicleConfig, state, SPECS)
	Runner.expectEqual(settings.WHEEL_GRIP_MULTIPLIERS[4], 0)
	local runner = ToyWorld.new({ config = settings, initialForwardSpeed = CRUISE_SPEED })
	runner.run(CRUISE_SECONDS, function()
		return controlsWith(0.3)
	end)
	local speed = vector.magnitude(runner.world.linearVelocity)
	Runner.expectEqual(speed == speed and speed < 1000, true)
end)

Runner.test("the damaged settings stay finite at every frame rate with heavy damage everywhere", function()
	local damages: { [string]: number } = {}
	for id in SPECS do
		damages[id] = 90
	end
	for _, fps in FRAME_RATES do
		local runner =
			ToyWorld.new({ config = settingsWith(damages), initialForwardSpeed = 30, frameSeconds = 1 / fps })
		runner.run(4, function()
			return controlsWith(0.5)
		end)
		local speed = vector.magnitude(runner.world.linearVelocity)
		Runner.expectEqual(speed == speed and speed < 1000, true)
	end
end)

Runner.finish()
