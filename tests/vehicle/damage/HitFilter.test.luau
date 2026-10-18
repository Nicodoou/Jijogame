--!strict
local Runner = require("../../Runner")
local DamageConfig = require("../../../src/vehicle/core/damage/DamageConfig")
local HitFilter = require("../../../src/vehicle/core/damage/HitFilter")

local SPEC = DamageConfig.PIECES.bonnet
local GROUND = DamageConfig.HITBOX.GROUND_IMPACT_SPEED
local COOLDOWN = DamageConfig.HITBOX.HIT_COOLDOWN_SECONDS
local FLAT = 1
local WALL = 0

Runner.test("a hit at or below the threshold of the sheet does not count", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, SPEC.impactThreshold, WALL, false), false)
	Runner.expectEqual(HitFilter.shouldCount(SPEC, 0, WALL, false), false)
	Runner.expectEqual(HitFilter.shouldCount(SPEC, SPEC.impactThreshold + 0.01, WALL, false), true)
end)

Runner.test("the sign of the speed does not matter", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, -60, WALL, false), true)
end)

Runner.test("a NaN speed does not count", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, 0 / 0, WALL, false), false)
end)

Runner.test("a slow hit of the bottom face against the terrain is the car resting and does not count", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, GROUND - 0.01, FLAT, true), false)
	Runner.expectEqual(HitFilter.shouldCount(SPEC, GROUND - 0.01, -FLAT, true), false)
end)

Runner.test("a fast landing against the terrain counts", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, GROUND, FLAT, true), true)
end)

Runner.test("a slow side hit against the terrain or a bottom hit against another part counts", function()
	Runner.expectEqual(HitFilter.shouldCount(SPEC, GROUND - 0.01, WALL, true), true)
	Runner.expectEqual(HitFilter.shouldCount(SPEC, GROUND - 0.01, FLAT, false), true)
end)

Runner.test("the same pair counts once per cooldown and again after it", function()
	local cooldowns = HitFilter.newCooldowns()
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "a|b", 10), true)
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "a|b", 10 + COOLDOWN - 0.01), false)
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "a|b", 10 + COOLDOWN), true)
end)

Runner.test("different pairs do not block each other", function()
	local cooldowns = HitFilter.newCooldowns()
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "a|b", 5), true)
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "a|c", 5), true)
	Runner.expectEqual(HitFilter.registerHit(cooldowns, "d|b", 5), true)
end)

Runner.test("the expired pairs are removed from the table", function()
	local cooldowns = HitFilter.newCooldowns()
	HitFilter.registerHit(cooldowns, "old", 0)
	HitFilter.registerHit(cooldowns, "new", COOLDOWN * 2)
	Runner.expectEqual(cooldowns.old, nil)
	Runner.expectEqual(cooldowns.new, COOLDOWN * 2)
end)

Runner.finish()
