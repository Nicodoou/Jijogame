--!strict
local Runner = require("../Runner")
local Automatic5 = require("../../src/vehicle/core/specs/gearboxes/Automatic5")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local Engine147 = require("../../src/vehicle/core/specs/engines/Engine147")
local Fiat147 = require("../../src/vehicle/core/specs/cars/Fiat147")
local SpecTypes = require("../../src/vehicle/core/specs/SpecTypes")
local VehicleBuild = require("../../src/vehicle/core/VehicleBuild")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")

type CarSpec = SpecTypes.CarSpec
type EngineSpec = SpecTypes.EngineSpec
type GearboxSpec = SpecTypes.GearboxSpec

local function engineWith(changes: { [string]: any }): EngineSpec
	local copy: any = table.clone(Engine147)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

local function gearboxWith(changes: { [string]: any }): GearboxSpec
	local copy: any = table.clone(Automatic5)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

local function carWith(changes: { [string]: any }): CarSpec
	local copy: any = table.clone(Fiat147)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

local function expectRejected(car: CarSpec, engine: EngineSpec, gearbox: GearboxSpec, reason: string)
	local settings, problem = VehicleBuild.assemble(car, engine, gearbox)
	Runner.expectEqual(settings, nil)
	Runner.expectEqual(type(problem) == "string" and string.find(problem :: string, reason, 1, true) ~= nil, true)
end

Runner.test("every invalid combination is rejected with its reason", function()
	expectRejected(Fiat147, Engine147, gearboxWith({ GEAR_RATIOS = {} }), "marchas")
	expectRejected(Fiat147, Engine147, gearboxWith({ GEAR_RATIOS = { 3, 0, 1 } }), "marcha 2")
	expectRejected(Fiat147, Engine147, gearboxWith({ GEAR_RATIOS = { 3, -1 } }), "marcha 2")
	expectRejected(Fiat147, Engine147, gearboxWith({ REVERSE_RATIO = 0 }), "relaciones")
	expectRejected(Fiat147, Engine147, gearboxWith({ FINAL_DRIVE = -1 }), "relaciones")
	expectRejected(Fiat147, Engine147, gearboxWith({ DRIVETRAIN_EFFICIENCY = 0 }), "eficiencia")
	expectRejected(Fiat147, Engine147, gearboxWith({ DRIVETRAIN_EFFICIENCY = 1.1 }), "eficiencia")
	expectRejected(Fiat147, engineWith({ TORQUE_CURVE = {} }), Automatic5, "vacía")
	local unsorted = { { rpm = 3000, fraction = 1 }, { rpm = 1000, fraction = 0.5 } }
	expectRejected(Fiat147, engineWith({ TORQUE_CURVE = unsorted }), Automatic5, "ordenada")
	local repeated = { { rpm = 1000, fraction = 1 }, { rpm = 1000, fraction = 0.5 } }
	expectRejected(Fiat147, engineWith({ TORQUE_CURVE = repeated }), Automatic5, "ordenada")
	expectRejected(Fiat147, engineWith({ PEAK_TORQUE = 0 }), Automatic5, "torque")
	expectRejected(Fiat147, engineWith({ ENGINE_MASS = 0 }), Automatic5, "motor")
	expectRejected(carWith({ CHASSIS_MASS = -5 }), Engine147, Automatic5, "chasis")
	expectRejected(Fiat147, engineWith({ REDLINE_RPM = Engine147.IDLE_RPM }), Automatic5, "corte")
	expectRejected(Fiat147, engineWith({ REDLINE_RPM = 500 }), Automatic5, "corte")
	expectRejected(carWith({ WHEEL_RADIUS_STUDS = 0 }), Engine147, Automatic5, "radio")
	expectRejected(carWith({ WHEELS = {} }), Engine147, Automatic5, "paso entre ejes")
end)

Runner.test("an efficiency of exactly 1 is valid", function()
	local settings, problem = VehicleBuild.assemble(Fiat147, Engine147, gearboxWith({ DRIVETRAIN_EFFICIENCY = 1 }))
	Runner.expectEqual(settings ~= nil and problem == nil, true)
end)

Runner.test("the output is frozen, does not change the specs and is deterministic", function()
	local first = VehicleBuild.assemble(Fiat147, Engine147, Automatic5)
	local second = VehicleBuild.assemble(Fiat147, Engine147, Automatic5)
	Runner.expectEqual(first ~= nil and table.isfrozen(first), true)
	Runner.expectEqual(table.isfrozen(Fiat147) and table.isfrozen(Engine147) and table.isfrozen(Automatic5), true)
	Runner.expectEqual(Fiat147.FRONT_WEIGHT_FRACTION, 0.6359595959596)
	Runner.expectEqual(Fiat147.CHASSIS_MASS, 70)
	Runner.expectEqual(Engine147.PEAK_TORQUE, 648)
	Runner.expectEqual(first ~= nil and second ~= nil, true)
	for key, value in (first :: any) :: { [string]: any } do
		Runner.expectEqual(((second :: any) :: { [string]: any })[key], value)
	end
	Runner.expectError(function()
		((first :: any) :: { [string]: any }).REAR_BIAS = 1
	end)
end)

Runner.test("the output has every key of the three specs and the derived ones", function()
	for _, spec in { Fiat147, Engine147, Automatic5 } :: { { [string]: any } } do
		for key in spec do
			Runner.expectEqual((VehicleConfig :: any)[key] ~= nil, true)
		end
	end
	Runner.expectEqual(Automatic5.kind, "automatic")
	Runner.expectEqual(VehicleConfig.MAX_STEP_SECONDS, 1 / 15)
	Runner.expectEqual(VehicleConfig.CONTACT_PLANE_DEGENERATE_THRESHOLD, 1e-4)
end)

Runner.test("a live tuning override replaces a key of the output as it does on any table", function()
	local copy: any = table.clone(VehicleConfig)
	copy.FIRST_GEAR_PEAK_ACCELERATION = 60
	local state = VehicleSimulator.newState()
	local controls = { steer = 0, throttle = 1, brake = 0, isHandbrakeOn = false }
	local base = Drivetrain.driveForce(state, controls, 4500, VehicleConfig.TOTAL_MASS)
	Runner.expectNear(Drivetrain.driveForce(state, controls, 4500, VehicleConfig.TOTAL_MASS, copy), base / 2, 1e-6)
end)

Runner.finish()
