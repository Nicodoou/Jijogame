--!strict
local UsesGlobals = {}

function UsesGlobals.touchEverything(): any
	local random = Random.new(1)
	task.wait()
	return { workspace, Instance.new("Part"), random }
end

return UsesGlobals
