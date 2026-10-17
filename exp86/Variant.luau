--!nocheck
-- Aplica una variante del experimento ("clave=valor,clave=valor") sobre Exp86. Tiene que llamarse ANTES de requerir RoadPath.
local Exp86 = require("../src/world/core/Exp86")
local Variant = {}
function Variant.apply(spec: string?)
	if spec == nil or spec == "" or spec == "base" then return end
	for pair in string.gmatch(spec, "[^,]+") do
		local key, value = string.match(pair, "^([%w_]+)=(.+)$")
		Exp86[key] = tonumber(value) or value
	end
end
return Variant
