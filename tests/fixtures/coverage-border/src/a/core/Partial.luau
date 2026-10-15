--!strict
local Partial = {}
function Partial.pick(flag: boolean): number
	if flag then
		return 1
	end
	return 2
end
function Partial.other(): number
	return 3
end
return Partial
