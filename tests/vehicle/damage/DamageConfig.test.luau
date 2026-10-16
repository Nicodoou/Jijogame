--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")

local SPECS = DamageConfig.PIECES
local TOLERANCE = 1e-12

local function expectProtects(protectorId: string, targetId: string, factor: number)
	local found = false
	for _, protection in SPECS[protectorId].protects do
		if protection.pieceId == targetId then
			found = true
			Runner.expectNear(protection.factor, factor, TOLERANCE)
		end
	end
	Runner.expectEqual(found, true)
end

Runner.test("every piece has its own id as key and a positive K", function()
	for id, spec in SPECS do
		Runner.expectEqual(spec.id, id)
		Runner.expectEqual(spec.damagePerImpact > 0, true)
		Runner.expectEqual(spec.wearPerDamage > 0, true)
	end
end)

Runner.test("the threshold is 15 studs per second and the wear 0.1 per damage point", function()
	for _, spec in SPECS do
		Runner.expectEqual(spec.impactThreshold, 15)
		Runner.expectEqual(spec.wearPerDamage, 0.1)
	end
end)

Runner.test("sheet metal has K 0.05 and glass and lights 0.08", function()
	Runner.expectEqual(SPECS.bonnet.damagePerImpact, 0.05)
	Runner.expectEqual(SPECS.fender_FL.damagePerImpact, 0.05)
	for _, id in { "windshield", "rearWindow", "window_L", "mirror_R", "headlight_L", "taillight_R" } do
		Runner.expectEqual(SPECS[id].damagePerImpact, 0.08)
	end
end)

Runner.test("the interior pieces have no collision box and the exterior ones do", function()
	for _, kind in { "engine", "radiator", "gearbox", "steering", "fuelTank", "suspension" } do
		for _, spec in SPECS do
			if spec.kind == kind then
				Runner.expectEqual(spec.isExterior, false)
			end
		end
	end
	Runner.expectEqual(SPECS.grille.isExterior, true)
	Runner.expectEqual(SPECS.wheel_FL.isExterior, true)
end)

Runner.test("every protection points to a piece that exists", function()
	for _, spec in SPECS do
		for _, protection in spec.protects do
			Runner.expectEqual(SPECS[protection.pieceId] ~= nil, true)
			Runner.expectEqual(protection.factor > 0 and protection.factor <= 1, true)
		end
	end
end)

Runner.test("the protections are the ones of the design", function()
	expectProtects("grille", "radiator", 0.6)
	expectProtects("frontBumper", "radiator", 0.6)
	expectProtects("radiator", "engine", 0.3)
	expectProtects("chassisBase", "fuelTank", 0.4)
	for _, name in { "FL", "FR", "RL", "RR" } do
		expectProtects("chassisBase", "suspension_" .. name, 0.4)
		expectProtects("fender_" .. name, "wheel_" .. name, 0.5)
		expectProtects("fender_" .. name, "suspension_" .. name, 0.5)
	end
end)

Runner.test("the wheels and their suspensions point to their wheel index", function()
	local expected: { [string]: number } = { FL = 1, FR = 2, RL = 3, RR = 4 }
	for name, index in expected do
		Runner.expectEqual(SPECS["wheel_" .. name].wheelIndex, index)
		Runner.expectEqual(SPECS["suspension_" .. name].wheelIndex, index)
	end
end)

Runner.test("the rules and effects are read only numbers", function()
	Runner.expectEqual(DamageConfig.RULES.DETACH_DAMAGE, 100)
	Runner.expectEqual(DamageConfig.RULES.MAX_PROTECTION_DEPTH > 0, true)
	Runner.expectError(function()
		(DamageConfig.RULES :: any).DETACH_DAMAGE = 1
	end)
	Runner.expectError(function()
		(DamageConfig.EFFECTS :: any).GEARBOX_SHIFT_SLOWDOWN = 1
	end)
end)

Runner.finish()
