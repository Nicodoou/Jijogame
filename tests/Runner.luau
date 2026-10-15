--!strict
-- Corredor de pruebas mínimo y compartido. Corre con el CLI `luau`, sin APIs de Roblox.
-- Cambiarlo es por acuerdo entre las áreas, igual que los contratos.

local SUMMARY_MARKER = "RESUMEN"
local NUMBER_FORMAT = "%.17g"

export type Suite = {
	test: (name: string, body: () -> ()) -> (),
	expectEqual: (actual: unknown, expected: unknown) -> (),
	expectNear: (actual: number, expected: number, tolerance: number) -> (),
	expectError: (body: () -> ()) -> (),
	finish: () -> (),
}

local function formatValue(value: unknown): string
	if type(value) == "number" then
		return string.format(NUMBER_FORMAT, value)
	end
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function createSuite(report: (line: string) -> ()): Suite
	local passedCount = 0
	local failedCount = 0

	local function test(name: string, body: () -> ())
		local succeeded, message = pcall(body :: any)
		if succeeded then
			passedCount += 1
			return
		end
		failedCount += 1
		report(`FALLA {name}: {message}`)
	end

	local function expectEqual(actual: unknown, expected: unknown)
		if actual ~= expected then
			error(`se esperaba {formatValue(expected)} y se obtuvo {formatValue(actual)}`, 0)
		end
	end

	local function expectNear(actual: number, expected: number, tolerance: number)
		local difference = math.abs(actual - expected)
		if not (difference <= tolerance) then
			error(
				`se esperaba {formatValue(expected)} con tolerancia {formatValue(tolerance)}`
					.. ` y se obtuvo {formatValue(actual)} (diferencia {formatValue(difference)})`,
				0
			)
		end
	end

	local function expectError(body: () -> ())
		local succeeded = pcall(body :: any)
		if succeeded then
			error("se esperaba un error y la función terminó sin errores", 0)
		end
	end

	local function finish()
		local total = passedCount + failedCount
		report(`{SUMMARY_MARKER}: {passedCount} OK, {failedCount} con falla, {total} pruebas`)
		if failedCount > 0 then
			error(`{failedCount} pruebas fallaron`, 0)
		end
	end

	return {
		test = test,
		expectEqual = expectEqual,
		expectNear = expectNear,
		expectError = expectError,
		finish = finish,
	}
end

local defaultSuite = createSuite(print)

return {
	createSuite = createSuite,
	test = defaultSuite.test,
	expectEqual = defaultSuite.expectEqual,
	expectNear = defaultSuite.expectNear,
	expectError = defaultSuite.expectError,
	finish = defaultSuite.finish,
}
