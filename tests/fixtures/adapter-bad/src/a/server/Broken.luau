--!strict
local Broken = {}

function Broken.count(): number
	local part = Instance.new("Part")
	part.Position = "not a vector"
	return part.Name
end

return Broken
