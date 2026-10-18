--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DamageModel = require("../../../src/vehicle/core/damage/DamageModel")
local DamageReport = require("../../../src/vehicle/core/damage/DamageReport")

local SPECS = DamageConfig.PIECES
local FULL = DamageConfig.RULES.DETACH_DAMAGE

local function payload(): any
	local state = DamageModel.newState(SPECS)
	state.pieces.bonnet.damage = 40
	state.pieces.bonnet.wear = 4
	return { pieces = state.pieces :: any }
end

local function withPiece(field: string, value: any): unknown
	local message = payload()
	message.pieces.bonnet[field] = value
	return message
end

Runner.test("a valid state is accepted and copied", function()
	local message = payload()
	local state = DamageReport.validate(message, SPECS)
	Runner.expectEqual(state ~= nil, true)
	Runner.expectEqual((state :: any).pieces.bonnet.damage, 40)
	Runner.expectEqual((state :: any).pieces.bonnet ~= message.pieces.bonnet, true)
end)

Runner.test("a message that is not a table or has no pieces is rejected", function()
	local bads: { any } = { 5, "x", true, {}, { pieces = 3 } }
	for _, bad in bads do
		Runner.expectEqual(DamageReport.validate(bad, SPECS), nil)
	end
	Runner.expectEqual(DamageReport.validate(nil, SPECS), nil)
end)

Runner.test("damage out of range, negative or NaN is rejected, 0 and 100 are accepted", function()
	local bads: { any } = { -0.01, FULL + 0.01, 0 / 0, math.huge, "10" }
	for _, bad in bads do
		Runner.expectEqual(DamageReport.validate(withPiece("damage", bad), SPECS), nil)
	end
	Runner.expectEqual(DamageReport.validate(withPiece("damage", 0), SPECS) ~= nil, true)
	Runner.expectEqual(DamageReport.validate(withPiece("damage", FULL), SPECS) ~= nil, true)
end)

Runner.test("wear above what the full damage would give is rejected", function()
	local limit = FULL * SPECS.bonnet.wearPerDamage
	Runner.expectEqual(DamageReport.validate(withPiece("wear", limit), SPECS) ~= nil, true)
	Runner.expectEqual(DamageReport.validate(withPiece("wear", limit + 0.01), SPECS), nil)
	Runner.expectEqual(DamageReport.validate(withPiece("wear", -1), SPECS), nil)
end)

Runner.test("isDetached has to be a boolean", function()
	Runner.expectEqual(DamageReport.validate(withPiece("isDetached", 1), SPECS), nil)
	Runner.expectEqual(DamageReport.validate(withPiece("isDetached", true), SPECS) ~= nil, true)
end)

Runner.test("a piece that is a number instead of a table is rejected", function()
	local message = payload()
	message.pieces.bonnet = 5 :: any
	Runner.expectEqual(DamageReport.validate(message, SPECS), nil)
end)

Runner.test("a missing piece or an unknown one is rejected", function()
	local missing = payload()
	missing.pieces.engine = nil
	Runner.expectEqual(DamageReport.validate(missing, SPECS), nil)
	local extra = payload()
	extra.pieces.spoiler = { damage = 0, wear = 0, isDetached = false }
	Runner.expectEqual(DamageReport.validate(extra, SPECS), nil)
	local numeric = payload()
	numeric.pieces[1 :: any] = { damage = 0, wear = 0, isDetached = false }
	Runner.expectEqual(DamageReport.validate(numeric, SPECS), nil)
end)

Runner.finish()
