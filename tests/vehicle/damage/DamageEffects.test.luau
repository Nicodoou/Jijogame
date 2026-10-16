--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DamageEffects = require("../../../src/vehicle/core/damage/DamageEffects")
local DamageModel = require("../../../src/vehicle/core/damage/DamageModel")
local DamageTypes = require("../../../src/vehicle/core/damage/DamageTypes")
local VehicleConfig = require("../../../src/vehicle/core/VehicleConfig")

type DamageState = DamageTypes.DamageState

local SPECS = DamageConfig.PIECES
local EFFECTS = DamageConfig.EFFECTS
local TOLERANCE = 1e-9
local FRONT_RIGHT = 2
local REAR_RIGHT = 4
local REAR_LEFT = 3

local function stateWith(damages: { [string]: number }, detached: { [string]: boolean }?): DamageState
	local state = DamageModel.newState(SPECS)
	for id, damage in damages do
		state.pieces[id].damage = damage
		state.pieces[id].isDetached = detached ~= nil and detached[id] == true
	end
	return state
end

Runner.test("with every piece at zero the settings are identical to the original", function()
	local result = DamageEffects.apply(VehicleConfig, DamageModel.newState(SPECS), SPECS)
	for key, value in VehicleConfig do
		if type(value) ~= "table" then
			Runner.expectEqual((result :: any)[key], value)
		end
	end
	for index = 1, 4 do
		Runner.expectEqual(result.WHEEL_GRIP_MULTIPLIERS[index], 1)
	end
	Runner.expectEqual(result.STEER_OFFSET_DEGREES, 0)
	Runner.expectEqual(result.WHEELS, VehicleConfig.WHEELS)
end)

Runner.test("the result is a copy: the original is never touched", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ engine = 50 }), SPECS)
	Runner.expectEqual(result ~= VehicleConfig, true)
	Runner.expectEqual(VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION, 120)
	Runner.expectEqual(table.isfrozen(VehicleConfig), true)
end)

Runner.test("the engine at 50 damage gives half the thrust", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ engine = 50 }), SPECS)
	Runner.expectNear(result.FIRST_GEAR_PEAK_ACCELERATION, 0.5 * VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION, TOLERANCE)
end)

Runner.test("the engine and the radiator multiply their effects", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ engine = 50, radiator = 100 }), SPECS)
	local expected = VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION * 0.5 * EFFECTS.RADIATOR_MIN_POWER
	Runner.expectNear(result.FIRST_GEAR_PEAK_ACCELERATION, expected, TOLERANCE)
end)

Runner.test("the radiator scales the power between 0.5 and 1", function()
	local half = DamageEffects.apply(VehicleConfig, stateWith({ radiator = 50 }), SPECS)
	Runner.expectNear(half.FIRST_GEAR_PEAK_ACCELERATION, VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION * 0.75, TOLERANCE)
	local gone = DamageEffects.apply(VehicleConfig, stateWith({ radiator = 100 }, { radiator = true }), SPECS)
	Runner.expectNear(gone.FIRST_GEAR_PEAK_ACCELERATION, VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION * 0.5, TOLERANCE)
end)

Runner.test("a detached engine leaves the car without thrust", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ engine = 100 }, { engine = true }), SPECS)
	Runner.expectEqual(result.FIRST_GEAR_PEAK_ACCELERATION, 0)
end)

Runner.test("the gearbox makes the shifts longer", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ gearbox = 50 }), SPECS)
	Runner.expectNear(
		result.SHIFT_DURATION_SECONDS,
		VehicleConfig.SHIFT_DURATION_SECONDS * (1 + EFFECTS.GEARBOX_SHIFT_SLOWDOWN * 0.5),
		TOLERANCE
	)
	local broken = DamageEffects.apply(VehicleConfig, stateWith({ gearbox = 100 }), SPECS)
	Runner.expectNear(broken.SHIFT_DURATION_SECONDS, 3 * VehicleConfig.SHIFT_DURATION_SECONDS, TOLERANCE)
end)

Runner.test("a damaged rear right suspension lowers that wheel's grip and pulls the steering to the right", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ suspension_RR = 80 }), SPECS)
	Runner.expectNear(result.WHEEL_GRIP_MULTIPLIERS[REAR_RIGHT], 1 - EFFECTS.SUSPENSION_GRIP_LOSS * 0.8, TOLERANCE)
	Runner.expectEqual(result.WHEEL_GRIP_MULTIPLIERS[REAR_LEFT], 1)
	Runner.expectEqual(result.WHEEL_GRIP_MULTIPLIERS[1], 1)
	Runner.expectNear(result.STEER_OFFSET_DEGREES, EFFECTS.STEERING_PULL_DEGREES_PER_DAMAGE * 80, TOLERANCE)
end)

Runner.test("a left suspension pulls to the left", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ suspension_FL = 60 }), SPECS)
	Runner.expectEqual(result.STEER_OFFSET_DEGREES < 0, true)
end)

Runner.test("the pulls of two sides cancel out", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ suspension_FL = 40, suspension_FR = 40 }), SPECS)
	Runner.expectNear(result.STEER_OFFSET_DEGREES, 0, TOLERANCE)
end)

Runner.test("the steering piece gives a fixed offset proportional to its damage", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ steering = 30 }), SPECS)
	Runner.expectNear(result.STEER_OFFSET_DEGREES, EFFECTS.STEERING_OFFSET_DEGREES_PER_DAMAGE * 30, TOLERANCE)
end)

Runner.test("a damaged wheel grips in proportion to its life", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ wheel_FR = 25 }), SPECS)
	Runner.expectNear(result.WHEEL_GRIP_MULTIPLIERS[FRONT_RIGHT], 0.75, TOLERANCE)
end)

Runner.test("a detached wheel has no grip", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ wheel_RL = 100 }, { wheel_RL = true }), SPECS)
	Runner.expectEqual(result.WHEEL_GRIP_MULTIPLIERS[REAR_LEFT], 0)
end)

Runner.test("the effects of the wheel and its suspension multiply", function()
	local result = DamageEffects.apply(VehicleConfig, stateWith({ wheel_FR = 50, suspension_FR = 100 }), SPECS)
	Runner.expectNear(result.WHEEL_GRIP_MULTIPLIERS[FRONT_RIGHT], 0.5 * (1 - EFFECTS.SUSPENSION_GRIP_LOSS), TOLERANCE)
end)

Runner.test("the pieces that are only visual change nothing in the driving", function()
	local visual =
		stateWith({ bonnet = 90, windshield = 70, door_L = 50, mirror_R = 100, headlight_L = 100, fuelTank = 100 })
	local result = DamageEffects.apply(VehicleConfig, visual, SPECS)
	Runner.expectEqual(result.FIRST_GEAR_PEAK_ACCELERATION, VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION)
	Runner.expectEqual(result.SHIFT_DURATION_SECONDS, VehicleConfig.SHIFT_DURATION_SECONDS)
	Runner.expectEqual(result.STEER_OFFSET_DEGREES, 0)
	for index = 1, 4 do
		Runner.expectEqual(result.WHEEL_GRIP_MULTIPLIERS[index], 1)
	end
end)

Runner.test("damage over 100 counts as 100 and a piece missing from the state is ignored", function()
	local over = DamageEffects.apply(VehicleConfig, stateWith({ engine = 500 }), SPECS)
	Runner.expectEqual(over.FIRST_GEAR_PEAK_ACCELERATION, 0)
	local empty: DamageState = { pieces = {} }
	local result = DamageEffects.apply(VehicleConfig, empty, SPECS)
	Runner.expectEqual(result.FIRST_GEAR_PEAK_ACCELERATION, VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION)
end)

Runner.test("the effects start from the grips and the offset the settings already have", function()
	local base = table.clone(VehicleConfig)
	base.WHEEL_GRIP_MULTIPLIERS = table.freeze({ 0.9, 1, 1, 1 })
	base.STEER_OFFSET_DEGREES = 1
	local result = DamageEffects.apply(base, stateWith({ wheel_FL = 50, steering = 20 }), SPECS)
	Runner.expectNear(result.WHEEL_GRIP_MULTIPLIERS[1], 0.45, TOLERANCE)
	Runner.expectNear(result.STEER_OFFSET_DEGREES, 1 + EFFECTS.STEERING_OFFSET_DEGREES_PER_DAMAGE * 20, TOLERANCE)
end)

Runner.test("apply does not modify its arguments", function()
	local state = stateWith({ engine = 50, suspension_FR = 60 })
	for _, piece in state.pieces do
		table.freeze(piece)
	end
	table.freeze(state.pieces)
	table.freeze(state)
	local result = DamageEffects.apply(VehicleConfig, state, SPECS)
	Runner.expectEqual(result.FIRST_GEAR_PEAK_ACCELERATION < VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION, true)
	Runner.expectEqual(state.pieces.engine.damage, 50)
end)

Runner.finish()
