--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local DamageModel = require("../../../src/vehicle/core/damage/DamageModel")
local DamageTypes = require("../../../src/vehicle/core/damage/DamageTypes")

type DamageEvent = DamageTypes.DamageEvent
type DamageState = DamageTypes.DamageState
type PieceSpecs = DamageTypes.PieceSpecs

local SPECS = DamageConfig.PIECES
local THRESHOLD = 15
local K = 0.05
local GLASS_K = 0.08
local TOLERANCE = 1e-9

local function pieceSpec(id: string, protects: { DamageTypes.Protection }?): DamageTypes.PieceSpec
	return {
		id = id,
		kind = "bonnet",
		isExterior = true,
		damagePerImpact = K,
		impactThreshold = THRESHOLD,
		wearPerDamage = 0.1,
		protects = protects or {},
		wheelIndex = nil,
	}
end

local function damageOf(state: DamageState, id: string): number
	return state.pieces[id].damage
end

local function expectedDamage(speed: number, k: number): number
	local excess = math.max(0, math.abs(speed) - THRESHOLD)
	return k * excess * excess
end

local function eventsOfKind(events: { DamageEvent }, kind: string, id: string): number
	local count = 0
	for _, event in events do
		if event.kind == kind and event.pieceId == id then
			count += 1
		end
	end
	return count
end

Runner.test("a new state has every piece at zero and nothing detached", function()
	local state = DamageModel.newState(SPECS)
	local count = 0
	for id, piece in state.pieces do
		count += 1
		Runner.expectEqual(piece.damage, 0)
		Runner.expectEqual(piece.wear, 0)
		Runner.expectEqual(piece.isDetached, false)
		Runner.expectEqual(SPECS[id] ~= nil, true)
	end
	Runner.expectEqual(count > 20, true)
end)

Runner.test("an impact below or at the threshold does no damage", function()
	local state = DamageModel.newState(SPECS)
	for _, speed in { 0, 5, THRESHOLD - 0.01, THRESHOLD } do
		local nextState, events = DamageModel.applyImpact(state, "bonnet", speed, SPECS)
		Runner.expectEqual(damageOf(nextState, "bonnet"), 0)
		Runner.expectEqual(#events, 0)
	end
end)

Runner.test("the damage grows with the square of what passes the threshold", function()
	local state = DamageModel.newState(SPECS)
	local small = DamageModel.applyImpact(state, "bonnet", THRESHOLD + 10, SPECS)
	local double = DamageModel.applyImpact(state, "bonnet", THRESHOLD + 20, SPECS)
	Runner.expectNear(damageOf(small, "bonnet"), expectedDamage(THRESHOLD + 10, K), TOLERANCE)
	Runner.expectNear(damageOf(double, "bonnet"), 4 * damageOf(small, "bonnet"), TOLERANCE)
end)

Runner.test("glass and lights take a bigger K", function()
	local state = DamageModel.newState(SPECS)
	local glass = DamageModel.applyImpact(state, "windshield", THRESHOLD + 10, SPECS)
	Runner.expectNear(damageOf(glass, "windshield"), expectedDamage(THRESHOLD + 10, GLASS_K), TOLERANCE)
end)

Runner.test("the sign of the speed does not matter", function()
	local state = DamageModel.newState(SPECS)
	local positive = DamageModel.applyImpact(state, "bonnet", 30, SPECS)
	local negative = DamageModel.applyImpact(state, "bonnet", -30, SPECS)
	Runner.expectEqual(damageOf(positive, "bonnet"), damageOf(negative, "bonnet"))
end)

Runner.test("NaN and infinity do no damage", function()
	local state = DamageModel.newState(SPECS)
	for _, speed in { 0 / 0, math.huge, -math.huge } do
		local nextState, events = DamageModel.applyImpact(state, "bonnet", speed, SPECS)
		Runner.expectEqual(damageOf(nextState, "bonnet"), 0)
		Runner.expectEqual(#events, 0)
	end
end)

Runner.test("a piece that does not exist is ignored", function()
	local state = DamageModel.newState(SPECS)
	local nextState, events = DamageModel.applyImpact(state, "doesNotExist", 100, SPECS)
	Runner.expectEqual(#events, 0)
	Runner.expectEqual(damageOf(nextState, "bonnet"), 0)
end)

Runner.test("the damage event lists the damage that went in", function()
	local state = DamageModel.newState(SPECS)
	local _, events = DamageModel.applyImpact(state, "bonnet", 30, SPECS)
	Runner.expectEqual(#events, 1)
	Runner.expectEqual(events[1].kind, "damaged")
	Runner.expectEqual(events[1].pieceId, "bonnet")
	Runner.expectNear(events[1].damage, expectedDamage(30, K), TOLERANCE)
end)

Runner.test("the wear goes up with the damage and never down", function()
	local state = DamageModel.newState(SPECS)
	local previousWear = 0
	for _, speed in { 20, 5, 30, 0, 25 } do
		state = DamageModel.applyImpact(state, "bonnet", speed, SPECS)
		local wear = state.pieces.bonnet.wear
		Runner.expectEqual(wear >= previousWear, true)
		previousWear = wear
	end
	Runner.expectNear(previousWear, 0.1 * damageOf(state, "bonnet"), TOLERANCE)
	Runner.expectEqual(previousWear > 0, true)
end)

Runner.test("a piece reaching 100 is detached, the event comes once and it takes no more damage", function()
	local state = DamageModel.newState(SPECS)
	local detachedEvents = 0
	for _ = 1, 6 do
		local events
		state, events = DamageModel.applyImpact(state, "bonnet", 100, SPECS)
		detachedEvents += eventsOfKind(events, "detached", "bonnet")
	end
	Runner.expectEqual(detachedEvents, 1)
	Runner.expectEqual(state.pieces.bonnet.isDetached, true)
	Runner.expectEqual(damageOf(state, "bonnet"), 100)
	local wearAfter = state.pieces.bonnet.wear
	local again = DamageModel.applyImpact(state, "bonnet", 100, SPECS)
	Runner.expectEqual(again.pieces.bonnet.wear, wearAfter)
	Runner.expectEqual(damageOf(again, "bonnet"), 100)
end)

Runner.test("the radiator takes 60% of what the grille takes", function()
	local state = DamageModel.newState(SPECS)
	local nextState = DamageModel.applyImpact(state, "grille", THRESHOLD + 20, SPECS)
	Runner.expectNear(damageOf(nextState, "radiator"), 0.6 * damageOf(nextState, "grille"), TOLERANCE)
end)

Runner.test("the damage keeps going down the chain: grille, radiator and engine", function()
	local state = DamageModel.newState(SPECS)
	local nextState = DamageModel.applyImpact(state, "grille", THRESHOLD + 20, SPECS)
	Runner.expectNear(damageOf(nextState, "engine"), 0.3 * damageOf(nextState, "radiator"), TOLERANCE)
	Runner.expectEqual(damageOf(nextState, "engine") > 0, true)
end)

Runner.test("with the grille detached the next hit goes straight to the radiator", function()
	local state = DamageModel.newState(SPECS)
	state.pieces.grille = { damage = 100, wear = 10, isDetached = true }
	local before = damageOf(state, "radiator")
	local grilleDamage = damageOf(state, "grille")
	local nextState = DamageModel.applyImpact(state, "grille", THRESHOLD + 20, SPECS)
	Runner.expectEqual(damageOf(nextState, "grille"), grilleDamage)
	Runner.expectNear(damageOf(nextState, "radiator") - before, expectedDamage(THRESHOLD + 20, K), TOLERANCE)
end)

Runner.test("the chassis base protects the suspension and the tank at 40%", function()
	local state = DamageModel.newState(SPECS)
	local nextState = DamageModel.applyImpact(state, "chassisBase", THRESHOLD + 20, SPECS)
	local base = damageOf(nextState, "chassisBase")
	Runner.expectNear(damageOf(nextState, "fuelTank"), 0.4 * base, TOLERANCE)
	for _, name in { "FL", "FR", "RL", "RR" } do
		Runner.expectNear(damageOf(nextState, "suspension_" .. name), 0.4 * base, TOLERANCE)
	end
end)

Runner.test("a fender protects its own wheel and suspension at 50%", function()
	local state = DamageModel.newState(SPECS)
	local nextState = DamageModel.applyImpact(state, "fender_RR", THRESHOLD + 20, SPECS)
	local fender = damageOf(nextState, "fender_RR")
	Runner.expectNear(damageOf(nextState, "wheel_RR"), 0.5 * fender, TOLERANCE)
	Runner.expectNear(damageOf(nextState, "suspension_RR"), 0.5 * fender, TOLERANCE)
	Runner.expectEqual(damageOf(nextState, "wheel_FL"), 0)
	Runner.expectEqual(damageOf(nextState, "suspension_FL"), 0)
end)

Runner.test("a badly made sheet where A protects B and B protects A does not loop", function()
	local specs: PieceSpecs = {
		A = pieceSpec("A", { { pieceId = "B", factor = 0.9 } }),
		B = pieceSpec("B", { { pieceId = "A", factor = 0.9 } }),
	}
	local state = DamageModel.newState(specs)
	local nextState, events = DamageModel.applyImpact(state, "A", 40, specs)
	Runner.expectEqual(damageOf(nextState, "A") > 0 and damageOf(nextState, "A") <= 100, true)
	Runner.expectEqual(damageOf(nextState, "B") > 0 and damageOf(nextState, "B") <= 100, true)
	Runner.expectEqual(#events <= 2 * (DamageConfig.RULES.MAX_PROTECTION_DEPTH + 2), true)
end)

Runner.test("a piece that protects itself does not loop either", function()
	local specs: PieceSpecs = { A = pieceSpec("A", { { pieceId = "A", factor = 1 } }) }
	local state = DamageModel.newState(specs)
	local nextState = DamageModel.applyImpact(state, "A", 30, specs)
	Runner.expectEqual(damageOf(nextState, "A") > 0, true)
end)

Runner.test("the damage never goes above 100", function()
	local state = DamageModel.newState(SPECS)
	local nextState = DamageModel.applyImpact(state, "bonnet", 1e6, SPECS)
	Runner.expectEqual(damageOf(nextState, "bonnet"), 100)
end)

Runner.test("applyImpact does not modify its arguments", function()
	local state = DamageModel.newState(SPECS)
	for _, piece in state.pieces do
		table.freeze(piece)
	end
	table.freeze(state.pieces)
	table.freeze(state)
	local nextState = DamageModel.applyImpact(state, "grille", 50, SPECS)
	Runner.expectEqual(nextState ~= state, true)
	Runner.expectEqual(state.pieces.grille.damage, 0)
	Runner.expectEqual(nextState.pieces.grille.damage > 0, true)
end)

Runner.test("the same impacts always give the same state", function()
	local first = DamageModel.newState(SPECS)
	local second = DamageModel.newState(SPECS)
	for _, speed in { 20, 35, 50 } do
		first = DamageModel.applyImpact(first, "frontBumper", speed, SPECS)
		second = DamageModel.applyImpact(second, "frontBumper", speed, SPECS)
	end
	Runner.expectEqual(damageOf(first, "engine"), damageOf(second, "engine"))
end)

Runner.finish()
