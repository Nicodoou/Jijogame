--!strict
local RoadPropertySuite = require("./RoadPropertySuite")
local Runner = require("../Runner")

-- Semillas que corren el CI y scripts/test.sh. La corrida completa (200) está en tests/world/long/RoadLongRun.luau.
local CI_SEED_COUNT = 40

RoadPropertySuite.defineTests(CI_SEED_COUNT)

Runner.finish()
