--!strict
local Runner = require("../Runner")
local Automatic5 = require("../../src/vehicle/core/specs/gearboxes/Automatic5")
local Drivetrain = require("../../src/vehicle/core/Drivetrain")
local Engine147 = require("../../src/vehicle/core/specs/engines/Engine147")
local Fiat147 = require("../../src/vehicle/core/specs/cars/Fiat147")
local SpecTypes = require("../../src/vehicle/core/specs/SpecTypes")
local ToyWorld = require("./ToyWorld")
local VehicleBuild = require("../../src/vehicle/core/VehicleBuild")
local VehicleConfig = require("../../src/vehicle/core/VehicleConfig")
local VehicleSimulator = require("../../src/vehicle/core/VehicleSimulator")

type CarSpec = SpecTypes.CarSpec
type EngineSpec = SpecTypes.EngineSpec
type GearboxSpec = SpecTypes.GearboxSpec

-- Valores de antes del WP-20a, escritos acá a propósito: son la referencia que no puede moverse.
local OLD_MASS = 84
local OLD_FIRST_GEAR_PEAK_ACCELERATION = 120
local OLD_RATIOS = { 3.5, 2.3, 1.65, 1.25, 1.0 }
local OLD_CURVE = { { 1000, 0.6 }, { 3000, 0.9 }, { 4500, 1.0 }, { 6500, 0.85 }, { 7000, 0.7 } }
local OLD_REDLINE = 7000
local OLD_SOFT_LIMITER = 400
local OLD_FINAL_DRIVE = 4.0
local OLD_WHEEL_RADIUS = 0.81
local OLD_TOP_SPEED_SIM = 141.352905
local FORCE_TOLERANCE = 0.01
local TOP_SPEED_TOLERANCE = 0.005
local FIRST_RPM, LAST_RPM, RPM_STEP = 1000, 7000, 250
local SIM_SECONDS = 60

local function oldFraction(rpm: number): number
	for index = 2, #OLD_CURVE do
		local lower, upper = OLD_CURVE[index - 1], OLD_CURVE[index]
		if rpm <= upper[1] then
			return lower[2] + (upper[2] - lower[2]) * (rpm - lower[1]) / (upper[1] - lower[1])
		end
	end
	return OLD_CURVE[#OLD_CURVE][2]
end

-- La fuerza de tracción a pleno pedal con la fórmula de antes: masa · aceleración · fracción · relación / relación de 1ra.
local function oldForce(gear: number, rpm: number): number
	local limiter = math.clamp((OLD_REDLINE - rpm) / OLD_SOFT_LIMITER, 0, 1)
	return OLD_MASS
		* OLD_FIRST_GEAR_PEAK_ACCELERATION
		* oldFraction(math.max(rpm, FIRST_RPM))
		* (OLD_RATIOS[gear] / OLD_RATIOS[1])
		* limiter
end

local function fullThrottleForce(gear: number, rpm: number): number
	local state = VehicleSimulator.newState()
	state.gear = gear
	local controls = { steer = 0, throttle = 1, brake = 0, isHandbrakeOn = false }
	return Drivetrain.driveForce(state, controls, rpm, VehicleConfig.TOTAL_MASS)
end

local function engineWith(changes: { [string]: any }): EngineSpec
	local copy: any = table.clone(Engine147)
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

Runner.test("the traction force is the one from before in every gear and rpm, within 1%", function()
	local worst = 0
	for gear = 1, #OLD_RATIOS do
		for rpm = FIRST_RPM, LAST_RPM, RPM_STEP do
			local expected, actual = oldForce(gear, rpm), fullThrottleForce(gear, rpm)
			if expected == 0 then
				Runner.expectNear(actual, 0, 1e-9)
			else
				worst = math.max(worst, math.abs(actual - expected) / expected)
			end
		end
	end
	Runner.expectEqual(worst <= FORCE_TOLERANCE, true)
end)

Runner.test("the traction force comes from the engine torque and not from the mass", function()
	local peak = Engine147.PEAK_TORQUE
	for gear = 1, #OLD_RATIOS do
		local rpm = 4500
		local expected = peak
			* Engine147.TORQUE_CURVE[3].fraction
			* Automatic5.GEAR_RATIOS[gear]
			* Automatic5.FINAL_DRIVE
			* Automatic5.DRIVETRAIN_EFFICIENCY
			/ Fiat147.WHEEL_RADIUS_STUDS
		Runner.expectNear(fullThrottleForce(gear, rpm), expected, 1e-6)
	end
	Runner.expectEqual(Engine147.PEAK_TORQUE, 84 * 120 * 0.81 / (3.5 * 4 * 0.9))
end)

Runner.test("a heavier engine with the same torque accelerates less", function()
	local heavy = VehicleBuild.assemble(Fiat147, engineWith({ ENGINE_MASS = 28 }), Automatic5)
	Runner.expectEqual(heavy ~= nil and heavy.TOTAL_MASS == 98, true)
	Runner.expectEqual(
		heavy ~= nil and heavy.FIRST_GEAR_PEAK_ACCELERATION < VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION,
		true
	)
	local lighter = VehicleBuild.assemble(Fiat147, engineWith({ ENGINE_MASS = 7 }), Automatic5)
	Runner.expectEqual(
		lighter ~= nil and lighter.FIRST_GEAR_PEAK_ACCELERATION > VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION,
		true
	)
	Runner.expectNear(VehicleConfig.FIRST_GEAR_PEAK_ACCELERATION, OLD_FIRST_GEAR_PEAK_ACCELERATION, 1e-9)
end)

Runner.test("the top speed in 5th gear is the one from before, within 0.5%", function()
	local redline = VehicleConfig.REDLINE_RPM
	local last = #VehicleConfig.GEAR_RATIOS
	local speed = redline
		/ 60
		/ (VehicleConfig.GEAR_RATIOS[last] * VehicleConfig.FINAL_DRIVE)
		* 2
		* math.pi
		* VehicleConfig.WHEEL_RADIUS_STUDS
	local oldSpeed = OLD_REDLINE / 60 / (OLD_RATIOS[5] * OLD_FINAL_DRIVE) * 2 * math.pi * OLD_WHEEL_RADIUS
	Runner.expectEqual(math.abs(speed - oldSpeed) / oldSpeed <= TOP_SPEED_TOLERANCE, true)
	Runner.expectNear(Drivetrain.rawRpm(speed, last), redline, 1e-6)
end)

Runner.test("the top speed in the simulation at full throttle is the one measured before the change", function()
	local runner = ToyWorld.new({})
	local controls = { steer = 0, throttle = 1, brake = 0, isHandbrakeOn = false }
	local top = 0
	runner.run(SIM_SECONDS, function()
		return controls
	end, function(world)
		top = math.max(top, world.feedback.forwardSpeedStudsPerSecond)
	end)
	Runner.expectEqual(math.abs(top - OLD_TOP_SPEED_SIM) / OLD_TOP_SPEED_SIM <= TOP_SPEED_TOLERANCE, true)
end)

Runner.test("the 147 weighs 84 and has a front weight of 0.7", function()
	Runner.expectEqual(VehicleConfig.TOTAL_MASS, OLD_MASS)
	Runner.expectEqual(Fiat147.CHASSIS_MASS + Engine147.ENGINE_MASS, OLD_MASS)
	Runner.expectEqual(VehicleConfig.FRONT_WEIGHT_FRACTION, 0.7)
end)

Runner.test("a heavier engine at the front loads the front axle and at the rear unloads it", function()
	local front = VehicleBuild.assemble(Fiat147, engineWith({ ENGINE_MASS = 40 }), Automatic5)
	Runner.expectEqual(front ~= nil and front.FRONT_WEIGHT_FRACTION > VehicleConfig.FRONT_WEIGHT_FRACTION, true)
	local rear = VehicleBuild.assemble(carWith({ ENGINE_POSITION_Z = 3 }), engineWith({ ENGINE_MASS = 40 }), Automatic5)
	Runner.expectEqual(rear ~= nil and rear.FRONT_WEIGHT_FRACTION < VehicleConfig.FRONT_WEIGHT_FRACTION, true)
end)

Runner.test("the game horsepower of the 147 engine is 50", function()
	Runner.expectNear(VehicleBuild.powerHp(Engine147), 50, 0.5)
	local stronger = engineWith({ PEAK_TORQUE = 2 * Engine147.PEAK_TORQUE })
	Runner.expectNear(VehicleBuild.powerHp(stronger), 100, 1)
end)

Runner.finish()
