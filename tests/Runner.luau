--!strict
local Runner = {}
local failures = 0
local total = 0

function Runner.eq(actual: any, expected: any, name: string)
	total += 1
	if actual ~= expected then
		failures += 1
		print(`FAIL {name}: esperado {expected}, obtenido {actual}`)
	end
end

function Runner.finish(): number
	print(`{total - failures}/{total} aserciones OK`)
	return failures
end

return Runner
