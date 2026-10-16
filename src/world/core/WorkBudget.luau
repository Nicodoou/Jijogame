--!strict
-- Avanza una fuente de trabajo en pasos chicos hasta gastar el presupuesto de milisegundos de un frame. El reloj entra
-- por parámetro (devuelve milisegundos), así en las pruebas es un reloj falso y el núcleo no usa os.clock.
-- Antes de cada paso se pregunta si cabe otro de lo que costó el más caro de los anteriores, para no pasarse del
-- presupuesto: pasarse por un paso sería justo el tirón que se quiere evitar.

local WorldConfig = require("./WorldConfig")

export type WorkSource = {
	hasWork: () -> boolean,
	-- Hace un paso del trabajo. Tiene que ser mucho más corto que el presupuesto.
	runStep: () -> (),
}

export type WorkBudget = {
	-- Corre pasos hasta que no quede trabajo o no quepa otro paso en el presupuesto. Devuelve cuántos corrió.
	advance: (source: WorkSource) -> number,
}

local WorkBudgetModule = {}

-- `stepEstimateDecay` baja la estimación del paso más caro en cada paso (WORK_BUDGET_STEP_ESTIMATE_DECAY por defecto).
function WorkBudgetModule.new(clock: () -> number, budgetMs: number, stepEstimateDecay: number?): WorkBudget
	if not (budgetMs > 0) then
		error("the budget has to be bigger than 0", 2)
	end
	-- Lo que costó el paso más caro de los últimos: baja de a poco, para que un pico aislado no frene todo para siempre.
	local expensiveStepMs = 0
	local decay = stepEstimateDecay or WorldConfig.WORK_BUDGET_STEP_ESTIMATE_DECAY

	local function advance(source: WorkSource): number
		local startMs = clock()
		local stepsRun = 0
		while stepsRun < WorldConfig.WORK_BUDGET_MAX_STEPS_PER_FRAME and source.hasWork() do
			local beforeMs = clock()
			-- Siempre corre un paso: si no, un paso más largo que el presupuesto no avanzaría nunca.
			if stepsRun > 0 and beforeMs - startMs + expensiveStepMs > budgetMs then
				break
			end
			source.runStep()
			expensiveStepMs = math.max(clock() - beforeMs, expensiveStepMs * decay)
			stepsRun += 1
		end
		return stepsRun
	end

	return { advance = advance }
end

return WorkBudgetModule
