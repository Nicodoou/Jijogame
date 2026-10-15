--!strict
local Other = require("../../b/core/Other")

local Caller = {}

function Caller.call(): number
	return Other.value()
end

return Caller
