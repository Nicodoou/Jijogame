--!strict
local Runner = require("../Runner")
local SeededRandom = require("../../src/world/core/SeededRandom")
local WorkBudget = require("../../src/world/core/WorkBudget")
local WorldConfig = require("../../src/world/core/WorldConfig")

local BUDGET_MS = WorldConfig.WORK_BUDGET_MS_PER_FRAME
local FRAMES = 300
-- Un tramo largo de trabajo: más pasos de los que caben en un frame.
local ENDLESS_STEPS = 1e9

type FakeWork = {
	source: WorkBudget.WorkSource,
	clock: () -> number,
	getStepsDone: () -> number,
	getTime: () -> number,
}

-- Un reloj falso que solo avanza cuando un paso gasta tiempo, y una fuente con `totalSteps` pasos de costo dado.
local function createFakeWork(totalSteps: number, costOfStep: (number) -> number): FakeWork
	local now = 0
	local stepsDone = 0
	local source: WorkBudget.WorkSource = {
		hasWork = function(): boolean
			return stepsDone < totalSteps
		end,
		runStep = function()
			stepsDone += 1
			now += costOfStep(stepsDone)
		end,
	}
	return {
		source = source,
		clock = function(): number
			return now
		end,
		getStepsDone = function(): number
			return stepsDone
		end,
		getTime = function(): number
			return now
		end,
	}
end

local function measureFrames(work: FakeWork, budget: WorkBudget.WorkBudget, frames: number): number
	local longest = 0
	for _ = 1, frames do
		local before = work.getTime()
		budget.advance(work.source)
		longest = math.max(longest, work.getTime() - before)
	end
	return longest
end

Runner.test("with steps of constant cost a frame never spends more than the budget", function()
	for _, cost in { 0.05, 0.1, 0.3, 0.5, 1, 1.3, 2, BUDGET_MS / 2, BUDGET_MS - 0.01, BUDGET_MS } do
		local work = createFakeWork(ENDLESS_STEPS, function()
			return cost
		end)
		local budget = WorkBudget.new(work.clock, BUDGET_MS)
		Runner.expectEqual(measureFrames(work, budget, FRAMES) <= BUDGET_MS + 1e-9, true)
	end
end)

Runner.test("it uses the budget: a frame runs as many steps as fit", function()
	local work = createFakeWork(ENDLESS_STEPS, function()
		return 0.5
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS)
	budget.advance(work.source)
	Runner.expectEqual(work.getStepsDone(), 8)
	Runner.expectEqual(budget.advance(work.source), 8)
end)

Runner.test("with steps of varying cost it stays inside the budget once it has seen the longest one", function()
	local random = SeededRandom.new(4)
	local costs: { number } = {}
	for index = 1, FRAMES * 40 do
		costs[index] = 0.05 + random.nextNumber() * 0.45
	end
	-- Los primeros pasos son los más caros que habrá; sin descenso de la estimación no hay sorpresas.
	costs[1], costs[2] = 0.5, 0.5
	local work = createFakeWork(ENDLESS_STEPS, function(step: number)
		return costs[step % #costs + 1]
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS, 1)
	budget.advance(work.source)
	Runner.expectEqual(measureFrames(work, budget, FRAMES) <= BUDGET_MS + 1e-9, true)
end)

Runner.test("a single step longer than the budget still runs, one per frame, so the work advances", function()
	local work = createFakeWork(ENDLESS_STEPS, function()
		return 3 * BUDGET_MS
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS)
	Runner.expectEqual(budget.advance(work.source), 1)
	Runner.expectEqual(budget.advance(work.source), 1)
	Runner.expectEqual(work.getStepsDone(), 2)
end)

Runner.test("it stops when there is no work left and does nothing when there is none", function()
	local work = createFakeWork(3, function()
		return 0.1
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS)
	Runner.expectEqual(budget.advance(work.source), 3)
	Runner.expectEqual(budget.advance(work.source), 0)
	Runner.expectEqual(work.getStepsDone(), 3)
end)

Runner.test("steps that cost nothing are capped per frame instead of looping forever", function()
	local work = createFakeWork(ENDLESS_STEPS, function()
		return 0
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS)
	Runner.expectEqual(budget.advance(work.source), WorldConfig.WORK_BUDGET_MAX_STEPS_PER_FRAME)
end)

Runner.test("after an expensive step the estimate fades and the frames fill up again", function()
	local work = createFakeWork(ENDLESS_STEPS, function(step: number)
		return if step == 1 then 3 else 0.1
	end)
	local budget = WorkBudget.new(work.clock, BUDGET_MS)
	local firstFrame = budget.advance(work.source)
	local lateFrame = 0
	for _ = 1, FRAMES do
		lateFrame = budget.advance(work.source)
	end
	Runner.expectEqual(firstFrame, 1)
	Runner.expectEqual(lateFrame > 30, true)
end)

Runner.test("the budget has to be a positive number", function()
	local clock = function(): number
		return 0
	end
	Runner.expectError(function()
		WorkBudget.new(clock, 0)
	end)
	Runner.expectError(function()
		WorkBudget.new(clock, -1)
	end)
	Runner.expectError(function()
		WorkBudget.new(clock, 0 / 0)
	end)
end)

Runner.finish()
