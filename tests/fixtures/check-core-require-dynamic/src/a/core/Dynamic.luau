--!strict
local Dynamic = {}

function Dynamic.load(name: string): any
	return require(name :: any)
end

return Dynamic
